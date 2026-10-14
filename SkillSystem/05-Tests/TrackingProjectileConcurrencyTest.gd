extends SceneTree
## 同一真实Runner的并发、同步接受边界及迟到失败；夹具只替代投射物启动/外部区域效果。
const FIXTURES = preload("res://SkillSystem/05-Tests/SingleSceneDeliveryRunnerTest.gd")
const UNIT = preload("res://UnitSystem/Base/00_UnitBase.tscn")
const SKILL = preload("res://SkillSystem/01-Core/SkillBase.tscn")
var failures: Array[String] = []
var trace: Array[StringName] = []
var hit_ids: Array[int] = []
var terminal_ids: Array[int] = []

class RecordingEffect:
	extends SkillEffectBase
	var log: Array[StringName]
	var ids: Array[int]
	var fail_after_apply: bool = false
	func apply(ctx: SkillContext, _result: SkillDeliveryResult, _target: Node3D) -> bool:
		log.append(&"effect")
		ids.append(ctx.damage_context.request_id)
		return not fail_after_apply

class FailingArea:
	extends Node3D
	func launch(context: SkillContext) -> bool:
		context.delivery_parent.get_meta(&"area_trace").append(&"effect")
		return false

func _initialize() -> void: call_deferred(&"_run")

func _run() -> void:
	await _verify_overlap_and_cancel(false)
	await _verify_overlap_and_cancel(true)
	await _verify_sync_and_false_launch()
	_verify_instant_and_ground()
	await _verify_old_failure_while_casting()
	for f in failures: push_error(f)
	if failures.is_empty(): print("TrackingProjectileConcurrencyTest: PASS")
	quit(0 if failures.is_empty() else 1)

func _world() -> Node3D:
	var world = Node3D.new()
	root.add_child(world)
	return world

func _unit(world: Node3D, team: int, position_value: Vector3) -> UnitBase:
	var unit = UNIT.instantiate() as UnitBase
	unit.team_id = team
	unit.position = position_value
	world.add_child(unit)
	unit.set_physics_process(false)
	return unit

func _context(caster: Node3D, target: Node3D, world: Node, id: int) -> SkillContext:
	var ctx = SkillContext.new()
	ctx.caster = caster
	ctx.resolved_target = target
	ctx.requested_target = target
	ctx.explicit_target_requested = true
	ctx.delivery_parent = world
	ctx.damage_context = CombatDamageContext.create(caster, world, CombatDamageContext.Origin.CHAIN, id, 1000, &"test")
	return ctx

func _pack(template: Node) -> PackedScene:
	var scene = PackedScene.new()
	_expect(scene.pack(template) == OK, "projectile/area fixture packs")
	template.free()
	return scene

func _tracking(scene: PackedScene) -> TrackingProjectileDeliveryConfig:
	var config = TrackingProjectileDeliveryConfig.new()
	config.projectile_scene = scene
	return config

func _effect(world: Node, fail_value: bool = false) -> RecordingEffect:
	var effect = RecordingEffect.new()
	effect.log = trace
	effect.ids = hit_ids
	effect.fail_after_apply = fail_value
	world.add_child(effect)
	return effect

func _runner(world: Node) -> SkillDeliveryRunner:
	var runner = SkillDeliveryRunner.new()
	world.add_child(runner)
	runner.delivery_started.connect(func(_ctx): trace.append(&"accepted"))
	runner.delivery_finished.connect(func(ctx, _result): terminal_ids.append(ctx.damage_context.request_id))
	runner.delivery_failed.connect(func(ctx, _reason):
		trace.append(&"failed")
		terminal_ids.append(ctx.damage_context.request_id))
	return runner

func _verify_overlap_and_cancel(real_fireball: bool) -> void:
	trace.clear()
	hit_ids.clear()
	terminal_ids.clear()
	var world = _world()
	var caster = _unit(world, 1, Vector3.ZERO)
	var target = _unit(world, 2, Vector3(8, 0, 0))
	var runner = _runner(world)
	var scene: PackedScene = load("res://Item/Projectiles/FireBall.tscn") if real_fireball else _pack(FIXTURES.FakeProjectile.new())
	var config = _tracking(scene)
	config.projectile_speed = 0.1
	var effects: Array[SkillEffectBase] = [_effect(world)]
	_expect(runner.execute(config, _context(caster, target, world, 1001), Transform3D.IDENTITY, effects), "first tracking accepted")
	_expect(runner.execute(config, _context(caster, target, world, 1002), Transform3D.IDENTITY, effects), "second tracking accepted while first flies")
	var projectiles: Array[Node] = []
	for child in world.get_children():
		if child.has_signal(&"projectile_impacted"): projectiles.append(child)
	_expect(projectiles.size() == 2, "independent real projectile instances")
	if not real_fireball and projectiles.size() == 2:
		projectiles[1].emit_signal(&"projectile_impacted", Vector3(8, 0, 0))
		projectiles[0].emit_signal(&"projectile_impacted", Vector3(8, 0, 0))
		_expect(hit_ids == [1002, 1001], "reverse impacts keep original root contexts")
		_expect(not runner.is_busy(), "all sessions terminal")
	else:
		runner.cancel(&"test_cancel")
		_expect(not runner.is_busy() and terminal_ids.size() == projectiles.size(), "cancel ends each accepted session once")
	await process_frame
	world.free()

