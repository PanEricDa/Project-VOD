extends SceneTree
## 真InputMap事件路由、持键防穿透、四项十字与视口布局；不把直接调用当按键验证。
const F = preload("res://UnitSystem/Tests/SquadFinisherSelectionControllerTest.gd")
const DISPLAY = "res://UnitSystem/Components/UI/SquadFinisherSelectionDisplay.tscn"
var failures: Array[String] = []

func _initialize() -> void: call_deferred(&"_run")
func _run() -> void:
	if not ResourceLoader.exists(DISPLAY):
		_expect(false,"missing finisher cross display scene")
		_finish()
		return
	if OS.get_cmdline_user_args().has("--review-only"):
		await _test_closing_event_owned_and_unbound_release()
		_finish()
		return
	await _test_fixed_cross_and_readonly_display()
	await _test_each_slot_input()
	await _test_held_repeat_multikey_no_leak()
	await _test_input_map_rebinding()
	await _test_closing_event_owned_and_unbound_release()
	await _test_preview_inherits_original()
	_finish()

func _four(f: Dictionary) -> void:
	var slots: Array[AllyBase] = [f.actor]
	for index in range(3):
		var actor = load("res://UnitSystem/AI/Ally/Units/Priest.tscn").instantiate()
		actor.name = "Partner"+str(index+2)
		actor.automatic_skill_cast_enabled = false
		actor.gravity_multiplier = 0
		f.world.add_child(actor)
		actor.set_physics_process(false)
		slots.append(actor)
	f.commander.companions = slots
	f.commander.call("_refresh_configuration")
	f.selection.call("_process",0.0)

func _test_fixed_cross_and_readonly_display() -> void:
	var f := F.make_selection_fixture(root)
	await physics_frame
	var viewport := SubViewport.new()
	viewport.size = Vector2i(2560,1440)
	root.add_child(viewport)
	var display = load(DISPLAY).instantiate()
	display.selection_source = f.selection
	viewport.add_child(display)
	F.qualify(f)
	await process_frame
	var cross: Control = display.get_node("Root/Cross")
	var left: Control = cross.get_node("Slot1")
	var top: Control = cross.get_node("Slot2")
	var right: Control = cross.get_node("Slot3")
	var bottom: Control = cross.get_node("Slot4")
	_expect(left.position.x < top.position.x and top.position.y < left.position.y and right.position.x > top.position.x and bottom.position.y > left.position.y,"fixed left1 up2 right3 down4")
	_expect(left.get_node("VBox/Actor").text == String(f.actor.name),"slot name from actual companion")
	var reserve: float = f.focus.get_reserved_focus()
	for size: Vector2i in [Vector2i(2560,1440),Vector2i(1920,1080),Vector2i(1280,720),Vector2i(960,540)]:
		viewport.size = size
		await process_frame
		await process_frame
		for path: String in ["Slot1","Slot2","Slot3","Slot4","Countdown"]:
			var control := cross.get_node(path) as Control
			var rect := control.get_global_rect()
			_expect(rect.position.x >= 0 and rect.position.y >= 0 and rect.end.x <= size.x+1 and rect.end.y <= size.y+1,"visible rect "+str(size)+" "+path)
	_expect(f.focus.get_reserved_focus() == reserve,"UI never reserves focus")
	await _wait(0.05)
	_expect(cross.get_node("Countdown").value < 1 and cross.get_node("Countdown").value > 0,"real countdown visible")
	_verify_controls(display)
	display.selection_source = null
	await process_frame
	_expect(not display.get_node("Root").visible,"unbound display hides without cancelling flow")
	_expect(f.selection.get_selection_status().phase != 0,"display is not flow owner")
	viewport.free()
	f.world.free()
	await process_frame

