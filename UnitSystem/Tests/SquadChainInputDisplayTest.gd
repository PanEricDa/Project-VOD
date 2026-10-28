extends SceneTree
## InputMap、只读卡片和静态场景装配；验证事件路由及实际配置，不用源码搜索代替行为。
var failures: Array[String] = []
const CONTROLLER_SCENE = "res://UnitSystem/Components/Combat/Squad/SquadChainCommandController.tscn"
const DISPLAY_SCENE = "res://UnitSystem/Components/UI/SquadChainCommandDisplay.tscn"
const PREVIEW_SCENE = "res://Scenes/Previews/SquadChainCommandPreview.tscn"
var _rejections: Array[int] = []

func _initialize() -> void: call_deferred(&"_run")
func _run() -> void:
	var paths: Array[String] = [CONTROLLER_SCENE, DISPLAY_SCENE, PREVIEW_SCENE]
	for name in ["GuardianBash", "GreaterHeal", "Firebolt", "RapidShot"]:
		var folder = {"GuardianBash": "GuardianBash", "GreaterHeal": "GreaterHeal", "Firebolt": "Firebolt", "RapidShot": "RapidShot"}[name]
		paths.append("res://SkillSystem/00-Skills/Combo_%s/Combo%sSkill.tscn" % [folder, name])
	for path in paths:
		_expect(ResourceLoader.exists(path), "new scene exists: " + path)
	if not failures.is_empty():
		_finish()
		return
	for path in paths: _expect(ResourceLoader.get_resource_uid(path) != ResourceUID.INVALID_ID, "scene has registered UID: " + path)
	var controller = load(CONTROLLER_SCENE).instantiate() as SquadChainCommandController
	root.add_child(controller)
	controller.command_rejected.connect(func(slot, _reason): _rejections.append(slot))
	for index in range(4):
		var action = StringName("squad_chain_%d" % (index + 1))
		_expect(InputMap.has_action(action), "action registered")
		var physical = InputEventKey.new()
		physical.physical_keycode = KEY_1 + index
		physical.keycode = KEY_1 + index
		physical.device = 0
		physical.pressed = true
		_expect(InputMap.event_is_action(physical, action), "real keyboard device0 matches physical binding")
		var event = InputEventAction.new()
		event.action = action
		event.pressed = true
		controller.call("_unhandled_input", event)
		event.pressed = false
		controller.call("_unhandled_input", event)
	_expect(_rejections == [0, 1, 2, 3], "new press routes each fixed slot once; release ignored")
	var echo = InputEventKey.new()
	echo.physical_keycode = KEY_1
	echo.pressed = true
	echo.echo = true
	controller.call("_unhandled_input", echo)
	_expect(_rejections == [0, 1, 2, 3], "echo ignored")
	var display = load(DISPLAY_SCENE).instantiate() as CanvasLayer
	display.command_source = controller
	root.add_child(display)
	_expect(display.get_node("Panel/VBox/Cards").get_child_count() == 4, "four visible stable cards")
	_verify_controls(display)
	display.free()
	controller.free()
	var preview = load(PREVIEW_SCENE).instantiate()
	root.add_child(preview)
	current_scene = preview
	await physics_frame
	await physics_frame
	var source = preview.get_node("SquadChainCommandController") as SquadChainCommandController
	_expect(source.companions.size() == 4 and source.focus_source.get_bound_scope() == preview, "preview binds inherited world and four companions")
	_expect(source.focus_source.initial_focus == 100.0, "preview-only initial focus")
	for slot in range(4):
		var actor = source.companions[slot]
		var host = actor.get_node("SkillHost") as SkillHostComponent
		_expect(host.get_equipped_regular_skills().size() == 2 and host.get_combo_skill() != null, "actor retains two regulars and independent chain")
	var ui = preview.get_node("SquadChainCommandDisplay")
	_expect(ui.get_node("Panel/VBox/Cards/Card1/VBox/Cost").text == "专注：" + str(source.get_slot_status(0).estimated_cost), "display renders real numeric quote")
	paused = true
	_expect(not source.submit_slot(0), "paused admission rejected")
	paused = false
	var initial = source.focus_source.get_reserved_focus()
	for step in range(100): source.get_slot_status(0)
	_expect(source.focus_source.get_reserved_focus() == initial, "display/status refresh does not reserve")
	source.set_input_enabled(false)
	_expect(not source.submit_slot(0), "input disable prevents admission")
	preview.get_node("EncounterController").call("begin_scene_unload")
	preview.free()
	current_scene = null
	await process_frame
	await _test_card_state_transitions()
	await _test_new_acceptance_clears_failure()
	_finish()

func _verify_controls(node: Node) -> void:
	if node is Control:
		_expect(node.mouse_filter == Control.MOUSE_FILTER_IGNORE and node.focus_mode == Control.FOCUS_NONE, "pure display never captures mouse/focus")
	for child in node.get_children(): _verify_controls(child)
