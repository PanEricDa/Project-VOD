extends SceneTree

## 使用真实Hero、SkillHost、Delivery和玩家动作验证输入/槽位适配，不替换冷却或施法算法。
const CONTROLLER_PATH := "res://UnitSystem/Components/Combat/PlayerSkillController.gd"
const INPUT_PATH := "res://UnitSystem/Components/Combat/PlayerSkillInputComponent.gd"
const ACTION_PATH := "res://Scenes/Tests/PlayerSkills/PlayerSkillProbeAction.tres"
var _failures: Array[String] = []
var _hero: PlayerBase
var _host: SkillHostComponent
var _controller: Node
var _input: Node
var _driver: PlayerAttackController
var _animator: CharacterAnimationEventPlayer
var _accepted: int = 0
var _rejected: Array[StringName] = []
var _effects: int = 0

class CountEffect extends SkillEffectBase:
	signal applied()
	func apply(_context: SkillContext, _result: SkillDeliveryResult, _target: Node3D) -> bool:
		applied.emit()
		return true

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	_expect(FileAccess.file_exists(CONTROLLER_PATH), "player skill Controller must exist")
	_expect(FileAccess.file_exists(INPUT_PATH), "InputMap skill input component must exist")
	if not FileAccess.file_exists(CONTROLLER_PATH) or not FileAccess.file_exists(INPUT_PATH):
		_finish()
		return
	await _setup()
	_test_empty_and_invalid_slot_rejected()
	_test_busy_cooldown_and_same_frame_requests()
	_test_cancel_and_old_callback()
	_test_start_failure_is_not_accepted()
	_test_input_disabled_does_not_cancel_started_action()
	_test_reentrant_old_callback_does_not_clear_new_action()
	_test_reentrant_cancel_does_not_clear_new_action()
	await _test_inputmap_dispatch_and_echo()
	await _test_move_turn_permissions_and_legacy_fallback()
	_test_death_cleanup()
	_hero.free()
	await process_frame
	_finish()

func _setup() -> void:
	_hero = load("res://UnitSystem/Player/Hero/Hero.tscn").instantiate() as PlayerBase
	_host = _hero.get_node("SkillHost") as SkillHostComponent
	_host.global_cooldown_duration = 0.0
	var skills: Array[SkillBase] = []
	for index: int in range(2):
		var skill := load("res://SkillSystem/01-Core/SkillBase.tscn").instantiate() as SkillBase
		skill.name = "Probe" + str(index)
		skill.skill_id = StringName("probe_" + str(index))
		skill.target_relations = TargetResolver.TargetRelationFlag.SELF
		skill.base_cast_time = 0.2 if index == 0 else 0.15
		skill.skill_cooldown = 10.0 if index == 0 else 12.0
		skill.automatic_cast_enabled = false
		skill.can_move_while_casting = true
		skill.can_turn_while_casting = true
		skill.set("action_animation", load(ACTION_PATH))
		skill.delivery = InstantTargetDeliveryConfig.new()
		var effect := CountEffect.new()
		effect.applied.connect(func() -> void: _effects += 1)
		skill.add_child(effect)
		_host.get_node("SkillSocket").add_child(skill)
		skills.append(skill)
	_host.regular_skills = skills
	_controller = _hero.get_node("PlayerSkillController")
	_input = _hero.get_node("PlayerSkillInputComponent")
	root.add_child(_hero)
	await process_frame
	await process_frame
	_hero.set_physics_process(false)
	_driver = _hero.get_node("AttackController")
	_driver.set_process(false)
	_animator = _hero.get_node("Visual/HeroVisual/CharacterAnimationPlayer")
	_animator.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	_controller.connect("slot_accepted", func(_slot: int, _skill: SkillBase) -> void: _accepted += 1)
	_controller.connect("slot_rejected", func(_slot: int, reason: StringName) -> void: _rejected.append(reason))
	_controller.call("bind_host", _host)
	_controller.call("bind_host", _host)

func _test_empty_and_invalid_slot_rejected() -> void:
	_expect(not _controller.call("request_slot", -1) and not _controller.call("request_slot", 2), "out of range slots reject")
	var saved := _host.regular_skills[1]
	_host.regular_skills[1] = null
	_expect(not _controller.call("request_slot", 1), "empty slot rejects safely")
	_expect(_accepted == 0 and _effects == 0, "invalid input does not start action or effect")
	_host.regular_skills[1] = saved
	_expect(_host.get_regular_skill(0) != _host.get_regular_skill(1), "two slots keep distinct instances")

