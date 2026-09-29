extends SceneTree

## 锁定同一技能实例的普通动作请求与独立实例的直接触发契约。

var failures: Array[String] = []

class TestUnit:
	extends Node3D
	var faction: StringName = &"ally"
	func is_targetable() -> bool: return true
	func is_dead() -> bool: return false
	func is_hostile_to(other: Node) -> bool:
		return other is TestUnit and other.faction != faction
	func is_friendly_to(other: Node) -> bool:
		return other is TestUnit and other.faction == faction
	func is_neutral_to(_other: Node) -> bool: return false

class RecordingEffect:
	extends SkillEffectBase
	var hits: int = 0
	func apply(_context: SkillContext, _result: SkillDeliveryResult, _target: Node3D) -> bool:
		hits += 1
		return true

class RejectCondition:
	extends SkillConditionBase
	var checks: int = 0
	func evaluate(_context: SkillContext) -> bool:
		checks += 1
		return false

class RejectCost:
	extends SkillCostBase
	func can_pay(_context: SkillContext) -> bool: return false

func _initialize() -> void:
	call_deferred(&"_run")

func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var caster := TestUnit.new()
	world.add_child(caster)
	var near_target := TestUnit.new()
	near_target.faction = &"enemy"
	near_target.position = Vector3(2, 0, 0)
	world.add_child(near_target)
	var far_target := TestUnit.new()
	far_target.faction = &"enemy"
	far_target.position = Vector3(20, 0, 0)
	world.add_child(far_target)

	var ordinary := _new_skill(world, caster)
	var ordinary_requests := [0]
	ordinary.action_requested.connect(func(_skill: SkillBase, _target: Node3D, _time: float) -> void:
		ordinary_requests[0] += 1
	)
	_expect(ordinary.request_skill(_context(caster, near_target, world)), "ordinary request is accepted")
	_expect(ordinary_requests[0] == 1, "ordinary request asks for a character action")
	ordinary.cancel_skill()

	var direct := _new_skill(world, caster)
	if not direct.has_method(&"activate"):
		_expect(false, "SkillBase exposes the shared activate(context) entry")
		_finish(world)
		return
	var direct_requests := [0]
	var releases := [0]
	var deliveries := [0]
	direct.action_requested.connect(func(_skill: SkillBase, _target: Node3D, _time: float) -> void:
		direct_requests[0] += 1
	)
	direct.release_started.connect(func(_context: SkillContext) -> void:
		releases[0] += 1
	)
	direct.delivery_started.connect(func(_context: SkillContext) -> void:
		deliveries[0] += 1
	)
	var missing_origin := _context(caster, far_target, world)
	missing_origin.set("execution_mode", 1)
	_expect(not bool(direct.call(&"activate", missing_origin)), "direct trigger rejects a missing launch origin")
	var trigger := _context(caster, far_target, world)
	trigger.request_source = SkillContext.RequestSource.AI_AUTOMATIC
	trigger.set("execution_mode", 1)
	trigger.set("activation_transform", Transform3D(Basis.IDENTITY, Vector3(19, 0, 0)))
	_expect(bool(direct.call(&"activate", trigger)), "direct trigger casts from impact origin, not distant caster")
	_expect(direct_requests[0] == 0, "direct trigger never asks for a character action")
	_expect(releases[0] == 1 and deliveries[0] == 1, "direct trigger uses release and delivery signals")
	_expect((direct.get_node("RecordingEffect") as RecordingEffect).hits == 1, "direct trigger applies the usual Effect")
	_expect(direct.is_ready(), "zero-cooldown trigger instance becomes ready again")
	var copied := trigger.duplicate_context() as SkillContext
	_expect(copied.get("execution_mode") == 1, "execution mode survives context copying")
	_expect((copied.get("activation_transform") as Transform3D).origin == Vector3(19, 0, 0), "launch origin survives context copying")

	var conditioned := _new_skill(world, caster)
	var condition := RejectCondition.new()
	condition.application_scope = SkillConditionBase.ApplicationScope.ALL_REQUESTS
	conditioned.add_child(condition)
	_expect(not bool(conditioned.call(&"activate", trigger)), "all-requests condition rejects direct trigger")
	_expect(condition.checks == 1, "direct trigger evaluates all-requests condition")
	condition.application_scope = SkillConditionBase.ApplicationScope.AUTOMATIC_ONLY
	_expect(bool(conditioned.call(&"activate", trigger)), "direct trigger is explicit even when parent was AI")
	_expect(condition.checks == 1, "automatic-only condition is skipped for direct trigger")

	var costly := _new_skill(world, caster)
	costly.add_child(RejectCost.new())
	_expect(not bool(costly.call(&"activate", trigger)), "child instance still checks its own cost")
	_finish(world)

func _new_skill(world: Node3D, caster: TestUnit) -> SkillBase:
	var scene := load("res://SkillSystem/01-Core/SkillBase.tscn") as PackedScene
	var skill := scene.instantiate() as SkillBase
	skill.target_relations = TargetResolver.TargetRelationFlag.HOSTILE
	skill.cast_range = 3.0
	skill.skill_cooldown = 0.0
	skill.delivery = InstantTargetDeliveryConfig.new()
	var effect := RecordingEffect.new()
	effect.name = "RecordingEffect"
	skill.add_child(effect)
	world.add_child(skill)
	skill.configure_owner(caster, null, world)
	return skill

func _context(caster: TestUnit, target: TestUnit, world: Node3D) -> SkillContext:
	var context := SkillContext.new()
	context.caster = caster
	context.requested_target = target
	context.explicit_target_requested = true
	context.delivery_parent = world
	return context

func _expect(value: bool, message: String) -> void:
	if not value:
		failures.append(message)

func _finish(world: Node3D) -> void:
	world.free()
	for failure: String in failures:
		push_error(failure)
	if failures.is_empty():
		print("TriggeredSkillActivationTest: PASS")
	quit(0 if failures.is_empty() else 1)
