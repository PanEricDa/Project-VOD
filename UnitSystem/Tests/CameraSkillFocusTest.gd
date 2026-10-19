extends SceneTree
## 临时构图不重绑玩家；真实桥/缩放两种处理顺序检测偏移争写。
class AttackSource extends Node:
	signal attack_hit(target: CharacterBody3D, hit_position: Vector3, hit_direction: Vector3, combo_index: int)
	func set_hit_stop_active(_active: bool) -> void: pass
var failures: Array[String] = []
func _initialize() -> void: call_deferred(&"_run")
func _run() -> void:
	var f = load("res://UnitSystem/Tests/AllyChainCommandPriorityTest.gd").make_fixture(root)
	await physics_frame
	await physics_frame
	var rig := Node3D.new()
	rig.set_script(load("res://UnitSystem/Components/Camera/CameraFollowController.gd"))
	var camera := Camera3D.new()
	camera.name = "Camera3D"
	camera.rotation_degrees.x = -50
	camera.fov = 45
	rig.add_child(camera)
	f.world.add_child(rig)
	rig.set_process(false)
	camera.make_current()
	await _test_zoom_disabled_preserves_authored_baseline(f)
	await _test_zoom_shake_composition(f,rig,camera)
	_test_distance_mapping()
	await _test_release_holds_camera_not_visuals(f,rig,camera)
	await _test_player_anchored_bias(f,rig,camera)
	_test_screen_space_limit(f)
	camera.make_current()
	_expect(rig.has_method(&"begin_presentation_focus"), "camera must provide temporary focus without rebinding")
	if rig.has_method(&"begin_presentation_focus"):
		await _test_focus_contract(f,rig,camera)
	f.world.free()
	paused = false
	for message in failures: push_error(message)
	if failures.is_empty(): print("CameraSkillFocusTest: PASS")
	quit(0 if failures.is_empty() else 1)
func _test_zoom_shake_composition(f: Dictionary,rig: Node3D,camera: Camera3D) -> void:
	var source := AttackSource.new()
	source.name = "AttackSource"
	f.world.add_child(source)
	var bridge := Node.new()
	bridge.set_script(load("res://Effects/Combat/HitFeedbackBridge.gd"))
	bridge.set("attack_source_path",NodePath("../AttackSource"))
	var profile := HitFeedbackProfile.new()
	profile.shake_duration = 0.12
	profile.minimum_feedback_interval = 0
	bridge.set("effect_profile",profile)
	f.world.add_child(bridge)
	bridge.set_process(false)
	for order in [0,1]:
		for index in range(4):
			bridge.call("play_hit_feedback",f.enemy,Vector3.ZERO,Vector3.FORWARD,1)
			for step in range(12):
				if order == 0:
					rig.call("_process",0.016)
					bridge.call("_process",0.016)
				else:
					bridge.call("_process",0.016)
					rig.call("_process",0.016)
				_expect(camera.position.is_equal_approx(camera.basis.z*3.0 + bridge.get("last_applied_camera_offset")), "zoom and shake compose without stale-offset subtraction")
			_expect(camera.position.is_equal_approx(camera.basis.z*3.0), "shake ends at exact base plus zoom in either processing order")
	bridge.call("play_hit_feedback",f.enemy,Vector3.ZERO,Vector3.FORWARD,1)
	var remaining = bridge.get("shake_remaining")
	paused = true
	bridge.call("_process",0.1)
	_expect(is_equal_approx(bridge.get("shake_remaining"),remaining), "paused bridge cannot consume shake time")
	paused = false
	bridge.free()
	source.free()
