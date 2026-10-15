
extends SceneTree
## 本次释放使用独立时钟；真实正常运动/冷却正对照排除从未运行的伪通过。
class Mover extends CharacterBody3D:
	func _physics_process(delta: float) -> void: position.x += delta
var failures: Array[String] = []
func _initialize() -> void: call_deferred(&"_run")
func _run() -> void:
	if not ResourceLoader.exists("res://GameFlow/Pause/GamePauseCoordinator.gd"):
		_expect(false, "release instances must keep running while battle pauses")
		_finish()
		return
	await _test_release_runs_battle_stops()
	await _test_accent_flash_scene()
	await _test_cast_visual_starts_before_release()
	await _test_expired_cast_visual_cleanup()
	await _test_cast_visual_midpoint()
	_test_cast_visual_uses_effective_duration()
	_finish()
func _wait(seconds: float) -> void:
	var deadline := Time.get_ticks_usec() + int(seconds*1000000.0)
	while Time.get_ticks_usec() < deadline: await process_frame
func _test_release_runs_battle_stops() -> void:
	var f = load("res://UnitSystem/Tests/AllyChainCommandPriorityTest.gd").make_fixture(root)
	await physics_frame
	await physics_frame
	var manager = load("res://GameFlow/Pause/GamePauseCoordinator.gd").new()
	f.world.add_child(manager)
	manager.bind_scope(f.world)
	var mover := Mover.new()
	mover.process_mode = Node.PROCESS_MODE_PAUSABLE
	f.world.add_child(mover)
	var projectile = load("res://Item/Projectiles/FireBall.tscn").instantiate()
	f.world.add_child(projectile)
	_expect(projectile.launch(f.player,f.enemy,Vector3(-10,2,0),Vector3.RIGHT,1.0,180.0,10.0,0.1),"real ordinary fireball launch")
	var regular: SkillBase = f.host.get_regular_skill(0)
	regular.skill_cooldown = 6.0
	regular.decision_delay_min = 0
	regular.decision_delay_max = 0
	regular.extra_hesitation_chance = 0
	regular.call("_start_cooldown")
	await _wait(0.06)
	_expect(mover.position.x > 0 and projectile.position.x > -10 and regular.get_cooldown_remaining() < 6.0, "real battle and ordinary cooldown run before pause")
	var scene := _visual()
	f.combo.release_effect_scene = scene
	f.combo.release_audio_stream = _wave()
	f.combo.release_accent_profile = ReleaseAccentProfile.new()
	var visual_nodes: Array[Node] = []
	var voices: Array[Node] = []
	f.combo.release_instance_prepared.connect(func(fact, instance):
		_expect(not instance.is_inside_tree(), "clock prepared before ready")
		_expect(manager.register_release_instance(fact.presentation_id,instance), "pure instance registered")
		if instance is AudioStreamPlayer3D: voices.append(instance)
		else: visual_nodes.append(instance))
	f.combo.release_presentation_started.connect(func(fact): manager.request_release_accent(fact.presentation_id,0.15,f.world))
	var request := SkillCommandRequest.create(501,500,f.actor,f.combo,f.world,8.0,func(): return true)
	f.requests[501] = request
	_expect(f.host.enqueue_command(request),"real root admitted")
	f.actor.get_behavior_state_machine().physics_tick(0.01)
	f.animation.release_action()
	_expect(paused and visual_nodes.size() == 1 and voices.size() == 1, "actual root starts accent and assets")
	var x := mover.position.x
	var px: float = projectile.position.x
	var cd := regular.get_cooldown_remaining()
	var visual := visual_nodes[0]
	var animation: AnimationPlayer = visual.get_node("AnimationPlayer")
	var at := animation.current_animation_position
	await _wait(0.055)
	_expect(paused and is_equal_approx(mover.position.x,x) and is_equal_approx(projectile.position.x,px), "battle motion frozen")
	_expect(is_equal_approx(regular.get_cooldown_remaining(),cd), "ordinary six second cooldown frozen")
	_expect(animation.current_animation_position > at, "native autoplay progresses during accent")
	var menu: int = manager.acquire_pause(f.world,&"menu")
	at = animation.current_animation_position
	await _wait(0.055)
	_expect(is_equal_approx(animation.current_animation_position,at), "explicit pause freezes native animation")
	_expect(not manager.is_presentation_allowed(), "explicit pause suspends presentation")
	manager.release_pause(menu)
	await _wait(0.18)
	_expect(not paused and mover.position.x > x and projectile.position.x > px and regular.get_cooldown_remaining() < cd, "battle and cooldown resume after accent")
	f.combo.queue_free()
	await process_frame
	_expect(is_instance_valid(visual) and visual.is_inside_tree(), "release outlives skill")
	await _wait(0.5)
	_expect(not is_instance_valid(visual), "native instance naturally recycles without skill")
	f.world.free()
	_expect(not paused, "world exits with clean pause state")
