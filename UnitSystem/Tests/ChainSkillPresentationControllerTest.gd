extends SceneTree
## 使用真实Commander/Focus/Host确认并发、乱序释放与暂停中的InputMap受理，不推进冻结AI。
var failures: Array[String] = []
func _initialize() -> void: call_deferred(&"_run")
func _run() -> void:
	if not ResourceLoader.exists("res://UnitSystem/Components/Combat/Squad/ChainSkillPresentationController.tscn"):
		_expect(false, "chain presentation requires explicit inspectable assembly")
		_finish()
		return
	await _test_explicit_pause_survives_command_rebind()
	await _test_duplicate_assembly_is_inert()
	await _test_nonpreemptive_camera_candidates()
	await _test_missing_channels_and_cast_watchdog()
	await _test_scope_change_during_instance_prepare()
	await _test_input_during_accent()
	await _test_preview_assembly_and_stress()
	_finish()
static func make_fixture(parent: Node) -> Dictionary:
	var f = load("res://UnitSystem/Tests/AllyChainCommandPriorityTest.gd").make_fixture(parent,"res://UnitSystem/AI/Ally/Units/Caster.tscn",false)
	var actor = load("res://UnitSystem/AI/Ally/Units/Caster.tscn").instantiate()
	actor.automatic_skill_cast_enabled = false
	actor.gravity_multiplier = 0
	actor.position = Vector3(0.5,0,0)
	f.world.add_child(actor)
	actor.set_physics_process(false)
	var host: SkillHostComponent = actor.get_node("SkillHost")
	host.configure_owner(actor,f.world)
	var animation = actor.get_node("Visual").find_child("CharacterAnimationPlayer",true,false)
	animation.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	actor.get_targeting_component().call("_set_locked_target",f.enemy)
	actor.get_targeting_component().set_physics_process(false)
	actor.get_behavior_state_machine().set_follow_target(f.player)
	var combo := host.get_combo_skill()
	combo.base_cast_time = 0.2
	combo.cast_range = 6
	f.combo.release_accent_profile = ReleaseAccentProfile.new()
	combo.release_accent_profile = ReleaseAccentProfile.new()
	f.combo.camera_effect_profile = SkillFocusCameraProfile.new()
	combo.camera_effect_profile = SkillFocusCameraProfile.new()
	var focus := SquadFocusComponent.new()
	focus.auto_bind_parent = false
	focus.initial_focus = 100
	f.world.add_child(focus)
	var party: Array[UnitBase] = [f.player,f.actor,actor]
	focus.bind_scope(f.world,party)
	var source := SquadChainCommandController.new()
	source.companions = [f.actor,actor,null,null]
	source.focus_source = focus
	f.world.add_child(source)
	source.set_round_source(func(): return 100,func(): return 100)
	var rig := CameraFollowController.new()
	var camera := Camera3D.new()
	camera.name = "Camera3D"
	rig.add_child(camera)
	f.world.add_child(rig)
	var presentation = load("res://UnitSystem/Components/Combat/Squad/ChainSkillPresentationController.tscn").instantiate()
	presentation.command_source = source
	presentation.camera_source = rig
	f.world.add_child(presentation)
	f.merge({"actor2":actor,"host2":host,"animation2":animation,"source":source,"focus":focus,"rig":rig,"presentation":presentation,"pause":presentation.pause_source})
	return f
func _test_nonpreemptive_camera_candidates() -> void:
	var f = make_fixture(root)
	await physics_frame
	await physics_frame
	_expect(f.source.submit_slot(0) and f.source.submit_slot(1),"two partners admitted independently")
	f.actor.get_behavior_state_machine().physics_tick(0.01)
	var a = f.combo.get_current_presentation_context()
	f.actor2.get_behavior_state_machine().physics_tick(0.01)
	var b = f.host2.get_combo_skill().get_current_presentation_context()
	_expect(f.rig.get("_focus_id") == a.presentation_id, "second caster does not preempt first")
	f.animation2.release_action()
	_expect(f.focus.get_current_focus() == 80, "later root releases and pays first")
	f.animation.release_action()
	_expect(f.focus.get_current_focus() == 60, "earlier identity can release after later identity")
	await _wait(0.24)
	_expect(not paused and f.rig.get("_focus_id") == 0,"finished candidate never replayed; camera returns")
	f.world.free()
	await process_frame
	_expect(not paused,"world cleanup restores")
