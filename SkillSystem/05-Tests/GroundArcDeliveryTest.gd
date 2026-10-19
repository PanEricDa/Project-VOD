extends SceneTree
## 通用地面弧线交付：有效地面、固定落点、空地完成、范围重复伤害及仅停止未发。
var failures: Array[String] = []
var launches: Array[Vector3] = []
var results: Array[SkillDeliveryResult] = []
var emissions: int = 0
func _initialize() -> void:
	call_deferred("_run")
func _run() -> void:
	var config := ArcProjectileDeliveryConfig.new()
	var supported := false
	for property: Dictionary in config.get_property_list():
		if property.name == "destination_mode": supported = true
	if not supported:
		failures.append("missing generic ground arc destination mode")
		_finish()
		return
	var world := Node3D.new()
	root.add_child(world)
	var source := _unit(world, 1, Vector3.ZERO)
	var target := _unit(world, 2, Vector3(0, 0, -3))
	var projectile := Node3D.new()
	projectile.set_script(load("res://Item/Projectiles/TrackingArcProjectile.gd"))
	projectile.set("flight_duration", 0.15)
	var packed := PackedScene.new()
	packed.pack(projectile)
	projectile.free()
	config.projectile_scene = packed
	config.set("destination_mode", 1)
	config.set("scatter_radius_m", 0.01)
	config.set("impact_radius_m", 3.0)
	config.shot_count = 5
	config.shot_interval_seconds = 0.04
	var context := SkillContext.new()
	context.caster = source
	context.resolved_target = target
	context.delivery_parent = world
	context.damage_context = CombatDamageContext.create(source, world, CombatDamageContext.Origin.FINISHER, 901)
	var runner := SkillDeliveryRunner.new()
	world.add_child(runner)
	var damage := HealthChangeSkillEffect.new()
	damage.operation = HealthChangeSkillEffect.Operation.DAMAGE
	damage.base_amount = 5
	damage.power_ratio = 0
	world.add_child(damage)
	var effects: Array[SkillEffectBase] = [damage]
	await physics_frame
	_expect(not runner.execute(config, context, Transform3D.IDENTITY, effects), "no ground rejects instead of floating in air")
	var ground := StaticBody3D.new()
	ground.collision_layer = 1
	ground.collision_mask = 0
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40, 0.1, 40)
	collision.shape = box
	ground.add_child(collision)
	world.add_child(ground)
	ground.position.y = -0.05
	await physics_frame
	await physics_frame
	runner.connect("projectile_launched", func(_ctx: SkillContext, _index: int, point: Vector3) -> void: launches.append(point))
	runner.connect("emission_finished", func(_ctx: SkillContext) -> void: emissions += 1)
	runner.delivery_finished.connect(func(_ctx: SkillContext, result: SkillDeliveryResult) -> void: results.append(result))
	var before := target.get_current_health()
	_expect(runner.execute(config, context, Transform3D(Basis.IDENTITY, Vector3(0, 1, 0)), effects), "ground delivery accepts")
	for frame: int in range(32): await physics_frame
	_expect(launches.size() == 5 and emissions == 1, "all five projectiles issue exactly once")
	_expect(results.size() == 1 and not runner.is_busy(), "one delivery completion")
	_expect(is_equal_approx(before - target.get_current_health(), 25.0), "five independent AoE hits reuse damage effect")
	for point: Vector3 in launches:
		_expect(Vector2(point.x, point.z + 3).length() <= 0.011 and absf(point.y) < 0.01, "points frozen on real ground inside scatter radius")
	launches.clear()
	target.position = Vector3(0, 0, -8)
	config.set("scatter_radius_m", 5.0)
	config.set("impact_radius_m", 0.02)
	var count := results.size()
	_expect(runner.execute(config, context, Transform3D(Basis.IDENTITY, Vector3(0, 1, 0)), effects), "empty landings accept")
	target.position = Vector3(18, 0, 18)
	for frame: int in range(32): await physics_frame
	_expect(results.size() == count + 1, "zero targets still successful ground delivery")
	_expect(launches.size() == 5, "original target movement does not cancel pending points")
	# 取消只停止未发，第一颗依旧落地；不删除已经发布的交付。
	launches.clear()
	target.position = Vector3(0,0,-3)
	context.damage_context = CombatDamageContext.create(source,world,CombatDamageContext.Origin.FINISHER,902)
	config.scatter_radius_m = 0.01
	config.impact_radius_m = 3.0
	config.shot_interval_seconds = 1.0
	before = target.get_current_health()
	_expect(runner.execute(config,context,Transform3D(Basis.IDENTITY,Vector3.UP),effects),"cancel fixture starts")
	runner.stop_pending_emission(902)
	for frame: int in range(20): await physics_frame
	_expect(launches.size() == 1 and not runner.is_busy(),"stop pending preserves one issued and completes")
	_expect(is_equal_approx(before-target.get_current_health(),5.0),"issued shot still damages")
	# 范围交付不继承Physics默认32结果上限。
	var crowd: Array[UnitBase] = []
	for index: int in range(65): crowd.append(_unit(world,2,Vector3(0,0,-3)))
	config.shot_count = 1
	launches.clear()
	_expect(runner.execute(config,context,Transform3D(Basis.IDENTITY,Vector3.UP),effects),"crowd fixture starts")
	for frame: int in range(20): await physics_frame
	for unit: UnitBase in crowd: _expect(is_equal_approx(unit.get_current_health(),unit.get_maximum_health()-5),"every crowded target hit")
	# 同步launch_point命中也必须在物理阶段执行查询和落地事实。
	var synchronous := Node3D.new()
	synchronous.set_script(load("res://SkillSystem/05-Tests/Fixtures/SynchronousGroundProjectile.gd"))
	var sync_packed := PackedScene.new()
	sync_packed.pack(synchronous)
	synchronous.free()
	config.projectile_scene = sync_packed
	var physical_hits: Array[bool] = []
	var physical_callback := func(_ctx: SkillContext,_index: int,_point: Vector3) -> void: physical_hits.append(Engine.is_in_physics_frame())
	runner.projectile_landed.connect(physical_callback)
	await process_frame
	_expect(not runner.execute(config,context,Transform3D(Basis.IDENTITY,Vector3.UP),effects),"direct ground runner rejects non-physics sampling")
	await physics_frame
	_expect(runner.execute(config,context,Transform3D(Basis.IDENTITY,Vector3.UP),effects),"synchronous ground fixture accepts")
	for frame: int in range(3): await physics_frame
	_expect(physical_hits == [true],"synchronous hit settles only in physics phase")
	runner.projectile_landed.disconnect(physical_callback)
	config.projectile_scene = packed
	# 最后一发已发后施法者被删除，不允许迟到命中解引用已释放节点或让Runner永久忙碌。
	_expect(runner.execute(config,context,Transform3D(Basis.IDENTITY,Vector3.UP),effects),"source exit fixture starts")
	source.queue_free()
	for frame: int in range(20): await physics_frame
	_expect(not runner.is_busy(),"source exit after emission settles safely")
	world.free()
	await process_frame
	await process_frame
	_finish()
func _unit(world: Node, team: int, point: Vector3) -> UnitBase:
	var unit := load("res://UnitSystem/Base/00_UnitBase.tscn").instantiate() as UnitBase
	unit.team_id = team
	unit.collision_layer = 2 if team == 1 else 4
	world.add_child(unit)
	unit.position = point
	return unit
func _expect(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
func _finish() -> void:
	for message in failures: printerr("FAIL: ", message)
	print("GroundArcDeliveryTest: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
