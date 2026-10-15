extends SceneTree
## 表现事实必须在真实Host确认/费用提交后发出；不以资源能加载代替时序。
var failures: Array[String] = []
var trace: Array[String] = []
var starts: Array = []
var releases: Array = []
var prepared: Array = []

func _initialize() -> void: call_deferred(&"_run")

func _run() -> void:
	var f = load("res://UnitSystem/Tests/AllyChainCommandPriorityTest.gd").make_fixture(root, "res://UnitSystem/AI/Ally/Units/Caster.tscn", false)
	await physics_frame
	await physics_frame
	var host: SkillHostComponent = f.host
	_expect(host.has_signal(&"command_action_started"), "Host must publish committed actual action start")
	_expect(f.combo.has_method(&"get_current_presentation_context"), "skill must expose current immutable presentation")
	_expect(f.combo.has_signal(&"release_instance_prepared"), "release instances require pre-ready registration")
	if not failures.is_empty():
		f.world.free()
		_finish()
		return
	var focus := SquadFocusComponent.new()
	focus.auto_bind_parent = false
	focus.initial_focus = 100.0
	f.world.add_child(focus)
	var party: Array[UnitBase] = [f.player, f.actor]
	focus.bind_scope(f.world, party)
	var commander := SquadChainCommandController.new()
	commander.companions = [f.actor, null, null, null]
	commander.focus_source = focus
	f.world.add_child(commander)
	commander.set_round_source(func(): return 100, func(): return 100)
	f.combo.get_combo_focus_cost().base_focus_cost = 20.0
	host.connect(&"command_action_started", func(request, presentation):
		_expect(request.has_action_started(), "action already confirmed before fact")
		_expect(host.get_active_command_id() == request.request_id, "Host active identity committed")
		_expect(host.get_pending_command_id() == 0, "pending migrated before fact")
		_expect(presentation.command_request_id == request.request_id, "same request identity")
		starts.append(presentation))
	commander.command_released.connect(func(_id, _cost): trace.append("fee"))
	commander.connect(&"command_release_instance_prepared", func(_slot, presentation, instance):
		_expect(not instance.is_inside_tree(), "prepared before add_child and ready")
		trace.append("prepared")
		prepared.append(presentation))
	commander.connect(&"command_release_presentation_started", func(_slot, presentation):
		trace.append("accent")
		releases.append(presentation))
	var visual := Node3D.new()
	visual.name = "PresentationProbe"
	var pack := PackedScene.new()
	pack.pack(visual)
	visual.free()
	f.combo.release_effect_scene = pack
	_expect(commander.submit_slot(0), "real command admitted")
	f.actor.get_behavior_state_machine().physics_tick(0.01)
	_expect(starts.size() == 1, "one committed begin")
	if starts.size() == 1:
		var cast = starts[0]
		_expect(cast.get_source() == f.actor and cast.get_world() == f.world, "weak node snapshot")
		_expect(cast.is_chain_root and cast.effective_cast_time > 0.0, "root and effective duration")
		f.combo.release_effect_scene = null
		f.animation.release_action()
		_expect(trace == ["fee", "prepared", "accent"], "fee precedes pre-ready instance and accent")
		_expect(focus.get_current_focus() == 80.0, "exactly one payment")
		_expect(prepared.size() == 1 and releases.size() == 1, "cast asset snapshot stable despite later edit")
		if releases.size() == 1:
			_expect(releases[0].presentation_id == cast.presentation_id, "same presentation identity across stages")
			_expect(releases[0].stage != cast.stage, "release is a separate immutable stage")
		f.animation.finish_action()
		var before = starts.size()
		_expect(commander.submit_slot(0), "repeat root admitted")
		f.actor.get_behavior_state_machine().physics_tick(0.01)
		_expect(starts.size() == before + 1, "repeat emits new start")
		if starts.size() > before:
			_expect(starts[-1].presentation_id != cast.presentation_id, "repeat uses new presentation id")
		host.set_cast_blocked(true)
	var weak_actor = weakref(f.actor)
	f.world.free()
	_expect(weak_actor.get_ref() == null, "snapshots never keep actor alive")
	await process_frame
	await _test_formal_assets_and_alias_migration()
	await _test_optional_and_legacy_configuration()
	await _test_reentrant_release_and_failure()
	_finish()

func _finish() -> void:
	for message in failures: push_error(message)
	if failures.is_empty(): print("SkillPresentationLifecycleTest: PASS")
	quit(0 if failures.is_empty() else 1)

func _expect(ok: bool, label: String) -> void:
	if not ok: failures.append(label)

