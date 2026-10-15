extends SceneTree
## 真实Host/Delivery/费用集成：旧弹与旧缓存不串轮，瞬发回收不丢首击。
const W = preload("res://UnitSystem/Tests/SquadChainRoundWindowTest.gd")
var failures: Array[String] = []
func _initialize() -> void: call_deferred(&"_run")
func _run() -> void:
	await _test_late_projectile_and_old_pending_price()
	await _test_real_rapid_and_fragments()
	await _test_synchronous_and_posthumous()
	_finish()

func _test_late_projectile_and_old_pending_price() -> void:
	var f := W.make_fixture(root)
	var actor2 = load("res://UnitSystem/AI/Ally/Units/Caster.tscn").instantiate()
	actor2.automatic_skill_cast_enabled = false
	actor2.gravity_multiplier = 0
	f.world.add_child(actor2)
	actor2.set_physics_process(false)
	var host2: SkillHostComponent = actor2.get_node("SkillHost")
	host2.configure_owner(actor2,f.world)
	var combo2 := host2.get_combo_skill()
	combo2.delivery = InstantTargetDeliveryConfig.new()
	combo2.base_cast_time = 0.2
	combo2.cast_range = 6.0
	var animation2 = actor2.get_node("Visual").find_child("CharacterAnimationPlayer",true,false)
	animation2.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	actor2.get_targeting_component().call("_set_locked_target",f.enemy)
	actor2.get_targeting_component().set_physics_process(false)
	actor2.get_behavior_state_machine().set_follow_target(f.player)
	var slots: Array[AllyBase] = [f.actor,actor2,null,null]
	f.commander.companions = slots
	var party: Array[UnitBase] = [f.player,f.actor,actor2]
	f.focus.bind_scope(f.world,party)
	f.focus.maximum_focus = 1000
	f.focus.initial_focus = 1000
	f.focus.reset_focus()
	await physics_frame
	await physics_frame
	var events: Array = []
	var fees: Dictionary = {}
	f.enemy.damage_resolved.connect(func(event): events.append(event))
	f.commander.command_released.connect(func(id,cost): fees[id] = cost)
	_expect(f.commander.submit_slot(0) and f.commander.submit_slot(1), "two actors reserve independently before release")
	_expect(is_equal_approx(f.focus.get_reserved_focus(),40), "parallel base reservations exact40")
	var failed_ids: Array = f.requests.keys().duplicate()
	for id in failed_ids:
		var pending: SkillCommandRequest = f.requests[id]
		var host: SkillHostComponent = f.host if pending.caster_instance_id == f.actor.get_instance_id() else host2
		host.cancel_command(id,&"integration_failed")
		host.cancel_command(id,&"integration_failed_duplicate")
	_expect(f.focus.get_reserved_focus() == 0 and f.focus.get_current_focus() == 1000, "failed parallel reservations refund exactly once")
	_expect(fees.is_empty(), "failed roots do not increase successful-repeat price")
	var first := W.start_released(f)
	W.deal(f,first,25)
	_expect(f.commander.submit_slot(0), "cache admitted into old round")
	var cached: SkillCommandRequest = f.requests.values().back()
	f.animation.finish_action()
	W.advance(f,2.000001)
	_expect(f.round.peek_current_round() == 0 and f.host.has_pending_command(), "close does not cancel old pending slot")
	_expect(f.commander.submit_slot(1), "other idle actor starts new round")
	var second: SkillCommandRequest = f.requests.values().back()
	_expect(second.round_id > first.round_id, "new request receives new round identity")
	host2.advance_pending_command(f.enemy,0)
	animation2.release_action()
	animation2.finish_action()
	var before: Dictionary = f.round.get_round_status()
	var focus_before: float = f.focus.get_current_focus()
	_expect(before.phase == 2 and before.hit_count > 0, "real instant delivery opens new round before request cleanup")
	f.host.advance_pending_command(f.enemy,0)
	f.animation.release_action()
	f.animation.finish_action()
	_expect(is_equal_approx(fees.get(cached.request_id,-1),30), "old cached request retains old repeat30")
	_expect(is_equal_approx(fees.get(second.request_id,-1),20), "new round first release costs base20")
	focus_before -= 30
	for i in range(70): await physics_frame
	var after: Dictionary = f.round.get_round_status()
	_expect(after.hit_count == before.hit_count and is_equal_approx(after.total_damage,before.total_damage), "real old projectiles do not join new score")
	_expect(is_equal_approx(f.focus.get_current_focus(),focus_before), "old chain damage never restores focus")
	_expect(events.any(func(event): return event.round_id == first.round_id and event.actual_damage > 0), "negative isolation check observes real old round damage")
	_expect(events.any(func(event): return event.round_id == second.round_id), "positive control observes new round damage")
	f.world.free()
	await process_frame

