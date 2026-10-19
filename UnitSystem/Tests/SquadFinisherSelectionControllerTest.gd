extends SceneTree
## 验证输入持有不误开启旧禁用，不撤销已受理技能；后续覆盖终结选择真实流程。
const W = preload("res://UnitSystem/Tests/SquadChainRoundWindowTest.gd")
const SELECTION = "res://UnitSystem/Components/Combat/Squad/SquadFinisherSelectionController.gd"
var failures: Array[String] = []
func _initialize() -> void: call_deferred(&"_run")
func _run() -> void:
	var probe := SquadChainCommandController.new()
	if not probe.has_method("acquire_input_block"):
		_expect(false,"missing owned input blocking interface")
		probe.free()
		_finish()
		return
	probe.free()
	if OS.get_cmdline_user_args().has("--review-only"):
		await _test_cancel_during_acquisition_rolls_back()
		await _test_rebind_cannot_replay_consumed_round()
		await _test_queued_deletion_on_closed()
		_finish()
		return
	await _test_input_block_preserves_other_owners()
	await _test_input_block_does_not_cancel_pending()
	if not ResourceLoader.exists(SELECTION):
		_expect(false,"missing finisher selection controller")
		_finish()
		return
	await _test_only_qualified_closed_round_opens()
	await _test_real_three_seconds_at_five_percent()
	await _test_external_pause_freezes_remaining()
	await _test_live_availability_and_no_effect()
	await _test_dead_and_cross_world_choices()
	await _test_cleanup_and_reentry()
	await _test_50_selection_cycles_and_10_world_reloads()
	await _test_cancel_during_acquisition_rolls_back()
	await _test_rebind_cannot_replay_consumed_round()
	await _test_queued_deletion_on_closed()
	_finish()

func _test_input_block_preserves_other_owners() -> void:
	var f := W.make_fixture(root)
	await physics_frame
	var a: int = f.commander.acquire_input_block(f.actor,&"selection")
	var b: int = f.commander.acquire_input_block(f.player,&"menu")
	f.commander.release_input_block(a)
	_expect(not f.commander.submit_slot(0),"one owner cannot enable another owner's block")
	f.commander.set_input_enabled(false)
	f.commander.release_input_block(b)
	f.commander.release_input_block(b)
	_expect(not f.commander.submit_slot(0),"release preserves original disabled flag")
	f.commander.set_input_enabled(true)
	_expect(f.commander.submit_slot(0),"new request resumes after all owned blocks end")
	var alien := Node.new()
	root.add_child(alien)
	_expect(f.commander.acquire_input_block(alien,&"alien") == 0,"cross-world input owner rejected")
	alien.free()
	f.world.free()
	await process_frame

func _test_input_block_does_not_cancel_pending() -> void:
	var f := W.make_fixture(root)
	await physics_frame
	_expect(f.commander.submit_slot(0),"pending request admitted")
	var before: Dictionary = f.commander.get_slot_status(0)
	var reserved: float = f.focus.get_reserved_focus()
	var owner := Node.new()
	f.world.add_child(owner)
	var token: int = f.commander.acquire_input_block(owner,&"selection")
	_expect(not f.commander.submit_slot(0),"new requests blocked")
	_expect(f.commander.get_slot_status(0).pending_request_id == before.pending_request_id,"pending request retained")
	_expect(is_equal_approx(f.focus.get_reserved_focus(),reserved),"reservation unchanged")
	f.host.advance_pending_command(f.enemy,0)
	f.animation.release_action()
	_expect(f.focus.get_current_focus() == 80,"blocked input does not reject existing release")
	f.animation.finish_action()
	owner.free()
	await process_frame
	_expect(f.commander.acquire_input_block(f.actor,&"new") > token,"tokens monotonic")
	f.focus.unbind_scope()
	f.commander.release_input_block(token)
	f.world.free()
	await process_frame

