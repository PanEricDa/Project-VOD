extends SceneTree
## 捕获普攻阻挡有效技能、段数丢失、松键强制攻击、无效请求取消普攻及换武器后的旧续段串入。
const HERO_PATH := "res://UnitSystem/Player/Hero/Hero.tscn"
const ACTION_PATH := "res://Scenes/Tests/PlayerSkills/PlayerSkillProbeAction.tres"
const SWORD := "res://Item/Weapon/Sword/IronSwordData.tres"
const SHIELD := "res://Item/Weapon/Shield/IronShieldData.tres"
var failures: Array[String] = []
var world: Node3D
var hero: PlayerBase
var driver: PlayerAttackController
var controller: PlayerSkillController
var host: SkillHostComponent
var animator: CharacterAnimationEventPlayer
var starts: Array[int] = []
func _initialize() -> void: call_deferred("_run")
func _run() -> void:
	await _test_held_resume(SWORD,2,3)
	await _test_held_resume(SHIELD,1,2)
	await _test_native_weapon_cast_animation()
	await _test_released_resume_and_timeout()
	await _test_final_segment_wraps()
	await _test_invalid_requests_preserve_attack()
	await _test_cancellation_and_weapon_change()
	await _test_reentrant_finish()
	await _test_finish_callback_clears_resume()
	await _test_skill_from_attack_finish_callback()
	await _test_inputmap_held_attack()
	for failure: String in failures: printerr("FAIL: ",failure)
	print("PlayerSkillAttackPreemptionTest: ","PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
func _setup(weapon_path: String = SWORD) -> void:
	world=Node3D.new()
	root.add_child(world)
	current_scene=world
	hero=load(HERO_PATH).instantiate() as PlayerBase
	host=hero.get_node("SkillHost") as SkillHostComponent
	host.global_cooldown_duration=0
	var skills: Array[SkillBase]=[]
	for i: int in range(2):
		var skill := load("res://SkillSystem/01-Core/SkillBase.tscn").instantiate() as SkillBase
		skill.name="PreemptionProbe"+str(i)
		skill.skill_id=StringName("preemption_"+str(i))
		skill.target_relations=TargetResolver.TargetRelationFlag.SELF
		skill.base_cast_time=0.2
		skill.skill_cooldown=10
		skill.automatic_cast_enabled=false
		skill.action_animation=load(ACTION_PATH)
		skill.delivery=InstantTargetDeliveryConfig.new()
		var effect := StatModifierSkillEffect.new()
		effect.amount=1
		effect.duration_seconds=3
		skill.add_child(effect)
		host.get_node("SkillSocket").add_child(skill)
		skills.append(skill)
	host.regular_skills=skills
	world.add_child(hero)
	await process_frame
	await process_frame
	hero.set_physics_process(false)
	driver=hero.get_node("AttackController") as PlayerAttackController
	driver.set_process(false)
	animator=hero.get_node("Visual/HeroVisual/CharacterAnimationPlayer") as CharacterAnimationEventPlayer
	animator.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	controller=hero.get_node("PlayerSkillController") as PlayerSkillController
	_expect(driver.equip_weapon(load(weapon_path)),"valid weapon equips "+weapon_path)
	starts.clear()
	driver.attack_started.connect(func(index): starts.append(index))
func _cleanup() -> void:
	Input.action_release(&"player_attack")
	host.cancel_active_skill(&"test_cleanup")
	driver.cancel_combo()
	world.free()
	current_scene=null
	await process_frame
func _start_segment(stage: int, held: bool = true) -> void:
	Input.action_press(&"player_attack")
	driver.request_attack()
	for i: int in range(1,stage):
		animator.advance(animator.current_animation_length+0.001)
	_expect(driver.is_attacking() and driver.get_combo_index()==stage,"fixture reaches actual segment "+str(stage))
	if not held: Input.action_release(&"player_attack")
func _cast(slot: int = 0) -> bool:
	var accepted := controller.request_slot(slot)
	_expect(accepted,"valid skill immediately preempts current basic attack")
	if not accepted: return false
	_expect(driver.is_external_action_in_progress() and not driver.is_attacking(),"skill owns animation immediately")
	_expect(not controller.request_slot(1-slot),"another ordinary skill cannot overwrite active skill")
	driver.request_attack()
	_expect(driver.is_external_action_in_progress(),"ordinary attack cannot steal active skill animation")
	return true
func _finish_cast() -> void:
	animator.advance(0.21)
	_expect(host.get_active_skill()!=null and not driver.is_attacking(),"release frame is not end of protected skill action")
	animator.advance(0.19)
	_expect(host.get_active_skill()==null,"finish frame releases host before attack continues")
func _test_held_resume(weapon_path: String, stage: int, next_stage: int) -> void:
	await _setup(weapon_path)
	_start_segment(stage)
	_expect(controller.get_slot_status(0).can_request,"HUD does not mark a preemptible attack as busy")
	animator.open_attack_hit_window()
	_expect(hero.get_node("MeleeHitbox").is_detecting(),"fixture has live hit window before preemption")
	hero.request_attack_motion(Vector3.FORWARD,0.5,2.0)
	_expect(hero.is_attack_motion_active(),"fixture has real attack motion before preemption")
	driver.set_hit_stop_active(true)
	if _cast():
		_expect(not hero.is_attack_motion_active() and not hero.get_node("MeleeHitbox").is_detecting(),"preemption closes real attack motion and hit window")
		_expect(not driver.is_hit_stop_active(),"preemption clears old local hit stop")
		# 不推进动画，仅推进超过普攻续段窗口的战斗秒，不应消耗被技能保护的段数。
		driver.call("_process",0.75)
		_finish_cast()
		_expect(driver.is_attacking() and driver.get_combo_index()==next_stage,"held input resumes next segment on same weapon")
		_expect(starts.back()==next_stage,"resumed real attack emits correct segment event")
	await _cleanup()
func _test_released_resume_and_timeout() -> void:
	await _setup()
	_start_segment(2)
	if _cast():
		Input.action_release(&"player_attack")
		_finish_cast()
		_expect(not driver.is_attacking(),"release during skill prevents forced auto attack")
		driver.request_attack()
		_expect(driver.is_attacking() and driver.get_combo_index()==3,"new input within ordinary window continues segment3")
	await _cleanup()
	await _setup()
	_start_segment(1,false)
	if _cast():
		_finish_cast()
		# 手动推进前让真实输入just_pressed跨帧清空，避免同帧测试把旧按下重新读为续段输入。
		await process_frame
		driver.call("_process",driver.combo_reset_duration+0.01)
		driver.request_attack()
		_expect(driver.get_combo_index()==1,"ordinary continuation timeout starts a fresh combo")
	await _cleanup()
func _test_final_segment_wraps() -> void:
	await _setup()
	_start_segment(3)
	if _cast():
		_finish_cast()
		_expect(driver.is_attacking() and driver.get_combo_index()==1,"interrupted last segment wraps to first rather than out of bounds")
	await _cleanup()
func _test_invalid_requests_preserve_attack() -> void:
	await _setup()
	_start_segment(2)
	var skill := host.get_regular_skill(0)
	var saved_animation := skill.action_animation
	skill.action_animation=Animation.new()
	skill.action_animation.length=0.4
	var before := animator.current_animation
	_expect(not controller.request_slot(0),"invalid skill animation rejects")
	_expect(driver.is_attacking() and driver.get_combo_index()==2 and animator.current_animation==before,"invalid action asset leaves original attack running")
	skill.action_animation=saved_animation
	skill.target_relations=TargetResolver.TargetRelationFlag.HOSTILE
	_expect(not controller.request_slot(0) and driver.is_attacking(),"missing locked target does not preempt")
	var enemy := load("res://UnitSystem/Base/00_UnitBase.tscn").instantiate() as UnitBase
	enemy.team_id=2
	enemy.position=Vector3(0,0,-3)
	world.add_child(enemy)
	hero.get_node("TargetingSystem").request_lock(enemy)
	skill.cast_range=1
	_expect(not controller.request_slot(0) and driver.is_attacking() and host.get_active_skill()==null,"out of range rejects without preempting or queuing")
	skill.target_relations=TargetResolver.TargetRelationFlag.SELF
	skill.cast_range=5
	host.set_cast_blocked(true)
	_expect(not controller.request_slot(0) and driver.is_attacking(),"cast block preserves original attack")
	host.set_cast_blocked(false)
	host.start_global_cooldown(1)
	_expect(not controller.request_slot(0) and driver.is_attacking(),"GCD rejection preserves attack")
	await _cleanup()
func _test_cancellation_and_weapon_change() -> void:
	for mode: String in ["cancel","death","weapon","unequip","input_disabled"]:
		await _setup()
		_start_segment(2)
		if _cast():
			match mode:
				"cancel": host.cancel_active_skill(&"test_cancel")
				"death": hero.apply_damage(100000)
				"weapon": _expect(driver.equip_weapon(load(SHIELD)),"weapon can change without carrying old combo")
				"unequip": driver.unequip_weapon()
				"input_disabled":
					hero.set_player_input_enabled(false)
					_finish_cast()
			_expect(not driver.is_attacking(),"terminal change prevents unwanted resumed attack: "+mode)
			Input.action_release(&"player_attack")
			if mode=="death": hero.revive(100)
			if mode=="unequip": driver.equip_weapon(load(SWORD))
			if mode=="input_disabled": hero.set_player_input_enabled(true)
			driver.request_attack()
			_expect(driver.get_combo_index()==1,"old continuation is discarded: "+mode)
		await _cleanup()
func _test_reentrant_finish() -> void:
	await _setup()
	_start_segment(1)
	if _cast():
		var original_serial := driver.get_external_action_serial()
		driver.external_action_lifecycle.connect(func(_request,serial,event):
			if serial==original_serial and event==&"finish":
				controller.request_slot(1))
		_finish_cast_without_idle_assert()
		_expect(driver.is_external_action_in_progress() and host.get_active_skill()==host.get_regular_skill(1),"new skill from finish notification is not overwritten by old resume")
		_finish_cast()
		_expect(not driver.is_attacking(),"old continuation does not leak into reentrant replacement skill")
	await _cleanup()
func _finish_cast_without_idle_assert() -> void:
	animator.advance(0.21)
	animator.advance(0.19)
func _test_inputmap_held_attack() -> void:
	await _setup()
	_start_segment(1)
	var e := InputEventAction.new()
	e.action=&"player_skill_1"
	e.pressed=true
	Input.parse_input_event(e)
	Input.flush_buffered_events()
	await process_frame
	_expect(not driver.is_external_action_in_progress() and driver.is_attacking(),"key down keeps held basic attack until skill confirmation")
	e=InputEventAction.new()
	e.action=&"player_skill_1"
	Input.parse_input_event(e)
	Input.flush_buffered_events()
	await process_frame
	_expect(driver.is_external_action_in_progress(),"InputMap release preempts while attack remains held")
	if driver.is_external_action_in_progress():
		_finish_cast()
		_expect(driver.get_combo_index()==2,"actual input route resumes next attack")
	await _cleanup()
func _expect(ok: bool, label: String) -> void:
	if not ok: failures.append(label)


func _test_finish_callback_clears_resume() -> void:
	await _setup()
	_start_segment(2)
	if _cast():
		var original_serial := driver.get_external_action_serial()
		driver.external_action_lifecycle.connect(func(_request,serial,event):
			if serial==original_serial and event==&"finish": driver.cancel_combo())
		_finish_cast()
		_expect(not driver.is_attacking() and driver.get_combo_index()==0,"explicit cancel during finish callback invalidates old continuation")
	await _cleanup()


func _test_skill_from_attack_finish_callback() -> void:
	await _setup()
	_start_segment(1)
	var accepted: Array[bool]=[]
	driver.attack_finished.connect(func(index):
		if index==1: accepted.append(controller.request_slot(0)))
	animator.advance(animator.current_animation_length+0.001)
	_expect(accepted==[true],"attack-finished listener may immediately start valid skill")
	_expect(driver.is_external_action_in_progress() and host.get_active_skill()==host.get_regular_skill(0),"old attack finish cannot overwrite newly accepted skill")
	if driver.is_external_action_in_progress():
		_finish_cast()
		_expect(driver.is_attacking() and driver.get_combo_index()==2,"callback-started skill still resumes correct next segment")
	await _cleanup()


# 正式武器库的帧时间来自float32，末帧与length的微小表示差异不能让有效动作被拒绝。
func _test_native_weapon_cast_animation() -> void:
	await _setup(SHIELD)
	_start_segment(1)
	var beyond_end := (load(ACTION_PATH) as Animation).duplicate() as Animation
	beyond_end.length=0.35
	host.get_regular_skill(0).action_animation=beyond_end
	_expect(not controller.request_slot(0) and driver.is_attacking(),"genuinely out-of-bounds finish marker still rejects without interrupting")
	host.get_regular_skill(0).action_animation=null
	if _cast():
		animator.advance(0.21)
		_expect(host.get_active_skill()!=null,"native shield cast remains protected until finish")
		animator.advance(0.41)
		_expect(host.get_active_skill()==null and driver.is_attacking() and driver.get_combo_index()==2,"native shield action finishes successfully and resumes segment2")
	await _cleanup()
