extends SceneTree
## 漏传技能/碎片归属、混淆多段与同次拆分，会让本测试失败。
var failures: Array[String] = []
func _initialize() -> void: call_deferred(&"_run")
func _run() -> void:
	var probe = SkillContext.new()
	var has_field = probe.get_property_list().any(func(p): return p.name == &"damage_context")
	if not has_field:
		failures.append("SkillContext provenance not implemented")
		_finish()
		return
	var world = Node3D.new()
	root.add_child(world)
	var caster = _unit(world, Vector3.ZERO, 1)
	var a = _unit(world, Vector3(3, 0, 0), 2)
	var b = _unit(world, Vector3(3.7, 0, 0), 2)
	var events: Array = []
	a.damage_resolved.connect(func(e): events.append(e))
	b.damage_resolved.connect(func(e): events.append(e))
	var context = _context(caster, a, world)
	var copied = context.duplicate_context()
	_expect(copied.damage_context != context.damage_context and copied.damage_context.round_id == 55, "copy provenance independent")
	var runner = SkillDeliveryRunner.new()
	world.add_child(runner)
	var damage = HealthChangeSkillEffect.new()
	damage.operation = HealthChangeSkillEffect.Operation.DAMAGE
	damage.base_amount = 3.0
	world.add_child(damage)
	var damage2 = HealthChangeSkillEffect.new()
	damage2.operation = HealthChangeSkillEffect.Operation.DAMAGE
	damage2.base_amount = 4.0
	world.add_child(damage2)
	var instant = InstantTargetDeliveryConfig.new()
	var split_effects: Array[SkillEffectBase] = [damage, damage2]
	var single_effects: Array[SkillEffectBase] = [damage]
	_expect(runner.execute(instant, context, Transform3D.IDENTITY, split_effects), "instant two effects execute")
	_expect(events.size() == 2 and events[0].hit_id == events[1].hit_id and events[0].event_id != events[1].event_id, "split damage shares one hit")
	_expect(events[0].origin == 2 and events[0].actual_damage == 3.0 and events[1].actual_damage == 4.0, "literal actual damage and source")
	events.clear()
	instant.target_collection_mode = InstantTargetDeliveryConfig.TargetCollectionMode.CASTER_RADIUS
	context.candidate_targets.append(b)
	_expect(runner.execute(instant, context, Transform3D.IDENTITY, split_effects), "real multi-target instant delivery")
	_expect(events.size() == 4, "two effects for two targets")
	if events.size() == 4:
		_expect(events[0].hit_id == events[1].hit_id and events[2].hit_id == events[3].hit_id and events[0].hit_id != events[2].hit_id, "per-target shared hit, targets distinct")
	instant.target_collection_mode = InstantTargetDeliveryConfig.TargetCollectionMode.SINGLE
	events.clear()
	var arc = ArcProjectileDeliveryConfig.new()
	arc.projectile_scene = load("res://Item/Projectiles/Arrow.tscn")
	arc.shot_count = 3
	arc.shot_interval_seconds = 0.05
	for _i in range(3): await physics_frame
	_expect(runner.execute(arc, context, Transform3D(Basis.IDENTITY, Vector3.UP), single_effects), "real multishot launch")
	var host: SkillHostComponent = caster.get_node("SkillHost")
	host.configure_owner(caster, world)
	var other_skill: SkillBase = load("res://SkillSystem/01-Core/SkillBase.tscn").instantiate()
	other_skill.skill_id = &"unrelated_normal_skill"
	other_skill.delivery = InstantTargetDeliveryConfig.new()
	caster.add_child(other_skill)
	host.register_skill(other_skill)
	var normal_context = _context(caster, a, world)
	normal_context.damage_context = CombatDamageContext.create(caster, world, CombatDamageContext.Origin.NORMAL, 91, 0)
	_expect(host._begin_decision(other_skill, normal_context) and host.get_active_skill() == other_skill, "caster switches to unrelated normal action during flight")
	for _i in range(80): await physics_frame
	host.cancel_active_skill(&"test_done")
	for e in events:
		_expect(e.origin == 2 and e.request_id == 44 and e.round_id == 55, "in-flight chain not reclassified by active normal skill")
	_expect(events.size() == 3, "three actual projectile hits")
	if events.size() == 3:
		_expect(events[0].hit_id != events[1].hit_id and events[1].hit_id != events[2].hit_id, "each projectile has own hit")
	events.clear()
	var tracking = TrackingProjectileDeliveryConfig.new()
	tracking.projectile_scene = load("res://Item/Projectiles/FireBall.tscn")
	tracking.impact_radius = 1.2
	_expect(runner.execute(tracking, context, Transform3D(Basis.IDENTITY, Vector3.UP), single_effects), "real tracking projectile launch")
	for _i in range(80): await physics_frame
	_expect(events.size() == 2, "tracking area hits two targets")
	if events.size() == 2:
		_expect(events[0].hit_id != events[1].hit_id and events[0].scene_scope_id == world.get_instance_id() and events[1].request_id == 44, "tracking targets distinct IDs and root scope")
	events.clear()
	var chain = load("res://SkillSystem/00-Skills/ExplosiveArrow/ExplosiveArrowSkill.tscn").instantiate()
	world.add_child(chain)
	chain.configure_owner(caster, null, world)
	var chain_context = _context(caster, a, world)
	chain_context.execution_mode = SkillContext.ExecutionMode.DIRECT_TRIGGER
	chain_context.explicit_target_requested = true
	chain_context.activation_transform = Transform3D(Basis.IDENTITY, Vector3.UP)
	b.get_status_effect_component().apply_named_status(&"burning", 8.0)
	_expect(chain.activate(chain_context), "real chain activates")
	for _i in range(90): await physics_frame
	_expect(events.size() >= 2, "main and child damage observed")
	var child_seen = false
	var hit_ids: Dictionary = {}
	for e in events:
		_expect(e.origin == 2 and e.request_id == 44 and e.round_id == 55 and e.focus_yield_multiplier == 0.0 and e.scene_scope_id == world.get_instance_id(), "descendant inherits root scope, not current skill")
		_expect(not hit_ids.has(e.hit_id), "fragment damage uses new child hit identity")
		hit_ids[e.hit_id] = true
		if e.skill_id != chain.skill_id:
			child_seen = true
			_expect(e.skill_id != &"root" and not e.skill_id.is_empty(), "child diagnostic skill updated")
	_expect(child_seen, "internal child skill attribution observed")
	world.free()
	_finish()
func _unit(world: Node3D, at: Vector3, team: int) -> UnitBase:
	var u = load("res://UnitSystem/Base/00_UnitBase.tscn").instantiate()
	u.team_id = team
	u.maximum_health = 1000.0
	u.attack_power = 0.0
	u.collision_layer = 4 if team == 2 else 2
	if team == 2: u.add_to_group(&"enemy_targets")
	world.add_child(u)
	u.position = at
	return u
func _context(caster: UnitBase, target: UnitBase, world: Node3D) -> SkillContext:
	var c = SkillContext.new()
	c.caster = caster
	c.resolved_target = target
	c.requested_target = target
	c.candidate_targets.append(target)
	c.delivery_parent = world
	c.set("damage_context", CombatDamageContext.create(caster, world, CombatDamageContext.Origin.CHAIN, 44, 55, &"root"))
	return c
func _expect(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
func _finish() -> void:
	for f in failures: push_error(f)
	if failures.is_empty(): print("SkillDamageProvenanceTest: PASS")
	quit(0 if failures.is_empty() else 1)