func _visual() -> PackedScene:
	var visual := Node3D.new()
	visual.name = "ClockVisual"
	var mesh := Node3D.new()
	mesh.name = "Marker"
	visual.add_child(mesh)
	mesh.owner = visual
	var animator := AnimationPlayer.new()
	animator.name = "AnimationPlayer"
	visual.add_child(animator)
	animator.owner = visual
	var animation := Animation.new()
	animation.length = 0.45
	var track := animation.add_track(Animation.TYPE_VALUE)
	animation.track_set_path(track,NodePath("Marker:position"))
	animation.track_insert_key(track,0.0,Vector3.ZERO)
	animation.track_insert_key(track,0.45,Vector3.UP)
	var library := AnimationLibrary.new()
	library.add_animation(&"flash",animation)
	animator.add_animation_library(&"",library)
	animator.autoplay = &"flash"
	var timer := Timer.new()
	timer.name = "Cleanup"
	timer.one_shot = true
	timer.wait_time = 0.5
	timer.autostart = true
	visual.add_child(timer)
	timer.owner = visual
	timer.timeout.connect(visual.queue_free,CONNECT_PERSIST)
	var scene := PackedScene.new()
	scene.pack(visual)
	visual.free()
	return scene
func _wave() -> AudioStreamWAV:
	var wave := AudioStreamWAV.new()
	wave.mix_rate = 8000
	wave.data = PackedByteArray()
	var data := PackedByteArray()
	data.resize(4000)
	data.fill(128)
	wave.data = data
	return wave
func _finish() -> void:
	paused = false
	for message in failures: push_error(message)
	if failures.is_empty(): print("ReleaseAccentClockTest: PASS")
	quit(0 if failures.is_empty() else 1)
func _expect(ok: bool,label: String) -> void:
	if not ok: failures.append(label)