func _test_each_slot_input() -> void:
	for index in range(4):
		var f := F.make_selection_fixture(root)
		_four(f)
		await physics_frame
		await process_frame
		var chosen: Array = []
		var accepted: Array = []
		f.selection.finisher_selected.connect(func(result): chosen.append(result))
		F.qualify(f)
		f.commander.command_accepted.connect(func(request): accepted.append(request))
		_event(index,true)
		_expect(chosen.size() == 1 and chosen[0].slot_index == index,"physical intent routes exact slot "+str(index))
		_expect(accepted.is_empty(),"choice never becomes chain")
		_event(index,false)
		await _wait(0.26)
		_expect(is_equal_approx(Engine.time_scale,1),"close restores after input")
		f.world.free()
		await process_frame

func _test_held_repeat_multikey_no_leak() -> void:
	var f := F.make_selection_fixture(root)
	_four(f)
	await physics_frame
	await process_frame
	Input.action_press(&"squad_chain_1")
	F.qualify(f)
	var chosen: Array = []
	var accepted: Array = []
	f.selection.finisher_selected.connect(func(result): chosen.append(result))
	f.commander.command_accepted.connect(func(request): accepted.append(request))
	_event(0,true)
	_expect(chosen.is_empty(),"held across open must release first")
	_event(0,false)
	_event(0,true)
	_event(1,true)
	_expect(chosen.size() == 1,"same frame multikey one choice")
	await _wait(0.27)
	_event(0,true)
	_expect(accepted.is_empty(),"held tail after close cannot leak to chain")
	_event(0,false)
	_event(1,false)
	f.animation.finish_action()
	_event(0,true)
	_expect(accepted.size() == 1,"fresh press after release returns to chain")
	_event(0,false)
	f.world.free()
	await process_frame

func _test_input_map_rebinding() -> void:
	var f := F.make_selection_fixture(root)
	await physics_frame
	var saved := InputMap.action_get_events(&"squad_chain_1")
	InputMap.action_erase_events(&"squad_chain_1")
	var binding := InputEventKey.new()
	binding.physical_keycode = KEY_K
	InputMap.action_add_event(&"squad_chain_1",binding)
	F.qualify(f)
	var chosen: Array = []
	f.selection.finisher_selected.connect(func(result): chosen.append(result))
	var event := InputEventKey.new()
	event.physical_keycode = KEY_K
	event.keycode = KEY_K
	event.pressed = true
	event.echo = true
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	_expect(chosen.is_empty(),"keyboard echo ignored")
	event = event.duplicate()
	event.echo = false
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	_expect(chosen.size() == 1,"InputMap remap works without hardcoded1")
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	Input.action_release(&"squad_chain_1")
	InputMap.action_erase_events(&"squad_chain_1")
	for original: InputEvent in saved: InputMap.action_add_event(&"squad_chain_1",original)
	f.world.free()
	await process_frame

func _test_closing_event_owned_and_unbound_release() -> void:
	var f := F.make_selection_fixture(root)
	_four(f)
	await physics_frame
	await process_frame
	F.qualify(f)
	_expect(f.selection.get_selection_status().phase != 0,"boundary fixture must own an open window")
	var accepted: Array = []
	f.commander.command_accepted.connect(func(request): accepted.append(request))
	f.commander.command_rejected.connect(func(slot,_reason): accepted.append(slot))
	f.selection.try_select_slot(0)
	f.selection.set_process(false)
	f.selection.set("_last_usec",Time.get_ticks_usec()-350000)
	_event(0,true)
	_expect(accepted.is_empty() and f.selection.get_selection_status().phase == 0,"event that completes closing cannot become chain")
	_event(0,false)
	f.world.free()
	await process_frame
	f = F.make_selection_fixture(root)
	await physics_frame
	F.qualify(f)
	_event(0,true)
	f.selection.round_source = null
	f.selection.call("_process",0.0)
	_event(0,false)
	f.selection.round_source = f.round
	f.selection.call("_process",0.0)
	var resumed: Array = []
	f.commander.command_accepted.connect(func(request): resumed.append(request))
	f.animation.finish_action()
	_event(0,true)
	_expect(resumed.size() == 1,"release while unbound does not swallow next fresh press")
	_event(0,false)
	f.world.free()
	await process_frame

