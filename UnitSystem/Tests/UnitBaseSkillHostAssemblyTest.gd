extends SceneTree

## 验证 UnitBase 只提供统一技能插槽，而不在 UnitBase.gd 中承担技能逻辑。

const UNIT_BASE_SCENE_PATH := "res://UnitSystem/Base/00_UnitBase.tscn"

var failures: Array[String] = []


func _initialize() -> void:
	var unit_scene := load(UNIT_BASE_SCENE_PATH) as PackedScene
	_expect(unit_scene != null, "UnitBase scene loads")
	if unit_scene == null:
		_finish()
		return

	var unit: Node3D = unit_scene.instantiate() as Node3D
	_expect(unit != null, "UnitBase scene instantiates")
	if unit == null:
		_finish()
		return
	root.add_child(unit)
	await process_frame

	var skill_host: Node = unit.get_node_or_null(^"SkillHost")
	_expect(skill_host != null, "UnitBase provides SkillHost")
	if skill_host != null:
		_expect(
			skill_host is SkillHostComponent,
			"UnitBase mounts the new single-scene SkillHost exactly once"
		)
		_expect(
			skill_host.get_node_or_null(^"SkillSocket") != null,
			"SkillHost provides SkillSocket"
		)
		_expect(
			skill_host.call("get_skill_owner") == unit,
			"SkillHost automatically uses UnitBase as caster"
		)
		var property_names: Array[StringName] = []
		for property: Dictionary in skill_host.get_property_list():
			property_names.append(
				StringName(property.get("name", &""))
			)
		for obsolete_property: StringName in [
			&"skill_owner",
			&"skill_socket_path",
			&"delivery_parent_path",
		]:
			_expect(
				obsolete_property not in property_names,
				"SkillHost does not duplicate %s" % obsolete_property
			)
	_expect(
		unit.find_children("*", "SkillHostComponent", true, false).size() == 1,
		"UnitBase contains one SkillHostComponent"
	)
	_expect(
		not unit.is_in_group(&"skill_target_candidates"),
		"UnitBase no longer registers the obsolete global skill candidate group"
	)

	root.remove_child(unit)
	unit.free()
	_finish()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("UnitBaseSkillHostAssemblyTest: PASS")
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	quit(1)
