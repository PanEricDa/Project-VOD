extends SceneTree
## 原四卡兼容与正式评价显示；界面查询不得创建轮次或修改专注。
const W = preload("res://UnitSystem/Tests/SquadChainRoundWindowTest.gd")
const UI = "res://UnitSystem/Components/UI/SquadChainCommandDisplay.tscn"
var failures: Array[String] = []
func _initialize() -> void: call_deferred(&"_run")
func _run() -> void:
	var display = load(UI).instantiate()
	root.add_child(display)
	var has_source: bool = display.get_property_list().any(func(p): return p.name == &"round_source")
	_expect(has_source, "existing command display needs optional round_source")
	var panel = display.get_node_or_null("Panel/VBox/Evaluation")
	_expect(panel != null, "native evaluation region must be inspectable in original UI scene")
	if not has_source or panel == null:
		display.free()
		_finish()
		return
	_expect(not panel.visible and display.get_node("Panel/VBox/Cards").get_child_count() == 4, "no round source keeps original four-card UI")
	display.free()
	await _test_evaluation_and_summary()
	await _test_wrong_source_and_read_only()
	await _test_preview_assembly()
	_finish()

func _test_evaluation_and_summary() -> void:
	var f := W.make_fixture(root)
	var display = load(UI).instantiate()
	display.command_source = f.commander
	display.round_source = f.round
	f.world.add_child(display)
	await physics_frame
	var area: Control = display.get_node("Panel/VBox/Evaluation")
	_expect(area.visible, "proper formal binding shows integrated region")
	var values: Label = area.get_node("Focus/Values")
	_expect(values.text.contains("100") and values.text.contains("预留"), "Focus uses existing current/reserved/available values")
	_expect(f.commander.submit_slot(0), "UI pending command admitted")
	_expect(not area.get_node("DamageInterval").visible and not area.get_node("ChainSummary").visible, "pending does not show fake countdown or zero combo")
	f.host.advance_pending_command(f.enemy,0)
	var request: SkillCommandRequest = f.requests.values().back()
	request.retain_delivery(CombatDamageContext.allocate_id())
	f.animation.release_action()
	W.deal(f,request,500)
	_expect(area.get_node("ChainSummary").visible and area.get_node("ChainSummary").text.contains("1"), "first damage updates visible combo")
	_expect(area.get_node("ScoreProgress").value == 1.0 and f.round.get_round_status().score > 100.0, "UI clamps progress without clamping score")
	_expect(area.get_node("Result").text == "终结就绪", "threshold ready is not an immediate finisher")
	W.advance(f,1)
	_expect(is_equal_approx(area.get_node("DamageInterval").value,0.5), "interval reads business half remaining")
	W.advance(f,1.000001)
	_expect(area.get_node("Result").text == "已取得终结资格", "closure shows result without pausing")
	_expect(not paused, "UI qualification never pauses")
	f.animation.finish_action()
	var next := W.start_released(f)
	W.deal(f,next,1)
	_expect(area.get_node("Result").text != "已取得终结资格", "new first hit replaces old summary immediately")
	W.advance(f,2.000001)
	_expect(area.get_node("Result").text == "连携结束", "low score end summary")
	var summary_before: float = display.get("_summary_remaining")
	paused = true
	await _wait(0.10)
	_expect(is_equal_approx(float(display.get("_summary_remaining")),summary_before), "explicit pause suspends summary presentation")
	paused = false
	await _wait(1.10)
	_expect(not area.get_node("Result").visible, "summary expires after internal one second without new business state remaining="+str(display.get("_summary_remaining")))
	_verify_controls(display)
	f.world.free()
	await process_frame

func _test_wrong_source_and_read_only() -> void:
	var f := W.make_fixture(root)
	var other := W.make_fixture(root)
	var display = load(UI).instantiate()
	display.command_source = f.commander
	display.round_source = other.round
	f.world.add_child(display)
	await physics_frame
	_expect(not display.get_node("Panel/VBox/Evaluation").visible, "different world/source cannot leak evaluation")
	display.round_source = f.round
	await process_frame
	var before: float = f.focus.get_current_focus()
	for i in range(100):
		display.call("_process",0)
		f.commander.get_slot_status(0)
	_expect(f.round.peek_current_round() == 0 and f.focus.get_current_focus() == before and f.focus.get_reserved_focus() == 0, "UI read and rebinding do not allocate/pay/reserve")
	_expect(display.get_node("Panel/VBox/Evaluation").visible, "changing only round_source refreshes binding")
	display.round_source = null
	await process_frame
	_expect(not display.get_node("Panel/VBox/Evaluation").visible, "removing optional source restores old layout")
	f.world.free()
	other.world.free()
	await process_frame

func _test_preview_assembly() -> void:
	var path := "res://Scenes/Previews/SquadChainRoundPreview.tscn"
	_expect(ResourceLoader.exists(path), "dedicated formal round preview must exist")
	if not ResourceLoader.exists(path): return
	var packed := load(path) as PackedScene
	_expect(packed.get_state().get_base_scene_state() != null, "preview is inherited not flattened")
	var preview := packed.instantiate()
	root.add_child(preview)
	current_scene = preview
	await physics_frame
	await physics_frame
	var evaluator := preview.get_node_or_null("SquadChainRoundController") as SquadChainRoundController
	_expect(preview.get_script() == null and evaluator != null, "preview root removes developer round script and adds formal evaluator")
	if evaluator != null:
		var commander: SquadChainCommandController = preview.get_node("SquadChainCommandController")
		var display := preview.get_node("SquadChainCommandDisplay") as SquadChainCommandDisplay
		_expect(evaluator.command_source == commander and display.round_source == evaluator and display.command_source == commander, "single explicit Inspector assembly")
		_expect(evaluator.peek_current_round() == 0 and evaluator.get_round_status().bound, "formal preview starts idle without development batch")
		_expect(not preview.get_node("SquadFocusDebugDisplay").visible, "preview disables duplicate focus debug via its own enabled switch")
		_expect(ResourceLoader.get_resource_uid(path) != ResourceUID.INVALID_ID, "preview has engine-registered UID")
	preview.get_node("EncounterController").call("begin_scene_unload")
	preview.free()
	current_scene = null
	await process_frame

func _wait(seconds: float) -> void:
	var deadline := Time.get_ticks_usec()+int(seconds*1000000.0)
	while Time.get_ticks_usec() < deadline: await process_frame

func _verify_controls(node: Node) -> void:
	if node is Control: _expect(node.mouse_filter == Control.MOUSE_FILTER_IGNORE and node.focus_mode == Control.FOCUS_NONE, "noninteractive native display")
	for child in node.get_children(): _verify_controls(child)
func _expect(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
func _finish() -> void:
	for message in failures: push_error(message)
	if failures.is_empty(): print("SquadChainRoundDisplayTest: PASS")
	quit(0 if failures.is_empty() else 1)
