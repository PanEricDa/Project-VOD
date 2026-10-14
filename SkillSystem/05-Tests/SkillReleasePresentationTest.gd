extends SceneTree
## 真实释放播放器契约；分组由命令行 --group 选择，无参数运行全部已实现用例。
const PLAYER_PATH = "res://SkillSystem/01-Core/SkillReleasePresentationPlayer.gd"
const PROFILE_PATH = "res://Effects/Camera/CameraEffectProfile.gd"
const UNIT_PATH = "res://UnitSystem/Base/00_UnitBase.tscn"
var failures: Array[String] = []
var player_script: Script
var profile_script: Script
var group: String = ""
class RecordingVisual extends Node3D:
	signal effect_finished()
	static var trace: Array = []
	static var ready_poses: Array[Transform3D] = []
	## 测试资产进入树时自动播放；false 用于验证底层只调用一次 play。
	@export var autoplay: bool = true
	var play_count: int = 0
	func _ready() -> void:
		ready_poses.append(global_transform)
		trace.append("visual")
		if autoplay: play()
	func play() -> void:
		play_count += 1
class RecordingEffect extends SkillEffectBase:
	var succeeds: bool = true
	func apply(_context: SkillContext, _result: SkillDeliveryResult, _target: Node3D) -> bool:
		RecordingVisual.trace.append("effect")
		return succeeds
func _initialize() -> void: call_deferred(&"_run")
func _run() -> void:
	var args = OS.get_cmdline_user_args()
	if "--group" in args:
		var index = args.find("--group")
		group = args[index + 1] if index + 1 < args.size() else "invalid"
	if group not in ["", "visual", "audio", "release", "preview"]:
		_expect(false, "unknown or not implemented group: " + group)
		_finish()
		return
	if not ResourceLoader.exists(PLAYER_PATH) or not ResourceLoader.exists(PROFILE_PATH):
		_expect(false, "release presentation player and camera profile interfaces are missing")
		_finish()
		return
	player_script = load(PLAYER_PATH)
	profile_script = load(PROFILE_PATH)
	if group in ["", "visual"]:
		await _test_prepare_is_read_only()
		await _test_ready_pose_and_anchor_space()
		await _test_top_level_pose()
		await _test_visual_outlives_player()
		await _test_profile_request_optional()
		await _test_empty_and_invalid_visual()
	if group in ["", "audio"]:
		await _test_audio_outlives_player()
		await _test_audio_overlap_resource_isolation()
		await _test_audio_loop_and_watchdog()
		await _test_audio_pause_and_world_exit()
	if group in ["", "release"]:
		await _test_root_configuration_and_inheritance()
		await _test_success_boundary_and_failure()
		await _test_acceptance_reentry_snapshot()
		await _test_trigger_outlives_skill()
		await _test_volley_once_and_old_delivery()
		await _test_optional_channels_and_world_exit()
		await _test_chain_fee_before_presentation()
		await _test_release_stress()
	if group in ["", "preview"]:
		await _test_preview_load_and_configuration()
		await _test_preview_repeat_and_cleanup()
	_finish()
func _make_fixture() -> Dictionary:
	RecordingVisual.trace.clear()
	RecordingVisual.ready_poses.clear()
	var world = Node3D.new()
	root.add_child(world)
	var source = load(UNIT_PATH).instantiate() as UnitBase
	var target = load(UNIT_PATH).instantiate() as UnitBase
	source.team_id = 1
	target.team_id = 2
	world.add_child(source)
	world.add_child(target)
	source.global_position = Vector3(2, 0, 3)
	target.global_position = Vector3(7, 0, 3)
	var player = player_script.new()
	world.add_child(player)
	var context = SkillContext.new()
	context.caster = source
	context.resolved_target = target
	context.requested_target = target
	context.explicit_target_requested = true
	context.delivery_parent = world
	context.target_position = Vector3(9, 0, 4)
	var visual = RecordingVisual.new()
	visual.name = "ProbeVisual"
	var scene = PackedScene.new()
	_expect(scene.pack(visual) == OK, "test visual packs")
	visual.free()
	var profile = profile_script.new()
	player.camera_effect_requested.connect(func(_p, _s, _t, _x): RecordingVisual.trace.append("camera"))
	return {"world": world, "source": source, "target": target, "player": player,
		"context": context, "action_transform": Transform3D(Basis.IDENTITY, Vector3(2, 1, 3)),
		"visual_scene": scene, "profile": profile}
