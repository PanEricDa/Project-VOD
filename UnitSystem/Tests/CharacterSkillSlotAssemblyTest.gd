extends SceneTree

## 验证角色场景的技能槽引用自己的原始技能节点。

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	_check_scene("Guardian", ["GuardianShieldSkill", "GuardianTauntSkill"])
	_check_scene("Priest", ["HolyLightSkill", "GreaterHealSkill"])
	_check_scene("Caster", ["FireboltSkill", ""])
	_check_scene("Archer", ["", ""])
	_check_scene("Saber", ["", ""])
	var priest_scene := load("res://UnitSystem/AI/Ally/Units/Priest.tscn") as PackedScene
	var first := priest_scene.instantiate() as Node3D
	var second := priest_scene.instantiate() as Node3D
	root.add_child(first)
	root.add_child(second)
	var first_host := first.get_node(^"SkillHost") as SkillHostComponent
	var second_host := second.get_node(^"SkillHost") as SkillHostComponent
	_expect(first_host.get_regular_skill(0) != null, "First Priest has HolyLight equipped")
	_expect(second_host.get_regular_skill(0) != null, "Second Priest has HolyLight equipped")
	_expect(first_host.get_regular_skill(0) != second_host.get_regular_skill(0), "Two Priests own separate skill instances")
	var first_skill := first_host.get_regular_skill(0)
	var second_skill := second_host.get_regular_skill(0)
	if first_skill != null and second_skill != null:
		first_skill._start_cooldown()
		_expect(not first_skill.is_ready() and second_skill.is_ready(), "Cooldown does not leak between instances")
		first_skill.reset_skill()
	var persisted := PackedScene.new()
	_expect(persisted.pack(first) == OK, "Can pack equipped Priest")
	var temporary_path := "user://skill_slot_contract_roundtrip_%d.tscn" % Time.get_ticks_usec()
	_expect(ResourceSaver.save(persisted, temporary_path) == OK, "Can save equipped Priest copy")
	var reloaded := ResourceLoader.load(temporary_path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	_expect(reloaded != null, "Equipped Priest copy reloads")
	if reloaded != null:
		var restored := reloaded.instantiate() as Node3D
		root.add_child(restored)
		var restored_host := restored.get_node(^"SkillHost") as SkillHostComponent
		_expect(restored_host.get_regular_skill(0) == restored.get_node(^"SkillHost/SkillSocket/HolyLightSkill"), "Saved slot resolves to reloaded node")
		restored.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary_path))
	first.free()
	second.free()
	if failures.is_empty():
		print("CharacterSkillSlotAssemblyTest: PASS")
	else:
		for failure: String in failures:
			push_error(failure)
	quit(0 if failures.is_empty() else 1)


func _check_scene(unit_name: String, skill_names: Array[String]) -> void:
	var path := "res://UnitSystem/AI/Ally/Units/%s.tscn" % unit_name
	var scene := load(path) as PackedScene
	_expect(scene != null, "%s scene loads" % unit_name)
	if scene == null:
		return
	var unit := scene.instantiate() as Node3D
	root.add_child(unit)
	var host := unit.get_node(^"SkillHost") as SkillHostComponent
	for index: int in range(2):
		var actual := host.get_regular_skill(index)
		if skill_names[index].is_empty():
			_expect(actual == null, "%s slot %d empty" % [unit_name, index])
		else:
			var expected := unit.get_node("SkillHost/SkillSocket/%s" % skill_names[index])
			_expect(actual == expected, "%s slot %d references original node" % [unit_name, index])
	_expect(host.get_finisher_skill() == null, "%s finisher empty" % unit_name)
	unit.free()


func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
