extends SceneTree
## 缺少遮挡抑制、恢复时机错误或旧身份误清理，都必须由真实模型可见性断言捕获。
var failures: Array[String] = []
func _initialize() -> void: call_deferred("_run")
func _expect(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
func _mesh(parent: Node, point: Vector3, size: Vector3 = Vector3(0.6,1.0,0.6)) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	m.mesh = box
	parent.add_child(m)
	m.position = point
	return m
func _unit(world: Node, point: Vector3) -> UnitBase:
	var u := load("res://UnitSystem/Base/00_UnitBase.tscn").instantiate() as UnitBase
	world.add_child(u)
	u.position = point
	_mesh(u.get_node("Visual"),Vector3(0,0.5,0))
	return u
func _run() -> void:
	var profile := SkillCinematicCameraProfile.new()
	_expect(profile.get("hide_closeup_occluders") != null,"camera profile exposes occlusion switch")
	_expect(profile.get("occlusion_corridor_width_m") != null,"camera profile exposes corridor width")
	if not failures.is_empty():
		_finish()
		return
	var world := Node3D.new()
	root.add_child(world)
	var caster := _unit(world,Vector3.ZERO)
	var own_fx := _mesh(caster,Vector3(0,0.8,-1))
	var blocker := _unit(world,Vector3(0,0,-1.4))
	var weapon := _mesh(blocker.get_node("Visual"),Vector3(1.2,0.6,0),Vector3(0.1,0.1,0.8))
	var side := _unit(world,Vector3(4,0,-1))
	var behind := _unit(world,Vector3(0,0,2))
	var prop := _mesh(world,Vector3(0.2,0.8,-2.0))
	var broad_prop := _mesh(world,Vector3(1.4,0.8,-1.8),Vector3(2,1,0.2))
	var custom_prop := _mesh(world,Vector3(2.2,0.8,-1.5),Vector3(0.1,0.1,0.1))
	custom_prop.custom_aabb = AABB(Vector3(-2.5,-0.2,-0.2),Vector3(3,0.4,0.4))
	var margin_prop := _mesh(world,Vector3(1.6,0.8,-1.5),Vector3(0.1,0.1,0.1))
	margin_prop.extra_cull_margin = 0.7
	var scaled_margin_prop := _mesh(world,Vector3(2.4,0.8,-1.5),Vector3(0.1,0.1,0.1))
	scaled_margin_prop.scale = Vector3.ONE*2
	scaled_margin_prop.extra_cull_margin = 0.7
	var emitter := SkillReleasePresentationPlayer.new()
	caster.add_child(emitter)
	var context := SkillContext.new()
	context.caster = caster
	context.resolved_target = blocker
	context.delivery_parent = world
	emitter.play_release(emitter.prepare_release(context,Transform3D.IDENTITY,load("res://Effects/Skills/Shared/ReleaseAccentFlash.tscn"),SkillBase.PresentationAnchor.RESOLVED_TARGET,null,null))
	var owned_target_root: Node3D = null
	for child: Node in blocker.get_children():
		if child.has_meta(&"presentation_source_ref"): owned_target_root = child as Node3D
	_expect(owned_target_root != null,"real target-anchored presentation carries source ownership")
	var own_target_mesh := _mesh(owned_target_root,Vector3(0,0.6,0))
	var floor_mesh := _mesh(world,Vector3(0,-0.1,0),Vector3(50,0.2,50))
	var hidden_prop := _mesh(world,Vector3(0,0.8,-2))
	hidden_prop.visible = false
	var ui_child := Node3D.new()
	blocker.get_node("WorldUIRoot").add_child(ui_child)
	var rig := CameraFollowController.new()
	var camera := Camera3D.new()
	camera.name = "Camera3D"
	rig.add_child(camera)
	world.add_child(rig)
	rig.set_process(false)
	var clock := SkillExecutionClock.new()
	clock.configure(world)
	var pose := Transform3D.IDENTITY
	_expect(rig.call("begin_cinematic",101,pose,profile,clock,caster),"front shot begins with caster identity")
	_expect(not blocker.get_node("Visual").visible and not blocker.get_node("WorldUIRoot").visible,"blocking unit model, weapon and world UI hidden before first closeup frame")
	_expect(blocker.visible and not blocker.get_node("CollisionShape3D").disabled,"unit root and collision are untouched")
	_expect(not weapon.is_visible_in_tree(),"weapon is hidden with unit visual")
	_expect(caster.get_node("Visual").visible and own_fx.visible,"caster and own casting visuals never hidden")
	_expect(not prop.visible and not broad_prop.visible,"independent props use actual bounds, not only root origin")
	_expect(not custom_prop.visible,"custom_aabb counts as configured visual bounds")
	_expect(not margin_prop.visible,"extra_cull_margin counts as expanded visual bounds")
	_expect(not scaled_margin_prop.visible,"local cull margin scales with the geometry before world-corridor expansion")
	_expect(own_target_mesh.is_visible_in_tree(),"caster-owned target-anchored presentation survives hiding the blocking target")
	_expect(side.get_node("Visual").visible and behind.get_node("Visual").visible and floor_mesh.visible,"outside corridor, rear units and ground stay visible")
	rig.show_cinematic_area(100,Vector3.ZERO,0)
	_expect(not prop.visible,"stale transition cannot reveal active closeup blockers")
	var late := _mesh(world,Vector3(0,0.8,-2.3))
	side.position = Vector3(0.2,0,-1)
	rig.call("_process",0.02)
	_expect(not late.visible and not side.get_node("Visual").visible,"new and moving blockers are suppressed during closeup")
	ui_child.visible = false
	var before := camera.global_transform
	rig.show_cinematic_area(101,Vector3.ZERO,0)
	_expect(prop.visible and late.visible and broad_prop.visible and blocker.get_node("Visual").visible and blocker.get_node("WorldUIRoot").visible,"start of cut-out restores visibility immediately")
	_expect(camera.global_transform.is_equal_approx(before),"restore happens before battle-camera transition moves")
	_expect(not hidden_prop.visible and not ui_child.visible,"original hidden and independently hidden children stay hidden")
	_expect(rig.call("begin_cinematic",102,pose,profile,clock,caster),"replacement closeup accepted")
	rig.end_cinematic(101,true)
	_expect(not prop.visible,"stale cleanup cannot restore replacement closeup")
	rig.end_cinematic(102,true)
	_expect(prop.visible and blocker.get_node("Visual").visible,"cancel restores models")
	profile.set("hide_closeup_occluders",false)
	_expect(rig.call("begin_cinematic",103,pose,profile,clock,caster),"disabled profile keeps camera flow")
	_expect(prop.visible and blocker.get_node("Visual").visible,"disabled switch suppresses no models")
	rig.end_cinematic(103,true)
	profile.set("hide_closeup_occluders",true)
	var edge_prop := _mesh(world,Vector3(1.2,0.8,-1.5),Vector3(0.2,0.2,0.2))
	profile.set("occlusion_corridor_width_m",0.2)
	rig.call("begin_cinematic",104,pose,profile,clock,caster)
	_expect(edge_prop.visible and not prop.visible,"narrow Inspector width changes spatial suppression without disabling it")
	rig.end_cinematic(104,true)
	profile.set("occlusion_corridor_width_m",2.4)
	rig.call("begin_cinematic",105,pose,profile,clock,caster)
	_expect(not edge_prop.visible,"wider Inspector width catches edge blockers")
	rig.end_cinematic(105,true)
	profile.set("occlusion_corridor_width_m",1.6)
	rig.call("begin_cinematic",106,pose,profile,clock,caster)
	prop.free()
	_expect(not blocker.get_node("Visual").visible,"remaining blocker held before removal")
	world.remove_child(rig)
	_expect(blocker.get_node("Visual").visible,"removing camera restores surviving world objects")
	world.add_child(rig)
	rig.call("begin_cinematic",205,pose,profile,clock,caster)
	var reverse_profile := profile.duplicate() as SkillCinematicCameraProfile
	reverse_profile.front_offset = Vector3(0.45,1.15,2.8)
	rig.call("begin_cinematic",206,pose,reverse_profile,clock,caster)
	_expect(blocker.get_node("Visual").visible and not behind.get_node("Visual").visible,"closeup replacement restores old set and hides new set")
	rig.end_cinematic(205,true)
	_expect(not behind.get_node("Visual").visible,"old closeup cleanup cannot reveal replacement set")
	rig.end_cinematic(206,true)
	rig.call("begin_cinematic",207,pose,profile,clock,caster)
	rig.remove_child(camera)
	_expect(blocker.get_node("Visual").visible and not rig.is_cinematic_active(),"removing only Camera3D restores the active hidden set")
	rig.add_child(camera)
	rig.call("begin_cinematic",107,pose,profile,clock,caster)
	caster.apply_damage(99999)
	rig.call("_process",0.01)
	_expect(not rig.is_cinematic_active() and blocker.get_node("Visual").visible,"caster death restores blockers even before another transition")
	rig.free()
	world.free()
	await process_frame
	await _real_director()
	await _archer_charge()
	await _sloped_ground()
	_finish()

func _real_director() -> void:
	var scene := load("res://Scenes/Previews/SquadFinisherComparisonPreview.tscn").instantiate() as Node3D
	root.add_child(scene)
	current_scene = scene
	for i: int in range(3): await physics_frame
	var battle := scene.get_node("Battle")
	var actor := battle.get_node("Caster") as AllyBase
	var visual := actor.get_node("Visual") as Node3D
	var point := actor.global_position + visual.global_basis * Vector3(0,0.6,-1.4)
	var prop := _mesh(battle,Vector3.ZERO)
	prop.global_position = point
	var director := battle.get_node("SquadFinisherExecutionController") as SquadFinisherExecutionController
	_expect(director.begin_finisher(actor),"real director accepts finisher")
	var start_deadline := Time.get_ticks_msec()+1000
	while director.get_execution_status().phase == &"pending" and Time.get_ticks_msec()<start_deadline: await process_frame
	_expect(not prop.visible,"director passes caster identity into closeup occlusion")
	var deadline := Time.get_ticks_msec()+3000
	while director.get_execution_status().phase != &"exit_closeup" and Time.get_ticks_msec()<deadline: await process_frame
	_expect(director.get_execution_status().phase == &"exit_closeup" and prop.visible,"real release frame restores prop at cut-out, before launching")
	director.cancel_execution(&"occlusion_test")
	_expect(prop.visible and not paused and is_equal_approx(Engine.time_scale,1),"real cancellation restores visuals and time")
	scene.free()
	current_scene = null
	await process_frame

func _finish() -> void:
	for failure: String in failures: printerr("FAIL: ",failure)
	print("FinisherCinematicOcclusionTest: ","PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)


func _archer_charge() -> void:
	var f: Dictionary = load("res://UnitSystem/Tests/AllyChainCommandPriorityTest.gd").make_fixture(root,"res://UnitSystem/AI/Ally/Units/Archer.tscn")
	var host: SkillHostComponent = f.host
	host.get_finisher_skill().base_cast_time = 3
	_expect(host.request_finisher(f.enemy,[f.enemy]),"actual Archer finisher starts its charge")
	var charge := host.get_finisher_skill().get("_cast_effect_instance") as Node3D
	_expect(is_instance_valid(charge) and charge.get_parent()==f.world,"actual ACTION_ORIGIN charge is outside caster subtree")
	if is_instance_valid(charge):
		charge.call("advance_effect",0.1)
		var core := charge.get_node("VisualRoot/Focus/Core") as MeshInstance3D
		_expect(core.visible,"charge core is authored visible before occlusion")
		var rig := CameraFollowController.new()
		var camera := Camera3D.new()
		camera.name = "Camera3D"
		rig.add_child(camera)
		f.world.add_child(rig)
		rig.set_process(false)
		var clock := SkillExecutionClock.new()
		clock.configure(f.world)
		var pose := Transform3D(f.actor.get_node("Visual").global_basis,f.actor.global_position)
		_expect(rig.call("begin_cinematic",301,pose,host.get_finisher_skill().camera_effect_profile,clock,f.actor),"Archer charge closeup is actually accepted")
		_expect(core.is_visible_in_tree(),"world-parented caster charge is never suppressed")
		rig.end_cinematic(301,true)
	f.world.free()
	await process_frame

func _sloped_ground() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var caster := _unit(world,Vector3.ZERO)
	var ramp := StaticBody3D.new()
	world.add_child(ramp)
	ramp.rotation_degrees.x = 25
	ramp.position.y = -0.15
	var geometry := _mesh(ramp,Vector3.ZERO,Vector3(6,0.2,6))
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(6,0.2,6)
	shape.shape = box
	ramp.add_child(shape)
	var obstruction := _mesh(world,Vector3(0,0.8,-1.4))
	var rig := CameraFollowController.new()
	var camera := Camera3D.new()
	camera.name = "Camera3D"
	rig.add_child(camera)
	world.add_child(rig)
	rig.set_process(false)
	await physics_frame
	await process_frame
	var clock := SkillExecutionClock.new()
	clock.configure(world)
	rig.call("begin_cinematic",401,Transform3D.IDENTITY,SkillCinematicCameraProfile.new(),clock,caster)
	_expect(geometry.visible and not obstruction.visible,"actual walkable sloped support stays visible while separate obstruction hides")
	rig.end_cinematic(401,true)
	world.free()
	await process_frame