func _prepare_fixture(f: Dictionary, anchor: int) -> Dictionary:
	return f.player.prepare_release(f.context, f.action_transform, f.visual_scene, anchor, null, f.profile)
func _test_prepare_is_read_only() -> void:
	var f = _make_fixture()
	var before = f.world.get_child_count()
	var snapshot = _prepare_fixture(f, SkillBase.PresentationAnchor.ACTION_ORIGIN)
	_expect(f.world.get_child_count() == before and RecordingVisual.trace.is_empty(), "prepare only snapshots")
	f.context.target_position = Vector3(99, 0, 99)
	f.player.play_release(snapshot)
	_expect(RecordingVisual.trace == ["visual", "camera"], "independent visual and camera once")
	var visual = f.world.get_node_or_null("ProbeVisual")
	_expect(visual != null and visual.global_position.is_equal_approx(Vector3(2, 1, 3)), "action position snapshot")
	_expect(visual != null and visual.play_count == 1, "autoplay is not doubled")
	f.world.free()
	await process_frame
func _test_ready_pose_and_anchor_space() -> void:
	var expected = [Vector3(2,1,3), Vector3(7,0,3), Vector3(9,0,4), Vector3(2,0,3)]
	for anchor in range(4):
		var f = _make_fixture()
		f.world.transform = Transform3D(Basis(Vector3.UP, 0.4).scaled(Vector3(2, 1.5, 2)), Vector3(4, 2, -5))
		f.source.global_position = Vector3(2,0,3)
		f.target.global_position = Vector3(7,0,3)
		var snapshot = _prepare_fixture(f, anchor)
		f.player.play_release(snapshot)
		_expect(RecordingVisual.ready_poses.size() == 1, "one ready pose")
		if not RecordingVisual.ready_poses.is_empty():
			_expect(RecordingVisual.ready_poses[0].origin.is_equal_approx(expected[anchor]), "ready sees final anchor %d" % anchor)
		var parent = f.source if anchor == 3 else f.target if anchor == 1 else f.world
		var visual = parent.get_node_or_null("ProbeVisual") as Node3D
		_expect(visual != null, "correct anchor parent %d" % anchor)
		if visual != null and anchor == 1:
			_expect(visual.basis.is_equal_approx(Basis.IDENTITY), "target local basis identity")
		if visual != null and anchor == 3:
			_expect((-visual.global_basis.z).normalized().dot(Vector3.RIGHT) > 0.999, "feet faces target horizontally")
		f.world.free()
		await process_frame
func _test_visual_outlives_player() -> void:
	var f = _make_fixture()
	var snapshot = _prepare_fixture(f, 0)
	f.player.play_release(snapshot)
	var visual = f.world.get_node("ProbeVisual")
	f.player.free()
	_expect(is_instance_valid(visual), "visual outlives player")
	var watchdog = visual.get_node("ReleaseWatchdog") as Timer
	_expect(is_equal_approx(watchdog.wait_time, 30), "visual safety timeout is internal 30s")
	paused = true
	await create_timer(0.04).timeout
	_expect(is_instance_valid(visual), "paused visual retained")
	paused = false
	visual.effect_finished.emit()
	await process_frame
	_expect(not is_instance_valid(visual), "finish frees without skill callback")
	f.world.free()
	await process_frame
	var f2 = _make_fixture()
	f2.player.play_release(_prepare_fixture(f2, 0))
	var v2 = f2.world.get_node("ProbeVisual")
	v2.get_node("ReleaseWatchdog").timeout.emit()
	await process_frame
	_expect(not is_instance_valid(v2), "watchdog recycles faulty visual")
	f2.world.free()
	await process_frame
