extends SceneTree
## 捕捉UI复制冷却、吞鼠标、重复订阅或将只读查询当技能请求的错误；使用真实测试场景与动作。
var _failures: Array[String] = []
var _world: Node3D
var _controller: Node
var _host: SkillHostComponent
var _bar: Node
var _accepted: int = 0
var _rejected: int = 0

func _initialize() -> void: call_deferred("_run")

func _run() -> void:
	_world = load("res://Scenes/Tests/PlayerSkills/PlayerSkillsTest.tscn").instantiate()
	root.add_child(_world)
	current_scene = _world
	await process_frame
	await process_frame
	_controller = _world.get_node("Hero/PlayerSkillController")
	_host = _world.get_node("Hero/SkillHost")
	_expect(_controller.has_method("get_slot_status"), "Controller must expose readonly slot status")
	_expect(ResourceLoader.exists("res://UnitSystem/Components/UI/PlayerSkillBar.tscn"), "two-slot HUD asset must exist")
	if not _controller.has_method("get_slot_status") or not ResourceLoader.exists("res://UnitSystem/Components/UI/PlayerSkillBar.tscn"):
		_world.free()
		_finish()
		return
	_bar = _world.get_node_or_null("PlayerSkillBar")
	_expect(_bar != null, "test scene must visibly assemble HUD")
	if _bar == null:
		_world.free()
		_finish()
		return
	var hero := _world.get_node("Hero") as PlayerBase
	hero.set_physics_process(false)
	var driver := hero.get_node("AttackController") as PlayerAttackController
	driver.set_process(false)
	var animator := hero.get_node("Visual/HeroVisual/CharacterAnimationPlayer") as CharacterAnimationEventPlayer
	animator.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	_host.global_cooldown_duration = 0.0
	_controller.connect("slot_accepted", func(_slot, _skill): _accepted += 1)
	_controller.connect("slot_rejected", func(_slot, _reason): _rejected += 1)
	var first := _host.get_regular_skill(0)
	var original_name := first.display_name
	first.display_name = "Gather Test"
	first.icon = GradientTexture1D.new()
	_bar.call("bind_source", _controller)
	_bar.call("bind_source", _controller)
	for i: int in range(3): _bar.call("refresh_immediately")
	var unavailable: Dictionary = _controller.call("get_slot_status",0)
	_expect(not unavailable.can_request and unavailable.reason==&"target_missing","target Q without lock is visibly unavailable")
	_expect(hero.get_node("TargetingSystem").request_lock(_world.get_node("EnemyContainer/TrainingMelee")),"HUD ready fixture has a real locked target")
	_bar.call("refresh_immediately")
	var status: Dictionary = _controller.call("get_slot_status", 0)
	_expect(status.configured and status.can_request and status.phase == &"ready", "ready slot can attempt request")
	_expect(_accepted == 0 and _rejected == 0 and first.is_ready(), "queries and repeated bind have no gameplay side effects")
	status.phase = &"corrupted"
	_expect(_controller.call("get_slot_status", 0).phase == &"ready", "returned dictionaries are independent")
	var card := _bar.get_node("Panel/Cards/Card0")
	_expect(card.get_node("Content/Name").text == "Gather Test" and card.get_node("Content/Icon").texture == first.icon, "HUD reads current skill name and icon")
	_expect(not card.get_node("Content/Placeholder").visible, "icon replaces placeholder")
	first.icon = null
	first.display_name = original_name
	_bar.call("refresh_immediately")
	_expect(card.get_node("Content/Placeholder").visible, "missing icon uses text placeholder")
	var saved_events := InputMap.action_get_events(&"player_skill_1")
	InputMap.action_erase_events(&"player_skill_1")
	var key := InputEventKey.new()
	key.physical_keycode = KEY_R
	InputMap.action_add_event(&"player_skill_1", key)
	_bar.call("refresh_immediately")
	_expect(card.get_node("Content/Key").text.contains("R"), "key label follows InputMap instead of hardcoded Q")
	InputMap.action_erase_events(&"player_skill_1")
	for event: InputEvent in saved_events: InputMap.action_add_event(&"player_skill_1",event)
	_expect(_controller.call("request_slot", 0), "real Q request accepted")
	_bar.call("refresh_immediately")
	_expect(_controller.call("get_slot_status", 0).phase == &"casting", "own active slot retains casting identity")
	_expect(not _controller.call("get_slot_status", 1).can_request, "other ready skill is blocked while action busy")
	animator.advance(0.21)
	animator.advance(0.2)
	_bar.call("refresh_immediately")
	status = _controller.call("get_slot_status", 0)
	_expect(status.phase == &"cooldown" and status.cooldown_remaining > 1.8, "actual release starts real two-second cooldown")
	_expect(is_equal_approx(status.cooldown_remaining, first.get_cooldown_remaining()), "query reads exact SkillBase remaining")
	_expect(is_equal_approx(card.get_node("Cooldown").value, status.cooldown_remaining / status.cooldown_duration), "cooldown shade consumes real skill state")
	var remaining := first.get_cooldown_remaining()
	paused = true
	await process_frame
	await process_frame
	_bar.call("refresh_immediately")
	_expect(not _controller.call("get_slot_status",1).can_request and is_equal_approx(first.get_cooldown_remaining(),remaining), "pause blocks ready skill without advancing cooldown")
	paused = false
	hero.set_player_input_enabled(false)
	_expect(_controller.call("get_slot_status",1).reason == &"input_disabled", "input permission is reflected before request")
	hero.set_player_input_enabled(true)
	var second := _host.regular_skills[1]
	_host.regular_skills[1] = null
	_expect(_controller.call("get_slot_status",1).phase == &"empty" and not _controller.call("get_slot_status",-1).configured, "empty and invalid slots are safe")
	_host.regular_skills[1] = second
	_host.set_skill_casting_enabled(false)
	_expect(not _controller.call("get_slot_status",1).can_request, "Host casting lock is visible")
	_host.set_skill_casting_enabled(true)
	_host.start_global_cooldown(0.8)
	var shared: Dictionary = _controller.call("get_slot_status",1)
	_expect(shared.global_blocked and shared.global_cooldown_remaining > 0.7 and shared.cooldown_remaining == 0 and not shared.can_request,"shared cooldown does not masquerade as skill cooldown")
	_host.set_use_external_global_cooldown(true)
	_host.set_external_global_cooldown_blocked(true)
	_expect(not _controller.call("get_slot_status",1).can_request,"external global cooldown lock is visible with zero remaining")
	_host.set_external_global_cooldown_blocked(false)
	_host.set_use_external_global_cooldown(false)
	_expect(_controller.call("request_slot",1), "E actual action starts")
	_bar.call("unbind_source")
	_expect(_host.get_active_skill() == second and driver.is_action_in_progress(), "HUD unbind never cancels gameplay")
	_bar.call("bind_source",_controller)
	_controller.call("request_slot",0)
	_bar.call("refresh_immediately")
	_expect(card.get_node("Feedback").theme_type_variation == &"PlayerSkillFailed" and _accepted == 2 and _rejected == 1, "busy input gives red feedback without duplicate acceptance")
	_host.cancel_active_skill(&"test_cleanup")
	for control: Node in _bar.find_children("*","Control",true,false):
		_expect(control.mouse_filter == Control.MOUSE_FILTER_IGNORE,"HUD never intercepts world mouse input")
	hero.apply_damage(hero.get_current_health()+1000)
	_expect(_controller.call("get_slot_status",1).reason == &"owner_dead", "death blocks slot before new request")
	_world.free()
	current_scene = null
	await process_frame
	_finish()

func _expect(value: bool, message: String) -> void:
	if not value: _failures.append(message)
func _finish() -> void:
	for message: String in _failures: printerr("FAIL: ",message)
	print("PlayerSkillBarTest: ","PASS" if _failures.is_empty() else "FAIL")
	quit(0 if _failures.is_empty() else 1)
