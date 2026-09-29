extends SceneTree

## 槽位引用的索引、有效性及生命周期契约。

const HOST_SCENE := preload("res://SkillSystem/01-Core/SkillHostComponent.tscn")
const SKILL_SCENE := preload("res://SkillSystem/01-Core/SkillBase.tscn")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	var caster := Node3D.new()
	root.add_child(caster)
	var host := HOST_SCENE.instantiate() as SkillHostComponent
	caster.add_child(host)
	var socket := host.get_node(^"SkillSocket")
	var a := _add_skill(host, socket, &"slot_a")
	var b := _add_skill(host, socket, &"slot_b")
	var outsider := Node3D.new()
	root.add_child(outsider)
	var foreign := SKILL_SCENE.instantiate() as SkillBase
	foreign.skill_id = &"foreign"
	outsider.add_child(foreign)

	_expect(host.get("regular_skills") is Array and (host.get("regular_skills") as Array).size() == 2, "Two default regular slots")
	_expect(host.get("finisher_skill") == null, "Empty default finisher")
	if not host.has_method(&"get_regular_skill"):
		_expect(false, "Host must expose regular slot lookup")
		_finish(caster, outsider)
		return

	var sparse: Array[SkillBase] = [null, a, null]
	host.regular_skills = sparse
	_expect(host.call("get_regular_skill", 0) == null, "Empty slot stays empty")
	_expect(host.call("get_regular_skill", 1) == a, "Sparse slot retains index")
	_expect(host.call("get_regular_skill", -1) == null, "Negative index is safe")
	_expect(host.call("get_regular_skill", 3) == null, "Oversized index is safe")
	var equipped := host.call("get_equipped_regular_skills") as Array
	_expect(equipped.size() == 1 and equipped[0] == a, "Only valid slots are listed")
	equipped.clear()
	_expect(host.call("get_regular_skill", 1) == a, "Returned list is a copy")

	var conflicting: Array[SkillBase] = [a, a, foreign, b]
	host.regular_skills = conflicting
	_expect(host.call("get_regular_skill", 0) == a, "First duplicate keeps slot")
	_expect(host.call("get_regular_skill", 1) == null, "Later duplicate is invalid")
	_expect(host.call("get_regular_skill", 2) == null, "Foreign node is invalid")
	_expect(host.call("get_regular_skill", 3) == b, "Later valid slot stays indexed")
	host.set("finisher_skill", a)
	_expect(host.call("get_finisher_skill") == null, "Regular slot wins duplicate finisher")
	var warnings: PackedStringArray = host._get_configuration_warnings()
	_expect(warnings.size() >= 2, "Conflicting references show editor warnings")

	var only_b: Array[SkillBase] = [b]
	host.regular_skills = only_b
	host.set("finisher_skill", a)
	_expect(host.call("get_finisher_skill") == a, "Independent finisher is valid")
	host.unregister_skill(a)
	_expect(host.call("get_finisher_skill") == null, "Unregistered finisher is invalid")
	var duplicate_id := SKILL_SCENE.instantiate() as SkillBase
	duplicate_id.skill_id = b.skill_id
	socket.add_child(duplicate_id)
	_expect(not host.register_skill(duplicate_id), "Duplicate skill ID cannot register")
	var duplicate_slots: Array[SkillBase] = [b, duplicate_id]
	host.regular_skills = duplicate_slots
	_expect(host.call("get_regular_skill", 1) == null, "Rejected duplicate ID cannot equip")
	var duplicate_warning_found := false
	for warning: String in host._get_configuration_warnings():
		if "常规槽 1" in warning and "ID" in warning:
			duplicate_warning_found = true
	_expect(duplicate_warning_found, "Duplicate ID warning identifies invalid slot")
	duplicate_id.free()
	host.unregister_skill(b)
	_expect(host.call("get_regular_skill", 0) == null, "Unregistered regular skill is invalid")
	_expect(host.register_skill(b), "Skill can be registered again")
	b.queue_free()
	_expect(host.call("get_regular_skill", 0) == null, "Queued deletion invalidates slot immediately")
	await process_frame
	_expect(host.call("get_regular_skill", 0) == null, "Freed skill remains invalid")
	var replacement := SKILL_SCENE.instantiate() as SkillBase
	replacement.skill_id = &"slot_b"
	socket.add_child(replacement)
	_expect(host.register_skill(replacement), "Freed registration does not reserve old skill ID")
	_finish(caster, outsider)


func _add_skill(host: SkillHostComponent, socket: Node, id: StringName) -> SkillBase:
	var skill := SKILL_SCENE.instantiate() as SkillBase
	skill.name = String(id)
	skill.skill_id = id
	socket.add_child(skill)
	_expect(host.register_skill(skill), "Register %s" % id)
	return skill


func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)


func _finish(caster: Node3D, outsider: Node3D) -> void:
	caster.free()
	outsider.free()
	if failures.is_empty():
		print("SkillSlotContractTest: PASS")
	else:
		for failure: String in failures:
			push_error(failure)
	quit(0 if failures.is_empty() else 1)
