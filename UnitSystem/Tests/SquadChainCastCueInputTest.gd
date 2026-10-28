extends SceneTree
## 连携输入节奏：真实Host/动画/Focus验证，不改变战斗评分和既有动作锁。
const FIXTURE = preload("res://UnitSystem/Tests/AllyChainCommandPriorityTest.gd")
var failures: Array[String] = []

func _initialize() -> void: call_deferred(&"_run")

func _run() -> void:
	await _test_cue_gate()
	await _test_failure_and_rebind()
	await _test_zero_cast_and_missing_visual()
	await _test_zero_cast_cue()
	await _test_reentrant_and_stale_callbacks()
	await _test_rebind_during_status_query()
	_test_formal_assembly()
	await process_frame
	await process_frame
	for message: String in failures: push_error(message)
	if failures.is_empty(): print("SquadChainCastCueInputTest: PASS")
	quit(0 if failures.is_empty() else 1)

func _fixture() -> Dictionary:
	var f: Dictionary = FIXTURE.make_fixture(root, "res://UnitSystem/AI/Ally/Units/Caster.tscn", false)
	var second := load("res://UnitSystem/AI/Ally/Units/Caster.tscn").instantiate() as AllyBase
	second.automatic_skill_cast_enabled = false
	second.gravity_multiplier = 0.0
	second.position = Vector3(-1,0,0)
	f.world.add_child(second)
	second.set_physics_process(false)
	var host := second.get_node("SkillHost") as SkillHostComponent
	host.configure_owner(second,f.world)
	second.get_targeting_component().call("_set_locked_target",f.enemy)
	second.get_targeting_component().set_physics_process(false)
	var animation := second.get_node("Visual").find_child("CharacterAnimationPlayer",true,false) as CharacterAnimationEventPlayer
	animation.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	f.second = second
	f.second_host = host
	f.second_combo = host.get_combo_skill()
	f.second_animation = animation
	for skill: SkillBase in [f.combo, f.second_combo]:
		skill.base_cast_time = 1.0
		skill.cast_effect_start_ratio = 0.5
		skill.cast_effect_scene = null
		skill.set_physics_process(false)
	var focus := SquadFocusComponent.new()
	focus.auto_bind_parent = false
	focus.initial_focus = 100.0
	f.world.add_child(focus)
	var party: Array[UnitBase] = [f.player,f.actor,second]
	focus.bind_scope(f.world,party)
	var source := SquadChainCommandController.new()
	source.companions = [f.actor,second,null,null]
	source.focus_source = focus
	for property: Dictionary in source.get_property_list():
		if property.name == &"wait_for_cast_cue": source.set("wait_for_cast_cue",true)
	f.world.add_child(source)
	source.set_round_source(func() -> int: return 100,func() -> int: return 100)
	f.source = source
	f.focus = focus
	f.accepted = []
	source.command_accepted.connect(func(request): f.accepted.append(request))
	var display = load("res://UnitSystem/Components/UI/SquadChainCommandDisplay.tscn").instantiate()
	display.command_source = source
	f.world.add_child(display)
	f.display = display
	return f

func _test_cue_gate() -> void:
	var f := _fixture()
	await physics_frame
	await physics_frame
	_expect(f.source.submit_slot(0),"first command accepted immediately")
	var early: bool = f.source.submit_slot(1)
	_expect(not early and f.accepted.size() == 1 and f.second_host.get_pending_command_id() == 0 and f.focus.get_reserved_focus() == 20.0,"before cue another companion cannot queue or reserve")
	if early:
		f.world.free()
		return
	_expect(not f.source.submit_slot(0),"repeat during initial wait ignored")
	var border := f.display.get_node("Panel/VBox/Cards/Card1/StateBorder") as Control
	_expect(border.theme_type_variation == &"ChainWaiting","ignored input preserves accepted reservation border")
	f.host.advance_pending_command(f.enemy,0.0)
	_expect(border.theme_type_variation == &"ChainCasting","native action begins green")
	_expect(not f.source.submit_slot(1),"animation start alone does not reopen input")
	_expect(not f.source.submit_slot(0) and border.theme_type_variation == &"ChainCasting","early repeat cannot paint executing request red")
	f.combo.call("_physics_process",0.49)
	_expect(not f.source.get_slot_status(1).can_submit,"before half-cast gate remains closed")
	f.combo.call("_physics_process",0.01)
	_expect(f.source.get_slot_status(1).can_submit,"existing half-cast cue reopens all companions without visual asset")
	_expect(f.source.submit_slot(1),"next companion accepted at cue")
	_expect(not f.source.submit_slot(0) and f.focus.get_reserved_focus() == 40.0,"next accepted command immediately closes gate again")
	f.animation.release_action()
	f.animation.finish_action()
	_expect(not f.source.get_slot_status(0).can_submit,"older release and action completion cannot unlock successor")
	f.second_host.advance_pending_command(f.enemy,0.0)
	f.second_combo.call("_physics_process",0.5)
	_expect(f.source.submit_slot(0),"second actor cue permits next choice")
	f.world.free()