func _test_accent_flash_scene() -> void:
	var path := "res://Effects/Skills/Shared/ReleaseAccentFlash.tscn"
	_expect(ResourceLoader.exists(path),"native release flash scene exists")
	if not ResourceLoader.exists(path): return
	_expect(ResourceLoader.get_resource_uid(path) != ResourceUID.INVALID_ID,"flash scene has valid UID")
	var visual = load(path).instantiate()
	_expect(visual.get_script() == null,"no special flash script")
	_expect(visual.get_node("AnimationPlayer") is AnimationPlayer and visual.get_node("CleanupTimer") is Timer,"native scene lifecycle visible")
	var rays: Node3D = visual.get_node_or_null("VisualRoot/BodyRays")
	var ring := visual.get_node_or_null("VisualRoot/GroundRing") as MeshInstance3D
	_expect(rays != null and ring != null, "body convergence rays and foot ring replace tiny sphere")
	if rays == null or ring == null:
		visual.free()
		return
	_expect(rays.get_child_count() == 8, "eight readable body streaks")
	for ray: MeshInstance3D in rays.get_children():
		var material := ray.material_override as StandardMaterial3D
		_expect(ray.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "rays do not cast shadows")
		_expect(material != null and material.albedo_color.b > material.albedo_color.r and material.albedo_color.r > 0.75, "silver white with subtle blue")
	_expect(ring.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "ground ring does not cast shadows")
	var world := Node3D.new()
	root.add_child(world)
	var pause := GamePauseCoordinator.new()
	world.add_child(pause)
	pause.bind_scope(world)
	_expect(pause.register_release_instance(909,visual),"native flash clock registration")
	world.add_child(visual)
	var animation: AnimationPlayer = visual.get_node("AnimationPlayer")
	var cleanup: Timer = visual.get_node("CleanupTimer")
	cleanup.stop() # 固定采样动画，避免无帧率上限的无头环境提前回收。
	animation.play(&"pulse")
	animation.seek(0.0, true)
	var first_ray: MeshInstance3D = rays.get_child(0)
	var outer: float = first_ray.position.length()
	animation.seek(0.08, true)
	_expect(first_ray.position.length() < outer, "streaks converge towards body")
	var outer_ring := ring.scale.x
	animation.seek(0.18, true)
	_expect(ring.scale.x < outer_ring, "delayed ground ring converges towards feet")
	animation.seek(0.25, true)
	_expect(ring.transparency > 0.99 and first_ray.transparency > 0.99, "all geometry fades by quarter second")
	animation.play(&"pulse")
	animation.seek(0.0, true)
	pause.request_release_accent(909,0.15,world)
	await _wait(0.055)
	_expect(paused and first_ray.position.length() < outer, "native convergence advances while battle paused")
	cleanup.start()
	await _wait(0.40)
	_expect(not paused and not is_instance_valid(visual), "native convergence recycles and pause restores independently")
	world.free()
	var preview = load("res://Effects/Skills/Shared/ReleaseAccentFlashPreview.tscn").instantiate()
	_expect(preview.anchor == SkillBase.PresentationAnchor.CASTER_FEET, "standalone preview uses feet anchor")
	preview.free()
	var integrated = load("res://Scenes/Previews/ChainSkillPresentationPreview.tscn").instantiate()
	for entry: String in ["Guardian/SkillHost/SkillSocket/ComboGuardianBashSkill", "Priest/SkillHost/SkillSocket/ComboGreaterHealSkill", "Caster/SkillHost/SkillSocket/ComboFireboltSkill", "Archer/SkillHost/SkillSocket/ComboRapidShotSkill"]:
		var skill: SkillBase = integrated.get_node(entry)
		_expect(skill.cast_effect_scene != null and skill.cast_effect_scene.resource_path == path and skill.get("cast_effect_anchor") == SkillBase.PresentationAnchor.CASTER_FEET and skill.release_effect_scene == null and skill.get("cast_effect_start_ratio") == 0.5, "shared preview visual is configured for cast midpoint: " + entry)
	integrated.free()

