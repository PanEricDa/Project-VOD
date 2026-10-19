extends SceneTree
## 正式终结技能的可配置参数不得在角色或继承预览中重复序列化，避免策划跨文件同步。
var failures: Array[String] = []
func _initialize() -> void:
	for path: String in ["res://UnitSystem/AI/Ally/Units/Caster.tscn","res://Scenes/Previews/SquadFinisherSelectionPreview.tscn","res://Scenes/Previews/SquadFinisherComparisonPreview.tscn"]:
		var scene := load(path) as PackedScene
		var state := scene.get_state()
		for i: int in range(state.get_node_count()):
			if not str(state.get_node_path(i)).ends_with("FlameBarrageFinisherSkill"): continue
			for j: int in range(state.get_node_property_count(i)):
				var property := state.get_node_property_name(i,j)
				if property in [&"delivery",&"cast_range",&"skill_id",&"cinematic_profile",&"release_effect_scene"]:
					failures.append(path+" redundant finisher override "+str(property))
	for failure: String in failures: printerr("FAIL: ",failure)
	print("FinisherSourceConfigurationTest: ","PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