func _test_failure_and_rebind() -> void:
	for stage: String in ["waiting","casting","timeout","unbind"]:
		var f := _fixture()
		await physics_frame
		await physics_frame
		_expect(f.source.submit_slot(0),"failure fixture accepted "+stage)
		var request: SkillCommandRequest = f.accepted[0]
		if stage == "casting": f.host.advance_pending_command(f.enemy,0.0)
		if stage == "timeout":
			f.host.advance_pending_command(f.enemy,9.0)
		elif stage == "unbind":
			f.focus.unbind_scope()
			var party: Array[UnitBase] = [f.player,f.actor,f.second]
			f.focus.bind_scope(f.world,party)
		else:
			f.host.cancel_command(request.request_id,&"test_interrupt")
		_expect(f.source.submit_slot(1),"failure/timeout/rebind restores next input "+stage)
		_expect(f.focus.get_reserved_focus() == 20.0,"only new request retains reservation "+stage)
		f.world.free()

func _test_zero_cast_and_missing_visual() -> void:
	for scenario: String in ["ratio_zero","release_fallback","real_flash"]:
		var f := _fixture()
		await physics_frame
		await physics_frame
		if scenario == "ratio_zero": f.combo.cast_effect_start_ratio = 0.0
		if scenario == "real_flash":
			f.combo.cast_effect_scene = load("res://Effects/Skills/Shared/ReleaseAccentFlash.tscn")
		_expect(f.source.submit_slot(0),"cue fixture accepted "+scenario)
		f.host.advance_pending_command(f.enemy,0.0)
		if scenario == "release_fallback":
			f.animation.release_action()
		elif scenario == "real_flash":
			f.combo.call("_physics_process",0.5)
			_expect(is_instance_valid(f.combo.get("_cast_effect_instance")),"real visual exists when next input opens")
		_expect(f.source.get_slot_status(1).can_submit,"zero/missing visual/low-frame release cannot lock gate "+scenario)
		f.world.free()

func _test_zero_cast_cue() -> void:
	var f := _fixture()
	await physics_frame
	await physics_frame
	# 零施法单测使用真实Skill入口；现有武器动作的release marker非零，不伪造兼容动作。
	var skill := load("res://SkillSystem/00-Skills/Firebolt/FireboltSkill.tscn").instantiate() as SkillBase
	skill.base_cast_time = 0.0
	skill.cast_effect_start_ratio = 0.5
	skill.cast_effect_scene = null
	f.world.add_child(skill)
	skill.configure_owner(f.actor,null,f.world)
	var cues: Array[SkillContext] = []
	skill.cast_cue_reached.connect(func(context): cues.append(context))
	var context := SkillContext.new()
	context.requested_target = f.enemy
	context.explicit_target_requested = true
	context.delivery_parent = f.world
	_expect(skill.request_skill(context) and skill.confirm_action_started(Transform3D.IDENTITY),"zero cast uses genuine activation and action confirmation")
	skill.call("_physics_process",0.5)
	_expect(cues.size() == 1,"zero cast without asset emits exactly one cue")
	skill.cancel_skill(&"test_cleanup")
	f.world.free()

func _test_reentrant_and_stale_callbacks() -> void:
	var f := _fixture()
	await physics_frame
	await physics_frame
	var nested: Array[bool] = []
	f.focus.focus_changed.connect(func(_a,_b,_c):
		if nested.is_empty():
			nested.append(false)
			nested[0] = f.source.submit_slot(1))
	_expect(f.source.submit_slot(0),"outer command survives synchronous focus listener")
	_expect(nested == [false] and f.accepted.size() == 1 and f.focus.get_reserved_focus() == 20.0,"synchronous reservation notification cannot bypass cue gate")
	f.host.advance_pending_command(f.enemy,0.0)
	f.combo.call("_physics_process",0.5)
	_expect(f.source.submit_slot(1),"successor accepted after first cue")
	f.host.cancel_command(f.accepted[0].request_id,&"late_old_cancel")
	_expect(not f.source.get_slot_status(0).can_submit,"old cancellation cannot unlock newer command")
	f.second_host.cancel_command(f.accepted[1].request_id,&"new_cancel")
	_expect(f.source.get_slot_status(0).can_submit,"only current blocker cancellation unlocks")
	f.world.free()
	await process_frame

func _test_rebind_during_status_query() -> void:
	var f := _fixture()
	await physics_frame
	await physics_frame
	var armed: Array[bool] = [false]
	f.source.set_round_source(func() -> int:
		if armed[0]:
			armed[0] = false
			f.focus.unbind_scope()
			var party: Array[UnitBase] = [f.player,f.actor,f.second]
			f.focus.bind_scope(f.world,party)
		return 100,func() -> int: return 100)
	armed[0] = true
	_expect(not f.source.submit_slot(0) and f.accepted.is_empty() and f.focus.get_reserved_focus() == 0.0,"status query rebinding invalidates old admission instead of moving it into new scope")
	_expect(f.source.submit_slot(1),"rebound scope can accept a fresh input")
	f.world.free()

func _test_formal_assembly() -> void:
	var scene = load("res://Scenes/CombatRoom.tscn").instantiate()
	var source := scene.get_node("SquadChainCommandController") as SquadChainCommandController
	_expect(source.get("wait_for_cast_cue") == true,"formal combat scene explicitly enables cue-gated input")
	scene.free()

func _expect(ok: bool, label: String) -> void:
	if not ok: failures.append(label)