func _test_input_during_accent() -> void:
	var f = make_fixture(root)
	await physics_frame
	await physics_frame
	_expect(f.source.submit_slot(0),"first admitted")
	f.actor.get_behavior_state_machine().physics_tick(0.01)
	f.animation.release_action()
	_expect(paused,"first real release freezes battle")
	var before: float = f.focus.get_reserved_focus()
	var accepted: Array = []
	f.source.command_accepted.connect(func(request): accepted.append(request.request_id))
	var event := InputEventAction.new()
	event.action = &"squad_chain_2"
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	await process_frame
	_expect(accepted.size() == 1 and f.focus.get_reserved_focus() > before,"real input admitted and reserved during accent")
	_expect(f.host2.has_pending_command() and f.host2.get_active_command_id() == 0,"input must not execute paused AI")
	var token: int = f.pause.acquire_pause(f.world,&"menu")
	event = InputEventAction.new()
	event.action = &"squad_chain_1"
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	_expect(accepted.size() == 1,"explicit pause ignores input without later buffering")
	f.pause.release_pause(token)
	await _wait(0.19)
	f.actor2.get_behavior_state_machine().physics_tick(0.01)
	_expect(f.host2.get_active_command_id() > 0,"saved request begins once after resume")
	f.animation2.release_action()
	await _wait(0.18)
	_expect(f.focus.get_current_focus() == 60,"cached request charged once")
	f.world.free()
	await process_frame
func _wait(seconds: float) -> void:
	var deadline := Time.get_ticks_usec()+int(seconds*1000000.0)
	while Time.get_ticks_usec() < deadline: await process_frame
func _expect(ok: bool,label: String) -> void:
	if not ok: failures.append(label)
func _finish() -> void:
	paused = false
	for message in failures: push_error(message)
	if failures.is_empty(): print("ChainSkillPresentationControllerTest: PASS")
	quit(0 if failures.is_empty() else 1)
func _test_preview_assembly_and_stress() -> void:
	var path := "res://Scenes/Previews/ChainSkillPresentationPreview.tscn"
	_expect(ResourceLoader.exists(path),"integrated inherited preview exists")
	if not ResourceLoader.exists(path): return
	var packed := load(path) as PackedScene
	_expect(ResourceLoader.get_resource_uid(path) != ResourceUID.INVALID_ID,"preview registered UID")
	var orphans_before := Node.get_orphan_node_ids()
	var preview := packed.instantiate()
	_expect(preview.get_script() == load("res://Scenes/Previews/SquadChainCommandPreview.gd"),"preview reuses original script")
	_expect(preview.get_node("ChainSkillPresentationController/PauseCoordinator") is GamePauseCoordinator,"pause child statically visible")
	for actor in ["Guardian","Priest","Caster","Archer"]:
		var host = preview.get_node(actor+"/SkillHost") as SkillHostComponent
		_expect(host != null and host.regular_skills.size() == 2,"original two regular slots retained")
	preview.free()
	for id in Node.get_orphan_node_ids():
		if not orphans_before.has(id):
			var orphan = instance_from_id(id)
			_expect(false,"preview creates no new orphan: "+str(orphan))
	await _stress_real_roots()
func _stress_real_roots() -> void:
	var completed: int = 0
	for cycle in range(10):
		var f = make_fixture(root)
		var display = load("res://UnitSystem/Components/UI/SquadChainCommandDisplay.tscn").instantiate()
		display.command_source = f.source
		f.world.add_child(display)
		f.combo.delivery = InstantTargetDeliveryConfig.new()
		f.combo.release_effect_scene = load("res://Effects/Skills/Shared/ReleaseAccentFlash.tscn")
		f.combo.get_combo_focus_cost().base_focus_cost = 0.25
		f.combo.get_combo_focus_cost().repeat_focus_cost = 0.0
		await physics_frame
		await physics_frame
		for step in range(10):
			# 手动驱动真实动作前，显式满足两次强调之间正常物理推进的既有前提。
			# 只等待0.18秒真实时间不能保证调度器已经完成一次正常物理处理。
			await physics_frame
			await process_frame
			_expect(not paused, "stress root starts after normal physics resumes")
			var admitted: bool = f.source.submit_slot(0)
			_expect(admitted,"stress root admission")
			if not admitted: break
			f.actor.get_behavior_state_machine().physics_tick(0.01)
			f.animation.release_action()
			_expect(paused,"stress real root accent cycle=%d step=%d normal_advanced=%s frame=%d resume_frame=%d" % [cycle,step,f.pause.get("_normal_advanced"),Engine.get_physics_frames(),f.pause.get("_resume_frame")])
			await _wait(0.18)
			f.animation.finish_action()
			completed += 1
		await _wait(0.45)
		_expect(not paused and f.pause.get("_tokens").is_empty() and f.pause.get("_instances").is_empty(),"tokens and weak instances return to baseline")
		_expect(f.presentation.get("_candidates").is_empty() and f.source.get("_records").is_empty() and display.get("_request_slots").is_empty(),"candidate/command/UI identity tables bounded after natural cleanup")
		f.world.free()
		await process_frame
		await process_frame
		_expect(not paused,"reload never retains pause")
	_expect(completed == 100,"100 actual roots across 10 world reloads")
	print("Stress: roots=",completed," worlds=10")