func _expect(ok: bool, label: String) -> void:
	if not ok: failures.append(label)
func _finish() -> void:
	for message in failures: push_error(message)
	if failures.is_empty(): print("SquadChainInputDisplayTest: PASS")
	quit(0 if failures.is_empty() else 1)

func _test_card_state_transitions() -> void:
	var f = load("res://UnitSystem/Tests/ChainSkillPresentationControllerTest.gd").make_fixture(root)
	var display = load(DISPLAY_SCENE).instantiate()
	display.command_source = f.source
	f.world.add_child(display)
	await physics_frame
	await physics_frame
	var border = display.get_node_or_null("Panel/VBox/Cards/Card1/StateBorder")
	_expect(border != null,"each card has independently styled StateBorder")
	if border == null:
		f.world.free()
		return
	_expect(f.source.submit_slot(0),"UI probe admitted")
	_expect(border.visible and border.theme_type_variation == &"ChainWaiting","accepted immediately uses waiting border")
	_verify_green_feedback(border,false)
	f.actor.get_behavior_state_machine().physics_tick(0.01)
	_expect(border.visible and border.theme_type_variation == &"ChainCasting","actual start uses full green fill")
	_verify_green_feedback(border,true)
	_expect(f.source.submit_slot(0),"one pending request while active")
	_expect(border.theme_type_variation == &"ChainCasting","pending confirmation never steals casting green")
	_expect(display.get_node_or_null("Panel/VBox/Cards/Card1/VBox/CachedConfirmation") != null and display.get_node("Panel/VBox/Cards/Card1/VBox/CachedConfirmation").visible,"cached request has separate confirmation text")
	_expect(not f.source.submit_slot(0),"third request rejected")
	_expect(border.theme_type_variation == &"ChainFailed","rejection immediate red")
	await _presentation_wait(0.33)
	_expect(border.theme_type_variation == &"ChainCasting","red expiry restores still casting fact")
	f.animation.release_action()
	await _presentation_wait(0.33)
	_expect(border.visible and border.theme_type_variation == &"ChainWaiting","old success timer cannot clear different pending request")
	f.animation.finish_action()
	f.actor.get_behavior_state_machine().physics_tick(0.01)
	_expect(border.theme_type_variation == &"ChainCasting","new request survives old deadline")
	f.animation.release_action()
	var token: int = f.pause.acquire_pause(f.world,&"UI_menu")
	await _presentation_wait(0.4)
	_expect(border.visible and border.theme_type_variation == &"ChainCasting","explicit pause suspends success hold")
	f.pause.release_pause(token)
	await _presentation_wait(0.33)
	_expect(not border.visible,"success clears after 0.3 presentation seconds independent of action tail")
	_expect(display.get_node("Panel/VBox/Cards/Card1").modulate == Color.WHITE,"availability grey never dims state border")
	f.world.free()
	await process_frame

func _verify_green_feedback(border: Control, filled: bool) -> void:
	var style := border.get_theme_stylebox("panel") as StyleBoxFlat
	_expect(style != null,"state uses an editable StyleBoxFlat")
	if style == null: return
	for edge: Side in [SIDE_LEFT,SIDE_TOP,SIDE_RIGHT,SIDE_BOTTOM]:
		_expect(style.get_border_width(edge) == 6,"state border is three times original 2px")
	_expect(style.border_color.g > style.border_color.r and style.border_color.g > style.border_color.b,"accepted and casting borders are green")
	_expect(style.bg_color.a >= 0.6 if filled else is_zero_approx(style.bg_color.a),"only actual casting fills button green")
	_expect(border.get_index() < border.get_parent().get_node("VBox").get_index(),"state background renders behind labels and icon")
	var card_style := (border.get_parent() as Control).get_theme_stylebox("panel")
	_expect(card_style.get_margin(SIDE_TOP) >= 8 and card_style.get_margin(SIDE_BOTTOM) >= 8,"thick border keeps clear padding around text")

func _test_new_acceptance_clears_failure() -> void:
	var f = load("res://UnitSystem/Tests/ChainSkillPresentationControllerTest.gd").make_fixture(root)
	var display = load(DISPLAY_SCENE).instantiate()
	display.command_source = f.source
	f.world.add_child(display)
	await physics_frame
	await physics_frame
	var border := display.get_node("Panel/VBox/Cards/Card1/StateBorder") as Control
	f.source.set_input_enabled(false)
	_expect(not f.source.submit_slot(0) and border.theme_type_variation == &"ChainFailed","real rejection displays failure")
	f.source.set_input_enabled(true)
	_expect(f.source.submit_slot(0),"new valid press accepted after rejection")
	_expect(border.theme_type_variation == &"ChainWaiting","new acceptance immediately replaces stale failure with reservation green")
	f.world.free()
	await process_frame

func _presentation_wait(seconds: float) -> void:
	var deadline := Time.get_ticks_usec()+int(seconds*1000000)
	while Time.get_ticks_usec() < deadline: await process_frame