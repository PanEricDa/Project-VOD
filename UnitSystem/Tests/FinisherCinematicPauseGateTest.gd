extends SceneTree
## 真实B流程：进退镜冻结世界和动画，菜单优先，方法帧前不发射，三时长可独立配置。
var failures: Array[String] = []
func _initialize() -> void: call_deferred("_run")
func _run() -> void:
	var scene := load("res://Scenes/Previews/SquadFinisherComparisonPreview.tscn").instantiate() as Node3D
	root.add_child(scene)
	current_scene = scene
	for frame: int in range(4): await process_frame
	await physics_frame
	var execution := scene.get_node("Battle/SquadFinisherExecutionController") as SquadFinisherExecutionController
	var rig := scene.get_node("Battle/CameraRig") as CameraFollowController
	var camera := rig.get_node("Camera3D") as Camera3D
	var actor := scene.get_node("Battle/Caster") as AllyBase
	var host := actor.get_node("SkillHost") as SkillHostComponent
	var ap := actor.get_node("Visual/CasterVisual/CharacterAnimationPlayer") as AnimationPlayer
	var driver := actor.get_combat_system().get_attack_controller()
	var pause := scene.get_node("Battle/ChainSkillPresentationController/PauseCoordinator") as GamePauseCoordinator
	var original_animation_callback := ap.callback_mode_method
	var profile := host.get_finisher_skill().camera_effect_profile.duplicate() as SkillCinematicCameraProfile
	for field: String in ["closeup_transition_seconds","battle_transition_seconds","player_return_seconds"]:
		var found := false
		for prop: Dictionary in profile.get_property_list():
			if prop.name == field: found = true
		_expect(found,"Inspector duration exists: "+field)
	if not failures.is_empty():
		scene.free()
		await process_frame
		_finish()
		return
	profile.set("closeup_transition_seconds",0.2)
	profile.set("battle_transition_seconds",0.2)
	profile.set("player_return_seconds",0.3)
	host.get_finisher_skill().camera_effect_profile = profile
	var initial_camera := camera.global_transform
	_expect(execution.begin_finisher(actor,171018,1),"real B request accepted")
	await _until(func() -> bool: return execution.get_execution_status().phase != &"pending",1.0)
	_expect(paused and is_zero_approx(ap.current_animation_position),"entry freezes world at authored zero frame")
	var world_probe: float = scene.get("_world_probe")
	await create_timer(0.05,true,false,true).timeout
	_expect(paused and is_zero_approx(ap.current_animation_position),"entry cannot eat initial animation")
	_expect(not camera.global_transform.is_equal_approx(initial_camera),"camera alone moves under owned transition pause")
	_expect(is_equal_approx(scene.get("_world_probe"),world_probe),"world does not advance during entry")
	var menu := pause.acquire_pause(execution,&"test_menu")
	var menu_camera := camera.global_transform
	await create_timer(0.12,true,false,true).timeout
	_expect(camera.global_transform.is_equal_approx(menu_camera) and paused,"menu freezes even transition camera")
	pause.release_pause(menu)
	await _until(func() -> bool: return execution.get_execution_status().phase == &"windup",1.0)
	_expect(not paused and is_equal_approx(Engine.time_scale,0.05),"entry completion resumes into five-percent world")
	# 故意模拟跨过方法帧的大步长，只允许推进到释放姿态。
	driver.set_physics_process(false)
	ap.seek(0.59,true,true)
	driver.call("_physics_process",0.005)
	_expect(paused and absf(ap.current_animation_position-0.6)<0.00001,"release gate clamps animation exactly to marker")
	_expect(execution.get_execution_status().launched == 0,"release marker queues instead of emitting early")
	var release_pose := ap.current_animation_position
	await create_timer(0.05,true,false,true).timeout
	_expect(paused and is_equal_approx(ap.current_animation_position,release_pose) and execution.get_execution_status().launched == 0,"retreat keeps release pose and zero projectiles")
	menu = pause.acquire_pause(execution,&"test_exit_menu")
	menu_camera = camera.global_transform
	await create_timer(0.12,true,false,true).timeout
	_expect(camera.global_transform.is_equal_approx(menu_camera) and execution.get_execution_status().launched == 0,"exit menu cannot bypass pending release")
	pause.release_pause(menu)
	await _until(func() -> bool: return execution.get_execution_status().launched >= 1,1.5)
	_expect(not paused and execution.get_execution_status().launched >= 1,"only completed retreat commits release")
	driver.set_physics_process(true)
	await _until(func() -> bool: return execution.get_execution_status().phase == &"returning",3.0)
	_expect(not paused and is_equal_approx(Engine.time_scale,1.0),"all impacts restore world before player return")
	_expect(execution.get_execution_status().launched == 5 and execution.get_execution_status().landed == 5,"all five shots survive both holds")
	await _until(func() -> bool: return execution.get_execution_status().phase == &"idle",1.0)
	_expect(not rig.is_cinematic_active() and pause.get("_tokens").is_empty(),"completion releases only owned camera pause")
	_expect(ap.callback_mode_method == original_animation_callback,"manual method delivery mode restored")
	scene.reset_preview()
	_expect(execution.begin_finisher(actor,171018,1),"cancellation during entry accepted")
	await _until(func() -> bool: return paused,1.0)
	menu = pause.acquire_pause(execution,&"keep_menu")
	execution.cancel_execution(&"test_cancel")
	_expect(paused and not rig.is_cinematic_active(),"cancel preserves independently held menu")
	pause.release_pause(menu)
	_expect(not paused and is_equal_approx(Engine.time_scale,1.0),"cancel does not leak cinematic time")
	scene.reset_preview()
	_expect(execution.begin_finisher(actor,171018,1),"exit cancellation starts")
	await _until(func() -> bool: return execution.get_execution_status().phase == &"exit_closeup",2.0)
	_expect(paused and execution.get_execution_status().launched == 0,"exit cancellation happens before emission")
	execution.cancel_execution(&"cancel_exit")
	await create_timer(0.25,true,false,true).timeout
	_expect(not paused and execution.get_execution_status().phase == &"idle" and execution.get_execution_status().launched == 0,"stale exit completion cannot emit canceled request")
	_expect(pause.get("_tokens").is_empty() and not host.has_command_action_lock(),"exit cancellation leaves no pause or animation lock")
	# 零时长仍必须完成状态交接，不能因暂停而等不到后续方法帧。
	scene.reset_preview()
	profile.set("closeup_transition_seconds",0.0)
	profile.set("battle_transition_seconds",0.0)
	profile.set("player_return_seconds",0.0)
	_expect(execution.begin_finisher(actor,171018,1),"zero-duration transitions accepted")
	await _until(func() -> bool: return execution.get_execution_status().phase == &"idle",3.5)
	_expect(execution.get_execution_status().launched == 5 and execution.get_execution_status().landed == 5 and not paused,"zero-duration sequence neither deadlocks nor duplicates shots")
	_expect(pause.get("_tokens").is_empty() and not rig.is_cinematic_active(),"zero-duration transition restores all ownership")
	# 镜头门闩不能把通用SkillBase终结入口限制成只有Arc投射物能用。
	scene.reset_preview()
	host.get_finisher_skill().delivery = InstantTargetDeliveryConfig.new()
	var hp_before: float = scene.targets[0].get_current_health()
	_expect(execution.begin_finisher(actor,171018,1),"generic instant finisher starts same B gate")
	await _until(func() -> bool: return execution.get_execution_status().phase == &"idle",2.0)
	_expect(scene.targets[0].get_current_health() < hp_before,"generic non-Arc delivery still commits after retreat")
	_expect(execution.get_execution_status().reason == &"completed" and not paused,"generic delivery completes camera gate without Arc coupling")
	# 没有镜头表现配置时保持原可选语义，不能走进无法到位的暂停。
	scene.reset_preview()
	host.get_finisher_skill().camera_effect_profile = null
	hp_before = scene.targets[0].get_current_health()
	_expect(execution.begin_finisher(actor,171018,1),"optional camera-less finisher accepted")
	await _until(func() -> bool: return execution.get_execution_status().phase == &"idle",2.0)
	_expect(scene.targets[0].get_current_health() < hp_before and execution.get_execution_status().reason == &"completed","missing optional camera profile does not cancel real delivery")
	_expect(not paused and pause.get("_tokens").is_empty(),"camera-less request owns no camera pause")
	host.get_finisher_skill().camera_effect_profile = profile
	scene.reset_preview()
	profile.set("closeup_transition_seconds",0.2)
	_expect(execution.begin_finisher(actor,171018,1),"scope teardown enters camera gate")
	await _until(func() -> bool: return paused,1.0)
	_expect(paused,"scope teardown really occurs under transition pause")
	scene.free()
	await process_frame
	await process_frame
	_expect(not paused and is_equal_approx(Engine.time_scale,1.0),"scope exit during gate restores global time and pause")
	_finish()
func _until(predicate: Callable,seconds: float) -> void:
	var deadline := Time.get_ticks_msec()+int(seconds*1000)
	while not predicate.call() and Time.get_ticks_msec()<deadline: await process_frame
func _expect(ok: bool,message: String) -> void:
	if not ok: failures.append(message)
func _finish() -> void:
	for message: String in failures: printerr("FAIL: ",message)
	print("FinisherCinematicPauseGateTest: ","PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