func _test_profile_request_optional() -> void:
	var f = _make_fixture()
	var snapshot = f.player.prepare_release(f.context, f.action_transform, null, 0, null, f.profile)
	f.player.play_release(snapshot)
	_expect(RecordingVisual.trace == ["camera"], "camera-only request supported")
	f.player.camera_effect_requested.disconnect(f.player.camera_effect_requested.get_connections()[0].callable)
	f.player.play_release(snapshot)
	_expect(f.world.get_child_count() == 3, "no subscriber creates nothing")
	f.target.free()
	f.player.play_release(snapshot)
	f.world.free()
	await process_frame
func _test_empty_and_invalid_visual() -> void:
	var f = _make_fixture()
	var count = f.world.get_child_count()
	var empty = f.player.prepare_release(f.context, f.action_transform, null, 0, null, null)
	f.player.play_release(empty)
	_expect(f.world.get_child_count() == count and RecordingVisual.trace.is_empty(), "all empty allocates nothing")
	var invalid = Node.new()
	var scene = PackedScene.new()
	scene.pack(invalid)
	invalid.free()
	var snapshot = f.player.prepare_release(f.context, f.action_transform, scene, 0, null, f.profile)
	f.player.play_release(snapshot)
	_expect(RecordingVisual.trace == ["camera"], "invalid visual isolated from camera")
	var no_world = f.player.prepare_release(null, f.action_transform, f.visual_scene, 0, null, f.profile)
	_expect(no_world.is_empty(), "invalid input rejected without effects")
	f.world.free()
	await process_frame
func _wave() -> AudioStreamWAV:
	var stream = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 22050
	var data = PackedByteArray()
	data.resize(4410)
	stream.data = data
	return stream
func _voices(world: Node) -> Array:
	return world.get_children().filter(func(n): return n is AudioStreamPlayer3D)
func _audio_snapshot(f: Dictionary, stream: AudioStream) -> Dictionary:
	return f.player.prepare_release(f.context, f.action_transform, f.visual_scene, 0, stream, f.profile)
func _test_audio_outlives_player() -> void:
	var f = _make_fixture()
	var stream = _wave()
	f.player.play_release(_audio_snapshot(f, stream))
	var voices = _voices(f.world)
	_expect(voices.size() == 1, "one audio voice starts")
	if voices.size() == 1:
		var voice = voices[0]
		_expect(voice.playing and voice.global_position.is_equal_approx(Vector3(2,1,3)), "audio plays at snapshot")
		_expect(is_equal_approx(voice.get_node("ReleaseWatchdog").wait_time, 1.1), "finite stream timeout adds one second")
		f.player.free()
		_expect(is_instance_valid(voice), "audio outlives player")
		await create_timer(0.35).timeout
		_expect(not is_instance_valid(voice), "audio naturally finishes and recycles")
	f.world.free()
	await process_frame
func _test_audio_overlap_resource_isolation() -> void:
	var f = _make_fixture()
	var stream = _wave()
	var snapshot = _audio_snapshot(f, stream)
	f.player.play_release(snapshot)
	f.player.play_release(snapshot)
	_expect(_voices(f.world).size() == 2, "repeated casts overlap independently")
	_expect(stream.loop_mode == AudioStreamWAV.LOOP_DISABLED, "shared stream not modified")
	_expect(RecordingVisual.trace.count("camera") == 2, "audio independent of repeated camera")
	var bus_index = AudioServer.bus_count
	AudioServer.add_bus()
	AudioServer.set_bus_name(bus_index, "SFX")
	f.player.play_release(snapshot)
	_expect(_voices(f.world).any(func(v): return v.bus == &"SFX"), "existing SFX bus used")
	AudioServer.remove_bus(bus_index)
	f.world.free()
	await process_frame
