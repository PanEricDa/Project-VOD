extends SceneTree

const BASE_SCENE_PATH := "res://UnitSystem/Components/Combat/AI/AICombatSystem.tscn"
const MELEE_SCENE_PATH := "res://UnitSystem/Components/Combat/AI/AIMeleeCombatSystem.tscn"
const RANGED_SCENE_PATH := "res://UnitSystem/Components/Combat/AI/AIRangedCombatSystem.tscn"

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var base := _instantiate(BASE_SCENE_PATH)
	_expect(base is AICombatSystem, "generic combat base instantiates")
	_expect(base.get_node_or_null(^"MeleeHitbox") == null, "base contains no melee delivery")

	var melee := _instantiate(MELEE_SCENE_PATH)
	_expect(melee is AIMeleeCombatSystem, "melee combat inherits the generic base")
	_expect(melee.get_node_or_null(^"MeleeHitbox") is MeleeHitboxComponent, "melee combat owns hitbox delivery")

	var ranged := _instantiate(RANGED_SCENE_PATH)
	_expect(ranged is AIRangedCombatSystem, "ranged combat inherits the generic base")
	_expect(ranged.get_node_or_null(^"MeleeHitbox") == null, "ranged combat does not include melee hitbox")

	for node: Node in [base, melee, ranged]:
		if is_instance_valid(node):
			node.free()
	_finish()


func _instantiate(scene_path: String) -> Node:
	var scene := load(scene_path) as PackedScene
	if scene == null:
		_failures.append("scene loads: " + scene_path)
		return Node.new()
	return scene.instantiate()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("AICombatInheritanceTest: PASS")
		quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	quit(1)