func _test_focus_contract(f: Dictionary,rig: Node3D,camera: Camera3D) -> void:
	rig.clear_presentation_focus()
	rig.snap_to_target()
	var normal_before := rig.global_position
	var target_before = rig.call("get_resolved_target")
	var basis_before := camera.basis
	var profile := SkillFocusCameraProfile.new()
	profile.enter_duration_seconds = 0
	profile.return_duration_seconds = 0
	f.actor.position = f.player.position + Vector3(8,0,2)
	_expect(rig.call("begin_presentation_focus",10,f.actor,profile), "valid focus accepted")
	_expect(rig.call("get_resolved_target") == target_before, "normal player target never rebound")
	var focused := rig.global_position
	_expect(focused.distance_to(normal_before) > 0.01 and focused.distance_to(normal_before) < 7.6, "zero enter immediately applies bounded bias")
	_expect(camera.basis.is_equal_approx(basis_before) and camera.fov == 45, "preserves angle and projection")
	f.player.position += Vector3(5,0,0)
	f.player.reset_physics_interpolation()
	rig.call("end_presentation_focus",9)
	_expect(rig.global_position.is_equal_approx(focused), "old identity cannot end new focus")
	rig.call("end_presentation_focus",10)
	_expect(rig.global_position.is_equal_approx(normal_before), "zero return removes only attention offset")
	rig.call("_process", 5.0)
	_expect(rig.global_position.is_equal_approx(f.player.global_position+rig.get("camera_offset")), "normal follow reaches current player rather than stale entry pose")
	_expect(not rig.call("begin_presentation_focus",11,f.actor,CameraEffectProfile.new()), "empty base strategy safely skips")
	profile.enter_duration_seconds = NAN
	_expect(not rig.call("begin_presentation_focus",12,f.actor,profile), "nonfinite duration safely skips")
	profile.enter_duration_seconds = 0.12
	profile.return_duration_seconds = 0.2
	var second := Node3D.new()
	second.set_script(rig.get_script())
	f.world.add_child(second)
	second.set_process(false)
	_expect(rig.call("begin_presentation_focus",13,f.actor,profile) and second.call("begin_presentation_focus",14,f.actor,profile), "shared preset supports independent cameras")
	rig.call("_process",0.05)
	_expect(second.global_position != rig.global_position and is_equal_approx(profile.enter_duration_seconds,0.12), "strategy has no shared playback progress")
	var pause = GamePauseCoordinator.new()
	f.world.add_child(pause)
	pause.bind_scope(f.world)
	rig.call("set_presentation_pause_source",pause)
	var before := rig.global_position
	var token: int = pause.acquire_pause(f.world,&"menu")
	rig.call("_process",0.1)
	_expect(rig.global_position == before, "explicit pause freezes transition")
	pause.release_pause(token)
	rig.call("set_presentation_pause_source",null)
	rig.call("clear_presentation_focus")
	second.free()

func _test_player_anchored_bias(f: Dictionary, rig: Node3D, camera: Camera3D) -> void:
	# 若恢复完整居中、让施法锁住玩家跟随、或在衔接时瞬移，这些行为断言应失败。
	var profile := SkillFocusCameraProfile.new()
	profile.enter_duration_seconds = 0.30
	profile.return_duration_seconds = 0.55
	var control := CameraFollowController.new()
	var control_camera := Camera3D.new()
	control_camera.name = "Camera3D"
	control_camera.rotation_degrees.x = -50
	control_camera.fov = 45
	control.add_child(control_camera)
	f.world.add_child(control)
	control.set_process(false)
	rig.clear_presentation_focus()
	rig.snap_to_target()
	control.snap_to_target()
	var normal := rig.global_position
	f.actor.position = f.player.position + Vector3(0.1, 0, 0)
	rig.begin_presentation_focus(101, f.actor, profile)
	rig.call("_process", 0.4)
	_expect(rig.global_position.distance_to(normal) < 0.01, "very nearby caster produces negligible movement without a hard distance step")
	rig.clear_presentation_focus()
	rig.snap_to_target()
	f.actor.position = f.player.position + Vector3(40, 0, 0)
	rig.begin_presentation_focus(102, f.actor, profile)
	rig.call("_process", 0.3)
	var bias: Vector3 = rig.global_position - normal
	_expect(bias.x > 0.05 and bias.length() < 7.6, "distant caster produces small bounded bias instead of full recenter")
	f.player.position += Vector3(5, 0, 0)
	f.player.reset_physics_interpolation()
	rig.call("_process", 0.016)
	control.call("_process", 0.016)
	var followed_bias: Vector3 = rig.global_position - control.global_position
	_expect(followed_bias.length() < 7.6, "normal player follow remains active during attention movement")
	var before := rig.global_position
	rig.end_presentation_focus(102)
	_expect(rig.global_position.is_equal_approx(before), "release does not jump when return begins")
	rig.call("_process", 0.1)
	control.call("_process", 0.1)
	before = rig.global_position
	f.actor.position = f.player.position + Vector3(-40, 0, 0)
	rig.begin_presentation_focus(103, f.actor, profile)
	_expect(rig.global_position.is_equal_approx(before), "next cast continues current bias without resetting to player or caster")
	for step in range(20):
		rig.call("_process", 0.016)
		control.call("_process", 0.016)
		_expect(rig.global_position.distance_to(control.global_position) < 7.6, "opposite casts stay inside small player-relative framing")
	rig.end_presentation_focus(103)
	for step in range(60):
		rig.call("_process", 0.016)
		control.call("_process", 0.016)
	_expect(rig.global_position.distance_to(control.global_position) < 0.01, "return removes attention offset without stale player position")
	_expect(rig.get_resolved_target() == f.player, "attention never rebinds player target")
	control.free()
	rig.clear_presentation_focus()