func _test_missing_channels_and_cast_watchdog() -> void:
	var f = make_fixture(root)
	f.combo.camera_effect_profile = null
	await physics_frame
	await physics_frame
	_expect(f.source.submit_slot(0) and f.source.submit_slot(1),"missing-channel roots admitted")
	f.actor.get_behavior_state_machine().physics_tick(0.01)
	f.actor2.get_behavior_state_machine().physics_tick(0.01)
	var b = f.host2.get_combo_skill().get_current_presentation_context()
	_expect(f.rig.get("_focus_id") == b.presentation_id,"missing camera profile must not block another valid candidate")
	var reserved: float = f.focus.get_reserved_focus()
	f.presentation.call("_process",1.3)
	_expect(f.presentation.get("_candidates").is_empty(),"cast watchdog only retires stale presentation candidates")
	_expect(f.host.has_command_action_lock() and f.host2.has_command_action_lock() and f.focus.get_reserved_focus() == reserved,"watchdog never cancels actions or refunds")
	f.world.free()
	await process_frame

func _test_scope_change_during_instance_prepare() -> void:
	var f = make_fixture(root)
	f.combo.release_effect_scene = load("res://Effects/Skills/Shared/ReleaseAccentFlash.tscn")
	await physics_frame
	await physics_frame
	f.source.command_release_instance_prepared.connect(func(_slot,_fact,_instance):
		var empty: Array[UnitBase] = []
		f.focus.bind_scope(null,empty))
	_expect(f.source.submit_slot(0),"reentrant scope test admitted")
	f.actor.get_behavior_state_machine().physics_tick(0.01)
	f.animation.release_action()
	_expect(not paused and f.pause.get("_instances").is_empty() and f.presentation.get("_candidates").is_empty(),"scope change during prepared cannot register in next world or leak pause")
	f.world.free()
	await process_frame
func _test_explicit_pause_survives_command_rebind() -> void:
	var f = make_fixture(root)
	await physics_frame
	await physics_frame
	var token: int = f.pause.acquire_pause(f.world,&"external_menu")
	var companions: Array[AllyBase] = [f.actor,f.actor2,null,null]
	var swapped: Array[AllyBase] = [f.actor2,f.actor,null,null]
	f.source.companions = swapped
	f.source.call("_refresh_configuration")
	_expect(paused and not f.pause.is_presentation_allowed(),"live-world command rebind cannot release external explicit pause")
	f.source.companions = companions
	f.source.call("_refresh_configuration")
	_expect(paused,"same-world reattach preserves token")
	f.pause.release_pause(token)
	_expect(not paused,"original menu token remains valid after command rebind")
	f.world.free()
	await process_frame

func _test_duplicate_assembly_is_inert() -> void:
	for shared_pause in [true,false]:
		var f = make_fixture(root)
		await physics_frame
		await physics_frame
		_expect(f.source.submit_slot(0),"duplicate test root admitted")
		f.actor.get_behavior_state_machine().physics_tick(0.01)
		var first_id: int = f.rig.get("_focus_id")
		var duplicate = load("res://UnitSystem/Components/Combat/Squad/ChainSkillPresentationController.tscn").instantiate()
		duplicate.command_source = f.source
		duplicate.camera_source = f.rig
		if shared_pause: duplicate.pause_source = f.pause
		f.world.add_child(duplicate)
		_expect(f.rig.get("_focus_id") == first_id,"rejected duplicate cannot clear valid focus")
		_expect(f.source.get("_presentation_pause_ref") != null and f.rig.get("_pause_ref") != null,"rejected duplicate cannot clear valid injections")
		duplicate.free()
		_expect(f.rig.get("_focus_id") == first_id,"removing rejected duplicate cannot clear valid focus")
		f.animation.release_action()
		_expect(paused and not f.source.is_feedback_suspended(),"first component accent still works after rejected duplicate")
		var event := InputEventAction.new()
		event.action = &"squad_chain_2"
		event.pressed = true
		Input.parse_input_event(event)
		await process_frame
		await process_frame
		_expect(f.host2.has_pending_command(),"first component retains accent-time input admission")
		await _wait(0.18)
		f.world.free()
		await process_frame