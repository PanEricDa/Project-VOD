extends SceneTree

## 防止连携只改变施法目标、却遗留旧攻击目标；同时验证取消/失效不切换及一次性语义。
var _failures: Array[String] = []
var _world: Node3D

func _initialize() -> void:
	call_deferred(&"_run")

func _run() -> void:
	_world = Node3D.new()
	root.add_child(_world)
	var actor = load("res://UnitSystem/AI/Ally/Units/Guardian.tscn").instantiate()
	actor.automatic_skill_cast_enabled = false
	_world.add_child(actor)
	# 不用 PROCESS_MODE_DISABLED：它会把单位的碰撞体从物理世界移除，无法验证真实索敌。
	actor.set_physics_process(false)
	actor.get_node(^"SkillHost").set_physics_process(false)
	var targeting: AITargetingComponent = actor.get_targeting_component()
	var old_target := _unit(Vector3(-0.4, 0, 0))
	var skill_target := _unit(Vector3(0.6, 0, 0))
	var skill = load("res://SkillSystem/00-Skills/Combo_GuardianBash/ComboGuardianBashSkill.tscn").instantiate()
	skill.cast_effect_scene = null
	skill.release_effect_scene = null
	skill.camera_effect_profile = null
	skill.release_accent_profile = null
	_world.add_child(skill)
	skill.configure_owner(actor, null, _world)
	_expect(skill.get_node_or_null(^"AdoptSkillTarget") != null, "Guardian combo equips reusable target adoption")
	targeting.hold_target(old_target)
	var context := _context(old_target)
	context.preferred_target = skill_target
	_expect(skill.activate(context), "real configured Guardian combo accepts target")
	_expect(targeting.get_locked_target() == old_target, "input acceptance does not change attack target")
	_expect(skill.confirm_action_started(Transform3D.IDENTITY), "real skill starts cast")
	_expect(targeting.get_locked_target() == old_target, "cast start does not change attack target")
	# 调用方的后续目标变化不可改写已经进入技能的请求副本。
	context.preferred_target = old_target
	_expect(skill.release_action(Transform3D.IDENTITY), "real delivery succeeds")
	_expect(targeting.get_locked_target() == skill_target, "successful release adopts resolved target, not later caller intent")
	_expect(not targeting.is_target_held(), "adoption releases previous protection hold without creating a new hold")
	targeting.refresh_target()
	_expect(targeting.get_locked_target() == skill_target, "normal refresh retains adopted legal target")
	targeting.adopt_target(old_target)
	_expect(not skill.release_action(Transform3D.IDENTITY), "duplicate release marker is rejected")
	_expect(targeting.get_locked_target() == old_target, "duplicate marker cannot reapply adoption after a later target change")

	skill.reset_skill()
	targeting.hold_target(old_target)
	_expect(skill.activate(_context(skill_target)), "cancelled case accepts request")
	_expect(skill.confirm_action_started(Transform3D.IDENTITY), "cancelled case starts cast")
	skill.cancel_skill(&"test_interrupted")
	_expect(targeting.get_locked_target() == old_target and targeting.is_target_held(), "cancelled cast preserves prior target and hold")

	skill.reset_skill()
	_expect(skill.activate(_context(skill_target)), "invalidated case accepts request")
	_expect(skill.confirm_action_started(Transform3D.IDENTITY), "invalidated case starts cast")
	skill_target.targetable = false
	_expect(not skill.release_action(Transform3D.IDENTITY), "invalid target fails real release")
	_expect(targeting.get_locked_target() == old_target, "failed release preserves previous target")
	skill_target.targetable = true

	skill.reset_skill()
	_expect(skill.activate(_context(skill_target)), "rejected delivery accepts initial request")
	_expect(skill.confirm_action_started(Transform3D.IDENTITY), "rejected delivery starts cast")
	var saved_delivery: SkillDeliveryConfig = skill.delivery
	skill.delivery = null
	_expect(not skill.release_action(Transform3D.IDENTITY), "delivery rejection is not successful release")
	_expect(targeting.get_locked_target() == old_target and targeting.is_target_held(), "delivery rejection preserves old target and hold")
	skill.delivery = saved_delivery

	skill.reset_skill()
	_expect(skill.activate(_context(skill_target)), "second release accepts request")
	_expect(skill.confirm_action_started(Transform3D.IDENTITY), "second release starts")
	_expect(skill.release_action(Transform3D.IDENTITY), "second release succeeds")
	_expect(targeting.get_locked_target() == skill_target, "component works on repeated releases")
	skill_target.apply_damage(100000)
	old_target.position = Vector3(0.3, 0, 0)
	await physics_frame
	await physics_frame
	targeting.refresh_target()
	_expect(targeting.get_locked_target() == old_target, "dead adopted target resumes normal acquisition (locked=%s, overlaps=%d, dead=%s)" % [str(targeting.get_locked_target()), targeting.get_overlapping_bodies().size(), skill_target.is_dead()])

	if targeting.has_method(&"adopt_target"):
		_expect(not targeting.call(&"adopt_target", skill_target), "dead target cannot be adopted")
		var friendly := _unit(Vector3(0.3, 0, 0), 1)
		_expect(not targeting.call(&"adopt_target", friendly), "friendly target cannot override hostile targeting policy")
		var distant := _unit(Vector3(100, 0, 0))
		_expect(not targeting.call(&"adopt_target", distant), "adoption cannot bypass normal retention distance")
		var legal := _unit(Vector3(0.6, 0, 0))
		targeting.hold_target(old_target)
		targeting.suspend_detection(1.0, false)
		_expect(not targeting.call(&"adopt_target", legal), "suspended targeting rejects adoption")
		_expect(targeting.get_locked_target() == old_target and targeting.is_target_held(), "rejected adoption preserves target hold")
		targeting.resume_detection()
	else:
		_expect(false, "targeting exposes validated one-shot adoption API")

	_world.free()
	await process_frame
	await _actual_chain_case()
	for message: String in _failures:
		printerr("FAIL: ", message)
	print("SkillAdoptTargetComponentTest: ", "PASS" if _failures.is_empty() else "FAIL")
	quit(0 if _failures.is_empty() else 1)