func _test_screen_space_limit(f: Dictionary) -> void:
	# 移除幅度上限、忽略缩放或意外增加垂直偏移，会使屏幕位移超过35%宽度（含透视方向容差）。
	for zoom_step in range(4):
		var rig := CameraFollowController.new()
		rig.initial_zoom_step = zoom_step
		var camera := Camera3D.new()
		camera.name = "Camera3D"
		camera.rotation_degrees.x = -50
		camera.fov = 45
		rig.add_child(camera)
		f.world.add_child(rig)
		rig.set_process(false)
		camera.make_current()
		var profile := SkillFocusCameraProfile.new()
		for direction in [Vector3.RIGHT, Vector3.FORWARD, Vector3.BACK, Vector3(1, 0, 1).normalized()]:
			rig.clear_presentation_focus()
			rig.snap_to_target()
			f.actor.position = f.player.position + direction * 40.0
			var before := camera.unproject_position(f.player.global_position)
			rig.begin_presentation_focus(200 + zoom_step, f.actor, profile)
			rig.call("_process", 1.0)
			var shift := camera.unproject_position(f.player.global_position).distance_to(before)
			var width := camera.get_viewport().get_visible_rect().size.x
			_expect(shift > 0.01 and shift <= width * 0.35, "all zoom levels and directions keep player screen displacement within 35% width")
			_expect(is_equal_approx(rig.global_position.y, f.player.global_position.y + rig.camera_offset.y), "attention bias never changes rig height")
		rig.clear_presentation_focus()
		rig.free()

func _test_distance_mapping() -> void:
	# 捕获远处与近处被相同低上限压平、过大死区及非有限输入未防护。
	var profile := SkillFocusCameraProfile.new()
	var previous := 0.0
	for fixture in [{"distance":1.0,"want":0.16128},{"distance":5.0,"want":2.88},{"distance":10.0,"want":5.76}]:
		var value := profile.get_focus_offset(Vector3(fixture.distance, 40.0, 0.0), 20.0)
		_expect(is_equal_approx(value.x, fixture.want) and is_zero_approx(value.y), "distance curve gives weak nearby and stronger distant attention without vertical movement")
		_expect(value.x > previous, "attention grows monotonically through useful companion distances")
		previous = value.x
	_expect(is_equal_approx(profile.get_focus_offset(Vector3(1000,0,0),20).length(),5.76), "very distant caster remains capped instead of taking over camera")
	_expect(profile.get_focus_offset(Vector3.ZERO,20) == Vector3.ZERO and profile.get_focus_offset(Vector3(INF,0,0),20) == Vector3.ZERO, "zero and invalid distance cannot move camera")
	_expect(profile.has_method("get_transition_duration"), "camera strategy can slow larger transitions without adding designer fields")
	if profile.has_method("get_transition_duration"):
		var nearby := Transform3D(Basis.IDENTITY, Vector3(0.1,0,0))
		var distant := Transform3D(Basis.IDENTITY, Vector3(3,0,0))
		for phase in [CameraEffectProfile.Phase.ENTER, CameraEffectProfile.Phase.RETURN]:
			var near_time: float = profile.call("get_transition_duration", Transform3D.IDENTITY, nearby, phase)
			var far_time: float = profile.call("get_transition_duration", Transform3D.IDENTITY, distant, phase)
			_expect(far_time > near_time and far_time <= near_time + 0.21, "larger movements take longer but extra duration remains bounded")
		_expect(is_equal_approx(profile.call("get_transition_duration", Transform3D.IDENTITY, nearby, 0), 0.20), "near entry uses previous duration divided by 1.5")
		_expect(is_equal_approx(profile.call("get_transition_duration", Transform3D.IDENTITY, distant, 0), 1.0/3.0), "far entry including distance easing uses previous duration divided by 1.5")
		_expect(is_equal_approx(profile.call("get_transition_duration", Transform3D.IDENTITY, nearby, 1), 0.55) and is_equal_approx(profile.call("get_transition_duration", Transform3D.IDENTITY, distant, 1), 0.75), "near and far return durations remain unchanged")
		profile.enter_duration_seconds = 0.0
		profile.return_duration_seconds = 0.0
		_expect(profile.call("get_transition_duration", Transform3D.IDENTITY, distant, 0) == 0.0 and profile.call("get_transition_duration", Transform3D.IDENTITY, distant, 1) == 0.0, "explicit zero duration stays instant regardless of distance")