func _test_preview_inherits_original() -> void:
	var path := "res://Scenes/Previews/SquadFinisherSelectionPreview.tscn"
	if not ResourceLoader.exists(path):
		_expect(false,"missing independent inherited finisher preview")
		return
	var scene: PackedScene = load(path)
	var state := scene.get_state()
	_expect(state.get_base_scene_state() != null and state.get_base_scene_state().get_path() == "res://Scenes/Previews/SquadChainRoundPreview.tscn","preview is genuinely inherited not expanded copy")
	var preview := scene.instantiate()
	root.add_child(preview)
	current_scene = preview
	await physics_frame
	await process_frame
	var selection := preview.get_node("SquadFinisherSelectionController")
	var display := preview.get_node("SquadFinisherSelectionDisplay")
	_expect(selection.round_source == preview.get_node("SquadChainRoundController") and selection.pause_source == preview.get_node("ChainSkillPresentationController/PauseCoordinator"),"references use original world sources")
	_expect(display.selection_source == selection,"display wired")
	var caster := preview.get_node("Caster") as AllyBase
	var enemy := preview.get_node("EnemyContainer/Pack_A/GoblinWarrior") as UnitBase
	caster.global_position = enemy.global_position + Vector3(0,0,3)
	caster.get_targeting_component().call("_set_locked_target",enemy)
	_expect(preview.get_node_or_null("SquadFinisherExecutionController") != null, "preview now includes real execution component")
	var round_controller: SquadChainRoundController = preview.get_node("SquadChainRoundController")
	var result := {"round_id":CombatDamageContext.allocate_id(),"scene_scope_id":preview.get_instance_id(),"qualified":true}
	round_controller.set("_last_result",result)
	round_controller.finisher_qualified.emit(result)
	_expect(selection.get_selection_status().phase != 0 and is_equal_approx(Engine.time_scale,0.05),"preview actually consumes qualification without manual binding")
	selection.cancel_selection(&"preview_probe")
	round_controller.set("_last_result",{})
	_expect(_count_pause(preview) == 1,"only one pause coordinator")
	for resource: String in [path,DISPLAY,"res://UnitSystem/Components/Combat/Squad/SquadFinisherSelectionController.tscn"]:
		_expect(ResourceLoader.get_resource_uid(resource) != ResourceUID.INVALID_ID,"scene UID valid "+resource)
	preview.get_node("EncounterController").begin_scene_unload()
	current_scene = null
	preview.free()
	await process_frame

func _count_pause(node: Node) -> int:
	var result := 1 if node is GamePauseCoordinator else 0
	for child: Node in node.get_children(): result += _count_pause(child)
	return result

func _event(slot: int, pressed: bool) -> void:
	var event := InputEventAction.new()
	event.action = StringName("squad_chain_%d" % (slot+1))
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()
func _verify_controls(node: Node) -> void:
	if node is Control: _expect(node.mouse_filter == Control.MOUSE_FILTER_IGNORE and node.focus_mode == Control.FOCUS_NONE,"pure display ignores mouse/focus")
	for child: Node in node.get_children(): _verify_controls(child)
func _wait(seconds: float) -> void:
	var deadline := Time.get_ticks_usec()+int(seconds*1000000)
	while Time.get_ticks_usec() < deadline: await process_frame
func _expect(ok: bool, label: String) -> void:
	if not ok: failures.append(label)
func _finish() -> void:
	for index in range(4): Input.action_release(StringName("squad_chain_%d" % (index+1)))
	Engine.time_scale = 1
	paused = false
	for label: String in failures: push_error(label)
	if failures.is_empty(): print("SquadFinisherSelectionInputDisplayTest: PASS")
	quit(0 if failures.is_empty() else 1)
