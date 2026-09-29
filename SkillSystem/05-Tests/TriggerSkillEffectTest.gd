extends SceneTree

## 子技能仅依本次实际伤害与命中前状态触发，分支失败不撤销父技能。

const TRIGGER_PATH := "res://SkillSystem/03-Extensions/TriggerSkillEffect.gd"
const UNIT_PATH := "res://UnitSystem/Base/00_UnitBase.tscn"
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	if not ResourceLoader.exists(TRIGGER_PATH):
		_expect(false, "generic TriggerSkillEffect exists")
		_finish()
		return
	var world := Node3D.new()
	root.add_child(world)
	var caster := _unit(world, 1, Vector3.ZERO)
	var hit_target := _unit(world, 2, Vector3(15, 0, 0))
	var a := _unit(world, 2, Vector3(16, 0, 0))
	var b := _unit(world, 2, Vector3(17, 0, 0))
	var c := _unit(world, 2, Vector3(17.5, 0, 0))
	for _frame in range(3):
		await physics_frame
	var trigger := (load(TRIGGER_PATH) as Script).new() as SkillEffectBase
	world.add_child(trigger)
	var child_scene := _child_skill_scene()
	trigger.set("child_skill_scene", child_scene)
	trigger.set("radius_m", 3.0)
	trigger.set("max_targets", 2)
	trigger.set("required_status_id", &"burning")
	var context := SkillContext.new()
	context.caster = caster
	context.delivery_parent = world
	var result := SkillDeliveryResult.new()
	result.current_hit = SkillHitOutcome.new()
	result.current_hit.target = hit_target
	result.current_hit.impact_position = hit_target.global_position
	var original_a := a.get_current_health()
	var original_b := b.get_current_health()
	var original_c := c.get_current_health()
	_expect(trigger.apply(context, result, hit_target), "zero damage safely skips trigger")
	_expect(a.get_current_health() == original_a, "zero damage creates no child hit")
	result.current_hit.actual_damage = 10.0
	_expect(trigger.apply(context, result, hit_target), "missing pre-hit status safely skips trigger")
	_expect(a.get_current_health() == original_a, "missing status creates no child hit")
	hit_target.get_status_effect_component().apply_named_status(&"burning", 4.0)
	_expect(trigger.apply(context, result, hit_target), "same-hit status does not retroactively qualify")
	_expect(a.get_current_health() == original_a, "same-hit status does not create child hit")
	result.current_hit.statuses_before_hit.append(&"burning")
	_expect(trigger.apply(context, result, hit_target), "positive damage with pre-hit status triggers child skills")
	_expect(is_equal_approx(original_a - a.get_current_health(), 4.0), "nearest child target takes damage")
	_expect(is_equal_approx(original_b - b.get_current_health(), 4.0), "second child target takes damage")
	_expect(is_equal_approx(original_c - c.get_current_health(), 0.0), "configured max_targets limits branches")
	var children := world.get_children().filter(func(node: Node) -> bool: return node is SkillBase)
	_expect(children.size() == 2, "two independent child skill instances created")
	if children.size() == 2:
		_expect(children[0].get_instance_id() != children[1].get_instance_id(), "sibling branches never share one SkillBase instance")
	await process_frame
	_expect(world.get_children().filter(func(node: Node) -> bool: return node is SkillBase).is_empty(), "completed child skills are released")

	# 即使子技能自身无法支付成本，本 Effect 仍成功并保留父技能已造成的伤害。
	var expensive_scene := _child_skill_scene(true)
	trigger.set("child_skill_scene", expensive_scene)
	var before_failure := a.get_current_health()
	_expect(trigger.apply(context, result, hit_target), "unpayable child branch does not fail parent effect")
	_expect(a.get_current_health() == before_failure, "unpayable child causes no extra damage")
	await process_frame
	_expect(world.get_children().filter(func(node: Node) -> bool: return node is SkillBase).is_empty(), "failed child branches are released")
	var conditional_scene := _child_skill_scene(false, true)
	trigger.set("child_skill_scene", conditional_scene)
	a.apply_healing(a.maximum_health, caster)
	b.apply_damage(10.0, caster)
	var before_a := a.get_current_health()
	var before_b := b.get_current_health()
	_expect(trigger.apply(context, result, hit_target), "one rejected branch does not fail the sibling branch")
	_expect(a.get_current_health() == before_a, "full-health candidate fails child-owned condition")
	_expect(is_equal_approx(before_b - b.get_current_health(), 4.0), "injured sibling still completes its child skill")
	await process_frame
	_expect(world.get_children().filter(func(node: Node) -> bool: return node is SkillBase).is_empty(), "mixed success and failure branches release both instances")

	var firebolt_scene := load("res://SkillSystem/00-Skills/Firebolt/FireboltSkill.tscn") as PackedScene
	trigger.set("child_skill_scene", firebolt_scene)
	context.trigger_scene_paths = [firebolt_scene.resource_path]
	_expect(trigger.apply(context, result, hit_target), "ancestor scene path rejects indirect trigger cycle")
	_expect(world.get_children().filter(func(node: Node) -> bool: return node is SkillBase).is_empty(), "cycle guard creates no child instance")
	context.trigger_scene_paths.clear()
	var parent_skill := firebolt_scene.instantiate() as SkillBase
	world.add_child(parent_skill)
	var self_trigger := (load(TRIGGER_PATH) as Script).new() as SkillEffectBase
	self_trigger.set("child_skill_scene", firebolt_scene)
	parent_skill.add_child(self_trigger)
	_expect(self_trigger.apply(context, result, hit_target), "direct self-reference safely ends without recursion")
	_expect(world.get_children().filter(func(node: Node) -> bool: return node is SkillBase).size() == 1, "self-reference does not instantiate another skill")
	parent_skill.free()
	trigger.set("child_skill_scene", _child_skill_scene(false, false, true))
	trigger.set("required_status_id", &"")
	_expect(trigger.apply(context, result, hit_target), "arc child skills start from same trigger interface")
	await physics_frame
	_expect(world.get_children().filter(func(node: Node) -> bool: return node is SkillBase).size() == 2, "flying arc children remain alive before impact")
	for _frame in range(40):
		await physics_frame
	_expect(world.get_children().filter(func(node: Node) -> bool: return node is SkillBase).is_empty(), "arc children release after impact, not at launch")
	world.free()
	_finish()


