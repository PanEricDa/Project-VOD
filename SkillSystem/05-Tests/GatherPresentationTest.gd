extends SceneTree
## 回归：Q视觉必须跟随真实释放几何/拉拽时间，释放后固定世界位置并自行回收。
var failures: Array[String] = []
const SKILL := "res://SkillSystem/00-Skills/Player_Gather/GatherSkill.tscn"
const BASE := "res://Effects/Skills/Gather/"
func _initialize() -> void: call_deferred("_run")
func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	world.scale = Vector3(2,1.5,2)
	var caster := Node3D.new()
	world.add_child(caster)
	var skill := load(SKILL).instantiate() as SkillBase
	caster.add_child(skill)
	_check(skill.cast_effect_scene != null, "Gather configures independent cast asset")
	_check(skill.release_effect_scene != null, "Gather configures independent release asset")
	var ctx := SkillContext.new()
	ctx.caster = caster
	ctx.resolved_target = caster
	ctx.delivery_parent = world
	ctx.release_caster_position = Vector3(4,0,2)
	ctx.release_facing_direction = Vector3.RIGHT
	var fact := SkillPresentationContext.create(skill,ctx,Transform3D.IDENTITY)
	_check(fact.has_method("get_effect_data"), "presentation supports read-only effect geometry")
	_check(ResourceLoader.exists(BASE+"GatherEffectPreview.tscn"), "combined preview exists")
	if not failures.is_empty():
		world.free()
		_finish()
		return
	var player := SkillReleasePresentationPlayer.new()
	world.add_child(player)
	var visuals: Array[Node3D] = []
	player.release_instance_prepared.connect(func(_fact, visual): visuals.append(visual))
	var snapshot := player.prepare_release(ctx,Transform3D.IDENTITY,skill.release_effect_scene,0,null,null,fact)
	caster.position = Vector3(100,0,100)
	ctx.release_caster_position = Vector3.ZERO
	ctx.release_facing_direction = Vector3.BACK
	skill.get_node("PullTargetSkillEffect").front_distance_m = 9.0
	player.play_release(snapshot)
	var fx: Node3D = visuals.back()
	fx.set_process(false)
	_check(fx.global_position.is_equal_approx(Vector3(4,0,2)), "release uses frozen feet, not weapon or later caster")
	var boundary := fx.get_node("VisualRoot/Boundary") as Node3D
	var destination := fx.get_node("VisualRoot/Destination") as Node3D
	_check(boundary.global_position.distance_to(Vector3(7,0.04,2)) < 0.001, "selection circle uses 3m forward offset")
	_check(destination.global_position.distance_to(Vector3(5.5,0.06,2)) < 0.001, "destination uses independent 1.5m offset")
	_check(is_equal_approx(boundary.scale.x,3.5), "selection circle reads delivery radius")
	_check(is_equal_approx(fx.get_node("VisualRoot/Destination/CollapseRing").scale.x,0.75),"collapse ring derives its size from .6m gather disk")
	caster.position = Vector3(-20,0,-20)
	_check(fx.global_position.is_equal_approx(Vector3(4,0,2)), "release does not follow caster")
	fx.call("advance_effect",0.119)
	_check(fx.call("is_playing"), "convergence still plays before pull completion")
	fx.call("advance_effect",0.002)
	_check(fx.get_node("VisualRoot/Ribbons").visible == false, "ribbons finish on actual .12s pull")
	_check(fx.call("is_playing"), "readable residue remains after convergence")
	fx.call("advance_effect",0.15)
	await process_frame
	await process_frame
	_check(not is_instance_valid(fx), "release auto-cleans after pull and residue")
	# 非默认参数：同一资产不能保留3.5/.12的硬编码，也不能把可写字典泄漏给消费者。
	skill.delivery = skill.delivery.duplicate()
	skill.delivery.effect_radius = 2.0
	skill.delivery.center_forward_offset_m = 1.0
	var pull := skill.get_node("PullTargetSkillEffect")
	pull.front_distance_m = 0.5
	pull.duration_seconds = 0.4
	ctx.release_caster_position = Vector3.ZERO
	ctx.release_facing_direction = Vector3.FORWARD
	var changed := SkillPresentationContext.create(skill,ctx,Transform3D.IDENTITY)
	var data: Dictionary = changed.call("get_effect_data",&"pull")
	data["duration_seconds"] = 99.0
	snapshot = player.prepare_release(ctx,Transform3D.IDENTITY,skill.release_effect_scene,0,null,null,changed)
	player.play_release(snapshot)
	fx = visuals.back()
	fx.set_process(false)
	_check(is_equal_approx(fx.get_node("VisualRoot/Boundary").scale.x,2.0), "changed radius applied without editing FX")
	fx.call("advance_effect",0.2)
	_check(fx.get_node("VisualRoot/Ribbons").visible, "changed pull duration drives convergence")
	fx.call("advance_effect",0.201)
	_check(not fx.get_node("VisualRoot/Ribbons").visible, "snapshot dictionary isolated from caller mutation")
	var second_fx := fx
	skill.delivery.effect_radius = 4.0
	var concurrent := SkillPresentationContext.create(skill,ctx,Transform3D.IDENTITY)
	player.play_release(player.prepare_release(ctx,Transform3D.IDENTITY,skill.release_effect_scene,0,null,null,concurrent))
	var third_fx: Node3D = visuals.back()
	third_fx.set_process(false)
	_check(is_equal_approx(second_fx.get_node("VisualRoot/Boundary").scale.x,2.0) and is_equal_approx(third_fx.get_node("VisualRoot/Boundary").scale.x,4.0),"concurrent visuals retain independent geometry")
	caster.free()
	_check(is_instance_valid(third_fx) and third_fx.is_inside_tree(),"released FX survives caster and skill removal")
	second_fx.call("advance_effect",0.15)
	third_fx.call("advance_effect",0.56)
	await process_frame
	await process_frame
	_check(not is_instance_valid(second_fx) and not is_instance_valid(third_fx),"orphaned released visuals finish without source or callbacks")
	world.free()
	await process_frame
	await _test_cancelled_cast()
	var preview: Node = load(BASE+"GatherEffectPreview.tscn").instantiate()
	root.add_child(preview)
	_check(preview.get_node_or_null("Transient") != null,"preview has independent transient container")
	preview.free()
	await process_frame
	_finish()
