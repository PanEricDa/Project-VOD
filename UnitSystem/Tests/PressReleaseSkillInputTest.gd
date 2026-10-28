extends SceneTree
## 捕捉按下即施法、错键确认、暂停迟到施法、按住抢占普攻与UI遮字；真实InputMap和现有技能管线。
const COMPONENT := "res://UnitSystem/Components/Input/PressReleaseInputComponent.tscn"
const THEME := "res://UnitSystem/Components/UI/Themes/SkillInputFeedbackTheme.tres"
var failures: Array[String] = []
var _world: Node3D
var _hero: PlayerBase
var _input: Node
var _controller: PlayerSkillController
var _host: SkillHostComponent
var _bar: PlayerSkillBar
var _driver: PlayerAttackController
var _accepted: int = 0
var _requests: int = 0

func _initialize() -> void: call_deferred("_run")

func _run() -> void:
	_test_shared_component()
	await _setup()
	await _test_press_hold_release_and_attack()
	await _test_wrong_release_and_repeated_press()
	await _test_target_at_confirmation()
	await _test_cancel_boundaries()
	await _test_recovered_input_starts_fresh()
	await _test_slot_replacement()
	await _test_rebinding_and_detached_ui()
	_world.free()
	current_scene = null
	await process_frame
	await _test_finisher_focus_recovery()
	for message in failures: printerr("FAIL: ",message)
	print("PressReleaseSkillInputTest: ","PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)

func _test_shared_component() -> void:
	_expect(ResourceLoader.exists(COMPONENT),"shared interaction scene exists")
	_expect(ResourceLoader.exists(THEME),"shared native feedback theme exists")
	if ResourceLoader.exists(THEME):
		var theme = load(THEME)
		_expect(theme is Theme and ResourceLoader.get_resource_uid(THEME) != ResourceUID.INVALID_ID,"shared Theme has native type and UID")
	if not ResourceLoader.exists(COMPONENT): return
	var first = load(COMPONENT).instantiate()
	var second = load(COMPONENT).instantiate()
	_expect(not first.begin_press(-1),"invalid slot never arms")
	_expect(first.begin_press(0,42),"first press arms")
	_expect(not first.begin_press(1,99) and first.get_pressed_slot()==0,"other press cannot overwrite active selection")
	_expect(second.get_pressed_slot()==-1,"separate instances have independent state")
	_expect(not first.end_press(1,42) and first.get_pressed_slot()==0,"other release does not confirm")
	_expect(not first.end_press(0,43) and first.get_pressed_slot()==-1,"replaced identity cancels")
	first.begin_press(1,99)
	_expect(first.end_press(1,99) and not first.end_press(1,99),"matching release confirms exactly once")
	first.begin_press(0)
	first.cancel_selection()
	_expect(not first.end_press(0),"cancel prevents delayed confirmation")
	first.free()
	second.free()

func _setup() -> void:
	_world = load("res://Scenes/Tests/PlayerSkills/PlayerSkillsTest.tscn").instantiate()
	root.add_child(_world)
	current_scene = _world
	await process_frame
	await process_frame
	_hero = _world.get_node("Hero")
	_input = _hero.get_node("PlayerSkillInputComponent")
	_controller = _hero.get_node("PlayerSkillController")
	_host = _hero.get_node("SkillHost")
	_bar = _world.get_node("PlayerSkillBar")
	_driver = _hero.get_node("AttackController")
	_hero.set_physics_process(false)
	_driver.set_process(false)
	var animator = _hero.get_node("Visual/HeroVisual/CharacterAnimationPlayer")
	animator.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	_host.global_cooldown_duration = 0
	for enemy in _world.get_node("EnemyContainer").get_children():
		enemy.set_physics_process(false)
		enemy.get_combat_system().set_physics_process(false)
	_hero.get_node("TargetingSystem").request_lock(_world.get_node("EnemyContainer/TrainingMelee"))
	_controller.slot_accepted.connect(func(_slot,_skill): _accepted+=1)
	_input.slot_requested.connect(func(_slot): _requests+=1)

func _test_press_hold_release_and_attack() -> void:
	var before := _accepted
	_driver.request_attack()
	_expect(_driver.is_action_in_progress(),"normal attack fixture started")
	await _send(&"player_skill_1",true)
	_bar.refresh_immediately()
	var card = _bar.get_node("Panel/Cards/Card0")
	_expect(_accepted==before and _host.get_active_skill()==null,"key down selects without requesting skill")
	_expect(not _driver.is_external_action_in_progress() and _driver.is_action_in_progress(),"held Q does not preempt normal attack")
	_expect(card.get_node("Feedback").visible and card.get_node("Feedback").theme_type_variation==&"PlayerSkillSelected","held Q shows selected green outline")
	_expect(card.scale.is_equal_approx(Vector2(1.06,1.06)),"held Q grows around center")
	var end := Time.get_ticks_usec()+150000
	while Time.get_ticks_usec()<end: await process_frame
	_expect(_accepted==before,"holding never auto-confirms")
	await _send(&"player_skill_1",false)
	_bar.refresh_immediately()
	_expect(_accepted==before+1 and _driver.is_external_action_in_progress(),"release requests once and now preempts basic attack")
	var feedback = card.get_node("Feedback")
	_expect(feedback.theme_type_variation==&"PlayerSkillCasting","accepted release shows green fill")
	var style = feedback.get_theme_stylebox("panel")
	_expect(style is StyleBoxFlat and style.bg_color.g>0.4 and style.bg_color.a>0.5,"confirmed feedback has visible green background")
	_expect(feedback.get_index()<card.get_node("Content").get_index(),"green fill stays below text")
	await _send(&"player_skill_1",false)
	_expect(_accepted==before+1,"duplicate release never casts twice")
	_reset()

func _test_wrong_release_and_repeated_press() -> void:
	var before := _accepted
	await _send(&"player_skill_1",true)
	await _send(&"player_skill_2",true)
	await _send(&"player_skill_2",false)
	_expect(_accepted==before,"releasing second key cannot confirm first or add request")
	await _send(&"player_skill_1",true)
	_expect(_accepted==before,"repeated down never casts")
	await _send(&"player_skill_1",false)
	_expect(_accepted==before+1 and _host.get_active_skill()==_host.get_regular_skill(0),"first key retains selection until release")
	_reset()

func _test_target_at_confirmation() -> void:
	var targeting = _hero.get_node("TargetingSystem")
	targeting.request_lock(_world.get_node("EnemyContainer/TrainingMelee"))
	await _send(&"player_skill_1",true)
	var next_target = _world.get_node("EnemyContainer/TrainingRanged")
	targeting.request_lock(next_target)
	await _send(&"player_skill_1",false)
	var active := _host.get_active_skill()
	_expect(active != null and active.get_current_context().resolved_target==next_target,"confirmation uses current lock instead of old key-down lock")
	_reset()

func _test_cancel_boundaries() -> void:
	var before := _accepted
	await _send(&"player_skill_2",true)
	paused = true
	await process_frame
	await process_frame
	paused = false
	await _send(&"player_skill_2",false)
	_expect(_accepted==before,"pause cancels held input even when release comes after resume")
	await _send(&"player_skill_2",true)
	_input.set_input_enabled(false)
	_input.set_input_enabled(true)
	await _send(&"player_skill_2",false)
	_expect(_accepted==before,"disabled component cannot retain old selection")
	await _send(&"player_skill_2",true)
	_hero.set_player_input_enabled(false)
	await process_frame
	await process_frame
	_hero.set_player_input_enabled(true)
	await _send(&"player_skill_2",false)
	_expect(_accepted==before,"player input block cancels held selection")
	await _send(&"player_skill_2",true)
	_input.notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	await _send(&"player_skill_2",false)
	_expect(_accepted==before,"focus loss prevents late release")
	_reset()

func _test_recovered_input_starts_fresh() -> void:
	var before := _requests
	await _send(&"player_skill_2",true)
	_input.notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	# Godot失焦会释放Input状态，但不会补发按键松开事件。
	Input.action_release(&"player_skill_2")
	await _send(&"player_skill_2",true)
	await _send(&"player_skill_2",false)
	_expect(_requests==before+1,"first fresh press after focus loss must not be swallowed")
	_reset()
	before = _requests
	await _send(&"player_skill_2",true)
	_hero.set_player_input_enabled(false)
	_hero.set_player_input_enabled(true)
	await _send(&"player_skill_2",false)
	_expect(_requests==before,"same-frame player disable cancels old selection synchronously")
	_reset()
	before = _requests
	await _send(&"player_skill_2",true)
	# 弹窗等上层消费者吞掉release时，只释放Input状态；不得自动补施法或卡住预选。
	Input.action_release(&"player_skill_2")
	await process_frame
	await process_frame
	await _send(&"player_skill_1",true)
	await _send(&"player_skill_1",false)
	_expect(_requests==before+1,"missing release is cancelled and next slot remains usable")
	_expect(not _controller.get_slot_status(-1).get("pressed",false),"invalid slot is never reported as selected")
	_reset()

func _test_slot_replacement() -> void:
	var before := _accepted
	await _send(&"player_skill_2",true)
	var saved := _host.regular_skills[1]
	_host.regular_skills[1] = _host.regular_skills[0]
	await _send(&"player_skill_2",false)
	_expect(_accepted==before,"held input cannot confirm a replacement skill")
	_host.regular_skills[1] = saved
	_reset()

func _test_rebinding_and_detached_ui() -> void:
	var saved: StringName = _input.skill_2_action
	var action := &"press_release_rebind_test"
	InputMap.add_action(action)
	_input.skill_2_action = action
	var before := _accepted
	await _send(action,true)
	_expect(_accepted==before,"rebound action still waits for release")
	_bar.free()
	await _send(action,false)
	_expect(_accepted==before+1,"input confirms rebound skill with UI removed")
	_input.skill_2_action = saved
	InputMap.erase_action(action)
	_reset()

func _test_finisher_focus_recovery() -> void:
	var fixture_script = load("res://UnitSystem/Tests/SquadFinisherSelectionControllerTest.gd")
	var f: Dictionary = fixture_script.make_selection_fixture(root)
	await physics_frame
	fixture_script.qualify(f)
	var chosen: Array = []
	f.selection.finisher_selected.connect(func(value): chosen.append(value))
	await _send(&"squad_chain_1",true)
	f.selection.notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	Input.action_release(&"squad_chain_1")
	await _send(&"squad_chain_1",true)
	_expect(f.selection.get_selection_status().pressed_slot==0,"finisher first press after focus loss selects normally")
	await _send(&"squad_chain_1",false)
	var end := Time.get_ticks_usec()+170000
	while Time.get_ticks_usec()<end: await process_frame
	_expect(chosen.size()==1,"finisher focus recovery confirms once after feedback")
	f.world.free()
	await process_frame

func _reset() -> void:
	_host.cancel_active_skill(&"test_cleanup")
	_driver.cancel_combo()
	_host.call("_physics_process",30.0)
	for skill in _host.regular_skills:
		if skill!=null: skill.call("_physics_process",30.0)

func _send(action: StringName, pressed: bool) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	await process_frame

func _expect(value: bool,message: String) -> void:
	if not value: failures.append(message)
