extends TestCase

## Tests du runner lui-même : asserts, attente, entrées, erreurs attendues.

var _before_each_calls: int = 0


func before_each() -> void:
	_before_each_calls += 1


func test_asserts_pass() -> void:
	assert_true(true)
	assert_false(false)
	assert_eq(2 + 2, 4)
	assert_eq(1, 1.0, "int and float compare by value")
	assert_ne("a", "b")
	assert_almost(0.1 + 0.2, 0.3, 0.0001)
	assert_almost(Vector2(1, 1), Vector2(1, 1.05), 0.1)
	assert_gt(3, 2)
	assert_lt(2, 3)
	assert_between(5, 1, 10)
	assert_null(null)
	assert_not_null(self)
	assert_has([1, 2, 3], 2)
	assert_has("gringo", "ring")
	assert_eq(failures.size(), 0, "no failure recorded")


func test_failed_assert_is_recorded() -> void:
	assert_eq(1, "1")
	assert_almost(1.0, 2.0, 0.5)
	var recorded: int = failures.size()
	# Remis à vide : ces échecs sont voulus.
	failures.clear()
	assert_eq(recorded, 2, "two failures recorded")


func test_before_each_runs_before_every_test() -> void:
	assert_gt(_before_each_calls, 0)


func test_seconds_counts_physics_frames() -> void:
	var start: int = Engine.get_physics_frames()
	await seconds(0.5)
	assert_almost(Engine.get_physics_frames() - start, 0.5 * Engine.physics_ticks_per_second, 1.0)


func test_until_times_out() -> void:
	var never: Callable = func() -> bool: return false
	assert_false(await until(never, 0.1))
	var counter: Dictionary = {n = 0}
	var soon: Callable = func() -> bool:
		counter.n += 1
		return counter.n > 3
	assert_true(await until(soon, 1.0))


func test_test_nodes_are_freed_after_the_test() -> void:
	var node: Node = add_test_node(Node.new())
	assert_true(node.is_inside_tree())
	assert_has(_test_nodes, node)


func test_expected_error_does_not_fail() -> void:
	expect_error("expected by the test")
	push_error("expected by the test")


func test_input_is_just_pressed_in_physics() -> void:
	if not InputMap.has_action(&"ui_accept"):
		skip("no ui_accept action")
		return
	var input: TestInput = add_test_node(TestInput.new())
	var probe: _Probe = add_test_node(_Probe.new())
	input.tap(&"ui_accept")
	await physics_frames(3)
	assert_eq(probe.just_pressed, 1, "just pressed seen once in _physics_process")
	assert_eq(probe.pressed, 1, "a tap lasts one physics frame")


# Compte ce que voit un nœud de jeu dans _physics_process.
class _Probe:
	extends Node
	var just_pressed: int = 0
	var pressed: int = 0

	func _physics_process(_delta: float) -> void:
		if Input.is_action_just_pressed(&"ui_accept"):
			just_pressed += 1
		if Input.is_action_pressed(&"ui_accept"):
			pressed += 1