func _verify_sync_and_false_launch() -> void:
	for successful in [true, false]:
		trace.clear()
		hit_ids.clear()
		var world = _world()
		var caster = _unit(world, 1, Vector3.ZERO)
		var target = _unit(world, 2, Vector3(8, 0, 0))
		var runner = _runner(world)
		var template = FIXTURES.SynchronousImpactProjectile.new() if successful else FIXTURES.FalseImpactLaunchProjectile.new()
		var config = _tracking(_pack(template))
		var effects: Array[SkillEffectBase] = [_effect(world)]
		var accepted = runner.execute(config, _context(caster, target, world, 1101), Transform3D.IDENTITY, effects)
		_expect(accepted == successful, "launch result controls acceptance")
		await process_frame
		_expect(trace == [&"accepted", &"effect"] if successful else trace.is_empty(), "synchronous effect follows acceptance; false launch applies nothing")
		world.free()

func _verify_instant_and_ground() -> void:
	trace.clear()
	var world = _world()
	var caster = _unit(world, 1, Vector3.ZERO)
	var target = _unit(world, 2, Vector3(2, 0, 0))
	var runner = _runner(world)
	var effects: Array[SkillEffectBase] = [_effect(world, true)]
	_expect(runner.execute(InstantTargetDeliveryConfig.new(), _context(caster, target, world, 1201), Transform3D.IDENTITY, effects), "accepted Instant failure still returns true")
	_expect(trace == [&"accepted", &"effect", &"failed"], "Instant accepts before effect and reports final failure")
	var area_runner = SkillDeliveryRunner.new()
	world.add_child(area_runner)
	var area_trace: Array[StringName] = []
	world.set_meta(&"area_trace", area_trace)
	area_runner.delivery_started.connect(func(_ctx): area_trace.append(&"accepted"))
	area_runner.delivery_failed.connect(func(_ctx, _reason): area_trace.append(&"failed"))
	var ground = GroundAreaDeliveryConfig.new()
	ground.area_scene = _pack(FailingArea.new())
	_expect(area_runner.execute(ground, _context(caster, target, world, 1202), Transform3D.IDENTITY, effects), "accepted GroundArea launch failure still returns true")
	_expect(area_trace == [&"accepted", &"effect", &"failed"], "GroundArea acceptance precedes area effect")
	world.free()

func _verify_old_failure_while_casting() -> void:
	var world = _world()
	var caster = _unit(world, 1, Vector3.ZERO)
	var target = _unit(world, 2, Vector3(2, 0, 0))
	var skill = SKILL.instantiate() as SkillBase
	skill.skill_id = &"late"
	skill.skill_cooldown = 0.0
	skill.cast_range = 20.0
	skill.delivery = _tracking(_pack(FIXTURES.FakeProjectile.new()))
	caster.add_child(skill)
	skill.configure_owner(caster, null, world)
	if not skill.has_signal(&"delivery_failed"):
		_expect(false, "independent delivery failure notification required")
		world.free()
		return
	var received: Array[int] = []
	skill.connect(&"delivery_failed", func(ctx, _reason): received.append(ctx.damage_context.request_id))
	var ctx = _context(caster, target, world, 1301)
	ctx.execution_mode = SkillContext.ExecutionMode.DIRECT_TRIGGER
	ctx.activation_transform = Transform3D.IDENTITY
	_expect(skill.activate(ctx), "old projectile released at zero cooldown")
	var next = _context(caster, target, world, 1302)
	_expect(skill.activate(next) and skill.confirm_action_started(Transform3D.IDENTITY), "new action casting while old projectile flies")
	for child in world.get_children():
		if child.has_signal(&"projectile_impacted"): child.queue_free()
	await process_frame
	_expect(received == [1301] and skill.is_casting(), "old failure forwarded without clearing new action")
	world.free()

func _expect(ok: bool, label: String) -> void:
	if not ok: failures.append(label)
