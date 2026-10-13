extends SceneTree

## 状态标记目标在释放前一次性确定；多枚 Arc 投射物同帧各自追踪并结算。

const QUERY_PATH := "res://SkillSystem/02-Delivery/MarkedHostileTargetExpansion.gd"
const UNIT_SCENE := preload("res://UnitSystem/Base/00_UnitBase.tscn")
const PROJECTILE_SCENE := preload("res://Item/Projectiles/ExplosiveArrow.tscn")
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	if not ResourceLoader.exists(QUERY_PATH):
		_expect(false, "generic marked-hostile target expansion exists")
		_finish()
		return
	var world := Node3D.new()
	root.add_child(world)
	var caster := _unit(world, 1, Vector3.ZERO)
	var primary := _unit(world, 2, Vector3(3, 0, 0))
	var marked_a := _unit(world, 2, Vector3(4, 0, 1))
	var marked_b := _unit(world, 2, Vector3(4, 0, -1))
	var unmarked := _unit(world, 2, Vector3(5, 0, 2))
	marked_a.get_status_effect_component().apply_named_status(&"burning", 8.0)
	marked_b.get_status_effect_component().apply_named_status(&"burning", 8.0)
	var query := (load(QUERY_PATH) as Script).new() as Resource
	query.set("status_id", &"burning")
	var config := ArcProjectileDeliveryConfig.new()
	config.projectile_scene = PROJECTILE_SCENE
	if not _has_property(config, &"target_expansion"):
		_expect(false, "Arc delivery accepts a target expansion resource")
		world.free()
		_finish()
		return
	config.set("target_expansion", query)
	var runner := SkillDeliveryRunner.new()
	world.add_child(runner)
	var damage := HealthChangeSkillEffect.new()
	damage.operation = HealthChangeSkillEffect.Operation.DAMAGE
	damage.base_amount = 5.0
	damage.power_ratio = 0.0
	world.add_child(damage)
	var consume := (load("res://SkillSystem/03-Extensions/ConsumeNamedStatusSkillEffect.gd") as Script).new() as SkillEffectBase
	consume.set("status_id", &"burning")
	world.add_child(consume)
	var effects: Array[SkillEffectBase] = [damage, consume]
	var completed: Array[SkillDeliveryResult] = []
	runner.delivery_finished.connect(func(_context: SkillContext, result: SkillDeliveryResult) -> void: completed.append(result))
	var context := SkillContext.new()
	context.caster = caster
	context.resolved_target = primary
	context.delivery_parent = world
	_expect(runner.execute(config, context, Transform3D(Basis.IDENTITY, caster.global_position), effects), "marked-target volley starts")
	var launched_targets: Array[UnitBase] = []
	for node: Node in world.get_children():
		if node is AITrackingArcProjectile:
			launched_targets.append((node as AITrackingArcProjectile).tracked_target)
	_expect(launched_targets.size() == 3, "primary and two marked hostiles launch in the same release frame")
	_expect(launched_targets.has(primary) and launched_targets.has(marked_a) and launched_targets.has(marked_b), "each expected hostile receives one projectile")
	_expect(not launched_targets.has(unmarked), "unmarked secondary receives no projectile")
	for _frame in range(50):
		await physics_frame
	_expect(completed.size() == 1, "one delivery finishes after three independent projectiles")
	if completed.size() == 1:
		_expect(completed[0].hit_outcomes.size() == 3, "three distinct hits are recorded")
	_expect(marked_a.get_current_health() < marked_a.maximum_health, "first marked target takes damage")
	_expect(marked_b.get_current_health() < marked_b.maximum_health, "second marked target takes damage")
	_expect(is_equal_approx(unmarked.get_current_health(), unmarked.maximum_health), "unmarked secondary is unharmed")
	_expect(not marked_a.get_status_effect_component().has_named_status(&"burning"), "first hit consumes burning")
	_expect(not marked_b.get_status_effect_component().has_named_status(&"burning"), "second hit consumes burning")
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


func _has_property(value: Object, key: StringName) -> bool:
	for item: Dictionary in value.get_property_list():
		if item.get("name") == key:
			return true
	return false


func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)


func _finish() -> void:
	for failure: String in failures:
		push_error(failure)
	if failures.is_empty():
		print("MarkedTargetVolleyTest: PASS")
	quit(0 if failures.is_empty() else 1)
