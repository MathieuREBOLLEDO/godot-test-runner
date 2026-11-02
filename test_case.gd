class_name TestCase
extends Node

## Base d'un fichier de tests : chaque méthode test_* est un test.
## Le runner (runner.gd) ajoute le fichier à l'arbre (les autoloads sont là),
## appelle before_all(), puis pour chaque test before_each(), le test et
## after_each(), puis after_all(). Toutes peuvent attendre (await).
## Un assert raté n'arrête pas le test : il est noté, le test continue. Les
## asserts rendent vrai si ça passe, pour sortir tôt :
##     if not assert_not_null(level): return
## Une erreur moteur ou push_error (donc Log.err) pendant un test le fait
## échouer, sauf si elle est attendue (expect_error()).
## Les nœuds ajoutés avec add_test_node() sont libérés après chaque test.

## Messages des asserts ratés du test en cours (lus par le runner).
var failures: PackedStringArray = []
## Raison donnée à skip() pendant le test en cours (vide : pas sauté).
var skip_reason: String = ""
## Extraits des erreurs attendues pendant le test en cours.
var expected_errors: PackedStringArray = []

# Nœuds du test en cours, libérés par le runner après after_each().
var _test_nodes: Array[Node] = []


func before_all() -> void:
	pass


func after_all() -> void:
	pass


func before_each() -> void:
	pass


func after_each() -> void:
	pass


# --- Nœuds et temps ---

## Ajoute node sous le fichier de tests et le libère à la fin du test.
func add_test_node(node: Node) -> Node:
	_test_nodes.append(node)
	add_child(node)
	return node


## Attend n images de physique.
func physics_frames(n: int) -> void:
	for i: int in n:
		await get_tree().physics_frame


## Attend n images (process).
func frames(n: int) -> void:
	for i: int in n:
		await get_tree().process_frame


## Attend t secondes de jeu, comptées en images de physique (déterministe).
func seconds(t: float) -> void:
	await physics_frames(ceili(t * Engine.physics_ticks_per_second))


## Attend que condition rende vrai, au plus max_seconds (images de physique).
## Rend vrai si la condition est remplie à temps.
func until(condition: Callable, max_seconds: float = 5.0) -> bool:
	var left: int = ceili(max_seconds * Engine.physics_ticks_per_second)
	while not condition.call():
		if left <= 0:
			return false
		left -= 1
		await get_tree().physics_frame
	return true


# --- Résultat ---

## Une erreur contenant text est attendue pendant ce test : elle ne le fait
## pas échouer. Si elle n'arrive pas, le test échoue.
func expect_error(text: String) -> void:
	expected_errors.append(text)


## Le test est sauté (compté à part), avec sa raison.
func skip(reason: String) -> void:
	skip_reason = reason


func fail(message: String) -> void:
	failures.append("%s  (%s)" % [message, _caller()])


# --- Asserts ---

func assert_true(value: bool, message: String = "") -> bool:
	return _check(value, "expected true", message)


func assert_false(value: bool, message: String = "") -> bool:
	return _check(not value, "expected false", message)


func assert_eq(actual: Variant, expected: Variant, message: String = "") -> bool:
	return _check(_same(actual, expected), "expected %s, got %s" % [_str(expected), _str(actual)], message)


func assert_ne(actual: Variant, not_expected: Variant, message: String = "") -> bool:
	return _check(not _same(actual, not_expected), "expected anything but %s" % _str(not_expected), message)


## actual à tolerance près de expected (float, Vector2, Vector3).
func assert_almost(actual: Variant, expected: Variant, tolerance: float, message: String = "") -> bool:
	var gap: float = INF
	if (typeof(actual) == TYPE_FLOAT or typeof(actual) == TYPE_INT) and (typeof(expected) == TYPE_FLOAT or typeof(expected) == TYPE_INT):
		gap = absf(float(actual) - float(expected))
	elif typeof(actual) == TYPE_VECTOR2 and typeof(expected) == TYPE_VECTOR2:
		gap = (actual as Vector2).distance_to(expected as Vector2)
	elif typeof(actual) == TYPE_VECTOR3 and typeof(expected) == TYPE_VECTOR3:
		gap = (actual as Vector3).distance_to(expected as Vector3)
	return _check(gap <= tolerance, "expected %s ± %s, got %s" % [_str(expected), _str(tolerance), _str(actual)], message)


func assert_gt(actual: Variant, limit: Variant, message: String = "") -> bool:
	return _check(actual > limit, "expected > %s, got %s" % [_str(limit), _str(actual)], message)


func assert_lt(actual: Variant, limit: Variant, message: String = "") -> bool:
	return _check(actual < limit, "expected < %s, got %s" % [_str(limit), _str(actual)], message)


func assert_between(actual: Variant, low: Variant, high: Variant, message: String = "") -> bool:
	return _check(actual >= low and actual <= high, "expected in [%s, %s], got %s" % [_str(low), _str(high), _str(actual)], message)


func assert_null(value: Variant, message: String = "") -> bool:
	return _check(value == null, "expected null, got %s" % _str(value), message)


func assert_not_null(value: Variant, message: String = "") -> bool:
	return _check(value != null, "expected a value, got null", message)


## container (Array, Dictionary, String…) contient item.
func assert_has(container: Variant, item: Variant, message: String = "") -> bool:
	return _check(item in container, "expected %s to contain %s" % [_str(container), _str(item)], message)


# --- Interne ---

func _check(ok: bool, detail: String, message: String) -> bool:
	if not ok:
		fail(detail if message.is_empty() else "%s: %s" % [message, detail])
	return ok


# Égalité sans erreur de type (1 == "1" plante en GDScript).
func _same(a: Variant, b: Variant) -> bool:
	var numbers: Array[int] = [TYPE_INT, TYPE_FLOAT]
	if typeof(a) != typeof(b) and not (typeof(a) in numbers and typeof(b) in numbers):
		return false
	return a == b


func _str(value: Variant) -> String:
	if typeof(value) == TYPE_STRING or typeof(value) == TYPE_STRING_NAME:
		return '"%s"' % value
	if typeof(value) == TYPE_FLOAT:
		return "%.3f" % value
	return str(value)


# Fichier et ligne du test qui a appelé l'assert (premier appel hors de ce script).
func _caller() -> String:
	var own: String = (TestCase as Script).resource_path
	for frame: Dictionary in get_stack():
		if frame.source != own:
			return "%s:%d" % [(frame.source as String).get_file(), frame.line]
	return "?"