func _test_release_holds_camera_not_visuals(f: Dictionary, rig: Node3D, camera: Camera3D) -> void:
	# 捕获时停时Rig仍追赶、缩放继续推进、或误把释放动画一起冻结。
	rig.clear_presentation_focus()
	rig.snap_to_target()
	var manager := GamePauseCoordinator.new()
	f.world.add_child(manager)
	manager.bind_scope(f.world)
	rig.set_presentation_pause_source(manager)
	var profile := SkillFocusCameraProfile.new()
	f.actor.position = f.player.position + Vector3(10,0,0)
	rig.begin_presentation_focus(301,f.actor,profile)
	rig.call("_process",0.08)
	var before := rig.global_transform
	var camera_before := camera.global_transform
	var elapsed_before: float = rig.get("_focus_elapsed")
	var visual = load("res://Effects/Skills/Shared/ReleaseAccentFlash.tscn").instantiate()
	_expect(manager.register_release_instance(301,visual), "release visual registered before entering scene")
	f.world.add_child(visual)
	# 这里只测独立时钟，关闭夹具的自动回收并由测试末尾显式释放。
	visual.get_node("CleanupTimer").stop()
	var animation: AnimationPlayer = visual.get_node("AnimationPlayer")
	animation.advance(0.0)
	var visual_before: float = visual.get_node("VisualRoot/GroundRing").scale.x
	manager.request_release_accent(301,0.20,f.world)
	var deadline := Time.get_ticks_usec() + 60000
	while Time.get_ticks_usec() < deadline: await process_frame
	rig.call("_process",0.06)
	_expect(paused and rig.global_transform.is_equal_approx(before) and camera.global_transform.is_equal_approx(camera_before), "release accent freezes actual rig and camera transform at current framing")
	_expect(is_equal_approx(rig.get("_focus_elapsed"),elapsed_before), "release hold consumes no camera transition progress")
	_expect(visual.get_node("VisualRoot/GroundRing").scale.x < visual_before, "release animation still advances while camera and battle stop")
	deadline = Time.get_ticks_usec() + 220000
	while Time.get_ticks_usec() < deadline: await process_frame
	rig.call("_process",0.04)
	_expect(not paused and rig.get("_focus_elapsed") > elapsed_before and not rig.global_transform.is_equal_approx(before), "camera resumes from held progress after accent ends")
	rig.clear_presentation_focus()
	rig.set_presentation_pause_source(null)
	visual.free()
	manager.free()

func _expect(ok: bool,label: String) -> void:
	if not ok: failures.append(label)
func _test_zoom_disabled_preserves_authored_baseline(f: Dictionary) -> void:
	var rig = CameraFollowController.new()
	rig.zoom_distances = PackedFloat32Array()
	var camera := Camera3D.new()
	camera.name = "Camera3D"
	var authored := Vector3(0.7,0.4,0.3)
	camera.position = authored
	rig.add_child(camera)
	f.world.add_child(rig)
	var offset := Vector3(0.2,0.1,0)
	rig.set_feedback_offset(f.actor,offset)
	_expect(camera.position.is_equal_approx(authored+offset),"disabled zoom retains authored camera baseline while feedback active")
	rig.clear_feedback_offset(f.actor)
	_expect(camera.position.is_equal_approx(authored),"feedback removal restores authored position when zoom disabled")
	rig.free()