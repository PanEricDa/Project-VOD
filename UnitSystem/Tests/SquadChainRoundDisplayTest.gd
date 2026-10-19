extends SceneTree
## 使用真实伤害夹具验证独立COMBO显示、只读性、动态窗口、暂停和跳字重入。
const W = preload("res://UnitSystem/Tests/SquadChainRoundWindowTest.gd")
const UI = "res://UnitSystem/Components/UI/SquadChainRoundDisplay.tscn"
const COMMAND_UI = "res://UnitSystem/Components/UI/SquadChainCommandDisplay.tscn"
var failures: Array[String] = []
func _initialize() -> void: call_deferred(&"_run")
func _run() -> void:
	_expect(ResourceLoader.exists(UI), "standalone COMBO component must exist")
	if not ResourceLoader.exists(UI):
		_finish()
		return
	_expect(ResourceLoader.get_resource_uid(UI) != ResourceUID.INVALID_ID, "native standalone scene UID")
	var empty = load(UI).instantiate()
	root.add_child(empty)
	_expect(not empty.get_node("Panel").visible, "unbound component hides without fake zero combo")
	empty.free()
	await _test_round_and_animation()
	await _test_rebind_and_read_only()
	await _test_assembly()
	_finish()

func _test_round_and_animation() -> void:
	var f := _make_fixture()
	var display = load(UI).instantiate()
	display.round_source = f.round
	f.world.add_child(display)
	var commands = load(COMMAND_UI).instantiate()
	commands.command_source = f.commander
	f.world.add_child(commands)
	await physics_frame
	var panel: Control = display.get_node("Panel")
	var number: Label = panel.get_node("VBox/ComboRow/Number")
	var score: ProgressBar = panel.get_node("VBox/ScoreProgress")
	var interval: ProgressBar = panel.get_node("VBox/DamageInterval")
	_expect(not panel.visible, "idle before first damage is hidden")
	_expect(panel.get_node("VBox/ComboRow/Caption").text == "COMBO", "caption is English COMBO")
	_expect(not score.show_percentage and not interval.show_percentage, "bars do not print score or countdown numbers")
	_expect(commands.get_node_or_null("Panel/VBox/Evaluation/ChainSummary") == null, "skill bar no longer contains combo feedback")
	_expect(commands.get_node_or_null("Panel/VBox/Evaluation/ScoreProgress") == null, "skill bar no longer contains score")
	var focus_label = commands.get_node("Panel/VBox/Focus/Values")
	_expect(focus_label.text.contains("100"), "focus stays in command bar without evaluation dependency")
	var request := W.start_released(f)
	_expect(not panel.visible, "pending and release without damage do not open visual combo")
	request.retain_delivery(CombatDamageContext.allocate_id())
	W.deal(f,request,500)
	_expect(panel.visible and number.text == "1", "first damage displays real hit count")
	_expect(score.value == 1.0 and f.round.get_round_status().score > 100, "visual full bar does not cap actual score")
	_expect(score.modulate != Color.WHITE, "qualification gives visible full-bar highlight")
	_verify_combo_text_only(panel)
	_expect(number.scale.x < 1.0, "new count starts smaller")
	await _wait(0.10)
	_expect(number.scale.x > 1.0, "count quickly grows beyond normal size")
	W.deal(f,request,1)
	_expect(number.text == "2" and number.scale.x < 1.0, "rapid next hit restarts one pulse with latest number")
	paused = true
	var held_scale: Vector2 = number.scale
	var held_interval: float = interval.value
	await _wait(0.12)
	_expect(number.scale.is_equal_approx(held_scale) and is_equal_approx(interval.value,held_interval), "pause freezes pulse and business countdown")
	paused = false
	await _wait(0.25)
	_expect(number.scale.is_equal_approx(Vector2.ONE), "pulse settles without accumulating transforms")
	W.advance(f,0.4)
	_expect(is_equal_approx(interval.value,0.5), "countdown uses actual adaptive0.8-second denominator")
	W.advance(f,0.400001)
	_expect(panel.visible and number.text == "2" and score.value == 1.0 and not interval.visible, "closed round retains combo and score but hides timer")
	_verify_combo_text_only(panel)
	await _wait(0.15)
	f.animation.finish_action()
	var next := W.start_released(f)
	_expect(number.text == "2" and not interval.visible, "new pending request retains previous result")
	W.deal(f,next,1)
	_expect(number.text == "1" and interval.visible and score.value > 0 and score.value < 0.1, "next first damage replaces previous result with fresh low score")
	_expect(score.modulate == Color.WHITE, "new unqualified round clears gold highlight")
	W.advance(f,2.000001)
	_expect(panel.visible and not interval.visible, "low score result also persists")
	_verify_controls(display)
	await process_frame
	var rect: Rect2 = panel.get_global_rect()
	var viewport: Rect2 = display.get_viewport().get_visible_rect()
	_expect(rect.position.x > viewport.size.x*0.5 and rect.position.y < viewport.size.y*0.4 and viewport.encloses(rect), "component is upper-right and inside viewport")
	var global_number: Rect2 = number.get_global_rect()
	_expect(global_number.end.y <= score.get_global_rect().position.y and score.get_global_rect().end.y <= interval.get_global_rect().position.y, "number then score then countdown vertically")
	f.world.free()
	await process_frame

