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
