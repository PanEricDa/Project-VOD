extends SceneTree

const AI_SCENE_PATH: String = "res://UnitSystem/Base/AIUnitBase.tscn"
const ALLY_SCENE_PATH: String = "res://UnitSystem/AI/Ally/AllyBase.tscn"
const ENEMY_SCENE_PATH: String = "res://UnitSystem/AI/Enemy/EnemyBase.tscn"
const ALLY_VISUAL_PATH: String = (
	"res://UnitSystem/Visuals/Ally/AllyVisual.tscn"
)
const ENEMY_VISUAL_PATH: String = (
	"res://UnitSystem/Visuals/Enemy/EnemyVisual.tscn"
)

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_verify_visual_scene(ALLY_VISUAL_PATH, "ally")
	_verify_visual_scene(ENEMY_VISUAL_PATH, "enemy")

	var ai_scene := load(AI_SCENE_PATH) as PackedScene
	var ai := ai_scene.instantiate() as AIUnitBase
	_expect(ai != null, "AIUnitBase instantiates")
	if ai != null:
		var visual_slot := ai.get_node_or_null(^"Visual") as Node3D
		_expect(visual_slot != null, "AIUnitBase keeps the Visual slot")
		if visual_slot != null:
			_expect(
				visual_slot.get_child_count() == 0,
				"AIUnitBase Visual slot is empty"
			)
		ai.free()

	_verify_unit_visual_is_empty(ALLY_SCENE_PATH, "AllyBase")
	_verify_unit_mounts_one_visual(ENEMY_SCENE_PATH, "EnemyBase")
	_finish()


func _verify_visual_scene(scene_path: String, label: String) -> void:
	var packed_scene := load(scene_path) as PackedScene
	_expect(packed_scene != null, "%s visual scene loads" % label)
	if packed_scene == null:
		return
	var visual := packed_scene.instantiate() as Node3D
	_expect(visual != null, "%s visual root is Node3D" % label)
	if visual == null:
		return
	_expect(
		visual.get_node_or_null(^"CharacterRoot") is Node3D,
		"%s visual provides CharacterRoot" % label
	)
	_expect(
		visual.get_node_or_null(^"CharacterRoot/WeaponSocket") is Node3D,
		"%s visual provides WeaponSocket" % label
	)
	_expect(
		visual.get_node_or_null(^"CharacterAnimationPlayer")
			is CharacterAnimationEventPlayer,
		"%s visual provides CharacterAnimationEventPlayer" % label
	)
	visual.free()


func _verify_unit_mounts_one_visual(
	scene_path: String,
	unit_label: String
) -> void:
	var unit := (load(scene_path) as PackedScene).instantiate() as AIUnitBase
	_expect(unit != null, "%s instantiates" % unit_label)
	if unit == null:
		return
	var visual_slot := unit.get_node_or_null(^"Visual") as Node3D
	_expect(visual_slot != null, "%s keeps Visual slot" % unit_label)
	if visual_slot != null:
		_expect(
			visual_slot.get_child_count() == 1,
			"%s mounts exactly one concrete visual" % unit_label
		)
	unit.free()


func _verify_unit_visual_is_empty(
	scene_path: String,
	unit_label: String
) -> void:
	var unit := (load(scene_path) as PackedScene).instantiate() as AIUnitBase
	_expect(unit != null, "%s instantiates" % unit_label)
	if unit == null:
		return
	var visual_slot := unit.get_node_or_null(^"Visual") as Node3D
	_expect(visual_slot != null, "%s keeps Visual slot" % unit_label)
	if visual_slot != null:
		_expect(
			visual_slot.get_child_count() == 0,
			"%s leaves concrete visual mounting to child units" % unit_label
		)
	unit.free()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("AIVisualContractTest: PASS")
		quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	print("AIVisualContractTest: FAIL (%d)" % _failures.size())
	quit(1)
