extends SceneTree

## 契约：AI 启动定向技能动作前，必须能把 Visual 的世界正前方精确对齐到目标方向。
const AI_UNIT_SCENE_PATH := "res://UnitSystem/Base/AIUnitBase.tscn"
const ALLY_VISUAL_SCENE_PATH := "res://UnitSystem/Visuals/Ally/AllyVisual.tscn"

func _init() -> void:
	call_deferred(&"_run")


func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var unit := (load(AI_UNIT_SCENE_PATH) as PackedScene).instantiate() as AIUnitBase
	var visual := (load(ALLY_VISUAL_SCENE_PATH) as PackedScene).instantiate() as Node3D
	world.add_child(unit)
	unit.get_node(^"Visual").add_child(visual)
	await process_frame
	if not unit.has_method(&"snap_visual_facing"):
		_fail("AIUnitBase must expose snap_visual_facing for action-start facing")
		return
	unit.call(&"snap_visual_facing", Vector3.RIGHT)
	var forward := -visual.global_basis.z
	forward.y = 0.0
	if forward.normalized().dot(Vector3.RIGHT) < 0.999:
		_fail("Visual forward does not match the requested world direction")
		return
	print("PASS: AI skill-facing snap aligns Visual to world direction")
	quit()


func _fail(message: String) -> void:
	push_error("FAIL: " + message)
	quit(1)