func _test_audio_loop_and_watchdog() -> void:
	var f = _make_fixture()
	var loop = _wave()
	loop.loop_mode = AudioStreamWAV.LOOP_FORWARD
	loop.loop_end = 2205
	f.player.play_release(_audio_snapshot(f, loop))
	_expect(_voices(f.world).is_empty(), "looping release audio rejected")
	_expect(RecordingVisual.trace == ["visual", "camera"], "loop rejection does not cancel other channels")
	_expect(loop.loop_mode == AudioStreamWAV.LOOP_FORWARD, "loop flag never changed")
	var randomizer = AudioStreamRandomizer.new()
	randomizer.add_stream(0, loop, 1.0)
	f.player.play_release(_audio_snapshot(f, randomizer))
	_expect(_voices(f.world).is_empty(), "randomized looping candidate rejected")
	var generator = AudioStreamGenerator.new()
	f.player.play_release(_audio_snapshot(f, generator))
	var voices = _voices(f.world)
	_expect(voices.size() == 1, "unknown-length stream accepted with safety timeout")
	if voices.size() == 1:
		var voice = voices[0]
		_expect(is_equal_approx(voice.get_node("ReleaseWatchdog").wait_time, 30), "unknown-length timeout safe")
		voice.get_node("ReleaseWatchdog").timeout.emit()
		await process_frame
		_expect(not is_instance_valid(voice), "unknown-length watchdog reclaims")
	f.world.free()
	await process_frame
func _test_audio_pause_and_world_exit() -> void:
	var f = _make_fixture()
	f.player.play_release(_audio_snapshot(f, _wave()))
	var voices = _voices(f.world)
	paused = true
	await create_timer(0.2).timeout
	if voices.size() == 1:
		_expect(is_instance_valid(voices[0]), "pause does not finish voice early")
	paused = false
	await create_timer(0.35).timeout
	_expect(_voices(f.world).is_empty(), "voice completes after resume")
	f.player.play_release(_audio_snapshot(f, AudioStreamGenerator.new()))
	var pending = _voices(f.world)
	f.world.free()
	await process_frame
	_expect(pending.all(func(v): return not is_instance_valid(v)), "world exit cleans audio")
func _has_property(value: Object, key: String) -> bool:
	return value.get_property_list().any(func(p): return p.name == key)
func _add_skill(f: Dictionary, direct: bool = false) -> SkillBase:
	var skill = load("res://SkillSystem/01-Core/SkillBase.tscn").instantiate() as SkillBase
	skill.automatic_cast_enabled = false
	skill.skill_cooldown = 0.0
	skill.cast_range = 20.0
	skill.delivery = InstantTargetDeliveryConfig.new()
	skill.release_effect_scene = f.visual_scene
	if _has_property(skill, "release_camera_effect"):
		skill.set("release_camera_effect", f.profile)
		skill.set("release_audio_stream", _wave())
	if skill.has_signal("camera_effect_requested"):
		skill.connect("camera_effect_requested", func(_p,_s,_t,_x): RecordingVisual.trace.append("camera"))
	skill.delivery_started.connect(func(_c): RecordingVisual.trace.append("accepted"))
	skill.add_child(RecordingEffect.new())
	f.world.add_child(skill)
	skill.configure_owner(f.source, null, f.world)
	f.context.execution_mode = SkillContext.ExecutionMode.DIRECT_TRIGGER if direct else SkillContext.ExecutionMode.CHARACTER_ACTION
	f.context.activation_transform = f.action_transform
	return skill
func _test_root_configuration_and_inheritance() -> void:
	var skill = load("res://SkillSystem/01-Core/SkillBase.tscn").instantiate() as SkillBase
	_expect(_has_property(skill, "release_audio_stream") and _has_property(skill, "release_camera_effect"), "root asset slots exist")
	_expect(skill.get_node("RuntimeEffects").get_script() == player_script, "base RuntimeEffects owns generic player")
	_expect(skill.has_signal("camera_effect_requested"), "root camera request output exists")
	for p in skill.get_property_list():
		if p.name == "release_camera_effect":
			_expect(p.hint_string == "CameraEffectProfile", "camera asset picker strongly typed")
	skill.get_node("RuntimeEffects").set_script(null)
	_expect(Array(skill._get_configuration_warnings()).any(func(w): return "SkillReleasePresentationPlayer" in w), "missing player shows Inspector warning")
	skill.free()
	await process_frame
