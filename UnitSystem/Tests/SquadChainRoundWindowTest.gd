extends SceneTree
## 正式轮次契约：查询不创建批次，真实Host/Focus接管，弱所有权不误撤销。
const FIXTURE = preload("res://UnitSystem/Tests/AllyChainCommandPriorityTest.gd")
const ROUND_PATH = "res://UnitSystem/Components/Combat/Squad/SquadChainRoundController.gd"
var failures: Array[String] = []

## parent为有效测试树；返回真实角色、Host、Focus、指令与评价，不向正式关卡写入单位。
static func make_fixture(parent: Node) -> Dictionary:
	var f := FIXTURE.make_fixture(parent, "res://UnitSystem/AI/Ally/Units/Caster.tscn", false)
	var focus := SquadFocusComponent.new()
	focus.auto_bind_parent = false
	focus.initial_focus = 100.0
	f.world.add_child(focus)
	var party: Array[UnitBase] = [f.player, f.actor]
	focus.bind_scope(f.world, party)
	var commander := SquadChainCommandController.new()
	var slots: Array[AllyBase] = [f.actor, null, null, null]
	commander.companions = slots
	commander.focus_source = focus
	f.world.add_child(commander)
	f.focus = focus
	f.commander = commander
	commander.command_accepted.connect(func(request): f.requests[request.request_id] = request)
	var evaluator = load(ROUND_PATH).new()
	evaluator.command_source = commander
	f.world.add_child(evaluator)
	evaluator.set_physics_process(false)
	f.round = evaluator
	return f

func _initialize() -> void: call_deferred(&"_run")
func _run() -> void:
	if not ResourceLoader.exists(ROUND_PATH):
		_expect(false, "formal round provider is missing; UI cannot create real rounds")
		_finish()
		return
	await _test_pending_is_lazy_and_shared()
	await _test_pending_zero_activity_cleans_without_result()
	await _test_acquire_rollback_cleans_empty_round()
	await _test_provider_ownership_is_compare_and_clear()
	await _test_released_identity_query()
	await _test_first_damage_and_deadlines()
	await _test_strict_expiry_before_sweep()
	await _test_delta_fraction_and_pause()
	await _test_event_and_hit_dedup()
	await _test_score_three_paths_and_snapshot()
	await _test_aoe_and_invalid_events()
	await _test_close_once_and_reentry()
	await _test_invalid_configuration_fails_closed()
	_finish()

func _test_pending_is_lazy_and_shared() -> void:
	var f := make_fixture(root)
	await physics_frame
	for i in range(100):
		f.commander.get_slot_status(0)
		f.round.get_round_status()
		_expect(f.round.peek_current_round() == 0, "UI queries must not allocate a round")
	_expect(f.commander.submit_slot(0), "first real command accepted")
	var first := int(f.round.peek_current_round())
	_expect(first > 0 and f.round.get_round_status().phase == 1, "accepted request owns pending round")
	f.host.advance_pending_command(f.enemy, 0.0)
	_expect(f.commander.submit_slot(0), "pending successor accepted")
	_expect(f.round.peek_current_round() == first, "requests before first damage share round")
	_expect(is_equal_approx(f.focus.get_reserved_focus(), 50.0), "original reservation 20+30 unchanged")
	f.world.free()
	await process_frame

func _test_pending_zero_activity_cleans_without_result() -> void:
	var f := make_fixture(root)
	await physics_frame
	var finished: Array = []
	var qualified: Array = []
	f.round.round_finished.connect(func(result): finished.append(result))
	f.round.finisher_qualified.connect(func(result): qualified.append(result))
	_expect(f.commander.submit_slot(0), "empty pending admitted")
	var id: int = f.requests.keys()[0]
	f.host.cancel_command(id, &"test_no_damage")
	_expect(f.round.peek_current_round() == 0 and f.round.get_round_status().phase == 0, "last failed request clears pending")
	_expect(finished.is_empty() and qualified.is_empty(), "empty round has no score result or qualification")
	_expect(is_equal_approx(f.focus.get_reserved_focus(), 0.0), "pending failure refunds original reserve")
	f.world.free()
	await process_frame

func _test_acquire_rollback_cleans_empty_round() -> void:
	var f := make_fixture(root)
	await physics_frame
	var generation := int(f.commander.get("_generation"))
	# acquire之后、正式登记前的同步无效化，原指令必须报告活动数0。
	f.round.round_state_changed.connect(func(snapshot):
		if snapshot.phase == 1: f.commander.set("_generation", generation+1))
	_expect(not f.commander.submit_slot(0), "admission invalidated during acquire")
	_expect(f.round.peek_current_round() == 0, "rolled back acquisition cannot leave phantom pending")
	_expect(f.focus.get_reserved_focus() == 0.0, "failed admission leaves no reserve")
	f.world.free()
	await process_frame

