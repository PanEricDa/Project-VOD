extends SceneTree
## 捕获子效果过早执行、取消/替换误触发、重复叠加、到期不恢复及状态未接入真实AI移动。
const SKILL_PATH := "res://SkillSystem/00-Skills/Player_TargetGather/TargetGatherSkill.tscn"
var failures: Array[String] = []
class WalkingAI extends AIUnitBase:
	var walking := false
	var requested_speed := -1.0
	func _update_ai_movement(_delta: float) -> void:
		if walking: set_movement_target(global_position + Vector3(10,0,0),requested_speed)
		else: clear_movement_target()
func _initialize() -> void: call_deferred("_run")
func _expect(value: bool, label: String) -> void:
	if not value: failures.append(label)
func _frames(count: int) -> void:
	for i: int in range(count):
		await physics_frame
		await process_frame
func _body(world: Node3D, at: Vector3) -> AIUnitBase:
	var body := load("res://UnitSystem/Base/AIUnitBase.tscn").instantiate() as AIUnitBase
	body.set_script(WalkingAI)
	body.position=at
	body.team_id=2
	body.gravity_multiplier=0
	body.collision_mask=0
	world.add_child(body)
	body.get_status_effect_component().set_physics_process(false)
	return body
func _context(caster: UnitBase, world: Node3D) -> SkillContext:
	var context := SkillContext.new()
	context.caster=caster
	context.resolved_target=caster
	context.target_position=Vector3.ZERO
	context.release_caster_position=caster.position
	context.release_facing_direction=Vector3.FORWARD
	context.delivery_parent=world
	return context
func _slow() -> StatModifierSkillEffect:
	var slow := StatModifierSkillEffect.new()
	slow.target_mode=StatModifierSkillEffect.TargetMode.DELIVERY_TARGET
	slow.modifier_stat=StatModifierSkillEffect.ModifierStat.MOVEMENT_SPEED
	slow.modifier_mode=StatModifierSkillEffect.ModifierMode.PERCENT
	slow.amount=-90
	slow.duration_seconds=3
	return slow