func _test_cast_visual_uses_effective_duration() -> void:
	var helper = load("res://SkillSystem/05-Tests/SingleSceneSkillBaseTest.gd")
	for row: Dictionary in [{"base":1.2,"speed":2.0,"before":0.29}, {"base":1.2,"speed":0.5,"before":1.19}, {"base":0.0,"speed":2.0,"before":0.0}]:
		var world := Node3D.new()
		root.add_child(world)
		var caster = helper.TestUnit.new()
		caster.faction = &"ally"
		caster.cast_speed_multiplier = row.speed
		world.add_child(caster)
		var target = helper.TestUnit.new()
		target.faction = &"enemy"
		world.add_child(target)
		var skill: SkillBase = load("res://SkillSystem/01-Core/SkillBase.tscn").instantiate()
		skill.base_cast_time = row.base
		skill.delivery = InstantTargetDeliveryConfig.new()
		skill.cast_effect_scene = load("res://Effects/Skills/Shared/ReleaseAccentFlash.tscn")
		skill.cast_effect_anchor = SkillBase.PresentationAnchor.CASTER_FEET
		skill.cast_effect_start_ratio = 0.5
		world.add_child(skill)
		skill.set_physics_process(false)
		skill.configure_owner(caster,null,world)
		var context := SkillContext.new()
		context.requested_target = target
		context.explicit_target_requested = true
		context.delivery_parent = world
		_expect(skill.request_skill(context) and skill.confirm_action_started(Transform3D.IDENTITY), "speed-scaled cast starts")
		if row.base > 0.0:
			skill.call("_physics_process",row.before)
			_expect(caster.get_node_or_null("ReleaseAccentFlash") == null, "speed-scaled effect absent just before actual midpoint")
			skill.call("_physics_process",0.01)
		_expect(caster.get_node_or_null("ReleaseAccentFlash") != null, "haste slow and zero cast use effective duration not base duration")
		world.free()

func _test_cast_visual_midpoint() -> void:
	var f = load("res://UnitSystem/Tests/AllyChainCommandPriorityTest.gd").make_fixture(root)
	await physics_frame
	await physics_frame
	var names: Array = f.combo.get_property_list().map(func(p): return p.name)
	_expect(names.has("cast_effect_start_ratio"), "cast visual exposes normalized phase instead of fixed delay seconds")
	if not names.has("cast_effect_start_ratio"):
		f.world.free()
		return
	f.combo.set_physics_process(false) # 明确推进战斗delta，不混入墙上时间或夹具动画的手动时钟。
	f.combo.cast_effect_scene = load("res://Effects/Skills/Shared/ReleaseAccentFlash.tscn")
	f.combo.set("cast_effect_anchor", SkillBase.PresentationAnchor.CASTER_FEET)
	f.combo.set("cast_effect_start_ratio", 0.5)
	for i: int in range(4):
		f.combo.base_cast_time = 0.8 if i == 0 else (0.4 if i == 1 else (0.1 if i == 2 else 0.8))
		var request := SkillCommandRequest.create(1901+i,1900,f.actor,f.combo,f.world,8.0,func(): return true)
		f.requests[1901+i] = request
		_expect(f.host.enqueue_command(request), "midpoint request admitted")
		f.actor.get_behavior_state_machine().physics_tick(0.01)
		_expect(f.actor.get_node_or_null("ReleaseAccentFlash") == null, "start does not play midpoint visual early")
		var before: float = 0.39 if i == 0 else (0.19 if i == 1 else (0.04 if i == 2 else 0.39))
		f.combo.call("_physics_process",before)
		_expect(f.actor.get_node_or_null("ReleaseAccentFlash") == null, "visual absent before half of actual cast duration")
		if i == 3:
			f.host.set_cast_blocked(true)
			f.combo.call("_physics_process",1.0)
			_expect(f.actor.get_node_or_null("ReleaseAccentFlash") == null, "interrupted pending visual never fires late")
		else:
			paused = true
			await process_frame
			_expect(f.actor.get_node_or_null("ReleaseAccentFlash") == null, "paused battle does not advance delayed visual")
			paused = false
			f.combo.call("_physics_process",0.01)
			var visual: Node3D = f.actor.get_node_or_null("ReleaseAccentFlash")
			_expect(visual != null, "visual starts at half duration including short cast")
			f.combo.call("_physics_process",0.02)
			_expect(f.actor.get_node_or_null("ReleaseAccentFlash") == visual, "phase crossing never creates duplicate visual")
			f.animation.release_action()
			f.animation.finish_action()
			await _wait(0.32)
	f.world.free()
	await process_frame