func _test_provider_ownership_is_compare_and_clear() -> void:
	var f := make_fixture(root)
	await physics_frame
	var second = load(ROUND_PATH).new()
	second.command_source = f.commander
	f.world.add_child(second)
	_expect(not second.get_round_status().bound, "duplicate evaluator remains inert")
	second.free()
	_expect(f.commander.submit_slot(0), "destroying rejected evaluator preserves original provider")
	var first: int = f.round.peek_current_round()
	var other_peek := func(): return 0
	var other_acquire := func(): return CombatDamageContext.allocate_id()
	f.commander.set_round_source(other_peek, other_acquire)
	f.round.free()
	_expect(f.commander.get("_peek_round") == other_peek, "old owner cannot clear replacement callable")
	_expect(first > 0, "original provider really used")
	f.world.free()
	await process_frame

func _test_released_identity_query() -> void:
	var f := make_fixture(root)
	await physics_frame
	_expect(f.commander.submit_slot(0), "identity probe admitted")
	var request: SkillCommandRequest = f.requests.values()[0]
	var args := [request.request_id, request.round_id, request.caster_instance_id, request.scene_scope_id]
	_expect(not f.commander.callv("is_released_request", args), "unreleased root is not damage authority")
	f.host.advance_pending_command(f.enemy, 0.0)
	f.animation.release_action()
	_expect(f.commander.callv("is_released_request", args), "real accepted release authorizes matching identity")
	for index in range(4):
		var wrong := args.duplicate()
		wrong[index] += 999999
		_expect(not f.commander.callv("is_released_request", wrong), "each root identity must match")
	f.world.free()
	await process_frame


## 真实受理和释放；保留测试交付token，精确驱动不受弹道时间影响。
static func start_released(f: Dictionary) -> SkillCommandRequest:
	f.commander.submit_slot(0)
	var request: SkillCommandRequest = f.requests.values().back()
	request.retain_delivery(CombatDamageContext.allocate_id())
	f.host.advance_pending_command(f.enemy, 0.0)
	f.animation.release_action()
	return request

## amount为真实生命损失请求，hit为同次命中身份；不伪造计分信号。
static func deal(f: Dictionary, request: SkillCommandRequest, amount: float, hit: int = 0) -> CombatDamageContext:
	var context := CombatDamageContext.create(f.actor,f.world,CombatDamageContext.Origin.CHAIN,request.request_id,request.round_id,f.combo.skill_id).for_hit(hit)
	f.enemy.apply_damage(amount,f.actor,1.0,context)
	return context

static func advance(f: Dictionary, seconds: float, sweep: bool = true) -> void:
	f.round.call("_physics_process",seconds)
	if sweep: f.round.call("_finish_frame",f.round.get("_clock_frame"),f.round.get("_generation"))

func _test_first_damage_and_deadlines() -> void:
	var f := make_fixture(root)
	await physics_frame
	var request := start_released(f)
	_expect(f.round.get_round_status().phase == 1, "release/VFX alone cannot open damage window")
	var normal := CombatDamageContext.create(f.actor,f.world)
	f.enemy.apply_damage(5,f.actor,1,normal)
	_expect(f.round.get_round_status().phase == 1, "normal damage cannot open chain")
	deal(f,request,25)
	var snapshot: Dictionary = f.round.get_round_status()
	_expect(snapshot.phase == 2 and snapshot.hit_count == 1 and is_equal_approx(snapshot.total_damage,25), "first actual chain damage counts before opening")
	_expect(is_equal_approx(snapshot.remaining_seconds,2), "first damage opens two-second interval")
	advance(f,2.0,false)
	deal(f,request,25)
	_expect(f.round.get_round_status().hit_count == 2, "exact deadline must accept damage")
	advance(f,2.0)
	_expect(f.round.peek_current_round() == request.round_id, "end sweep at exact deadline keeps round")
	for i in range(10):
		deal(f,request,1)
		advance(f,1.0)
	_expect(f.round.peek_current_round() == request.round_id, "continuous damage has no ten-second whole-round limit")
	f.world.free()
	await process_frame

func _test_strict_expiry_before_sweep() -> void:
	var f := make_fixture(root)
	await physics_frame
	var request := start_released(f)
	deal(f,request,25)
	var finished: Array = []
	f.round.round_finished.connect(func(result): finished.append(result))
	advance(f,2.000001,false)
	_expect(f.round.peek_current_round() == 0, "strictly expired peek hides old round before deferred sweep")
	_expect(finished.is_empty(), "peek never settles expired round")
	var next: int = f.round.acquire_round()
	_expect(next > request.round_id and finished.size() == 1, "acquire first closes expired round and starts larger identity")
	deal(f,request,25)
	_expect(f.round.get_round_status().phase == 1 and f.round.get_round_status().hit_count == 0, "old late hit cannot open new pending round")
	f.world.free()
	await process_frame

