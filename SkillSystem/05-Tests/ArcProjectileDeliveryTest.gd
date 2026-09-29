extends SceneTree

## 弧线箭通过独立交付会话结算命中，且不会占用另一发箭的运行状态。

const CONFIG_PATH := "res://SkillSystem/02-Delivery/ArcProjectileDeliveryConfig.gd"
const ARROW_PATH := "res://Item/Projectiles/Arrow.tscn"
const UNIT_PATH := "res://UnitSystem/Base/00_UnitBase.tscn"
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	if not ResourceLoader.exists(CONFIG_PATH):
		_expect(false, "Arc delivery config exists")
		_finish()
		return
	var world := Node3D.new()
	root.add_child(world)
	var caster := _unit(world, 1, Vector3.ZERO)
	var a := _unit(world, 2, Vector3(3, 0, 0))
	var b := _unit(world, 2, Vector3(4, 0, 0))
	var runner := SkillDeliveryRunner.new()
	world.add_child(runner)
	var config := (load(CONFIG_PATH) as Script).new() as SkillDeliveryConfig
	config.set("projectile_scene", load(ARROW_PATH))
	var damage := HealthChangeSkillEffect.new()
	damage.operation = HealthChangeSkillEffect.Operation.DAMAGE
	damage.base_amount = 9.0
	world.add_child(damage)
	var effects: Array[SkillEffectBase] = [damage]
	var finished: Array[SkillDeliveryResult] = []
	var failed: Array[StringName] = []
	runner.delivery_finished.connect(func(_context: SkillContext, result: SkillDeliveryResult) -> void: finished.append(result))
	runner.delivery_failed.connect(func(_context: SkillContext, reason: StringName) -> void: failed.append(reason))
	var original_a := a.get_current_health()
	var original_b := b.get_current_health()
	_expect(runner.execute(config, _context(caster, a, world), Transform3D(Basis.IDENTITY, caster.global_position), effects), "first arc launch succeeds")
	_expect(runner.execute(config, _context(caster, b, world), Transform3D(Basis.IDENTITY, caster.global_position), effects), "second arc launch succeeds while first flies")
	_expect(runner.is_busy(), "runner reports in-flight arc sessions")
	for _frame in range(40):
		await physics_frame
	_expect(finished.size() == 2, "both arc sessions complete exactly once")
	_expect(failed.is_empty(), "successful arc sessions have no failures")
	_expect(not runner.is_busy(), "runner releases both completed arc sessions")
	_expect(is_equal_approx(original_a - a.get_current_health(), 9.0), "first target loses nine actual health")
	_expect(is_equal_approx(original_b - b.get_current_health(), 9.0), "second target loses nine actual health")
	if finished.size() == 2:
		_expect(finished[0].current_hit.actual_damage == 9.0 and finished[1].current_hit.actual_damage == 9.0, "each result owns a per-target actual-damage outcome")

	var c := _unit(world, 2, Vector3(5, 0, 0))
	var before_cancel := finished.size()
	_expect(runner.execute(config, _context(caster, c, world), Transform3D(Basis.IDENTITY, caster.global_position), effects), "third arc launch succeeds")
	c.free()
	for _frame in range(40):
		await physics_frame
	_expect(finished.size() == before_cancel, "lost target does not receive a hit")
	_expect(failed.size() == 1, "lost target closes its session as failure")
	_expect(world.get_children().filter(func(node: Node) -> bool: return node is AITrackingArcProjectile).is_empty(), "no arc projectiles remain after terminal events")
	var d := _unit(world, 2, Vector3(6, 0, 0))
	_expect(runner.execute(config, _context(caster, d, world), Transform3D(Basis.IDENTITY, caster.global_position), effects), "exit-cleanup arc launch succeeds")
	runner.free()
	await process_frame
	_expect(world.get_children().filter(func(node: Node) -> bool: return node is AITrackingArcProjectile).is_empty(), "runner exit releases in-flight arc projectile")
	world.free()
	_finish()


func _unit(world: Node3D, team: int, at: Vector3) -> UnitBase:
	var unit := (load(UNIT_PATH) as PackedScene).instantiate() as UnitBase
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
		print("ArcProjectileDeliveryTest: PASS")
	quit(0 if failures.is_empty() else 1)
