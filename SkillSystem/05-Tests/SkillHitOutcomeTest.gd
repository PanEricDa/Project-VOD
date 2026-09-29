extends SceneTree

## 每个目标在效果开始前拍摄状态快照，伤害和治疗只记录真实生命变化。

const OUTCOME_PATH := "res://SkillSystem/01-Core/SkillHitOutcome.gd"
var failures: Array[String] = []

class CaptureEffect:
	extends SkillEffectBase
	var observations: Array[Dictionary] = []
	func apply(_context: SkillContext, result: SkillDeliveryResult, target: Node3D) -> bool:
		var hit: Variant = result.get("current_hit")
		if hit == null:
			observations.append({})
			return true
		observations.append({
			"target": target,
			"damage": float(hit.get("actual_damage")),
			"healing": float(hit.get("actual_healing")),
			"statuses": (hit.get("statuses_before_hit") as Array).duplicate(),
		})
		return true

func _initialize() -> void:
	call_deferred(&"_run")

func _run() -> void:
	if not ResourceLoader.exists(OUTCOME_PATH):
		_expect(false, "per-target SkillHitOutcome type exists")
		_finish()
		return
	var world := Node3D.new()
	root.add_child(world)
	var caster := _unit(world, 1, Vector3.ZERO)
	var a := _unit(world, 2, Vector3(2, 0, 0))
	var b := _unit(world, 2, Vector3(3, 0, 0))
	var runner := SkillDeliveryRunner.new()
	world.add_child(runner)
	var config := InstantTargetDeliveryConfig.new()
	var damage := HealthChangeSkillEffect.new()
	damage.operation = HealthChangeSkillEffect.Operation.DAMAGE
	damage.base_amount = 10.0
	damage.power_ratio = 0.0
	world.add_child(damage)
	var status := ApplyNamedStatusSkillEffect.new()
	status.status_id = &"burning"
	world.add_child(status)
	var capture := CaptureEffect.new()
	world.add_child(capture)
	var effects: Array[SkillEffectBase] = [damage, status, capture]
	_expect(runner.execute(config, _context(caster, a, world), Transform3D.IDENTITY, effects), "damage/status/recording delivery succeeds")
	_expect(capture.observations.size() == 1, "one target produces one observation")
	if capture.observations.size() == 1:
		_expect(is_equal_approx(capture.observations[0].damage, 10.0), "actual damage is recorded")
		_expect(not capture.observations[0].statuses.has(&"burning"), "status added during this hit is absent from pre-hit snapshot")
	_expect(bool(a.get_status_effect_component().call(&"has_named_status", &"burning")), "status was still applied after damage")

	var zero := HealthChangeSkillEffect.new()
	zero.operation = HealthChangeSkillEffect.Operation.DAMAGE
	zero.base_amount = 0.0
	zero.power_ratio = 0.0
	world.add_child(zero)
	var zero_capture := CaptureEffect.new()
	world.add_child(zero_capture)
	var zero_effects: Array[SkillEffectBase] = [zero, zero_capture]
	_expect(runner.execute(config, _context(caster, b, world), Transform3D.IDENTITY, zero_effects), "zero damage is a successful effect execution")
	if zero_capture.observations.size() == 1:
		_expect(is_zero_approx(zero_capture.observations[0].damage), "zero actual damage stays zero")
	else:
		_expect(false, "zero damage hit has an outcome")

	config.target_collection_mode = InstantTargetDeliveryConfig.TargetCollectionMode.CASTER_RADIUS
	config.effect_radius = 5.0
	var multi_context := _context(caster, a, world)
	multi_context.candidate_targets = [a, b]
	var multi_capture := CaptureEffect.new()
	world.add_child(multi_capture)
	var multi_effects: Array[SkillEffectBase] = [damage, multi_capture]
	_expect(runner.execute(config, multi_context, Transform3D.IDENTITY, multi_effects), "two-target delivery succeeds")
	_expect(multi_capture.observations.size() == 2, "both targets have separate outcome observations")
	if multi_capture.observations.size() == 2:
		_expect(multi_capture.observations[0].statuses.has(&"burning"), "first target snapshot contains earlier burning")
		_expect(not multi_capture.observations[1].statuses.has(&"burning"), "second target snapshot does not inherit first target status")

	config.target_collection_mode = InstantTargetDeliveryConfig.TargetCollectionMode.SINGLE
	b.apply_damage(20.0, caster)
	var heal := HealthChangeSkillEffect.new()
	heal.operation = HealthChangeSkillEffect.Operation.HEAL
	heal.base_amount = 10.0
	heal.power_ratio = 0.0
	world.add_child(heal)
	var heal_capture := CaptureEffect.new()
	world.add_child(heal_capture)
	var heal_effects: Array[SkillEffectBase] = [heal, heal_capture]
	_expect(runner.execute(config, _context(caster, b, world), Transform3D.IDENTITY, heal_effects), "heal delivery succeeds")
	if heal_capture.observations.size() == 1:
		_expect(is_equal_approx(heal_capture.observations[0].healing, 10.0), "actual healing is recorded")
		_expect(is_zero_approx(heal_capture.observations[0].damage), "healing is not damage")

	var c := _unit(world, 2, Vector3(4, 0, 0))
	c.apply_damage(c.get_current_health() - 7.0, caster)
	var overkill := HealthChangeSkillEffect.new()
	overkill.operation = HealthChangeSkillEffect.Operation.DAMAGE
	overkill.base_amount = 200.0
	overkill.power_ratio = 0.0
	world.add_child(overkill)
	var overkill_capture := CaptureEffect.new()
	world.add_child(overkill_capture)
	var overkill_effects: Array[SkillEffectBase] = [overkill, overkill_capture]
	_expect(runner.execute(config, _context(caster, c, world), Transform3D.IDENTITY, overkill_effects), "overkill delivery succeeds")
	if overkill_capture.observations.size() == 1:
		_expect(is_equal_approx(overkill_capture.observations[0].damage, 7.0), "overkill records actual 7 health lost, not raw 200")
	world.free()
	_finish()

func _unit(world: Node3D, team: int, at: Vector3) -> UnitBase:
	var unit := (load("res://UnitSystem/Base/00_UnitBase.tscn") as PackedScene).instantiate() as UnitBase
	unit.team_id = team
	world.add_child(unit)
	unit.position = at
	return unit

func _context(caster: UnitBase, target: UnitBase, world: Node3D) -> SkillContext:
	var context := SkillContext.new()
	context.caster = caster
	context.resolved_target = target
	context.delivery_parent = world
	return context

func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)

func _finish() -> void:
	for failure: String in failures:
		push_error(failure)
	if failures.is_empty():
		print("SkillHitOutcomeTest: PASS")
	quit(0 if failures.is_empty() else 1)
