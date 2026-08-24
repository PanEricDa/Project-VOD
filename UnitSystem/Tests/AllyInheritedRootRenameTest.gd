extends SceneTree

const ALLY_SCENE_PATH: String = \
	"res://UnitSystem/AI/Ally/Units/Saber.tscn"

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var saber_scene := load(ALLY_SCENE_PATH) as PackedScene
	_expect(saber_scene != null, "Saber inherited scene loads")
	if saber_scene == null:
		_finish()
		return

	var saber := saber_scene.instantiate() as AllyBase
	_expect(saber != null, "Saber inherited scene instantiates")
	if saber == null:
		_finish()
		return
	_expect(saber.name == &"Saber", "inherited Ally root keeps its custom name")

	var behavior := saber.get_node(
		^"BehaviorStateMachine"
	) as AllyBehaviorStateMachine
	_expect(behavior != null, "Saber retains BehaviorStateMachine")
	if behavior != null:
		_expect(
			behavior.get("player_path") == null,
			"Saber no longer stores a fragile external player path"
		)
		_expect(
			typeof(behavior.follow_target_facing_node_path) == TYPE_STRING,
			"follow target facing path is stored as String"
		)
		_expect(
			str(behavior.follow_target_facing_node_path) == "Visual",
			"Saber keeps the default visual-facing path for its follow target"
		)

	saber.free()
	_finish()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("AllyInheritedRootRenameTest: PASS")
		quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	print(
		"AllyInheritedRootRenameTest: FAIL (%d)"
		% _failures.size()
	)
	quit(1)
