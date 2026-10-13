extends SceneTree

## 同步命中的多目标投射物不能在 launch 回调期间覆盖或提前终结同轮交付。

const FIXTURE_PATH := "res://SkillSystem/05-Tests/Fixtures/ImmediateArcProjectile.tscn"
const UNIT_SCENE := preload("res://UnitSystem/Base/00_UnitBase.tscn")
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	if not ResourceLoader.exists(FIXTURE_PATH):
		_expect(false, "immediate-hit Arc projectile fixture exists")
		_finish()
		return
	var world := Node3D.new()
	root.add_child(world)
	var caster := _unit(world, 1)
	var primary := _unit(world, 2)
	var marked := _unit(world, 2)
	marked.get_status_effect_component().apply_named_status(&"burning", 8.0)
	var query := MarkedHostileTargetExpansion.new()
	query.status_id = &"burning"
	var config := ArcProjectileDeliveryConfig.new()
	config.projectile_scene = load(FIXTURE_PATH) as PackedScene
	config.target_expansion = query
	var damage := HealthChangeSkillEffect.new()
	damage.operation = HealthChangeSkillEffect.Operation.DAMAGE
	damage.base_amount = 5.0
	damage.power_ratio = 0.0
	world.add_child(damage)
	var effects: Array[SkillEffectBase] = [damage]
	var runner := SkillDeliveryRunner.new()
	world.add_child(runner)
	var completed: Array[SkillDeliveryResult] = []
	runner.delivery_finished.connect(func(_context: SkillContext, result: SkillDeliveryResult) -> void: completed.append(result))
	var context := SkillContext.new()
	context.caster = caster
	context.resolved_target = primary
	context.delivery_parent = world
	_expect(runner.execute(config, context, Transform3D.IDENTITY, effects), "synchronous two-target volley starts")
	for _frame in range(3):
		await process_frame
	_expect(completed.size() == 1 and completed[0].hit_outcomes.size() == 2, "both immediate callbacks settle into one delivery result")
	_expect(primary.get_current_health() < primary.maximum_health and marked.get_current_health() < marked.maximum_health, "both intended targets receive damage")
	_expect(not runner.is_busy(), "synchronous volley releases its session")
	world.free()
	_finish()


func _unit(world: Node3D, team: int) -> UnitBase:
	var unit := UNIT_SCENE.instantiate() as UnitBase
	unit.team_id = team
	world.add_child(unit)
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
		print("ImmediateArcVolleyTest: PASS")
	quit(0 if failures.is_empty() else 1)