func _test_success_boundary_and_failure() -> void:
	var f = _make_fixture()
	var skill = _add_skill(f)
	_expect(skill.activate(f.context), "request accepted")
	_expect(RecordingVisual.trace.is_empty(), "queue has no release presentation")
	_expect(skill.confirm_action_started(f.action_transform), "action starts")
	_expect(RecordingVisual.trace.is_empty(), "cast is not release")
	_expect(skill.release_action(f.action_transform), "delivery accepts")
	_expect(RecordingVisual.trace == ["accepted","visual","camera","effect"], "acceptance/presentation/effect ordering")
	skill.release_action(f.action_transform)
	_expect(RecordingVisual.trace.count("visual") == 1, "duplicate release track is ignored")
	f.world.free()
	await process_frame
	var rejected = _make_fixture()
	var bad_skill = _add_skill(rejected)
	var recording_effects = bad_skill.get_children().filter(func(n):return n is RecordingEffect)
	recording_effects[0].free()
	_expect(bad_skill.activate(rejected.context), "bad delivery gets to release validation")
	bad_skill.confirm_action_started(rejected.action_transform)
	_expect(not bad_skill.release_action(rejected.action_transform), "empty effect delivery not accepted")
	_expect(RecordingVisual.trace.is_empty(), "failed startup never shows success")
	rejected.world.free()
	await process_frame
	var cancelled = _make_fixture()
	var cancel_skill = _add_skill(cancelled)
	cancel_skill.activate(cancelled.context)
	cancel_skill.confirm_action_started(cancelled.action_transform)
	cancel_skill.cancel_skill(&"interrupted")
	_expect(RecordingVisual.trace.is_empty(), "interruption has no success")
	cancelled.world.free()
	await process_frame
	var failed = _make_fixture()
	var accepted = _add_skill(failed, true)
	accepted.get_children().filter(func(n):return n is RecordingEffect)[0].succeeds = false
	_expect(accepted.activate(failed.context), "accepted effect failure still released")
	_expect(RecordingVisual.trace == ["accepted","visual","camera","effect"], "effect failure cannot retract release")
	failed.world.free()
	await process_frame
func _test_acceptance_reentry_snapshot() -> void:
	var f = _make_fixture()
	var skill = _add_skill(f, true)
	skill.release_effect_anchor = SkillBase.PresentationAnchor.TARGET_POSITION
	skill.delivery_started.connect(func(ctx):
		ctx.target_position = Vector3(90,0,90)
		f.target.global_position = Vector3(60,0,60)
		skill.release_effect_scene = null)
	_expect(skill.activate(f.context), "reentrant acceptance released")
	var visual = f.world.get_node_or_null("ProbeVisual")
	_expect(visual != null and visual.global_position.is_equal_approx(Vector3(7,0,3)), "position and asset snapshot precede notification")
	f.world.free()
	await process_frame
func _test_trigger_outlives_skill() -> void:
	var f = _make_fixture()
	var skill = _add_skill(f, true)
	_expect(skill.activate(f.context), "direct activation succeeds")
	var visual = f.world.get_node_or_null("ProbeVisual")
	var voices = _voices(f.world)
	skill.free()
	await process_frame
	_expect(is_instance_valid(visual), "child skill destruction keeps release visual")
	_expect(voices.size() == 1 and is_instance_valid(voices[0]), "child skill destruction keeps release audio")
	if is_instance_valid(visual): visual.effect_finished.emit()
	await create_timer(0.35).timeout
	_expect(not is_instance_valid(visual) and _voices(f.world).is_empty(), "detached releases recycle")
	f.world.free()
	await process_frame