func _test_optional_and_legacy_configuration() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var source := Node3D.new()
	world.add_child(source)
	var skill = load("res://SkillSystem/01-Core/SkillBase.tscn").instantiate()
	world.add_child(skill)
	var profile := SkillFocusCameraProfile.new()
	skill.release_camera_effect = profile
	_expect(skill.camera_effect_profile == profile, "legacy alias routes canonical slot")
	var exported: Array[String] = []
	for property in skill.get_property_list():
		if int(property.usage) & PROPERTY_USAGE_EDITOR: exported.append(property.name)
	_expect(not exported.has("release_camera_effect") and exported.has("camera_effect_profile"), "only one Inspector camera slot")
	var ctx := SkillContext.new()
	ctx.caster = source
	ctx.delivery_parent = world
	var cast := SkillPresentationContext.create(skill, ctx, Transform3D.IDENTITY)
	profile.enter_duration_seconds = 2.0
	_expect(is_equal_approx(cast.get_camera_profile().get_phase_duration(0), 0.30), "shared profile mutation cannot change active snapshot")
	ctx.execution_mode = SkillContext.ExecutionMode.DIRECT_TRIGGER
	ctx.purpose = SkillContext.Purpose.REGULAR
	var direct := SkillPresentationContext.create(skill, ctx, Transform3D.IDENTITY)
	_expect(not direct.is_chain_root, "trigger not root")
	var player = skill.get_node("RuntimeEffects")
	var notifications: Array = []
	player.release_presentation_started.connect(func(fact): notifications.append(fact))
	player.play_release(player.prepare_release(ctx, Transform3D.IDENTITY, null, 0, null, null, cast))
	_expect(notifications.size() == 1, "no visual/audio still reports success fact for accent")
	var path := "user://chain_presentation_legacy_fixture.tscn"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string('[gd_scene load_steps=3 format=3]\n[ext_resource type="Script" path="res://SkillSystem/01-Core/SkillBase.gd" id="1"]\n[ext_resource type="Script" path="res://Effects/Camera/SkillFocusCameraProfile.gd" id="2"]\n[sub_resource type="Resource" id="Profile"]\nscript = ExtResource("2")\n[node name="LegacySkill" type="Node"]\nscript = ExtResource("1")\nrelease_camera_effect = SubResource("Profile")\n')
	file.close()
	var loaded := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	var legacy = loaded.instantiate()
	_expect(legacy.camera_effect_profile is SkillFocusCameraProfile, "old serialized field really loads")
	var saved := PackedScene.new()
	saved.pack(legacy)
	_expect(ResourceSaver.save(saved, path) == OK, "Godot migration save")
	_expect(not FileAccess.get_file_as_string(path).contains("release_camera_effect ="), "resave contains canonical field only")
	legacy.free()
	DirAccess.remove_absolute(path)
	world.free()
	await process_frame

func _test_reentrant_release_and_failure() -> void:
	var f = load("res://UnitSystem/Tests/AllyChainCommandPriorityTest.gd").make_fixture(root, "res://UnitSystem/AI/Ally/Units/Caster.tscn", false)
	await physics_frame
	var focus := SquadFocusComponent.new()
	focus.auto_bind_parent = false
	focus.initial_focus = 100
	f.world.add_child(focus)
	var party: Array[UnitBase] = [f.player, f.actor]
	focus.bind_scope(f.world, party)
	var command := SquadChainCommandController.new()
	command.companions = [f.actor, null, null, null]
	command.focus_source = focus
	f.world.add_child(command)
	command.set_round_source(func(): return 100, func(): return 100)
	var facts: Array = []
	command.command_failed.connect(func(slot, id, reason): facts.append([slot,id,reason]))
	_expect(command.submit_slot(0), "failure probe admitted")
	var id = f.host.get_pending_command_id()
	f.host.set_cast_blocked(true)
	_expect(facts.size() == 1 and facts[0] == [0,id,&"cast_blocked"], "failed identity survives synchronous lifetime removal")
	_expect(focus.get_reserved_focus() == 0, "failure refunded exactly once")
	f.world.free()
	var world := Node3D.new()
	root.add_child(world)
	var player := SkillReleasePresentationPlayer.new()
	world.add_child(player)
	var node := Node3D.new()
	var scene := PackedScene.new()
	scene.pack(node)
	node.free()
	var context := SkillContext.new()
	context.delivery_parent = world
	var ran: Array = []
	player.release_instance_prepared.connect(func(_fact, instance): instance.free())
	player.camera_effect_requested.connect(func(_p,_s,_t,_x): ran.append(true))
	player.play_release(player.prepare_release(context, Transform3D.IDENTITY, scene, 0, null, CameraEffectProfile.new()))
	_expect(ran.size() == 1 and world.get_child_count() == 1, "freed prepared visual skips safely without blocking other channels")
	world.free()
	await process_frame
func _test_formal_assets_and_alias_migration() -> void:
	var paths := ["res://Effects/Camera/Presets/ChainSkillFocus.tres","res://Effects/Combat/Presets/ChainReleaseAccent.tres"]
	for path in paths:
		_expect(ResourceLoader.exists(path),"formal preset exists: "+path)
		if not ResourceLoader.exists(path): return
		_expect(ResourceLoader.get_resource_uid(path) != ResourceUID.INVALID_ID,"formal preset registered UID: "+path)
	var camera = load(paths[0])
	var accent = load(paths[1])
	_expect(camera is SkillFocusCameraProfile and accent is ReleaseAccentProfile,"strong preset types")
	_expect(is_equal_approx(camera.enter_duration_seconds,0.30) and is_equal_approx(camera.return_duration_seconds,0.55),"camera preset defaults")
	_expect(is_equal_approx(accent.pause_duration_seconds,0.10),"accent preset default")
	for name in ["GuardianBash","GreaterHeal","Firebolt","RapidShot"]:
		var skill = load("res://SkillSystem/00-Skills/Combo_%s/Combo%sSkill.tscn" % [name,name]).instantiate()
		_expect(skill.camera_effect_profile == camera and skill.release_accent_profile == accent,"four combo roots select shared presets")
		_expect(skill.get_node("RuntimeEffects") is SkillReleasePresentationPlayer,"no second presentation player")
		skill.free()