## 测试夹具使用真实评价/Host与暂停协调；不写入正式关卡。
static func make_selection_fixture(parent: Node, duration: float = 3.0) -> Dictionary:
	var f := W.make_fixture(parent)
	var pause := GamePauseCoordinator.new()
	f.world.add_child(pause)
	pause.bind_scope(f.world)
	var selection = load(SELECTION).new()
	selection.round_source = f.round
	selection.pause_source = pause
	selection.selection_duration_seconds = duration
	f.world.add_child(selection)
	f.pause = pause
	f.selection = selection
	return f

## 真实释放及伤害，手动推进夹具的2秒业务间隔；不是伪造资格。
static func qualify(f: Dictionary) -> void:
	var request := W.start_released(f)
	W.deal(f,request,500.0)
	W.advance(f,2.000001)

func _test_only_qualified_closed_round_opens() -> void:
	var f := make_selection_fixture(root)
	await physics_frame
	var chosen: Array = []
	var ended: Array = []
	f.selection.finisher_selected.connect(func(result): chosen.append(result))
	f.selection.selection_closed.connect(func(result): ended.append(result))
	var request := W.start_released(f)
	W.deal(f,request,500.0)
	_expect(f.round.get_round_status().finisher_ready and f.selection.get_selection_status().phase == 0,"scoring threshold does not open early")
	W.advance(f,2.000001)
	_expect(f.selection.get_selection_status().phase == 1 and is_equal_approx(Engine.time_scale,0.05),"closed qualified round opens window at5percent")
	var result: Dictionary = f.round.get_round_status().last_result
	f.round.finisher_qualified.emit(result)
	var snapshot: Dictionary = f.selection.get_selection_status()
	snapshot.slots[0].actor_name = "mutated"
	_expect(f.selection.get_selection_status().slots[0].actor_name != "mutated","snapshot independent")
	_expect(f.selection.try_select_slot(0) and not f.selection.try_select_slot(0),"one choice only")
	_expect(chosen.size() == 1 and chosen[0].round_id == request.round_id and chosen[0].slot_index == 0,"choice preserves identity")
	await _wait(0.27)
	_expect(ended.size() == 1 and ended[0].reason == &"selected" and is_equal_approx(Engine.time_scale,1),"success closes and restores")
	f.round.finisher_qualified.emit(result)
	_expect(f.selection.get_selection_status().phase == 0,"no repeated qualification")
	f.selection.free()
	var fresh = load(SELECTION).new()
	fresh.round_source = f.round
	fresh.pause_source = f.pause
	f.world.add_child(fresh)
	await process_frame
	_expect(fresh.get_selection_status().phase == 0,"late binding does not replay last result")
	f.world.free()
	await process_frame

func _test_real_three_seconds_at_five_percent() -> void:
	var f := make_selection_fixture(root)
	await physics_frame
	qualify(f)
	var start := Time.get_ticks_usec()
	await _wait(3.14)
	_expect(f.selection.get_selection_status().phase == 0,"3real seconds plus close finishes at5percent")
	_expect(is_equal_approx(Engine.time_scale,1) and float(Time.get_ticks_usec()-start)/1000000.0 < 3.5,"real deadline not scaled to60seconds")
	f.world.free()
	await process_frame

func _test_external_pause_freezes_remaining() -> void:
	var f := make_selection_fixture(root,0.5)
	await physics_frame
	qualify(f)
	await _wait(0.08)
	var token: int = f.pause.acquire_pause(f.world,&"menu")
	var before: float = f.selection.get_selection_status().remaining_seconds
	await _wait(0.25)
	_expect(absf(f.selection.get_selection_status().remaining_seconds-before) < 0.015 and not f.selection.try_select_slot(0),"explicit pause suspends countdown and input")
	f.pause.release_pause(token)
	await _wait(0.08)
	_expect(f.selection.get_selection_status().remaining_seconds < before-0.04,"resume does not charge paused interval")
	f.selection.cancel_selection(&"test")
	_expect(not paused and is_equal_approx(Engine.time_scale,1),"cancel releases own state")
	f.world.free()
	await process_frame