func _test_busy_cooldown_and_same_frame_requests() -> void:
	_expect(_controller.call("request_slot", 0), "slot zero accepted")
	_expect(_host.get_active_skill() == _host.get_regular_skill(0), "slot selects its own skill")
	_expect(not _controller.call("request_slot", 1), "same frame second slot rejected while busy")
	_expect(_host.get_regular_skill(1).is_ready(), "rejected skill remains ready")
	_expect(_effects == 0, "accepting a request is not applying an effect")
	_animator.advance(0.21)
	_expect(_effects == 1 and _host.get_regular_skill(0).get_cooldown_remaining() > 9.9, "release applies exactly once and starts normal cooldown")
	_animator.advance(0.20)
	_expect(_host.get_active_skill() == null, "finish releases Host")
	_expect(not _controller.call("request_slot", 0), "cooling skill cannot be requested")
	_expect(_controller.call("request_slot", 1), "other slot uses its own skill")
	_expect(_host.get_active_skill() == _host.get_regular_skill(1), "second slot selects second instance")
	_host.cancel_active_skill(&"test_reset")
	_clear_cooldowns()
	_driver.request_attack()
	_expect(_controller.call("request_slot", 0), "valid player skill preempts normal attack")
	_expect(_driver.is_external_action_in_progress(), "skill owns animation after preemption")
	_host.cancel_active_skill(&"test_reset")
	_driver.cancel_combo()

func _test_cancel_and_old_callback() -> void:
	_clear_cooldowns()
	var effects_before := _effects
	_expect(_controller.call("request_slot", 0), "cancellation fixture accepted")
	var serial: int = _driver.call("get_external_action_serial")
	_host.cancel_active_skill(&"test_cancel_before_release")
	_expect(_host.get_regular_skill(0).is_ready() and not _driver.call("is_action_in_progress"), "pre-release cancellation clears action without cooldown")
	_expect(_effects == effects_before, "cancel before release never applies effect")
	_expect(_controller.call("request_slot", 1), "new action accepted after cancellation")
	_driver.emit_signal("external_action_lifecycle", 0, serial, &"release")
	_driver.emit_signal("external_action_lifecycle", 0, serial, &"finish")
	_expect(_host.get_active_skill() == _host.get_regular_skill(1) and _effects == effects_before, "old serial cannot release or finish new action")
	_animator.advance(0.16)
	_expect(_effects == effects_before + 1, "new action applies only its own effect")
	_host.cancel_active_skill(&"test_cancel_after_release")
	_expect(_host.get_regular_skill(1).get_cooldown_remaining() > 11.9, "post-release cancel does not refund cooldown")
	_clear_cooldowns()

func _test_start_failure_is_not_accepted() -> void:
	var skill := _host.get_regular_skill(0)
	var saved: Animation = skill.get("action_animation")
	var invalid := Animation.new()
	invalid.length = 0.4
	skill.set("action_animation", invalid)
	var before := _accepted
	_expect(not _controller.call("request_slot", 0), "invalid action fails synchronously")
	_expect(_accepted == before and _rejected.back() == &"action_rejected", "startup failure never announces acceptance")
	_expect(_host.get_active_skill() == null and skill.is_ready(), "startup failure leaves Host and cooldown clean")
	skill.set("action_animation", saved)

func _test_input_disabled_does_not_cancel_started_action() -> void:
	_expect(_controller.call("request_slot", 0), "input disable fixture accepted")
	_hero.set_player_input_enabled(false)
	_expect(not _controller.call("request_slot", 1), "direct request respects player input permission")
	_animator.advance(0.40)
	_expect(_host.get_active_skill() == null and _host.get_regular_skill(0).get_cooldown_remaining() > 0.0, "disabling input does not cancel already started skill")
	_hero.set_player_input_enabled(true)
	_clear_cooldowns()

func _test_reentrant_old_callback_does_not_clear_new_action() -> void:
	var action_finished := func(_request_id: int, _serial: int, event: StringName) -> void:
		if event == &"finish": _controller.call("request_slot", 1)
	_driver.connect("external_action_lifecycle", action_finished)
	_expect(_controller.call("request_slot", 0), "reentrant fixture accepted")
	_animator.advance(0.40)
	_expect(_host.get_active_skill() == _host.get_regular_skill(1), "old finish stack preserves synchronously requested new skill")
	_expect(_driver.call("is_action_in_progress"), "new action still owns animation")
	_driver.disconnect("external_action_lifecycle", action_finished)
	_host.cancel_active_skill(&"test_reset")
	_clear_cooldowns()

func _test_reentrant_cancel_does_not_clear_new_action() -> void:
	_clear_cooldowns()
	var first := _host.get_regular_skill(0)
	var second := _host.get_regular_skill(1)
	var on_cancel := func(_context: SkillContext, _reason: StringName) -> void:
		_controller.call("request_slot", 1)
	first.skill_cancelled.connect(on_cancel)
	_controller.call("request_slot", 0)
	_host.cancel_active_skill(&"reentrant_cancel")
	_expect(_host.get_active_skill() == second and _driver.is_action_in_progress(), "old Host cancellation stack must not clear a new skill accepted in cancellation callback")
	first.skill_cancelled.disconnect(on_cancel)
	_host.cancel_active_skill(&"fixture_cleanup")
	if not second.is_ready(): second.cancel_skill(&"fixture_cleanup")
	_clear_cooldowns()

