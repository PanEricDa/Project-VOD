extends SceneTree
## 回归：临时仇恨标记由真实状态持有，不能独立倒计时、重复堆叠或改变仇恨结果。
const SKILL := "res://SkillSystem/00-Skills/Player_ThreatMark/ThreatMarkSkill.tscn"
const BASE := "res://Effects/Skills/ThreatMark/"
var failures: Array[String] = []
func _initialize() -> void: call_deferred("_run")
func _check(ok: bool, text: String) -> void:
	if not ok: failures.append(text)
func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var caster := UnitBase.new()
	caster.team_id = 1
	world.add_child(caster)
	var skill := load(SKILL).instantiate() as SkillBase
	world.add_child(skill)
	var effect := skill.get_node("ThreatChangeSkillEffect") as ThreatChangeSkillEffect
	_check(skill.release_effect_scene != null,"E configures independent radius release effect")
	_check(effect.get("status_visual_scene") is PackedScene,"E effect exposes and selects status mark asset")
	_check(ResourceLoader.exists(BASE+"ThreatMarkEffectPreview.tscn"),"combined E visual preview exists")
	if not failures.is_empty():
		world.free()
		_finish()
		return
	for path: String in [BASE+"ThreatMarkStatusEffect.tscn",BASE+"ThreatMarkReleaseEffect.tscn",BASE+"ThreatMarkEffectPreview.tscn"]:
		_check(ResourceLoader.get_resource_uid(path)!=ResourceUID.INVALID_ID,"native scene UID registered: "+path)
	var enemy := load("res://UnitSystem/AI/Enemy/EnemyBase.tscn").instantiate() as EnemyBase
	world.add_child(enemy)
	# 只停止夹具AI与状态自动时间，真实状态/仇恨仍通过公开接口执行。
	enemy.process_mode = Node.PROCESS_MODE_DISABLED
	var status := enemy.get_status_effect_component() as StatusEffectComponent
	var threat := enemy.get_threat_component() as EnemyThreatComponent
	threat.threat_half_life = 0.0
	var ctx := SkillContext.new()
	ctx.caster = caster
	ctx.delivery_parent = world
	var result := SkillDeliveryResult.new()
	threat.submit_threat(ThreatEvent.create_damage(caster,75))
	_check(effect.apply(ctx,result,enemy),"real timed E effect applies")
	var marks := _marks(enemy)
	_check(marks.size()==1,"successful status creates exactly one mark")
	if marks.size()!=1:
		world.free()
		_finish()
		return
	var mark: Node3D = marks[0]
	var first_id := mark.get_instance_id()
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.current = true
	camera.look_at_from_position(Vector3(4,6,8),Vector3.ZERO,Vector3.UP)
	mark.call("_process",0.0)
	_check(mark.global_position.is_equal_approx(Vector3(0,1.55,0)),"mark clears existing1.15m health bar by .4m")
	_check(mark.global_basis.is_equal_approx(camera.global_basis.orthonormalized()),"whole glyph faces camera")
	enemy.position = Vector3(2,0,3)
	enemy.rotation.y = PI * 0.7
	mark.call("_process",0.0)
	_check(mark.global_position.is_equal_approx(Vector3(2,1.55,3)) and mark.global_basis.is_equal_approx(camera.global_basis.orthonormalized()),"moving or turning target preserves readable head mark")
	enemy.position = Vector3.ZERO
	_check(threat.get_threat_for(caster)==2075,"visual does not alter ordinary75 plus temporary2000 threat")
	status.advance_effects(7.0)
	_check(effect.apply(ctx,result,enemy),"repeat refresh accepted")
	marks = _marks(enemy)
	_check(marks.size()==1 and marks[0].get_instance_id()==first_id,"refresh reuses same mark without restarting gain")
	status.advance_effects(2.0)
	_check(status.has_named_status(&"temporary_threat") and is_instance_valid(mark),"mark follows refreshed status, not original deadline")
	# 不把瞬时锁定目标当作状态；清理仇恨才是外部正式结束。
	effect.free()
	_check(is_instance_valid(mark),"skill effect removal does not orphan state-owned mark")
	status.advance_effects(6.1)
	_check(not status.has_named_status(&"temporary_threat") and threat.get_threat_for(caster)==75,"expiry removes only temporary threat")
	_check(mark.get_node("AnimationPlayer").current_animation=="out","expiry immediately starts pure visual out")
	_advance_out(mark)
	await process_frame
	await process_frame
	_check(not is_instance_valid(mark),"finite out releases marker")
	# 共享效果独立于单一来源；两个来源也只显示一个相同状态标记。
	var other := UnitBase.new()
	other.team_id = 1
	world.add_child(other)
	effect = ThreatChangeSkillEffect.new()
	effect.duration_seconds = 8
	effect.threat_amount = 2000
	effect.set("status_visual_scene",load(BASE+"ThreatMarkStatusEffect.tscn"))
	world.add_child(effect)
	ctx.caster = caster
	effect.apply(ctx,result,enemy)
	ctx.caster = other
	effect.apply(ctx,result,enemy)
	marks = _marks(enemy)
	_check(marks.size()==1,"two active sources aggregate one visible named-state mark")
	mark = marks[0]
	caster.free()
	_check(status.has_named_status(&"temporary_threat") and mark.get_node("AnimationPlayer").current_animation!="out","one source leaving keeps other source and mark")
	threat.clear_threat()
	_check(not status.has_named_status(&"temporary_threat") and mark.get_node("AnimationPlayer").current_animation=="out","external clear ends mark with bound status")
	_advance_out(mark)
	await process_frame
	# 失败提交不能制造标记；旧有效状态与视觉不被失败刷新替换。
	var visual := load(BASE+"ThreatMarkStatusEffect.tscn") as PackedScene
	var token: int = status.prepare_bound_status(&"probe",other,&"key",8.0,func(): pass)
	_check(not status.call("commit_bound_status",token,func(): return false,visual),"failed commit rejected")
	_check(_marks(enemy).is_empty(),"failed commit creates no status mark")
	var ok: int = status.prepare_bound_status(&"probe",other,&"key",8.0,func(): pass)
	_check(status.call("commit_bound_status",ok,Callable(),visual),"generic bound visual can be configured")
	mark = _marks(enemy)[0]
	token = status.prepare_bound_status(&"probe",other,&"key",8.0,func(): pass)
	status.call("commit_bound_status",token,func(): return false,visual)
	_check(_marks(enemy).size()==1 and _marks(enemy)[0]==mark,"rollback retains previous visual")
	enemy.apply_damage(100000)
	_check(not status.has_named_status(&"probe") and mark.get_node("AnimationPlayer").current_animation=="out","target death ends mark")
	_advance_out(mark)
	await process_frame
	world.free()
	await process_frame
	await _test_radius_and_preview()
	await _test_multisource_rollback()
	await _test_render_sampling()
	_finish()
