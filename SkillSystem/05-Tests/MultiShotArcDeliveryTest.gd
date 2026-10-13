extends SceneTree

## 连射交付必须在一次释放内产生三次独立伤害，并保留普通单箭结果契约。

const CONFIG_SCRIPT := preload("res://SkillSystem/02-Delivery/ArcProjectileDeliveryConfig.gd")
const ARROW_SCENE := preload("res://Item/Projectiles/Arrow.tscn")
const UNIT_SCENE := preload("res://UnitSystem/Base/00_UnitBase.tscn")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var caster := _unit(world, 1, Vector3.ZERO)
	var target := _unit(world, 2, Vector3(3, 0, 0))
	var runner := SkillDeliveryRunner.new()
	world.add_child(runner)
	var config := CONFIG_SCRIPT.new() as ArcProjectileDeliveryConfig
	config.projectile_scene = ARROW_SCENE
	if not _has_property(config, &"shot_count") or not _has_property(config, &"shot_interval_seconds"):
		_expect(false, "arc config exposes configurable shot count and interval")
		world.free()
		_finish()
		return
	config.set("shot_count", 3)
	config.set("shot_interval_seconds", 0.12)
	var damage := HealthChangeSkillEffect.new()
	damage.operation = HealthChangeSkillEffect.Operation.DAMAGE
	damage.base_amount = 5.0
	world.add_child(damage)
	var effects: Array[SkillEffectBase] = [damage]
	var finished: Array[SkillDeliveryResult] = []
	var failures_from_delivery: Array[StringName] = []
	runner.delivery_finished.connect(func(_context: SkillContext, result: SkillDeliveryResult) -> void: finished.append(result))
	runner.delivery_failed.connect(func(_context: SkillContext, reason: StringName) -> void: failures_from_delivery.append(reason))
	var before := target.get_current_health()
	_expect(runner.execute(config, _context(caster, target, world), Transform3D(Basis.IDENTITY, caster.global_position), effects), "three-shot delivery starts")
	for _frame in range(50):
		await physics_frame
	_expect(is_equal_approx(before - target.get_current_health(), 15.0), "three shots each deal five actual damage")
	_expect(finished.size() == 1 and failures_from_delivery.is_empty(), "one skill delivery completes after all three shots")
	if finished.size() == 1:
		var outcomes: Variant = finished[0].get("hit_outcomes")
		_expect(outcomes is Array and outcomes.size() == 3, "result preserves three independent hit outcomes")
		if outcomes is Array and outcomes.size() == 3:
			for outcome: Variant in outcomes:
				_expect(outcome is SkillHitOutcome and is_equal_approx(outcome.actual_damage, 5.0), "each hit reports actual damage separately")
	_expect(not runner.is_busy(), "volley releases delivery session")
	var fragile := _unit(world, 2, Vector3(4, 0, 0))
	var lethal := HealthChangeSkillEffect.new()
	lethal.operation = HealthChangeSkillEffect.Operation.DAMAGE
	lethal.base_amount = 200.0
	world.add_child(lethal)
	var lethal_effects: Array[SkillEffectBase] = [lethal]
	config.shot_interval_seconds = 0.4
	var completed_before := finished.size()
	_expect(runner.execute(config, _context(caster, fragile, world), Transform3D(Basis.IDENTITY, caster.global_position), lethal_effects), "volley starts against low-survival target")
	for _frame in range(80):
		await physics_frame
	_expect(finished.size() == completed_before + 1, "target death closes partially fired volley once")
	if finished.size() == completed_before + 1:
		_expect(finished[-1].hit_outcomes.size() == 1, "target death prevents remaining arrows from launching")
	_expect(not runner.is_busy(), "partial volley releases session")
	world.free()
	_finish()


func _has_property(value: Object, key: StringName) -> bool:
	for property: Dictionary in value.get_property_list():
		if property.get("name") == key:
			return true
	return false


func _unit(world: Node3D, team: int, at: Vector3) -> UnitBase:
	var unit := UNIT_SCENE.instantiate() as UnitBase
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
		print("MultiShotArcDeliveryTest: PASS")
	quit(0 if failures.is_empty() else 1)