func _test_inputmap_dispatch_and_echo() -> void:
	_expect(InputMap.has_action(&"player_skill_1") and InputMap.has_action(&"player_skill_2"), "Q/E use project InputMap")
	if not InputMap.has_action(&"player_skill_1") or not InputMap.has_action(&"player_skill_2"): return
	var q := false
	var e := false
	for event: InputEvent in InputMap.action_get_events(&"player_skill_1"):
		if event is InputEventKey and (event.physical_keycode == KEY_Q or event.keycode == KEY_Q): q = true
	for event: InputEvent in InputMap.action_get_events(&"player_skill_2"):
		if event is InputEventKey and (event.physical_keycode == KEY_E or event.keycode == KEY_E): e = true
	_expect(q and e, "default Q/E bindings are saved")
	var before := _accepted
	await _tap(&"player_skill_1")
	_expect(_accepted == before + 1, "real InputMap event accepted once")
	_host.cancel_active_skill(&"test_reset")
	_clear_cooldowns()
	var echo := InputEventKey.new()
	echo.physical_keycode = KEY_Q
	echo.pressed = true
	echo.echo = true
	_input.call("_unhandled_input", echo)
	_expect(_accepted == before + 1, "keyboard echo cannot issue another request")
	var replacement := &"test_player_skill_rebind"
	InputMap.add_action(replacement)
	_input.set("skill_1_action", replacement)
	await _tap(replacement)
	_expect(_accepted == before + 2, "rebound action routes without hardcoded Q test")
	_host.cancel_active_skill(&"test_reset")
	_clear_cooldowns()
	_input.set("skill_1_action", &"player_skill_1")
	InputMap.erase_action(replacement)
	paused = true
	_input.call("_unhandled_input", _pressed_action(&"player_skill_1"))
	_expect(_accepted == before + 2, "paused game rejects manual input dispatch")
	paused = false

func _test_move_turn_permissions_and_legacy_fallback() -> void:
	_expect(_hero.has_method("set_skill_action_permissions"), "PlayerBase exposes skill permissions")
	if not _hero.has_method("set_skill_action_permissions"): return
	_host.get_regular_skill(0).can_move_while_casting = false
	_host.get_regular_skill(0).can_turn_while_casting = false
	_controller.call("request_slot", 0)
	_hero.position = Vector3(0, 3, 0)
	_hero.velocity = Vector3.ZERO
	var visual := _hero.get_node("Visual") as Node3D
	var before_rotation := visual.rotation
	Input.action_press(&"player_move_right")
	_hero.call("_physics_process", 0.02)
	Input.action_release(&"player_move_right")
	_expect(absf(_hero.velocity.x) < 0.001 and _hero.velocity.y < 0.0, "skill movement lock stops horizontal input but keeps gravity")
	_expect(visual.rotation.is_equal_approx(before_rotation), "skill turning lock preserves facing")
	_host.cancel_active_skill(&"test_reset")
	Input.action_press(&"player_move_right")
	_hero.call("_physics_process", 0.02)
	Input.action_release(&"player_move_right")
	_expect(_hero.velocity.x > 0.0, "cancellation restores movement")
	_host.get_regular_skill(0).can_move_while_casting = true
	_host.get_regular_skill(0).can_turn_while_casting = true
	var plain := load("res://UnitSystem/Player/Hero/Hero.tscn").instantiate() as PlayerBase
	# 仅运行时撤下新适配器，保留无组件时的旧移动契约，不修改Hero源。
	plain.get_node("PlayerSkillController").free()
	plain.get_node("PlayerSkillInputComponent").free()
	root.add_child(plain)
	await process_frame
	plain.set_physics_process(false)
	Input.action_press(&"player_move_right")
	plain.call("_physics_process", 0.02)
	Input.action_release(&"player_move_right")
	_expect(plain.velocity.x > 0.0, "Hero without new components keeps legacy movement")
	plain.free()
	await process_frame

func _test_death_cleanup() -> void:
	_clear_cooldowns()
	_controller.call("request_slot", 0)
	_hero.apply_damage(100000.0)
	_expect(_hero.is_dead() and _host.get_active_skill() == null and not _driver.call("is_action_in_progress"), "death clears skill and action")
	_expect(not _controller.call("request_slot", 1), "dead player cannot request skill")
	_expect(not str(_animator.current_animation).ends_with("weapon/RESET"), "death cancellation does not cover death with weapon RESET")

func _clear_cooldowns() -> void:
	_host.call("_physics_process", 30.0)
	for skill: SkillBase in _host.regular_skills:
		if skill != null: skill.call("_physics_process", 30.0)

func _tap(action: StringName) -> void:
	Input.parse_input_event(_pressed_action(action))
	Input.flush_buffered_events()
	await process_frame
	var event := InputEventAction.new()
	event.action = action
	event.pressed = false
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	await process_frame

func _pressed_action(action: StringName) -> InputEventAction:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	return event

func _expect(condition: bool, message: String) -> void:
	if not condition: _failures.append(message)

func _finish() -> void:
	for message: String in _failures: print("FAIL: " + message)
	print("PlayerSkillControlTest: " + ("PASS" if _failures.is_empty() else "FAIL"))
	quit(0 if _failures.is_empty() else 1)
