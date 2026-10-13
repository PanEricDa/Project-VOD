extends SceneTree
## 正式 TestCombatRoom 的只读配置审计：只实例化运行时副本，不保存场景或改正式单位资源。
## 默认3轮各20秒实际战斗、10轮重载及2000笔零额事务；--cycles/seconds/reloads可调整测试时长。
## 使用已有自动攻击驱动，立即恢复原 can_die；不会赋予无敌或改伤害、血量、技能配置。
const ROOM_PATH: String = "res://Scenes/TestCombatRoom.tscn"
const DRIVER = preload("res://Tools/CombatSimulation/IdealHeroCombatDriver.gd")
var failures: Array[String] = []
var report: Dictionary = {"rounds": [], "cleanup": [], "transaction_count": 0}
var world: Node3D
var focus: SquadFocusComponent
var party: Dictionary = {}
var actor_names: Dictionary = {}
var expected: float = 0.0
var seen: Dictionary = {}
var cycle_stats: Dictionary = {}
var last_event: CombatDamageEvent
var current_callbacks: Array = []
var baseline_nodes: int = 0
var baseline_orphans: int = 0
var baseline_paths: Array[String] = []

func _initialize() -> void: call_deferred(&"_run")

func _run() -> void:
	var cycles: int = _argument("cycles", 3)
	var seconds: int = _argument("seconds", 20)
	var reloads: int = _argument("reloads", 10)
	await _empty_world()
	# 预热正式 HUD 的可复用 Dash 分隔线和资源缓存；不把一次性初始化当成逐轮泄漏。
	if not await _load_world():
		_finish()
		return
	await _empty_world()
	baseline_nodes = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	baseline_orphans = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	baseline_paths = _node_paths(root)
	report["baseline_actual_nodes"] = get_node_count()
	report["baseline_paths"] = baseline_paths
	for index in range(cycles):
		if not await _load_world():
			_finish()
			return
		_start_audit()
		_expect(focus.get("_scope") == world, "world scope automatically bound")
		_expect(party.size() == 5 and focus.get("_party").size() == 5, "five party members automatically bound")
		_expect(focus.get("_observed").size() == 17, "all seventeen scene units observed")
		_expect(world.get_node("SquadFocusDebugDisplay").get("_bound_focus") == focus, "display source correct")
		_check_connections()
		var hero: PlayerBase = world.get_node("Hero")
		var driver: IdealHeroCombatDriver = DRIVER.new()
		world.add_child(driver)
		var original_can_die: bool = hero.can_die
		driver.configure(hero)
		hero.can_die = original_can_die
		for pack in world.get_node("EnemyContainer").get_children():
			for unit in pack.get_children():
				if unit is EnemyBase:
					unit.get_targeting_component().call("_set_locked_target", hero)
					unit.enter_combat()
		var end_time: int = Time.get_ticks_msec() + seconds * 1000
		while Time.get_ticks_msec() < end_time:
			await create_timer(0.1).timeout
			_assert_balance("battle sample")
			_check_connections()
			# 防止容量饱和掩盖后续漏算：只在测试副本中清空资源会话继续核对。
			if focus.get_current_focus() >= focus.get_maximum_focus():
				focus.reset_focus()
				expected = focus.get_current_focus()
				cycle_stats.cap_resets += 1
		driver.set_physics_process(false)
		cycle_stats["focus_final"] = focus.get_current_focus()
		cycle_stats["expected_final"] = expected
		cycle_stats["recorded_events"] = seen.size()
		report.rounds.append(cycle_stats.duplicate(true))
		_expect(cycle_stats.rewarded_events > 0, "real battle produced rewardable events")
		_transaction_stress(2000 if index == 0 else 100)
		var old_focus: WeakRef = weakref(focus)
		var old_world: WeakRef = weakref(world)
		var old_units: Array[WeakRef] = []
		for unit in _units(world): old_units.append(weakref(unit))
		_stop_audit()
		await _empty_world()
		await _settle()
		_expect(old_world.get_ref() == null and old_focus.get_ref() == null, "old world and pool released")
		for ref in old_units: _expect(ref.get_ref() == null, "old unit released")
		_record_cleanup(index)
	# 反复按正式 SceneTree 切换路径加载/卸载，不手工修补技能 Host 的范围。
	for index in range(reloads):
		if not await _load_world():
			_finish()
			return
		_expect(is_equal_approx(focus.get_current_focus(), focus.initial_focus), "reload initial resource")
		var all_units: Array[UnitBase] = _units(world)
		var enemy: UnitBase
		for u in all_units:
			if u.faction_id == "Enemy":
				enemy = u
				break
		if last_event != null and enemy != null:
			var before: float = focus.get_current_focus()
			enemy.damage_resolved.emit(last_event)
			_expect(focus.get_current_focus() == before, "old damage event cannot reward new scene")
		var old_pool: WeakRef = weakref(focus)
		world = null
		focus = null
		await _empty_world()
		await _settle()
		_expect(old_pool.get_ref() == null, "reload pool released")
		_record_cleanup(cycles + index)
	_finish()