func _child_skill_scene(expensive: bool = false, only_injured: bool = false, arc: bool = false) -> PackedScene:
	var skill := SkillBase.new()
	skill.name = "TestTriggeredSkill"
	skill.skill_cooldown = 0.0
	skill.cast_range = 4.0
	if arc:
		var arc_config := ArcProjectileDeliveryConfig.new()
		arc_config.projectile_scene = load("res://Item/Projectiles/Arrow.tscn") as PackedScene
		skill.delivery = arc_config
	else:
		skill.delivery = InstantTargetDeliveryConfig.new()
	var runner := SkillDeliveryRunner.new()
	runner.name = "DeliveryRunner"
	skill.add_child(runner)
	runner.owner = skill
	var runtime := Node.new()
	runtime.name = "RuntimeEffects"
	skill.add_child(runtime)
	runtime.owner = skill
	var damage := HealthChangeSkillEffect.new()
	damage.operation = HealthChangeSkillEffect.Operation.DAMAGE
	damage.base_amount = 4.0
	skill.add_child(damage)
	damage.owner = skill
	if expensive:
		var cost := SkillCostBase.new()
		skill.add_child(cost)
		cost.owner = skill
	if only_injured:
		var condition := TargetHealthCondition.new()
		condition.application_scope = SkillConditionBase.ApplicationScope.ALL_REQUESTS
		skill.add_child(condition)
		condition.owner = skill
	var packed := PackedScene.new()
	_expect(packed.pack(skill) == OK, "test child skill packs")
	skill.free()
	return packed


func _unit(world: Node3D, team: int, at: Vector3) -> UnitBase:
	var unit := (load(UNIT_PATH) as PackedScene).instantiate() as UnitBase
	unit.team_id = team
	unit.collision_layer = 2 if team == 1 else 4
	world.add_child(unit)
	unit.position = at
	return unit


func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)


func _finish() -> void:
	for failure: String in failures:
		push_error(failure)
	if failures.is_empty():
		print("TriggerSkillEffectTest: PASS")
	quit(0 if failures.is_empty() else 1)