func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	current_scene=world
	var caster := load("res://UnitSystem/Base/00_UnitBase.tscn").instantiate() as UnitBase
	caster.team_id=1
	caster.position=Vector3(0,0,3)
	world.add_child(caster)
	var body := _body(world,Vector3(2,0,0))
	var status := body.get_status_effect_component() as StatusEffectComponent
	var pull := PullTargetSkillEffect.new()
	pull.center_mode=PullTargetSkillEffect.CenterMode.TARGET_POSITION
	pull.gather_radius_m=0
	pull.duration_seconds=0.12
	var slow := _slow()
	pull.add_child(slow)
	world.add_child(pull)
	var context := _context(caster,world)
	_expect(pull.apply(context,SkillDeliveryResult.new(),body),"pull with independently composed slow accepts")
	_expect(status.get_active_modifier_count()==0,"no slow before actual pull completion")
	await _frames(12)
	_expect(body.position.distance_to(Vector3.ZERO)<0.02 and not body.is_forced_movement_active(),"real physics completes pull")
	_expect(status.get_active_modifier_count()==1 and is_equal_approx(status.get_modified_value(2,4.2),0.42),"arrival applies 90 percent slow exactly once")
	var walking_body := body as WalkingAI
	walking_body.walking=true
	await _frames(20)
	_expect(absf(body.velocity.x-0.42)<0.015,"real default-speed AI motion uses slow rather than raw4.2")
	walking_body.requested_speed=2
	await _frames(10)
	_expect(absf(body.velocity.x-0.2)<0.015,"explicit AI movement request also receives speed modifier exactly once")
	walking_body.walking=false
	# 可控战斗秒验证时长与同组件刷新，无需等待真实三秒。
	status.advance_effects(2.9)
	_expect(status.get_active_modifier_count()==1,"slow remains before three battle seconds")
	body.position=Vector3(2,0,0)
	_expect(pull.apply(context,SkillDeliveryResult.new(),body),"repeat pull accepts")
	await _frames(12)
	status.advance_effects(0.2)
	_expect(status.get_active_modifier_count()==1 and is_equal_approx(status.get_modified_value(2,4.2),0.42),"repeat pull refreshes duration instead of stacking to zero")
	status.advance_effects(2.79)
	_expect(status.get_active_modifier_count()==1,"refreshed slow remains until new expiry")
	status.advance_effects(0.02)
	_expect(status.get_active_modifier_count()==0,"three seconds after last completion removes slow")
	walking_body.requested_speed=-1
	walking_body.walking=true
	await _frames(20)
	_expect(absf(body.velocity.x-4.2)<0.015 and is_equal_approx(body.movement_speed,4.2),"expiry restores actual speed without rewriting base")
	walking_body.walking=false
	# 完成接口执行既有通用Effect，而不是硬编码减速：替换配置可直接做降防。
	slow.modifier_stat=StatModifierSkillEffect.ModifierStat.DEFENSE
	slow.amount=-25
	body.defense=80
	body.position=Vector3(2,0,0)
	pull.apply(context,SkillDeliveryResult.new(),body)
	await _frames(12)
	_expect(is_equal_approx(body.get_defense(),60) and is_equal_approx(status.get_modified_value(2,4.2),4.2),"completion composes another property without new pipeline")
	status.clear_all_modifiers()
	slow.modifier_stat=StatModifierSkillEffect.ModifierStat.MOVEMENT_SPEED
	slow.amount=-90
	for reason: StringName in [&"cancelled",&"replaced",&"disabled",&"owner_invalid"]:
		status.clear_all_modifiers()
		body.position=Vector3(2,0,0)
		pull.apply(context,SkillDeliveryResult.new(),body)
		var token := body.get_forced_movement_token()
		match reason:
			&"cancelled": body.cancel_forced_movement(token)
			&"replaced":
				var replacement := body.request_forced_movement(caster,Vector3(1,0,0),0.08,true)
				_expect(replacement>token,"replacement has fresh request identity")
			&"disabled": body.forced_movement_enabled=false
			&"owner_invalid": body.apply_damage(999999)
		await _frames(12)
		_expect(status.get_active_modifier_count()==0,"noncompletion must not apply stale followup: "+String(reason))
		if body.is_dead(): body.revive(100)
		body.forced_movement_enabled=true
	status.clear_all_modifiers()
	body.position=Vector3.ZERO
	_expect(pull.apply(context,SkillDeliveryResult.new(),body),"already centered is accepted without movement")
	await _frames(2)
	_expect(not body.is_forced_movement_active() and status.get_active_modifier_count()==0,"unmoved anchor receives no slow")
	body.position=Vector3(2,0,0)
	pull.apply(context,SkillDeliveryResult.new(),body)
	var surviving_token := body.get_forced_movement_token()
	pull.free()
	_expect(body.get_forced_movement_token()==surviving_token and surviving_token>0,"removing effect leaves original physical request active")
	await _frames(12)
	_expect(body.position.distance_to(Vector3.ZERO)<0.02,"physical request still arrives after effect removal")
	_expect(status.get_active_modifier_count()==0 and body.forced_movement_finished.get_connections().is_empty(),"effect removal disconnects pending followup without cancelling real movement")
	# 直接挂普通属性效果仍立即生效；拉拽不固化子效果类型。
	var standalone := _slow()
	world.add_child(standalone)
	standalone.apply(context,SkillDeliveryResult.new(),body)
	_expect(status.get_active_modifier_count()==1,"same stat effect remains usable immediately outside pull")
	standalone.free()
	status.clear_all_modifiers()
	var skill := load(SKILL_PATH).instantiate() as SkillBase
	world.add_child(skill)
	var content_slow := skill.get_node_or_null("PullTargetSkillEffect/StatModifierSkillEffect") as StatModifierSkillEffect
	_expect(content_slow!=null,"formal content assembles independent child modifier")
	_expect(is_equal_approx(skill.delivery.effect_radius,5),"formal target radius is five meters")
	var old := load("res://SkillSystem/00-Skills/Player_Gather/GatherSkill.tscn").instantiate() as SkillBase
	_expect(old.get_node("PullTargetSkillEffect").get_child_count()==0,"old front Gather remains free of new slow")
	old.free()
	world.free()
	current_scene=null
	await process_frame
	await _test_delayed_damage_identity()
	for failure: String in failures: printerr("FAIL: ",failure)
	print("PullCompletionEffectTest: ","PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)


# 两个实际目标先受到即时伤害，后受到完成后伤害；每个目标两笔伤害必须保持同一命中身份。
func _test_delayed_damage_identity() -> void:
	var world := Node3D.new()
	root.add_child(world)
	current_scene=world
	var caster := load("res://UnitSystem/Base/00_UnitBase.tscn").instantiate() as UnitBase
	caster.team_id=1
	caster.position=Vector3(0,0,3)
	world.add_child(caster)
	var a := _body(world,Vector3(2,0,0))
	var b := _body(world,Vector3(-2,0,0))
	var events_a: Array[CombatDamageEvent]=[]
	var events_b: Array[CombatDamageEvent]=[]
	a.damage_resolved.connect(func(event): events_a.append(event))
	b.damage_resolved.connect(func(event): events_b.append(event))
	var damage := HealthChangeSkillEffect.new()
	damage.operation=HealthChangeSkillEffect.Operation.DAMAGE
	damage.base_amount=3
	world.add_child(damage)
	var pull := PullTargetSkillEffect.new()
	pull.center_mode=PullTargetSkillEffect.CenterMode.TARGET_POSITION
	pull.gather_radius_m=0
	pull.duration_seconds=0.12
	var delayed_damage := HealthChangeSkillEffect.new()
	delayed_damage.operation=HealthChangeSkillEffect.Operation.DAMAGE
	delayed_damage.base_amount=7
	pull.add_child(delayed_damage)
	world.add_child(pull)
	var runner := SkillDeliveryRunner.new()
	world.add_child(runner)
	var config := InstantTargetDeliveryConfig.new()
	config.candidate_source=InstantTargetDeliveryConfig.CandidateSource.WORLD_SCOPE
	config.target_collection_mode=InstantTargetDeliveryConfig.TargetCollectionMode.TARGET_RADIUS
	config.effect_radius=5
	var effects: Array[SkillEffectBase]=[damage,pull]
	_expect(runner.execute(config,_context(caster,world),caster.global_transform,effects),"real multi-target delivery accepts delayed generic damage")
	_expect(events_a.size()==1 and events_b.size()==1,"only immediate damage occurs before movement")
	await _frames(20)
	for events: Array in [events_a,events_b]:
		_expect(events.size()==2,"each receiver takes one immediate and one delayed damage")
		if events.size()==2:
			_expect(events[0].hit_id==events[1].hit_id,"delayed damage retains its own original hit identity")
			_expect(is_equal_approx(events[1].actual_damage,7),"generic delayed damage amount remains intact")
	_expect(events_a[0].hit_id!=events_b[0].hit_id,"different receiver identities remain distinct")
	world.free()
	current_scene=null
	await process_frame