func _test_volley_once_and_old_delivery() -> void:
	var f = _make_fixture()
	var skill = load("res://SkillSystem/00-Skills/RapidShot/RapidShotSkill.tscn").instantiate() as SkillBase
	skill.skill_cooldown = 0.0
	skill.release_effect_scene = f.visual_scene
	f.world.add_child(skill)
	skill.configure_owner(f.source, null, f.world)
	f.context.execution_mode = SkillContext.ExecutionMode.DIRECT_TRIGGER
	f.context.activation_transform = f.action_transform
	_expect(skill.activate(f.context), "three-shot volley released")
	_expect(RecordingVisual.trace.count("visual") == 1, "volley starts one presentation")
	for _frame in range(55): await physics_frame
	_expect(not skill.get_node("DeliveryRunner").is_busy(), "all three arrows settle without extra release presentation")
	_expect(RecordingVisual.trace.count("visual") == 1, "three actual shots still one presentation")
	_expect(skill.activate(f.context), "second volley released")
	_expect(skill.activate(f.context), "third concurrent volley released")
	_expect(RecordingVisual.trace.count("visual") == 3, "each activation once")
	skill.get_node("DeliveryRunner").cancel(&"old_miss")
	_expect(RecordingVisual.trace.count("visual") == 3, "old delivery outcomes do not replay")
	f.world.free()
	await process_frame
func _test_optional_channels_and_world_exit() -> void:
	var f = _make_fixture()
	var skill = _add_skill(f, true)
	skill.get_node("RuntimeEffects").free()
	_expect(skill.activate(f.context), "missing optional player does not reject gameplay")
	_expect(RecordingVisual.trace == ["accepted","effect"], "missing player skips only presentation")
	f.world.free()
	await process_frame
	var f2 = _make_fixture()
	var s2 = _add_skill(f2, true)
	s2.delivery_started.connect(func(_c): f2.world.queue_free())
	_expect(s2.activate(f2.context), "world transition preserves acceptance")
	_expect(RecordingVisual.trace.count("visual") == 0 and _voices(f2.world).is_empty(), "queued world does not spawn new effects")
	await process_frame
func _round() -> int: return 1
func _test_chain_fee_before_presentation() -> void:
	var f = load("res://UnitSystem/Tests/AllyChainCommandPriorityTest.gd").make_fixture(root, "res://UnitSystem/AI/Ally/Units/Caster.tscn", false)
	var focus = SquadFocusComponent.new()
	focus.auto_bind_parent = false
	focus.initial_focus = 100.0
	f.world.add_child(focus)
	var party: Array[UnitBase] = [f.player, f.actor]
	focus.bind_scope(f.world, party)
	var controller = SquadChainCommandController.new()
	var companions: Array[AllyBase] = [f.actor, null, null, null]
	controller.companions = companions
	controller.focus_source = focus
	f.world.add_child(controller)
	controller.set_round_source(Callable(self,"_round"), Callable(self,"_round"))
	if _has_property(f.combo,"release_camera_effect"):
		f.combo.set("release_camera_effect", profile_script.new())
	var observed: Array[float] = []
	if f.combo.has_signal("camera_effect_requested"):
		f.combo.connect("camera_effect_requested",func(_p,_s,_t,_x): observed.append(focus.get_current_focus()))
	await physics_frame
	await physics_frame
	_expect(controller.submit_slot(0), "chain instruction admitted")
	f.host.advance_pending_command(f.enemy, 0.0)
	f.animation.release_action()
	_expect(observed == [80.0], "chain presentation follows true focus payment")
	f.animation.finish_action()
	f.world.free()
	await process_frame
func _test_preview_load_and_configuration() -> void:
	var path = "res://Scenes/Previews/SkillReleasePresentationPreview.tscn"
	if not ResourceLoader.exists(path):
		_expect(false, "independent release preview scene missing")
		return
	var scene = load(path).instantiate()
	root.add_child(scene)
	_expect(scene.has_method("play_preview"), "preview offers one-shot operation")
	var nodes = ["SourceMarker","TargetMarker","WorldPlayback","RuntimeEffects","Camera3D",
		"CanvasLayer/Panel/VBox/PlayButton","CanvasLayer/Panel/VBox/TestChannelsButton","CanvasLayer/Panel/VBox/RequestCountLabel"]
	for path_item in nodes:
		_expect(scene.has_node(path_item), "preview node " + path_item)
	var before = scene.get_node("Camera3D").global_transform
	var requests: Array = []
	scene.get_node("RuntimeEffects").camera_effect_requested.connect(func(_p,_s,_t,_x): requests.append(1))
	scene.play_preview()
	_expect(requests.is_empty(), "empty preview does not fake a camera request")
	scene.get_node("CanvasLayer/Panel/VBox/TestChannelsButton").pressed.emit()
	_expect(requests.size() == 1, "test channels emit one actual request")
	_expect(scene.get_node("CanvasLayer/Panel/VBox/RequestCountLabel").text.begins_with("镜头请求：1"), "label observes real request")
	_expect(scene.get_node("Camera3D").global_transform.is_equal_approx(before), "camera request is not movement")
	_expect(_voices(scene.get_node("WorldPlayback")).size() == 1, "test channels create actual voice")
	_expect(ResourceLoader.get_resource_uid(path) != ResourceUID.INVALID_ID, "preview UID valid")
	scene.free()
	await process_frame