func _test_delta_fraction_and_pause() -> void:
	for steps in [60,120,1000]:
		var f := make_fixture(root)
		var before := int(f.round.get("_clock_usec"))
		for i in range(steps): advance(f,1.0/float(steps),false)
		_expect(absi(int(f.round.get("_clock_usec"))-before-1000000) <= 1, "fractional delta residual avoids accumulated drift")
		var now := int(f.round.get("_clock_usec"))
		for bad in [-1.0,NAN,INF]: advance(f,bad,false)
		_expect(int(f.round.get("_clock_usec")) == now, "nonfinite/negative delta cannot advance battle time")
		f.world.free()
	var f := make_fixture(root)
	await physics_frame
	var request := start_released(f)
	deal(f,request,25)
	f.round.set_physics_process(true)
	var before := int(f.round.get("_clock_usec"))
	paused = true
	await create_timer(0.05,true).timeout
	_expect(int(f.round.get("_clock_usec")) == before, "real tree pause freezes clock even while physics identities advance")
	_expect(is_equal_approx(f.round.get_round_status().remaining_seconds,2.0), "pause freezes business interval")
	paused = false
	await physics_frame
	await physics_frame
	_expect(int(f.round.get("_clock_usec")) > before, "battle clock resumes after pause")
	var pause_manager := GamePauseCoordinator.new()
	f.world.add_child(pause_manager)
	_expect(pause_manager.bind_scope(f.world), "existing pause coordinator binds")
	var accent_before := int(f.round.get("_clock_usec"))
	var accent_remaining: float = f.round.get_round_status().remaining_seconds
	_expect(pause_manager.request_release_accent(CombatDamageContext.allocate_id(),0.10,f.world) > 0, "existing release accent starts")
	await create_timer(0.03,true).timeout
	_expect(paused and int(f.round.get("_clock_usec")) == accent_before, "real release accent freezes evaluation clock")
	_expect(is_equal_approx(f.round.get_round_status().remaining_seconds,accent_remaining), "accent uses battle remaining not wall clock")
	await create_timer(0.12,true).timeout
	_expect(not paused, "accent ends without evaluator pause ownership")
	f.world.free()
	await process_frame


func _test_event_and_hit_dedup() -> void:
	var f := make_fixture(root)
	await physics_frame
	var request := start_released(f)
	var events: Array = []
	f.enemy.damage_resolved.connect(func(event): events.append(event))
	var hit := CombatDamageContext.allocate_id()
	deal(f,request,10,hit)
	deal(f,request,15,hit)
	_expect(f.round.get_round_status().hit_count == 1, "same hit split into two damage effects counts once")
	_expect(is_equal_approx(f.round.get_round_status().total_damage,25), "split hit sums real damage")
	_expect(is_equal_approx(f.round.get_round_status().score,10), "one hit plus25 damage equals10 score")
	advance(f,1.0)
	f.enemy.damage_resolved.emit(events[0])
	_expect(f.round.get_round_status().hit_count == 1 and is_equal_approx(f.round.get_round_status().total_damage,25), "duplicate event adds neither H nor D")
	_expect(is_equal_approx(f.round.get_round_status().remaining_seconds,1.0), "duplicate event cannot refresh interval")
	f.world.free()
	await process_frame

func _test_score_three_paths_and_snapshot() -> void:
	for row in [[20,1.0,104.0],[1,500.0,105.0],[10,25.0,100.0],[1,25.0,10.0]]:
		var f := make_fixture(root)
		await physics_frame
		var request := start_released(f)
		var finished: Array = []
		var qualified: Array = []
		f.round.round_finished.connect(func(result): finished.append(result))
		f.round.finisher_qualified.connect(func(result): qualified.append(result))
		for i in range(row[0]): deal(f,request,row[1])
		_expect(is_equal_approx(f.round.get_round_status().score,row[2]), "hand-derived score path "+str(row))
		_expect(qualified.is_empty(), "ready round never qualifies before gap ends")
		f.round.damage_interval_seconds = 0.5
		f.round.hit_score_scale = 1
		f.round.damage_score_scale = 1
		_expect(is_equal_approx(f.round.get_round_status().interval_seconds,2), "current round retains captured interval")
		advance(f,2.000001)
		advance(f,1)
		_expect(finished.size() == 1 and qualified.size() == (1 if row[2] >= 100 else 0), "one closure and only qualifying score event")
		if not finished.is_empty():
			_expect(is_equal_approx(finished[0].score,row[2]), "config changes cannot retroactively score current round")
			var copy: Dictionary = f.round.get_round_status()
			copy.last_result.score = -1
			_expect(is_equal_approx(f.round.get_round_status().last_result.score,row[2]), "snapshot returns deep value copy")
		var next: int = f.round.acquire_round()
		_expect(next > request.round_id and is_equal_approx(f.round.get_round_status().interval_seconds,0.5), "next round captures edited scale and gap")
		f.world.free()
		await process_frame
	var f := make_fixture(root)
	await physics_frame
	var request := start_released(f)
	f.enemy.maximum_health = 5
	f.enemy.set("_current_health",5.0)
	deal(f,request,500)
	_expect(is_equal_approx(f.round.get_round_status().total_damage,5), "overkill counts only remaining5 health")
	f.world.free()
	await process_frame

