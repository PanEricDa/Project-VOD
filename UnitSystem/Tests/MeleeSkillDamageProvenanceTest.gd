extends SceneTree
## 外部近战必须使用动作快照，不能把非空元数据误变成空技能的攻击 payload。
var failures: Array[String] = []
func _initialize() -> void: call_deferred(&"_run")
func _run() -> void:
	if not SkillContext.new().get_property_list().any(func(p): return p.name == &"damage_context"):
		failures.append("melee provenance not implemented")
		_finish()
		return
	var world = Node3D.new()
	root.add_child(world)
	var guardian = load("res://UnitSystem/AI/Ally/Units/Guardian.tscn").instantiate()
	guardian.automatic_skill_cast_enabled = false
	world.add_child(guardian)
	var target = load("res://UnitSystem/Base/00_UnitBase.tscn").instantiate()
	target.team_id = 2
	target.maximum_health = 1000.0
	world.add_child(target)
	target.position = Vector3(0.2, 0, 0)
	var host = guardian.get_node("SkillHost")
	host.configure_owner(guardian, world)
	var skill = host.get_regular_skill(0)
	var context = SkillContext.new()
	context.caster = guardian
	context.requested_target = target
	context.explicit_target_requested = true
	context.delivery_parent = world
	context.set("damage_context", CombatDamageContext.create(guardian, world, CombatDamageContext.Origin.CHAIN, 81, 82))
	var events: Array = []
	target.damage_resolved.connect(func(e): events.append(e))
	_expect(host._begin_decision(skill, context), "melee action begins")
	var payload = skill.get_action_payload()
	_expect(payload.has("damage_context"), "external action carries metadata")
	var system = guardian.get_combat_system()
	system._apply_resolved_hit_damage(target, 1)
	_expect(events.size() == 1 and events[0].origin == 2 and events[0].request_id == 81, "actual external melee forwards metadata")
	system._apply_basic_attack_damage(target, 1)
	_expect(events.size() == 2 and events[1].origin == 1, "basic attack stays normal during external skill")
	var empty = SkillBase.new()
	_expect(empty.get_action_payload().is_empty(), "empty payload remains empty")
	empty.free()
	var archer = load("res://UnitSystem/AI/Ally/Units/Archer.tscn").instantiate()
	archer.automatic_skill_cast_enabled = false
	world.add_child(archer)
	archer.position = Vector3(0, 0, -4)
	archer.set_physics_process(false)
	guardian.set_physics_process(false)
	current_scene = world
	for _i in range(3): await physics_frame
	var ranged_system = archer.get_combat_system()
	var controller = ranged_system.get_attack_controller()
	controller.projectile_release_requested.emit(ranged_system.get_equipped_weapon(), target, 1, Vector3.FORWARD)
	var ranged_host = archer.get_node("SkillHost")
	var ranged_skill = ranged_host.get_regular_skill(0)
	var ranged_context = SkillContext.new()
	ranged_context.caster = archer
	ranged_context.requested_target = target
	ranged_context.explicit_target_requested = true
	ranged_context.delivery_parent = world
	ranged_context.damage_context = CombatDamageContext.create(archer, world, CombatDamageContext.Origin.CHAIN, 181, 182)
	_expect(ranged_host._begin_decision(ranged_skill, ranged_context), "other ranged action starts after ordinary projectile launch")
	for _i in range(40): await physics_frame
	var delayed_normal_seen = false
	for e in events:
		if e.source_instance_id == archer.get_instance_id() and e.origin == CombatDamageContext.Origin.NORMAL:
			delayed_normal_seen = true
			_expect(e.request_id == 0 and e.scene_scope_id == world.get_instance_id(), "late normal projectile callback keeps normal identity")
	_expect(delayed_normal_seen, "real ordinary projectile damages through controller while other skill runs")
	world.free()
	_finish()
func _expect(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
func _finish() -> void:
	for f in failures: push_error(f)
	if failures.is_empty(): print("MeleeSkillDamageProvenanceTest: PASS")
	quit(0 if failures.is_empty() else 1)