func _test_preview_repeat_and_cleanup() -> void:
	var path = "res://Scenes/Previews/SkillReleasePresentationPreview.tscn"
	if not ResourceLoader.exists(path): return
	var scene = load(path).instantiate()
	root.add_child(scene)
	for index in range(3):
		scene.get_node("CanvasLayer/Panel/VBox/TestChannelsButton").pressed.emit()
	_expect(scene.get_node("CanvasLayer/Panel/VBox/RequestCountLabel").text.begins_with("镜头请求：3"), "repeat does not duplicate listeners")
	var voices = _voices(scene.get_node("WorldPlayback"))
	scene.free()
	await process_frame
	_expect(voices.all(func(v):return not is_instance_valid(v)), "preview exit reclaims voices")
func _test_release_stress() -> void:
	var f = _make_fixture()
	var skill = _add_skill(f, true)
	var baseline = f.world.get_child_count()
	for index in range(100):
		_expect(skill.activate(f.context), "stress activation %d" % index)
	_expect(RecordingVisual.trace.count("accepted") == 100 and RecordingVisual.trace.count("camera") == 100, "100 accepts/requests no duplicates")
	for child in f.world.get_children():
		if child is RecordingVisual: child.effect_finished.emit()
	for poll in range(20):
		if f.world.get_child_count() == baseline: break
		await create_timer(0.05).timeout
	if f.world.get_child_count() != baseline:
		print("STRESS LEFTOVERS baseline=", baseline, " nodes=", f.world.get_children().map(func(n):return [n.name,n.get_class(),n is RecordingVisual,n.has_signal("effect_finished"),n.get("playing") if n is AudioStreamPlayer3D else null]))
	_expect(f.world.get_child_count() == baseline, "100 voices/visuals reclaim to baseline")
	f.world.free()
	await process_frame
	var orphans = Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)
	for iteration in range(10):
		var next = _make_fixture()
		var next_skill = _add_skill(next, true)
		_expect(next_skill.activate(next.context), "reload activation")
		next.world.free()
		await process_frame
	_expect(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT) == orphans, "10 world reloads leave no new orphans")
func _test_top_level_pose() -> void:
	var f = _make_fixture()
	f.world.position = Vector3(10,0,0)
	f.source.global_position = Vector3(2,0,3)
	f.target.global_position = Vector3(7,0,3)
	var template = RecordingVisual.new()
	template.name = "TopLevelProbe"
	template.top_level = true
	var scene = PackedScene.new()
	scene.pack(template)
	template.free()
	var snapshot = f.player.prepare_release(f.context, f.action_transform, scene, 0, null, null)
	f.player.play_release(snapshot)
	_expect(RecordingVisual.ready_poses.size() == 1, "top-level ready recorded")
	if not RecordingVisual.ready_poses.is_empty():
		_expect(RecordingVisual.ready_poses[0].origin.is_equal_approx(Vector3(2,1,3)), "top-level visual uses world pose without parent inverse")
	f.world.free()
	await process_frame
func _expect(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
func _finish() -> void:
	for message in failures: push_error(message)
	if failures.is_empty(): print("SkillReleasePresentationTest: PASS")
	quit(0 if failures.is_empty() else 1)