func _marks(enemy: Node) -> Array[Node3D]:
	var result: Array[Node3D] = []
	for node: Node in enemy.find_children("*","Node3D",true,false):
		if node.scene_file_path == BASE+"ThreatMarkStatusEffect.tscn" and not node.is_queued_for_deletion() and not bool(node.get("_ending")):
			result.append(node as Node3D)
	return result
func _advance_out(mark: Node3D) -> void:
	var player := mark.get_node("AnimationPlayer") as AnimationPlayer
	player.advance(0.16)
func _test_radius_and_preview() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var caster := Node3D.new()
	world.add_child(caster)
	var skill := load(SKILL).instantiate() as SkillBase
	world.add_child(skill)
	var ctx := SkillContext.new()
	ctx.caster = caster
	ctx.delivery_parent = world
	ctx.release_caster_position = Vector3(2,0,3)
	ctx.release_facing_direction = Vector3.FORWARD
	var fact := SkillPresentationContext.create(skill,ctx,Transform3D.IDENTITY)
	var player := skill.get_node("RuntimeEffects") as SkillReleasePresentationPlayer
	var nodes: Array[Node3D] = []
	player.release_instance_prepared.connect(func(_fact, node): nodes.append(node))
	player.play_release(player.prepare_release(ctx,Transform3D.IDENTITY,skill.release_effect_scene,0,null,null,fact))
	var pulse: Node3D = nodes[0]
	pulse.set_process(false)
	pulse.advance_effect(0.18)
	_check(pulse.global_position==Vector3(2,0,3),"pulse centered on frozen release feet")
	_check(is_equal_approx(pulse.get_node("VisualRoot/RangeRoot").scale.x,5.0),"pulse reads actual five-meter skill radius")
	var ring: MeshInstance3D = pulse.get_node("VisualRoot/RangeRoot/PulseRing")
	_check(is_equal_approx((ring.mesh as TorusMesh).outer_radius * ring.scale.x,1.0),"pulse reaches full authored unit radius")
	caster.position = Vector3(10,0,10)
	_check(pulse.global_position==Vector3(2,0,3),"released pulse stays world-fixed")
	pulse.advance_effect(0.2)
	await process_frame
	await process_frame
	_check(not is_instance_valid(pulse),"release pulse auto-cleans")
	world.free()
	await process_frame
	var preview: Node = load(BASE+"ThreatMarkEffectPreview.tscn").instantiate()
	root.add_child(preview)
	_check(preview.get_node_or_null("Transient")!=null,"preview has isolated transient effects")
	preview.free()
	await process_frame