func _context(target: UnitBase) -> SkillContext:
	var context := SkillContext.new()
	context.requested_target = target
	context.explicit_target_requested = true
	return context

func _unit(at: Vector3, team: int = 2) -> UnitBase:
	var unit = load("res://UnitSystem/Base/00_UnitBase.tscn").instantiate()
	unit.team_id = team
	unit.maximum_health = 10000
	unit.collision_layer = 4
	unit.position = at
	_world.add_child(unit)
	return unit

func _expect(ok: bool, message: String) -> void:
	if not ok: _failures.append(message)


# 验证真实连携命令/动画入口，而非只在测试里发出成功信号。
func _actual_chain_case() -> void:
	var fixture_script = load("res://UnitSystem/Tests/AllyChainCommandPriorityTest.gd")
	var f: Dictionary = fixture_script.make_fixture(root, "res://UnitSystem/AI/Ally/Units/Guardian.tscn")
	_world = f.world
	var next_target := _unit(Vector3(0, 0, -0.5))
	f.enemy.position = Vector3(0.5, 0, 0)
	var host: SkillHostComponent = f.host
	var skill := host.get_node(^"SkillSocket/ComboGuardianBashSkill") as SkillBase
	host.combo_skill = skill
	skill.cast_effect_scene = null
	skill.release_effect_scene = null
	skill.camera_effect_profile = null
	skill.release_accent_profile = null
	var targeting: AITargetingComponent = f.actor.get_targeting_component()
	targeting.hold_target(f.enemy)
	await physics_frame
	await physics_frame
	var request := SkillCommandRequest.create(701, 700, f.actor, skill, f.world, 8.0, Callable(self, &"_authorize"))
	f.requests[701] = request
	_expect(host.enqueue_command(request), "real Guardian chain command enqueued")
	host.advance_pending_command(next_target, 0.01)
	_expect(host.get_active_command_id() == 701, "real chain starts Guardian animation")
	_expect(targeting.get_locked_target() == f.enemy, "real chain cast preserves prior AI target")
	f.animation.release_action()
	_expect(request.has_released(), "real animation marker releases chain delivery")
	_expect(targeting.get_locked_target() == next_target and not targeting.is_target_held(), "real chain adopts actual target without extra hold")
	f.animation.finish_action()
	_expect(not host.has_command_action_lock(), "target adoption does not prevent chain action cleanup")
	f.enemy.get_targeting_component().hold_target(f.player)
	f.actor.get_behavior_state_machine().physics_tick(0.01)
	_expect(targeting.get_locked_target() == f.enemy and targeting.is_target_held(), "existing Guardian protection can replace adopted target after chain action")
	f.world.free()
	await process_frame

func _authorize() -> bool:
	return true