func _test_live_availability_and_no_effect() -> void:
	var f := make_selection_fixture(root)
	# 此用例明确验证未配置执行provider的纯选择接口，不依赖Caster内容槽的默认装配。
	f.actor.get_node("SkillHost").finisher_skill = null
	await physics_frame
	qualify(f)
	var health: float = f.enemy.get_current_health()
	var focus: float = f.focus.get_current_focus()
	var pending: int = f.commander.get_slot_status(0).pending_request_id
	_expect(f.actor.get_node("SkillHost").get_finisher_skill() == null and f.selection.get_selection_status().slots[0].available,"unequipped finisher is testable")
	_expect(not f.selection.try_select_slot(1),"empty slot cannot select")
	_expect(f.selection.try_select_slot(0),"living companion selectable")
	_expect(f.enemy.get_current_health() == health and f.focus.get_current_focus() == focus and f.commander.get_slot_status(0).pending_request_id == pending,"selection has no combat effects")
	f.selection.cancel_selection(&"test")
	f.world.free()
	await process_frame
	f = make_selection_fixture(root)
	await physics_frame
	f.commander.companions.assign([f.actor,f.actor,null,null])
	await process_frame
	# 真实资格在重复伙伴装配下不能受理，因此先产生资格，再改变名单。
	f.commander.companions.assign([f.actor,null,null,null])
	await process_frame
	qualify(f)
	f.commander.companions.assign([f.actor,f.actor,null,null])
	_expect(not f.selection.try_select_slot(0) and not f.selection.try_select_slot(1),"duplicate companions cannot select")
	await process_frame
	await process_frame
	_expect(f.selection.get_selection_status().phase == 0,"all invalid closes safely")
	var connections: Array = f.host.command_action_started.get_connections().filter(func(connection): return connection.callable.get_object() == f.commander)
	_expect(connections.is_empty(),"invalid duplicate companion must not connect host twice")
	f.world.free()
	await process_frame

func _test_dead_and_cross_world_choices() -> void:
	var f := make_selection_fixture(root)
	await physics_frame
	qualify(f)
	f.actor.can_die = true
	f.actor.apply_damage(99999)
	_expect(not f.selection.get_selection_status().slots[0].available and not f.selection.try_select_slot(0),"dead partner cannot select")
	await process_frame
	await process_frame
	_expect(f.selection.get_selection_status().phase == 0 and is_equal_approx(Engine.time_scale,1),"last living partner death closes safely")
	f.world.free()
	await process_frame
	f = make_selection_fixture(root)
	await physics_frame
	qualify(f)
	var alien = load("res://UnitSystem/AI/Ally/Units/Priest.tscn").instantiate()
	alien.automatic_skill_cast_enabled = false
	root.add_child(alien)
	f.commander.companions[1] = alien
	_expect(f.selection.get_selection_status().slots[1].reason == &"wrong_scope" and not f.selection.try_select_slot(1),"cross-world partner cannot select")
	alien.free()
	f.world.free()
	await process_frame

func _test_cleanup_and_reentry() -> void:
	for mode: String in ["selection","pause","round","scope"]:
		var f := make_selection_fixture(root)
		await physics_frame
		qualify(f)
		match mode:
			"selection": f.selection.free()
			"pause": f.pause.free()
			"round": f.round.free()
			"scope": f.focus.unbind_scope()
		await process_frame
		await process_frame
		_expect(is_equal_approx(Engine.time_scale,1),"dependency removal cannot leak slow: "+mode)
		f.world.free()
		await process_frame
	var f := make_selection_fixture(root)
	await physics_frame
	f.selection.finisher_selected.connect(func(_result): f.selection.cancel_selection(&"callback"))
	qualify(f)
	_expect(f.selection.try_select_slot(0),"choice accepted despite synchronous cancellation")
	_expect(is_equal_approx(Engine.time_scale,1) and f.selection.get_selection_status().phase == 0,"reentrant cancel leaves no hold")
	f.world.free()
	await process_frame

