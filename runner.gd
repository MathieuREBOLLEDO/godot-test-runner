extends Node

## Lance les tests du projet et quitte avec 0 (tout passe) ou 1.
## godot --headless --fixed-fps 60 --path <projet> res://addons/test_runner/runner.tscn -- [options]
## Options (après --) :
##   --dir=res://game/gameplay   dossier où chercher (plusieurs : virgules)
##   --filter=hat                fichiers ou tests dont le nom contient ce texte
##   --timeout=30                secondes de jeu maximales par test
## Tests : fichiers test_*.gd rangés dans un dossier tests/, qui étendent
## TestCase. Lancé comme scène (et non avec -s) : les autoloads existent
## avant que les tests soient compilés.
## --fixed-fps 60 : chaque image vaut 1/60 s quel que soit le temps réel ;
## les tests vont aussi vite que la machine le permet et restent
## déterministes.

const TESTS_DIR: String = "tests"
const FILE_PREFIX: String = "test_"
const METHOD_PREFIX: String = "test_"
const DEFAULT_TIMEOUT: float = 30.0
const ErrorCatcher := preload("res://addons/test_runner/error_catcher.gd")

var _dirs: PackedStringArray = ["res://"]
var _filter: String = ""
var _timeout: float = DEFAULT_TIMEOUT
var _catcher: ErrorCatcher = ErrorCatcher.new()
var _passed: int = 0
var _failed: int = 0
var _skipped: int = 0
var _failed_names: PackedStringArray = []


func _ready() -> void:
	# Le runner continue pendant une pause ; les fichiers de tests la suivent.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_read_args()
	OS.add_logger(_catcher)
	_run.call_deferred()


func _read_args() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--dir="):
			_dirs = arg.trim_prefix("--dir=").split(",", false)
		elif arg.begins_with("--filter="):
			_filter = arg.trim_prefix("--filter=")
		elif arg.begins_with("--timeout="):
			_timeout = arg.trim_prefix("--timeout=").to_float()


func _run() -> void:
	var start: int = Time.get_ticks_msec()
	var files: PackedStringArray = []
	for dir: String in _dirs:
		_find_tests(dir if dir.ends_with("://") else dir.trim_suffix("/"), files)
	files.sort()
	print("Test runner: %d file(s)%s" % [files.size(), "" if _filter.is_empty() else " (filter: %s)" % _filter])
	# Erreurs du démarrage (autoloads, scène) : signalées, pas comptées.
	for error: String in _catcher.take():
		print("  startup error: %s" % error)
	for path: String in files:
		await _run_file(path)
	var seconds: float = (Time.get_ticks_msec() - start) / 1000.0
	print("")
	print("== %d passed, %d failed, %d skipped in %.1f s" % [_passed, _failed, _skipped, seconds])
	for name: String in _failed_names:
		print("   FAILED %s" % name)
	OS.remove_logger(_catcher)
	get_tree().quit(1 if _failed > 0 or files.is_empty() else 0)


# Fichiers test_*.gd dans un dossier tests/ (à n'importe quelle profondeur).
func _find_tests(dir: String, out: PackedStringArray) -> void:
	for sub: String in DirAccess.get_directories_at(dir):
		if sub.begins_with("."):
			continue
		_find_tests(dir.path_join(sub), out)
	if dir.get_file() != TESTS_DIR:
		return
	for file: String in DirAccess.get_files_at(dir):
		if file.begins_with(FILE_PREFIX) and file.ends_with(".gd"):
			out.append(dir.path_join(file))


func _run_file(path: String) -> void:
	var file_matches: bool = _filter.is_empty() or path.get_file().contains(_filter)
	var script: GDScript = load(path) as GDScript
	var errors: PackedStringArray = _catcher.take()
	if script == null or not script.can_instantiate():
		print("\n-- %s" % path)
		_record(path, "(load)", PackedStringArray(["script does not compile"]) + errors, "")
		return

	var methods: PackedStringArray = []
	for method: Dictionary in script.get_script_method_list():
		var method_name: String = method.name
		if method_name.begins_with(METHOD_PREFIX) and not method_name in methods:
			if file_matches or method_name.contains(_filter):
				methods.append(method_name)
	if methods.is_empty():
		return
	print("\n-- %s" % path)
	var suite: TestCase = script.new() as TestCase
	if suite == null:
		_record(path, "(load)", PackedStringArray(["does not extend TestCase"]), "")
		return
	suite.name = path.get_file().get_basename()
	suite.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(suite)

	if not await _guarded(suite.before_all, "before_all"):
		_record(path, "before_all", PackedStringArray(["timed out"]), "")
	_catcher.take()
	for method_name: String in methods:
		await _run_test(path, suite, method_name)
	await _guarded(suite.after_all, "after_all")
	_catcher.take()
	suite.queue_free()
	await get_tree().process_frame


func _run_test(path: String, suite: TestCase, method_name: String) -> void:
	suite.failures = []
	suite.skip_reason = ""
	suite.expected_errors = []
	_catcher.take()
	var start_frame: int = Engine.get_physics_frames()
	var finished: bool = await _guarded(func() -> void:
		await suite.before_each()
		await suite.call(method_name)
		await suite.after_each(), method_name)

	# Remise en état : nœuds du test, pause, vitesse du temps, entrées.
	for node: Node in suite._test_nodes:
		if is_instance_valid(node):
			node.queue_free()
	suite._test_nodes.clear()
	get_tree().paused = false
	Engine.time_scale = 1.0
	await get_tree().process_frame

	var problems: PackedStringArray = suite.failures.duplicate()
	if not finished:
		problems.append("timed out after %.0f s (or stopped by a script error)" % _timeout)
	for error: String in _catcher.take():
		var expected: bool = false
		for i: int in suite.expected_errors.size():
			if error.contains(suite.expected_errors[i]):
				suite.expected_errors.remove_at(i)
				expected = true
				break
		if not expected:
			problems.append("error: %s" % error)
	for missing: String in suite.expected_errors:
		problems.append("expected error did not happen: %s" % missing)
	var frames: int = Engine.get_physics_frames() - start_frame
	_record(path, method_name, problems, suite.skip_reason, frames)


# Lance step (qui peut attendre) et rend faux s'il ne finit pas avant le
# délai : un test bloqué ou arrêté par une erreur de script ne bloque pas
# toute la suite.
func _guarded(step: Callable, _label: String) -> bool:
	var state: Dictionary = {done = false}
	var wrapper: Callable = func() -> void:
		await step.call()
		state.done = true
	wrapper.call()
	var left: int = ceili(_timeout * Engine.physics_ticks_per_second)
	while not state.done and left > 0:
		left -= 1
		await get_tree().physics_frame
	return state.done


func _record(path: String, test: String, problems: PackedStringArray, skip_reason: String, frames: int = 0) -> void:
	var duration: String = "%.2f s" % (float(frames) / Engine.physics_ticks_per_second)
	if not skip_reason.is_empty() and problems.is_empty():
		_skipped += 1
		print("   SKIP %s  (%s)" % [test, skip_reason])
		return
	if problems.is_empty():
		_passed += 1
		print("   ok   %s  [%s]" % [test, duration])
		return
	_failed += 1
	_failed_names.append("%s :: %s" % [path.get_file(), test])
	print("   FAIL %s  [%s]" % [test, duration])
	for problem: String in problems:
		print("        - %s" % problem)