func _test_expired_cast_visual_cleanup() -> void:
	var f = load("res://UnitSystem/Tests/AllyChainCommandPriorityTest.gd").make_fixture(root)
	await physics_frame
	await physics_frame
	f.combo.cast_effect_scene = load("res://Effects/Skills/Shared/ReleaseAccentFlash.tscn")
	f.combo.base_cast_time = 1.0
	for i: int in range(3):
		var request := SkillCommandRequest.create(1801+i,1800,f.actor,f.combo,f.world,8.0,func(): return true)
		f.requests[1801+i] = request
		_expect(f.host.enqueue_command(request), "expired visual request accepted")
		f.actor.get_behavior_state_machine().physics_tick(0.01)
		await _wait(0.35)
		match i:
			0:
				f.animation.release_action()
				f.animation.finish_action()
			1:
				f.host.set_cast_blocked(true)
				f.host.set_cast_blocked(false)
			2:
				f.combo.reset_skill()
		_expect(f.combo.get("_runtime_effect_instances").is_empty(), "expired native cast visual pruned without passing freed object to typed-array erase")
	f.world.free()
	await process_frame

func _test_cast_visual_starts_before_release() -> void:
	var f = load("res://UnitSystem/Tests/AllyChainCommandPriorityTest.gd").make_fixture(root)
	await physics_frame
	await physics_frame
	var properties: Array = f.combo.get_property_list().map(func(p): return p.name)
	_expect(properties.has("cast_effect_anchor"), "cast visual supports the shared anchor contract")
	if not properties.has("cast_effect_anchor"):
		f.world.free()
		return
	var node := Node3D.new()
	node.name = "CastPhaseProbe"
	var cleanup := Timer.new()
	cleanup.name = "Cleanup"
	cleanup.wait_time = 0.28
	cleanup.one_shot = true
	cleanup.autostart = true
	node.add_child(cleanup)
	cleanup.owner = node
	cleanup.timeout.connect(node.queue_free, CONNECT_PERSIST)
	var packed := PackedScene.new()
	packed.pack(node)
	node.free()
	f.combo.cast_effect_scene = packed
	f.combo.set("cast_effect_anchor", SkillBase.PresentationAnchor.CASTER_FEET)
	f.combo.release_effect_scene = null
	var successes: Array = []
	f.combo.release_presentation_started.connect(func(fact): successes.append(fact))
	for i: int in range(2):
		var request := SkillCommandRequest.create(1701+i,1700,f.actor,f.combo,f.world,8.0,func(): return true)
		f.requests[1701+i] = request
		_expect(f.host.enqueue_command(request), "cast visual request admitted")
		_expect(f.actor.get_node_or_null("CastPhaseProbe") == null, "queued request has no cast visual")
		f.actor.get_behavior_state_machine().physics_tick(0.01)
		var visual: Node3D = f.actor.get_node_or_null("CastPhaseProbe")
		_expect(visual != null, "visual appears at actual cast start before release marker")
		if visual == null: continue
		_expect(visual.global_position.is_equal_approx(f.actor.global_position), "cast visual attaches to caster feet rather than weapon")
		_expect(successes.size() == i, "cast visual does not report release success or start hit stop")
		_expect(not f.combo.confirm_action_started(Transform3D.IDENTITY), "duplicate start cannot replay cast visual")
		if i == 0:
			f.animation.release_action()
			_expect(successes.size() == 1, "release success remains at the release marker")
			_expect(is_instance_valid(visual) and not visual.is_queued_for_deletion(), "short casts do not clip one-shot cast visual before its natural finish")
			f.animation.finish_action()
			await _wait(0.35)
		else:
			f.host.set_cast_blocked(true)
			_expect(successes.size() == 1, "interrupted cast never reports release success")
		await process_frame
		_expect(not is_instance_valid(visual) and f.actor.get_node_or_null("CastPhaseProbe") == null, "one-shot finish or interruption removes cast visual without replay")
	f.world.free()
	await process_frame