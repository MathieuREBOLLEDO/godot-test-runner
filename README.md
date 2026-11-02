# Test Runner

Tests automatiques pour Godot 4.5+ (GDScript typé), sans dépendance : un
runner headless, une base de tests (`TestCase`) et un pilote d'entrées
(`TestInput`). Pas de plugin à activer.

## Lancer

```
godot --headless --fixed-fps 60 --path <projet> res://addons/test_runner/runner.tscn -- [options]
```

- `--dir=res://game/gameplay` : dossier(s) où chercher, séparés par des
  virgules (défaut : `res://`).
- `--filter=hat` : seulement les fichiers ou les tests dont le nom contient
  ce texte.
- `--timeout=30` : secondes de jeu au plus par test.

Sortie 0 si tout passe, 1 sinon (ou si aucun test n'est trouvé).
`--fixed-fps 60` : chaque image vaut 1/60 s, quel que soit le temps réel ;
les tests vont aussi vite que la machine et restent déterministes.
Après la création d'un fichier avec un `class_name` nouveau, lancer d'abord
`godot --headless --path <projet> --import`.

Le runner est lancé comme scène (et non avec `-s`) : les autoloads existent
avant que les tests soient compilés.

## Écrire un test

Un fichier `test_*.gd` rangé dans un dossier `tests/`, qui étend `TestCase` :
chaque méthode `test_*` est un test.

```gdscript
extends TestCase

func test_addition() -> void:
	assert_eq(2 + 2, 4)

func test_falls() -> void:
	var body: RigidBody2D = add_test_node(RigidBody2D.new())
	await seconds(0.5)
	assert_gt(body.position.y, 0.0, "fell")
```

- `before_all()`, `after_all()`, `before_each()`, `after_each()` : à
  redéfinir (penser à `super()` si la base en a un).
- Attendre : `await seconds(t)`, `await physics_frames(n)`,
  `await frames(n)`, `await until(condition, max_seconds)` (rend faux si le
  délai passe).
- Asserts : `assert_true`, `assert_false`, `assert_eq`, `assert_ne`,
  `assert_almost(actual, expected, tolerance)` (float, Vector2, Vector3),
  `assert_gt`, `assert_lt`, `assert_between`, `assert_null`,
  `assert_not_null`, `assert_has`, `fail(message)`. Un assert raté n'arrête
  pas le test ; ils rendent `true` si ça passe :
  `if not assert_not_null(x): return`.
- `add_test_node(node)` : ajoute sous le fichier de tests ; libéré après le
  test.
- `expect_error("texte")` : une erreur contenant ce texte est attendue.
- `skip("raison")` : test sauté, compté à part.

Un test échoue aussi si :
- une erreur moteur, de script ou un `push_error` arrive pendant qu'il tourne
  (relevées par un `Logger`, `OS.add_logger`) ; les avertissements ne
  comptent pas ;
- il dépasse le délai (test bloqué, ou arrêté par une erreur de script).

Après chaque test : nœuds du test libérés, pause levée, `Engine.time_scale`
remis à 1.

## Entrées

`TestInput` appuie sur les actions au début de l'image de physique, avant
les autres nœuds : `is_action_just_pressed()` les voit dans
`_physics_process()`, ce que `Input.action_press()` appelé depuis un test ne
garantit pas.

```gdscript
var input: TestInput = add_test_node(TestInput.new())
input.tap(&"jump")              # une image de physique
input.hold(&"move_right", 1.0)  # une seconde
input.press(&"jump")            # jusqu'à release()
input.release(&"jump")
```

## Tests de l'addon

`tests/test_test_runner.gd` : asserts, attente, nœuds libérés, erreurs
attendues, entrées vues par la physique.