func _load_world() -> bool:
	var code: Error = change_scene_to_file(ROOM_PATH)
	if code != OK:
		_expect(false, "formal scene load returned " + str(code))
		return false
	await scene_changed
	await _settle()
	world = current_scene as Node3D
	focus = world.get_node_or_null("SquadFocusComponent") as SquadFocusComponent
	if focus == null:
		_expect(false, "formal scene has no saved focus component")
		return false
	return true

func _empty_world() -> void:
	# 与 GameRunController 正式重开流程一样，先通知遭遇系统这是合法卸载。
	if is_instance_valid(current_scene):
		var encounter = current_scene.get_node_or_null("EncounterController")
		if encounter is EncounterController: encounter.begin_scene_unload()
	world = null
	focus = null
	var node: Node3D = Node3D.new()
	node.name = "AuditIdleWorld"
	var packed: PackedScene = PackedScene.new()
	packed.pack(node)
	node.free()
	change_scene_to_packed(packed)
	await scene_changed
	await _settle()

func _settle() -> void:
	for _i in range(4): await process_frame
	await physics_frame

func _start_audit() -> void:
	party.clear()
	actor_names.clear()
	seen.clear()
	current_callbacks.clear()
	expected = focus.get_current_focus()
	cycle_stats = {"all_events": 0, "rewarded_events": 0, "rewarded_damage": 0.0, "excluded_events": 0, "scope_mismatches": 0, "cap_resets": 0, "max_error": 0.0, "skills": {}, "casters": {}}
	for unit in _units(world):
		actor_names[unit.get_instance_id()] = str(unit.name)
		if unit.faction_id in ["Player", "Ally"]: party[unit.get_instance_id()] = unit.team_id
		unit.damage_resolved.connect(_on_damage)
		current_callbacks.append(weakref(unit))

func _stop_audit() -> void:
	for ref in current_callbacks:
		var unit = ref.get_ref()
		if is_instance_valid(unit) and unit.damage_resolved.is_connected(_on_damage): unit.damage_resolved.disconnect(_on_damage)
	current_callbacks.clear()
	party.clear()
	actor_names.clear()
	seen.clear()

func _on_damage(event: CombatDamageEvent) -> void:
	if not is_instance_valid(focus): return
	cycle_stats.all_events += 1
	_expect(not seen.has(event.event_id), "event ID unique for actual published damage")
	seen[event.event_id] = true
	last_event = event
	_expect(is_finite(event.actual_damage) and event.actual_damage > 0.0 and is_equal_approx(event.actual_damage, event.health_before - event.health_after), "actual finite positive damage agrees with health delta")
	var friendly_source: bool = party.has(event.source_instance_id) and party[event.source_instance_id] == event.source_team_id
	var hostile_target: bool = event.target_team_id != 0 and event.target_team_id != event.source_team_id
	if friendly_source and hostile_target and event.focus_yield_multiplier > 0.0:
		cycle_stats.rewarded_events += 1
		cycle_stats.rewarded_damage += event.actual_damage
		if event.scene_scope_id != world.get_instance_id(): cycle_stats.scope_mismatches += 1
		var gain: float = event.actual_damage * event.focus_yield_multiplier * focus.damage_to_focus_ratio
		expected = minf(expected + gain, focus.get_maximum_focus())
		var skill_key: String = str(event.skill_id) if not event.skill_id.is_empty() else "ordinary_attack"
		cycle_stats.skills[skill_key] = int(cycle_stats.skills.get(skill_key, 0)) + 1
		var caster_key: String = str(actor_names.get(event.source_instance_id, "departed_source"))
		cycle_stats.casters[caster_key] = int(cycle_stats.casters.get(caster_key, 0)) + 1
	else:
		cycle_stats.excluded_events += 1
	_assert_balance("actual damage callback")