# 不同来源、不同资产的失败刷新不能改变原先成功的视觉优先顺序或重建当前标记。
func _test_multisource_rollback() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var owner := UnitBase.new()
	world.add_child(owner)
	var first := UnitBase.new()
	world.add_child(first)
	var second := UnitBase.new()
	world.add_child(second)
	var status := StatusEffectComponent.new()
	owner.add_child(status)
	status.configure_owner(owner)
	var visual_a := load(BASE+"ThreatMarkStatusEffect.tscn") as PackedScene
	var visual_b := load("res://Effects/Skills/HolyBlessing/HolyBlessingBuffEffect.tscn") as PackedScene
	var token := status.prepare_bound_status(&"multi",first,&"key",8.0,func(): pass)
	status.commit_bound_status(token,Callable(),visual_a)
	token = status.prepare_bound_status(&"multi",second,&"key",8.0,func(): pass)
	status.commit_bound_status(token,Callable(),visual_b)
	var current: Node3D
	for node: Node3D in owner.get_node("StatusModifierVisuals").get_children():
		if not bool(node.get("_ending")): current = node
	_check(current != null and current.scene_file_path==visual_b.resource_path,"last successful distinct source chooses visual B")
	token = status.prepare_bound_status(&"multi",first,&"key",8.0,func(): pass)
	_check(not status.commit_bound_status(token,func(): return false,visual_a),"source A refresh intentionally fails")
	var active: Array[Node3D] = []
	for node: Node3D in owner.get_node("StatusModifierVisuals").get_children():
		if not bool(node.get("_ending")): active.append(node)
	_check(active.size()==1 and active[0]==current,"failed multi-source refresh preserves same current visual B instance")
	world.free()
	await process_frame

# 原生物理插值采样：用10Hz物理/120Hz渲染放大差异，标记应跟随血条实际显示位置。
func _test_render_sampling() -> void:
	var original_ticks := Engine.physics_ticks_per_second
	var original_fps := Engine.max_fps
	Engine.physics_ticks_per_second = 10
	Engine.max_fps = 120
	var world := Node3D.new()
	root.add_child(world)
	var owner := UnitBase.new()
	owner.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON
	world.add_child(owner)
	var bar := load("res://UnitSystem/Components/UI/WorldHealthBar.tscn").instantiate() as Node3D
	owner.add_child(bar)
	var mark := load(BASE+"ThreatMarkStatusEffect.tscn").instantiate() as Node3D
	owner.add_child(mark)
	mark.set_process(false)
	owner.reset_physics_interpolation()
	bar.get_global_transform_interpolated()
	await physics_frame
	owner.position.x = 2.0
	await process_frame
	await physics_frame
	owner.position.x = 4.0
	var saw_interpolation := false
	var aligned := true
	for i: int in range(12):
		await process_frame
		var rendered := bar.get_global_transform_interpolated().origin
		if rendered.distance_to(bar.global_position) > 0.01:
			saw_interpolation = true
			mark.call("_process",0.0)
			if mark.global_position.distance_to(rendered+Vector3.UP*0.4) > 0.001: aligned = false
	_check(saw_interpolation,"render fixture observes interpolated bar distinct from latest physical pose")
	_check(aligned,"head mark samples same interpolated pose as rendered health bar")
	world.free()
	Engine.physics_ticks_per_second = original_ticks
	Engine.max_fps = original_fps
	await process_frame

func _finish() -> void:
	for text: String in failures: printerr("FAIL: ",text)
	print("ThreatMarkPresentationTest: ","PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
