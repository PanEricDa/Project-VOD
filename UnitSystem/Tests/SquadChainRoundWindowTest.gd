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

func _expect(condition: bool, message: String) -> void:
	if not condition: failures.append(message)
func _finish() -> void:
	for message in failures: push_error(message)
	if failures.is_empty(): print("SquadChainRoundWindowTest: PASS")
	quit(0 if failures.is_empty() else 1)