func _assert_balance(label: String) -> void:
	var error: float = absf(focus.get_current_focus() - expected)
	cycle_stats.max_error = maxf(cycle_stats.max_error, error)
	if error > 0.00001: _expect(false, label + ": actual=" + str(focus.get_current_focus()) + " expected=" + str(expected))
	_expect(is_finite(focus.get_current_focus()) and focus.get_available_focus() >= 0.0 and focus.get_current_focus() <= focus.get_maximum_focus(), "resource bounds finite")
	_expect(focus.get_reserved_focus() == 0.0, "unrequested reservation remains zero")

func _check_connections() -> void:
	var tree_connections: int = 0
	for connection in node_added.get_connections():
		if connection.callable.get_object() == focus: tree_connections += 1
	_expect(tree_connections == 1, "one global node-added connection per active pool")
	for unit in _units(world):
		var count: int = 0
		for connection in unit.damage_resolved.get_connections():
			if connection.callable.get_object() == focus: count += 1
		_expect(count == 1, "one damage listener per observed unit")

func _transaction_stress(count: int) -> void:
	var ledger: ComboCostLedger = ComboCostLedger.new()
	var before: float = focus.get_current_focus()
	for index in range(count):
		var round_id: int = CombatDamageContext.allocate_id()
		var request: int = CombatDamageContext.allocate_id()
		_expect(focus.reserve(request, 0.0), "zero promise accepted")
		if index % 2 == 0:
			_expect(focus.commit(request, 0.0) and not focus.commit(request, 0.0), "commit is single-shot")
		else:
			_expect(focus.refund(request) and not focus.refund(request), "refund is single-shot")
		_expect(focus.release_request(request), "terminal resource record released")
		_expect(ledger.register_request(request, round_id, 1, &"audit", 20.0, 10.0), "ledger register")
		if index % 3 == 0: ledger.mark_failed(request)
		else: _expect(ledger.mark_released(request) == 20.0, "new round fee")
		ledger.close_round(round_id)
		ledger.release_request(request)
	_expect(focus.get("_transactions").is_empty() and focus.get_reserved_focus() == 0.0 and focus.get_current_focus() == before, "transaction stress clears all records without pool drift")
	_expect(ledger.get("_records").is_empty() and ledger.get("_successes").is_empty(), "closed ledger records collected")
	report.transaction_count += count

func _record_cleanup(index: int) -> void:
	var nodes: int = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var orphans: int = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	var focus_callbacks: int = 0
	for connection in node_added.get_connections():
		if is_instance_valid(connection.callable.get_object()) and connection.callable.get_object() is SquadFocusComponent: focus_callbacks += 1
	var paths: Array[String] = _node_paths(root)
	var added: Array[String] = []
	for path in paths:
		if not baseline_paths.has(path): added.append(path)
	report.cleanup.append({"added_paths":added,"actual_nodes":get_node_count(),"iteration":index,"nodes":nodes,"baseline_nodes":baseline_nodes,"orphans":orphans,"baseline_orphans":baseline_orphans,"focus_callbacks":focus_callbacks,"objects":int(Performance.get_monitor(Performance.OBJECT_COUNT)),"resources":int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),"static_memory":int(Performance.get_monitor(Performance.MEMORY_STATIC))})
	_expect(nodes == baseline_nodes, "no residual scene nodes after reload " + str(index))
	_expect(orphans == baseline_orphans, "no new orphan nodes after reload " + str(index))
	_expect(focus_callbacks == 0, "no old focus connection after reload")

func _node_paths(node: Node) -> Array[String]:
	var paths: Array[String] = [str(node.get_path())]
	for child in node.get_children(): paths.append_array(_node_paths(child))
	return paths

func _units(node: Node) -> Array[UnitBase]:
	var result: Array[UnitBase] = []
	if node is UnitBase: result.append(node)
	for child in node.get_children(): result.append_array(_units(child))
	return result

func _argument(key: String, fallback: int) -> int:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--" + key + "="): return maxi(arg.get_slice("=", 1).to_int(), 1)
	return fallback

func _expect(ok: bool, message: String) -> void:
	if not ok and not failures.has(message): failures.append(message)

func _finish() -> void:
	_stop_audit()
	last_event = null
	report["failures"] = failures
	print("SquadFocusSceneAudit: " + JSON.stringify(report))
	for failure in failures: push_error(failure)
	print("SquadFocusSceneAudit: PASS" if failures.is_empty() else "SquadFocusSceneAudit: FAIL")
	quit(0 if failures.is_empty() else 1)
