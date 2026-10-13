extends SceneTree
## 兼容契约：漏发真实事件、过量计量、免伤误发或旧信号改序会失败。
var failures: Array[String] = []
func _initialize() -> void: call_deferred(&"_run")
func _run() -> void:
	var target = UnitBase.new()
	var found = false
	for s in target.get_signal_list():
		if s.name == &"damage_resolved": found = true
	if not found:
		target.free()
		failures.append("UnitBase has no damage_resolved event")
		_finish()
		return
	var world = Node3D.new()
	root.add_child(world)
	var source = UnitBase.new()
	source.team_id = 1
	source.attack_power = 0.0
	world.add_child(source)
	target.team_id = 2
	target.maximum_health = 7.0
	world.add_child(target)
	var events: Array = []
	var order: Array[StringName] = []
	target.connect(&"damage_resolved", func(e): events.append(e))
	target.health_changed.connect(func(_a, _b, _c, _s): order.append(&"health_changed"))
	target.damaged.connect(func(_a, _s): order.append(&"damaged"))
	target.died.connect(func(_s): order.append(&"died"))
	var context = CombatDamageContext.create(source, world, CombatDamageContext.Origin.CHAIN, 7, 9)
	var applied = load("res://UnitSystem/Combat/CombatValueResolver.gd").call(&"apply_damage", source, target, 200.0, 0.0, 1.0, 1.0, 0.0, context)
	_expect(applied == 7.0 and events.size() == 1, "one actual lethal event")
	_expect(events[0].actual_damage == 7.0 and events[0].round_id == 9, "overkill and attribution")
	_expect(order == [&"health_changed", &"damaged", &"died"], "legacy relative order")
	_expect(target.apply_damage(1.0) == 0.0 and events.size() == 1, "dead target no duplicate")
	var other = UnitBase.new()
	world.add_child(other)
	var extra: Array = []
	other.connect(&"damage_resolved", func(e): extra.append(e))
	_expect(other.apply_damage(INF) == 0.0 and other.apply_damage(NAN) == 0.0 and other.get_current_health() == 100.0, "finite health guard")
	other.apply_damage(5.0, source)
	_expect(extra.size() == 1 and extra[0].focus_yield_multiplier == 0.0, "unknown direct damage has no focus yield")
	var player = load("res://UnitSystem/Player/PlayerBase.tscn").instantiate()
	world.add_child(player)
	var player_events: Array = []
	player.connect(&"damage_resolved", func(e): player_events.append(e))
	player._start_dash(Vector3.FORWARD)
	_expect(player.call(&"apply_damage", 5.0, source, 1.0, context) == 0.0 and player_events.is_empty(), "invulnerability suppresses rich event")
	player.set("_dash_remaining_distance", 0.0)
	player.call(&"apply_damage", 5.0, source, 1.0, context)
	_expect(player_events.size() == 1, "player override forwards context")
	var enemy = load("res://UnitSystem/AI/Enemy/EnemyBase.tscn").instantiate()
	enemy.maximum_health = 17.0
	world.add_child(enemy)
	var enemy_events: Array = []
	enemy.damage_resolved.connect(func(e): enemy_events.append(e))
	var enemy_context = CombatDamageContext.create(source, world, CombatDamageContext.Origin.CHAIN, 101, 102)
	CombatValueResolver.apply_damage(source, enemy, 10.0, 0.0, 1.0, 3.0, 0.0, enemy_context)
	_expect(enemy_events.size() == 1 and enemy_events[0].request_id == 101, "enemy rich attribution forwarded")
	_expect(enemy.get_threat_component().get_threat_for(source) == 30.0, "rich event does not duplicate or bypass threat")
	CombatValueResolver.apply_damage(source, enemy, 200.0, 0.0, 1.0, 3.0, 0.0, enemy_context)
	_expect(enemy_events.size() == 2 and enemy_events[1].actual_damage == 7.0 and enemy.get_threat_component().get_threat_for(source) == 0.0, "lethal rich event and death threat cleanup")
	var disposable_source = UnitBase.new()
	world.add_child(disposable_source)
	var disposable_target = UnitBase.new()
	disposable_target.maximum_health = 7.0
	world.add_child(disposable_target)
	var disposed_events: Array = []
	var source_id = disposable_source.get_instance_id()
	var target_id = disposable_target.get_instance_id()
	disposable_target.damage_resolved.connect(func(e): disposed_events.append(e))
	disposable_target.died.connect(func(_s):
		_expect(disposed_events.size() == 1, "rich snapshot published before disposal callback")
		disposable_source.queue_free()
		disposable_target.queue_free()
	)
	CombatValueResolver.apply_damage(disposable_source, disposable_target, 200.0, 0.0, 1.0, 1.0, 0.0, CombatDamageContext.create(disposable_source, world))
	await process_frame
	_expect(not is_instance_valid(disposable_source) and not is_instance_valid(disposable_target), "death callback disposed source and target")
	_expect(disposed_events.size() == 1 and disposed_events[0].source_instance_id == source_id and disposed_events[0].target_instance_id == target_id and disposed_events[0].actual_damage == 7.0, "lethal snapshot survives both nodes")
	world.free()
	_finish()
func _expect(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
func _finish() -> void:
	for f in failures: push_error(f)
	if failures.is_empty(): print("DamageAttributionIntegrationTest: PASS")
	quit(0 if failures.is_empty() else 1)