# 真实标准激活/开始/取消：蓄力按实际施法时间拉伸，取消不能遗留风线或产生释放特效。
func _test_cancelled_cast() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var caster := UnitBase.new()
	caster.team_id = 1
	world.add_child(caster)
	var skill := load(SKILL).instantiate() as SkillBase
	world.add_child(skill)
	skill.configure_owner(caster,null,world)
	var ctx := SkillContext.new()
	ctx.caster = caster
	ctx.requested_target = caster
	ctx.resolved_target = caster
	ctx.explicit_target_requested = true
	ctx.delivery_parent = world
	var releases := [0]
	skill.release_instance_prepared.connect(func(_fact,_visual): releases[0] += 1)
	_check(skill.activate(ctx),"cast request accepted through normal pipeline")
	_check(skill.confirm_action_started(Transform3D(Basis.IDENTITY,Vector3(0,1,0))),"actual cast start accepted")
	var charge: Node3D
	for node: Node in world.get_children():
		if node.scene_file_path.ends_with("GatherCastEffect.tscn"): charge = node as Node3D
	_check(is_instance_valid(charge),"cast creates configured palm wind")
	if is_instance_valid(charge):
		charge.set_process(false)
		charge.advance_effect(0.1)
		_check(is_equal_approx(charge.get_remaining_seconds(),0.1),"palm wind scales to .2s actual cast")
	skill.cancel_skill()
	await process_frame
	await process_frame
	_check(not is_instance_valid(charge),"cancel removes palm wind")
	_check(releases[0] == 0,"cancelled cast never starts release FX")
	world.free()
	await process_frame

func _check(ok: bool, label: String) -> void:
	if not ok: failures.append(label)
func _finish() -> void:
	for label: String in failures: printerr("FAIL: ",label)
	print("GatherPresentationTest: ","PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