func _test_real_rapid_and_fragments() -> void:
	for path in ["res://SkillSystem/00-Skills/Combo_RapidShot/ComboRapidShotSkill.tscn","res://SkillSystem/00-Skills/ExplosiveArrow/ExplosiveArrowSkill.tscn"]:
		var f := W.make_fixture(root)
		var skill := load(path).instantiate() as SkillBase
		skill.automatic_cast_enabled = false
		skill.skill_cooldown = 0
		skill.base_cast_time = 0.2
		skill.cast_range = 6
		if skill.get_combo_focus_cost() == null: skill.add_child(ComboFocusCost.new())
		f.host.get_node("SkillSocket").add_child(skill)
		f.host.register_skill(skill)
		f.host.combo_skill = skill
		f.combo = skill
		var events: Array = []
		f.enemy.damage_resolved.connect(func(event): events.append(event))
		if path.contains("Explosive"):
			for i in range(3):
				var enemy = load("res://UnitSystem/Base/00_UnitBase.tscn").instantiate()
				enemy.team_id = 2
				enemy.maximum_health = 1000
				enemy.attack_power = 0
				enemy.collision_layer = 4
				enemy.add_to_group(&"enemy_targets")
				f.world.add_child(enemy)
				enemy.position = Vector3(2.4+float(i)*0.3,0,0.2)
				enemy.get_status_effect_component().apply_named_status(&"burning",8)
				enemy.damage_resolved.connect(func(event): events.append(event))
		await physics_frame
		await physics_frame
		_expect(f.commander.submit_slot(0), "content skill admitted "+path)
		var request: SkillCommandRequest = f.requests.values().back()
		f.host.advance_pending_command(f.enemy,0)
		f.animation.release_action()
		f.animation.finish_action()
		for i in range(100): await physics_frame
		_expect(events.size() >= (4 if path.contains("Explosive") else 3), "real projectiles/fragments deal multiple damage "+path+" observed="+str(events.size()))
		var seen: Dictionary = {}
		for event in events:
			_expect(event.round_id == request.round_id and event.request_id == request.request_id, "descendants preserve root round/request")
			seen["%d:%d" % [event.hit_id,event.target_instance_id]] = true
		_expect(f.round.get_round_status().hit_count == seen.size(), "score counts all true projectile/fragment hits")
		_expect(f.commander.get("_records").is_empty(), "real root and child lifetimes naturally cleaned")
		f.world.free()
		await process_frame

func _test_synchronous_and_posthumous() -> void:
	for mode in ["instant","dead_source"]:
		var f := W.make_fixture(root)
		await physics_frame
		if mode == "instant": f.combo.delivery = InstantTargetDeliveryConfig.new()
		_expect(f.commander.submit_slot(0), "lifetime probe admitted")
		var request: SkillCommandRequest = f.requests.values().back()
		f.host.advance_pending_command(f.enemy,0)
		f.animation.release_action()
		f.animation.finish_action()
		if mode == "dead_source": f.actor.apply_damage(100000,f.enemy)
		for i in range(70): await physics_frame
		_expect(f.round.get_round_status().hit_count > 0, "released damage survives immediate cleanup/source death "+mode)
		_expect(f.commander.get("_records").is_empty(), "lifetime cleaned after "+mode)
		_expect(request.has_released(), "root remains released identity")
		f.world.free()
		await process_frame

func _expect(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
func _finish() -> void:
	for message in failures: push_error(message)
	if failures.is_empty(): print("SquadChainRoundIntegrationTest: PASS")
	quit(0 if failures.is_empty() else 1)
