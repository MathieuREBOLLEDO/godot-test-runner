class_name TestInput
extends Node

## Appuie sur des actions d'entrée pour un test.
## Les appuis sont faits au début de l'image de physique, avant les autres
## nœuds (process_physics_priority très bas) : is_action_just_pressed() les
## voit dans _physics_process(), ce que Input.action_press() appelé depuis un
## test (après un await) ne garantit pas.
## Les actions encore tenues sont relâchées quand le nœud quitte l'arbre.

# Action -> images de physique restantes (-1 : jusqu'à release()).
var _held: Dictionary[StringName, int] = {}
# Appuis et relâchements à faire à la prochaine image de physique.
var _to_press: Dictionary[StringName, int] = {}
var _to_release: Array[StringName] = []


func _init() -> void:
	process_physics_priority = -1000
	process_mode = Node.PROCESS_MODE_ALWAYS


## Appuie sur action à la prochaine image de physique, jusqu'à release().
func press(action: StringName) -> void:
	_to_press[action] = -1


## Appuie sur action pendant physics_frames images de physique.
func tap(action: StringName, physics_frames: int = 1) -> void:
	_to_press[action] = maxi(physics_frames, 1)


## Appuie sur action pendant t secondes.
func hold(action: StringName, t: float) -> void:
	tap(action, ceili(t * Engine.physics_ticks_per_second))


## Relâche action à la prochaine image de physique.
func release(action: StringName) -> void:
	_to_press.erase(action)
	_to_release.append(action)


func release_all() -> void:
	for action: StringName in _held:
		Input.action_release(action)
	_held.clear()
	_to_press.clear()
	_to_release.clear()


func is_holding(action: StringName) -> bool:
	return _held.has(action) or _to_press.has(action)


func _physics_process(_delta: float) -> void:
	# Fin des appuis limités, comptés depuis l'image précédente.
	for action: StringName in _held.keys():
		if _held[action] > 0:
			_held[action] -= 1
			if _held[action] == 0:
				_to_release.append(action)
	for action: StringName in _to_release:
		Input.action_release(action)
		_held.erase(action)
	_to_release.clear()
	for action: StringName in _to_press:
		Input.action_press(action)
		_held[action] = _to_press[action]
	_to_press.clear()


func _exit_tree() -> void:
	release_all()