func _test_aoe_and_invalid_events() -> void:
	var f := make_fixture(root)
	await physics_frame
	var request := start_released(f)
	var context := CombatDamageContext.create(f.actor,f.world,CombatDamageContext.Origin.CHAIN,request.request_id,request.round_id).for_hit(CombatDamageContext.allocate_id())
	var targets: Array[UnitBase] = [f.enemy]
	for i in range(4):
		var enemy := UnitBase.new()
		enemy.team_id = 2
		f.world.add_child(enemy)
		targets.append(enemy)
	for target in targets: target.apply_damage(10,f.actor,1,context)
	_expect(f.round.get_round_status().hit_count == 5, "same AoE hit on five enemies counts five")
	advance(f,1)
	var valid_event := CombatDamageEvent.create(context,f.enemy,100,90)
	for field in ["origin","round_id","request_id","source_instance_id","scene_scope_id","source_team_id","target_team_id","actual_damage"]:
		var invalid := CombatDamageEvent.new()
		invalid.set("_data",valid_event.get("_data").duplicate())
		var data: Dictionary = invalid.get("_data")
		data.event_id = CombatDamageContext.allocate_id()
		data[field] = NAN if field == "actual_damage" else 0
		f.enemy.damage_resolved.emit(invalid)
	_expect(f.round.get_round_status().hit_count == 5 and is_equal_approx(f.round.get_round_status().total_damage,50), "adversarial invalid metadata never scores")
	_expect(is_equal_approx(f.round.get_round_status().remaining_seconds,1), "invalid event never refreshes")
	f.world.free()
	await process_frame

func _test_close_once_and_reentry() -> void:
	for mode in ["next","unbind","remove"]:
		var f := make_fixture(root)
		await physics_frame
		var request := start_released(f)
		deal(f,request,500)
		var finished: Array = []
		var qualified: Array = []
		var next_rounds: Array = []
		f.round.finisher_qualified.connect(func(result): qualified.append(result))
		f.round.round_finished.connect(func(result):
			finished.append(result)
			if mode == "next": next_rounds.append(f.round.acquire_round())
			elif mode == "unbind": f.focus.unbind_scope()
			else: f.round.queue_free())
		advance(f,2.000001,false)
		f.round.call("_finish_frame",f.round.get("_clock_frame"),f.round.get("_generation"))
		_expect(finished.size() == 1, "closure signals exactly once under reentrant "+mode)
		_expect(qualified.size() == (1 if mode == "next" else 0), "scope/removal invalidation suppresses stale qualification")
		if mode == "next":
			_expect(next_rounds[0] > request.round_id and f.round.peek_current_round() == next_rounds[0], "closing old round must not clear reentrant new round")
		f.world.free()
		await process_frame


func _test_invalid_configuration_fails_closed() -> void:
	for entry in [["damage_interval_seconds",0.0],["damage_interval_seconds",NAN],["damage_interval_seconds",INF],["hit_score_scale",0],["damage_score_scale",-1.0],["damage_score_scale",INF]]:
		var f := make_fixture(root)
		await physics_frame
		f.round.set(entry[0],entry[1])
		_expect(f.round.acquire_round() == 0 and f.round.peek_current_round() == 0, "invalid configuration refuses new round "+str(entry[0]))
		_expect(f.focus.get_reserved_focus() == 0 and f.focus.get_current_focus() == 100, "invalid evaluator never pays or resets focus")
		f.world.free()
		await process_frame

func _expect(condition: bool, message: String) -> void:
	if not condition: failures.append(message)
func _finish() -> void:
	for message in failures: push_error(message)
	if failures.is_empty(): print("SquadChainRoundWindowTest: PASS")
	quit(0 if failures.is_empty() else 1)