func _test_50_selection_cycles_and_10_world_reloads() -> void:
	var completed: int = 0
	for world_index in range(10):
		var f := make_selection_fixture(root,0.03)
		await physics_frame
		for cycle in range(5):
			f.focus.reset_focus()
			f.enemy.apply_healing(f.enemy.get_maximum_health())
			qualify(f)
			_expect(f.selection.get_selection_status().phase != 0,"stress real qualified closure opens")
			if cycle % 2 == 0: _expect(f.selection.try_select_slot(0),"stress selection")
			await _wait(0.26)
			_expect(f.selection.get_selection_status().phase == 0 and is_equal_approx(Engine.time_scale,1),"stress complete restores")
			_expect(f.commander.get("_input_blocks").is_empty() and f.pause.get("_scale_tokens").is_empty(),"no owned token accumulation")
			f.animation.finish_action()
			# 夹具显式retain的交付由测试自己结清，真实管线无永久保活。
			for request: SkillCommandRequest in f.requests.values():
				var tokens: Dictionary = request.get("_tokens")
				if tokens != null:
					for token in tokens.keys(): request.finish_delivery(token)
			completed += 1
		f.world.free()
		await process_frame
	_expect(completed == 50 and not paused and is_equal_approx(Engine.time_scale,1),"50 cycles 10 worlds clean")
	print("Finisher stress: cycles=50 worlds=10")

func _test_cancel_during_acquisition_rolls_back() -> void:
	var f := make_selection_fixture(root)
	await physics_frame
	var once: Array[bool] = [false]
	f.commander.slot_status_changed.connect(func(_slot):
		if not once[0] and f.selection.get_selection_status().phase == 1:
			once[0] = true
			f.selection.cancel_selection(&"acquisition_callback"))
	qualify(f)
	_expect(f.selection.get_selection_status().phase == 0 and f.commander.get("_input_blocks").is_empty(),"synchronous acquisition cancel rolls back returned input token")
	_expect(is_equal_approx(Engine.time_scale,1),"acquisition cancellation restores slow")
	f.world.free()
	await process_frame

func _test_rebind_cannot_replay_consumed_round() -> void:
	var f := make_selection_fixture(root)
	await physics_frame
	qualify(f)
	var result: Dictionary = f.round.get_round_status().last_result
	f.selection.cancel_selection(&"test")
	f.selection.round_source = null
	f.selection.call("_process",0.0)
	f.selection.round_source = f.round
	f.selection.call("_process",0.0)
	f.round.finisher_qualified.emit(result)
	_expect(f.selection.get_selection_status().phase == 0,"same settled round cannot replay after temporary rebind")
	f.world.free()
	await process_frame

func _test_queued_deletion_on_closed() -> void:
	for mode: String in ["detach","clock","input"]:
		var f := make_selection_fixture(root,0.02)
		await physics_frame
		qualify(f)
		var observer: WeakRef = weakref(f.selection)
		f.selection.selection_closed.connect(func(_result): f.selection.queue_free())
		if mode == "detach":
			f.focus.unbind_scope()
		else:
			f.selection.set_process(false)
			f.selection.set("_last_usec",Time.get_ticks_usec()-200000)
			if mode == "clock": f.selection.call("_process",0.0)
			else:
				var event := InputEventAction.new()
				event.action = &"squad_chain_1"
				event.pressed = true
				Input.parse_input_event(event)
				Input.flush_buffered_events()
				event = event.duplicate()
				event.pressed = false
				Input.parse_input_event(event)
				Input.flush_buffered_events()
		await process_frame
		_expect(observer.get_ref() == null and is_equal_approx(Engine.time_scale,1),"closed callback queued deletion safe: "+mode)
		f.world.free()
		await process_frame

func _wait(seconds: float) -> void:
	var deadline := Time.get_ticks_usec()+int(seconds*1000000)
	while Time.get_ticks_usec() < deadline: await process_frame
func _expect(ok: bool, label: String) -> void:
	if not ok: failures.append(label)
func _finish() -> void:
	Engine.time_scale = 1.0
	paused = false
	for label: String in failures: push_error(label)
	if failures.is_empty(): print("SquadFinisherSelectionControllerTest: PASS")
	quit(0 if failures.is_empty() else 1)