func _test_rebind_and_read_only() -> void:
	var f := _make_fixture()
	var other := _make_fixture()
	var display = load(UI).instantiate()
	display.round_source = f.round
	f.world.add_child(display)
	await physics_frame
	var before: float = f.focus.get_current_focus()
	for i: int in range(100): display.call("_process",0)
	_expect(f.round.peek_current_round() == 0 and f.focus.get_current_focus() == before and f.focus.get_reserved_focus() == 0, "display queries never create round or charge focus")
	var request := W.start_released(f)
	request.retain_delivery(CombatDamageContext.allocate_id())
	W.deal(f,request,10)
	_expect(display.get_node("Panel").visible, "first world can show own damage")
	display.round_source = other.round
	await process_frame
	await process_frame
	_expect(not display.get_node("Panel").visible, "switch to idle world clears old result")
	W.deal(f,request,10)
	_expect(not display.get_node("Panel").visible, "old source disconnected and cannot leak damage")
	display.round_source = f.round
	await process_frame
	await process_frame
	_expect(display.get_node("Panel/VBox/ComboRow/Number").text == "2", "binding active evaluator restores actual count")
	f.focus.unbind_scope()
	await process_frame
	_expect(not display.get_node("Panel").visible, "scope unload clears retained feedback")
	display.round_source = null
	await process_frame
	_expect(not display.get_node("Panel").visible, "null source is safe")
	f.world.free()
	other.world.free()
	await process_frame

func _test_assembly() -> void:
	for path: String in ["res://Scenes/CombatRoom.tscn","res://Scenes/Previews/SquadChainRoundPreview.tscn","res://Scenes/Previews/SquadFinisherSelectionPreview.tscn"]:
		var before_orphans := Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)
		var scene = load(path).instantiate()
		root.add_child(scene)
		current_scene = scene
		await physics_frame
		await physics_frame
		var display = scene.get_node_or_null("SquadChainRoundDisplay")
		_expect(display != null, "explicit standalone assembly in "+path)
		if display != null:
			_expect(display.round_source == scene.get_node("SquadChainRoundController"), "display points to existing evaluator in "+path)
		_expect(scene.get_node("SquadChainCommandDisplay").command_source == scene.get_node("SquadChainCommandController"), "skill bar keeps original command binding")
		scene.get_node("EncounterController").call("begin_scene_unload")
		scene.free()
		current_scene = null
		await process_frame
		_expect(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT) <= before_orphans, "room cleanup leaves no orphan UI nodes in "+path)

func _make_fixture() -> Dictionary:
	var f := W.make_fixture(root)
	# UI测试手动注入真实伤害；放慢真实投射物，避免等待动画期间产生非预期的额外命中。
	f.combo.delivery = f.combo.delivery.duplicate()
	f.combo.delivery.projectile_speed = 0.1
	return f

func _verify_combo_text_only(node: Node) -> void:
	if node is Label and node.is_visible_in_tree():
		_expect(node.text == "COMBO" or node.text.is_valid_int(), "combo feedback contains no finisher qualification text")
	for child: Node in node.get_children(): _verify_combo_text_only(child)

func _wait(seconds: float) -> void:
	var deadline := Time.get_ticks_usec()+int(seconds*1000000.0)
	while Time.get_ticks_usec() < deadline: await process_frame
func _verify_controls(node: Node) -> void:
	if node is Control: _expect(node.mouse_filter == Control.MOUSE_FILTER_IGNORE and node.focus_mode == Control.FOCUS_NONE, "read-only display never captures input")
	for child: Node in node.get_children(): _verify_controls(child)
func _expect(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
func _finish() -> void:
	for message: String in failures: push_error(message)
	if failures.is_empty(): print("SquadChainRoundDisplayTest: PASS")
	quit(0 if failures.is_empty() else 1)
