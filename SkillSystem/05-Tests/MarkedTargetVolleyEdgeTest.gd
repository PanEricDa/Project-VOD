extends SceneTree

## 已灼烧的主要目标不重复发射；释放后的新灼烧不追加投射物，单个目标失效不影响其余命中。

const UNIT_SCENE := preload("res://UnitSystem/Base/00_UnitBase.tscn")
const PROJECTILE_SCENE := preload("res://Item/Projectiles/PyroblastProjectile.tscn")
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var caster := _unit(world, 1, Vector3.ZERO)
	var primary := _unit(world, 2, Vector3(3, 0, 0))
	var secondary := _unit(world, 2, Vector3(4, 0, 1))
	var late := _unit(world, 2, Vector3(4, 0, -1))
	primary.get_status_effect_component().apply_named_status(&"burning", 8.0)
	secondary.get_status_effect_component().apply_named_status(&"burning", 8.0)
	var query := MarkedHostileTargetExpansion.new()
	query.status_id = &"burning"
	var config := ArcProjectileDeliveryConfig.new()
	config.projectile_scene = PROJECTILE_SCENE
	config.target_expansion = query
	var runner := SkillDeliveryRunner.new()
	world.add_child(runner)
	var damage := HealthChangeSkillEffect.new()
	damage.operation = HealthChangeSkillEffect.Operation.DAMAGE
	damage.base_amount = 5.0
	damage.power_ratio = 0.0
	world.add_child(damage)
	var effects: Array[SkillEffectBase] = [damage]
	var completed: Array[SkillDeliveryResult] = []
	runner.delivery_finished.connect(func(_context: SkillContext, result: SkillDeliveryResult) -> void: completed.append(result))
	var context := SkillContext.new()
	context.caster = caster
	context.resolved_target = primary
	context.delivery_parent = world
	_expect(runner.execute(config, context, Transform3D(Basis.IDENTITY, caster.global_position), effects), "marked-primary volley starts")
	var tracked: Array[UnitBase] = []
	for node: Node in world.get_children():
		if node is AITrackingArcProjectile:
			tracked.append((node as AITrackingArcProjectile).tracked_target)
	_expect(tracked.size() == 2 and tracked.has(primary) and tracked.has(secondary), "burning primary receives one projectile, not a duplicate")
	late.get_status_effect_component().apply_named_status(&"burning", 8.0)
	secondary.free()
	for _frame in range(50):
		await physics_frame
	_expect(completed.size() == 1 and completed[0].hit_outcomes.size() == 1, "one lost projectile does not cancel surviving primary hit")
	_expect(primary.get_current_health() < primary.maximum_health, "primary hit still lands")
	_expect(is_equal_approx(late.get_current_health(), late.maximum_health), "post-launch burning never adds a projectile")
	_expect(not runner.is_busy(), "all volley projectiles eventually settle")
	world.free()
	_finish()


func _unit(world: Node3D, team: int, at: Vector3) -> UnitBase:
	var unit := UNIT_SCENE.instantiate() as UnitBase
	unit.team_id = team
	world.add_child(unit)
	unit.position = at
	if team == 2:
		unit.add_to_group(&"enemy_targets")
	return unit


func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)


func _finish() -> void:
	for failure: String in failures:
		push_error(failure)
	if failures.is_empty():
		print("MarkedTargetVolleyEdgeTest: PASS")
	quit(0 if failures.is_empty() else 1)
