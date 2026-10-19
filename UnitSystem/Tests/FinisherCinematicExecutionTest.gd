extends SceneTree
## 镜头单写者契约：正面特写、固定区域、真实暂停、身份隔离及原缩放/角度恢复。
var failures: Array[String] = []
func _initialize() -> void: call_deferred("_run")
func _run() -> void:
	var rig := CameraFollowController.new()
	if not rig.has_method("begin_cinematic"):
		rig.free()
		failures.append("missing cinematic camera interface")
		_finish()
		return
	var f: Dictionary = load("res://UnitSystem/Tests/AllyChainCommandPriorityTest.gd").make_fixture(root)
	var camera := Camera3D.new()
	camera.name = "Camera3D"
	camera.rotation_degrees.x = -50
	camera.fov = 45
	rig.add_child(camera)
	f.world.add_child(rig)
	rig.set_process(false)
	rig.snap_to_target()
	var local := camera.transform
	var zoom: int = rig.get("_zoom_step")
	var profile: CameraEffectProfile = load("res://Effects/Camera/SkillCinematicCameraProfile.gd").new()
	var clock := SkillExecutionClock.new()
	clock.configure(f.world)
	var pose := Transform3D(Basis.IDENTITY, f.actor.global_position)
	var origin := camera.global_transform
	Engine.time_scale = 0.05
	_expect(rig.call("begin_cinematic", 77, pose, profile, clock), "front closeup accepted")
	_expect(camera.global_transform.is_equal_approx(origin), "begin preserves current camera instead of cutting")
	# 5%世界的0.005秒即0.1真实活动秒；此时应处于推进中点而非起点或终点。
	rig.call("_process", 0.005)
	var front_position: Vector3 = f.actor.global_position + Vector3(0.45,1.15,-2.8)
	_expect(not camera.global_position.is_equal_approx(origin.origin) and not camera.global_position.is_equal_approx(front_position), "closeup progresses continuously at five-percent world speed")
	_expect(camera.global_position.distance_to(front_position) < origin.origin.distance_to(front_position), "push moves closer to front composition")
	var locked := camera.global_transform
	paused = true
	rig.call("_process", 1.0)
	_expect(camera.global_transform.is_equal_approx(locked), "true pause freezes cinematic camera")
	paused = false
	rig.call("_process", 0.005)
	_expect(camera.global_position.is_equal_approx(front_position), "push reaches front composition in about 0.2 real seconds")
	_expect(camera.global_position.distance_to(f.actor.global_position) < 5.0, "front closeup at actor")
	locked = camera.global_transform
	Engine.time_scale = 1.0
	var center := Vector3(8, 0, -6)
	rig.call("show_cinematic_area", 76, center, 8.0)
	_expect(camera.global_transform.is_equal_approx(locked), "stale identity cannot change phase")
	rig.call("show_cinematic_area", 77, center, 8.0)
	# B世界仍为5%速度，转战斗视角应在0.2真实活动秒到位，不继续遮挡动作。
	Engine.time_scale = 0.05
	rig.call("_process",0.005)
	_expect(not camera.global_transform.is_equal_approx(locked),"area transition moves smoothly before arrival")
	rig.call("_process",0.005)
	var area_pose := camera.global_transform
	rig.call("_process",0.0025)
	_expect(camera.global_transform.is_equal_approx(area_pose),"battle composition settled by 0.2 real seconds")
	Engine.time_scale = 1.0
	_expect(rig.call("is_cinematic_active"), "B area remains owned")
	rig.call("end_cinematic", 76, true)
	_expect(rig.call("is_cinematic_active"), "stale identity cannot end cinematic")
	rig.call("end_cinematic", 77, true)
	_expect(not rig.call("is_cinematic_active"), "A immediate release clears owner")
	_expect(camera.transform.is_equal_approx(local) and camera.fov == 45 and rig.get("_zoom_step") == zoom, "restore authored angle projection and zoom")
	# 更快的释放可在推进完成前切区域，不等待特写到位、不跳过当前画面。
	var next_clock := SkillExecutionClock.new()
	next_clock.configure(f.world)
	_expect(rig.call("begin_cinematic",78,pose,profile,next_clock),"second closeup accepted")
	rig.call("_process",0.025)
	var early := camera.global_transform
	rig.call("show_cinematic_area",78,center,8.0)
	_expect(camera.global_transform.is_equal_approx(early),"early release starts area transition from current push pose")
	rig.call("_process",0.05)
	_expect(not camera.global_transform.is_equal_approx(early),"early release advances area without waiting for closeup")
	rig.call("end_cinematic",78,false)
	rig.call("_process",0.1)
	_expect(rig.call("is_cinematic_active"),"player return still smooth before completion")
	rig.call("_process",0.1)
	_expect(not rig.call("is_cinematic_active"),"player camera ownership restored by 0.2 seconds")
	_expect(camera.transform.is_equal_approx(local) and camera.fov == 45 and rig.get("_zoom_step") == zoom,"accelerated return preserves normal camera configuration")
	# 三个Inspector时长须独立生效，不可退化成同一个固定0.2。
	profile.set("closeup_transition_seconds",0.3)
	profile.set("battle_transition_seconds",0.4)
	profile.set("player_return_seconds",0.5)
	_expect(rig.call("begin_cinematic",79,pose,profile,next_clock),"custom timing closeup accepted")
	for i: int in range(2): rig.call("_process",0.1)
	_expect(not camera.global_position.is_equal_approx(front_position),"custom closeup not complete at 0.2")
	rig.call("_process",0.1)
	_expect(camera.global_position.is_equal_approx(front_position),"custom closeup completes at 0.3")
	rig.call("show_cinematic_area",79,center,8.0)
	for i: int in range(3): rig.call("_process",0.1)
	var before_arrival := camera.global_transform
	rig.call("_process",0.1)
	_expect(not camera.global_transform.is_equal_approx(before_arrival),"custom battle transition continues beyond 0.3")
	var arrived := camera.global_transform
	rig.call("_process",0.1)
	_expect(camera.global_transform.is_equal_approx(arrived),"custom battle transition settles at 0.4")
	rig.call("end_cinematic",79,false)
	for i: int in range(4): rig.call("_process",0.1)
	_expect(rig.call("is_cinematic_active"),"custom player return still owned at 0.4")
	rig.call("_process",0.1)
	_expect(not rig.call("is_cinematic_active"),"custom player return completes at 0.5")
	f.world.free()
	await process_frame
	_finish()
func _expect(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
func _finish() -> void:
	for message in failures: printerr("FAIL: ",message)
	print("FinisherCinematicExecutionTest: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
