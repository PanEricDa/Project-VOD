extends SceneTree
## 捕捉重复绑定重置资源、动态单位漏订阅、重入树重复信号及旧场景回调泄漏。
var failures: Array[String] = []
func _initialize() -> void: call_deferred(&"_run")
func _run() -> void:
	var path = "res://UnitSystem/Components/Combat/Squad/SquadFocusComponent.tscn"
	if not ResourceLoader.exists(path):
		failures.append("focus source scene missing")
		_finish()
		return
	_expect(ResourceLoader.get_resource_uid(path) != ResourceUID.INVALID_ID, "saved source scene UID")
	var world = Node3D.new()
	root.add_child(world)
	var source = _unit(world, 1)
	source.faction_id = "Player"
	var target = _unit(world, 2)
	var focus = load(path).instantiate()
	focus.auto_bind_parent = false
	world.add_child(focus)
	var party: Array[UnitBase] = [source]
	focus.bind_scope(world, party)
	var events: Array = []
	target.damage_resolved.connect(func(e): events.append(e))
	_hit(source, target, world)
	_expect(focus.get_current_focus() == 1.0, "gain before duplicate bind")
	focus.bind_scope(world, party)
	_expect(focus.get_current_focus() == 1.0, "same bind preserves balance")
	focus.unbind_scope()
	focus.bind_scope(world, party)
	target.damage_resolved.emit(events[0])
	_expect(focus.get_current_focus() == 0.0, "same scope new session rejects old event")
	_hit(source, target, world)
	_expect(focus.get_current_focus() == 1.0, "same scope fresh damage earns")
	var dynamic = _unit(world, 2)
	_hit(source, dynamic, world)
	_expect(focus.get_current_focus() == 2.0, "dynamic target observed")
	world.remove_child(dynamic)
	for connection in dynamic.tree_exiting.get_connections():
		_expect(connection.callable.get_object() != focus, "removed target releases exit listener")
	world.add_child(dynamic)
	_hit(source, dynamic, world)
	_expect(focus.get_current_focus() == 3.0, "reentered target exactly once")
	var next = Node3D.new()
	root.add_child(next)
	var source2 = _unit(next, 1)
	var target2 = _unit(next, 2)
	var party2: Array[UnitBase] = [source2]
	focus.bind_scope(next, party2)
	_expect(focus.get_current_focus() == 0.0, "new scope resets")
	target.damage_resolved.emit(events[0])
	_expect(focus.get_current_focus() == 0.0, "old scope disconnected")
	_hit(source2, target2, next)
	_expect(focus.get_current_focus() == 1.0, "new scope earns independently")
	focus.reserve(101, 1.0)
	focus.unbind_scope()
	_expect(focus.get_reserved_focus() == 0.0, "unbind releases promises")
	next.free()
	world.free()
	var auto_world = Node3D.new()
	root.add_child(auto_world)
	var player = _unit(auto_world, 1)
	player.faction_id = "Player"
	var auto_target = _unit(auto_world, 2)
	var auto_focus = load(path).instantiate()
	auto_world.add_child(auto_focus)
	await process_frame
	_hit(player, auto_target, auto_world)
	_expect(auto_focus.get_current_focus() == 1.0, "auto binds unique player")
	var ally = _unit(auto_world, 1)
	ally.faction_id = "Ally"
	# node_added reads configured identity; configure before entering, not after.
	auto_world.remove_child(ally)
	auto_world.add_child(ally)
	_hit(ally, auto_target, auto_world)
	_expect(auto_focus.get_current_focus() == 2.0, "dynamic same team ally earns")
	var in_flight = CombatDamageContext.create(player, auto_world)
	player.free()
	CombatValueResolver.apply_damage(null, auto_target, 10.0, 0.0, 1.0, 1.0, 0.0, in_flight)
	_expect(auto_focus.get_current_focus() == 3.0, "source deletion preserves in-flight credit")
	auto_world.free()
	for player_count in [0, 2]:
		var invalid_world = Node3D.new()
		root.add_child(invalid_world)
		var invalid_source: UnitBase
		for _i in range(player_count):
			var p = UnitBase.new()
			p.team_id = 1
			p.faction_id = "Player"
			invalid_world.add_child(p)
			invalid_source = p
		var invalid_target = _unit(invalid_world, 2)
		var invalid_focus = load(path).instantiate()
		invalid_world.add_child(invalid_focus)
		await process_frame
		_hit(invalid_source, invalid_target, invalid_world)
		_expect(invalid_focus.get_current_focus() == 0.0, "automatic ambiguous or missing player fails closed")
		invalid_world.free()
	_finish()
func _unit(world: Node3D, team: int) -> UnitBase:
	var u = UnitBase.new()
	u.maximum_health = 1000.0
	u.team_id = team
	world.add_child(u)
	return u
func _hit(source: UnitBase, target: UnitBase, world: Node3D) -> void:
	CombatValueResolver.apply_damage(source, target, 10.0, 0.0, 1.0, 1.0, 0.0, CombatDamageContext.create(source, world))
func _expect(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
func _finish() -> void:
	for f in failures: push_error(f)
	if failures.is_empty(): print("SquadFocusSceneBindingTest: PASS")
	quit(0 if failures.is_empty() else 1)
