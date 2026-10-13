extends SceneTree
## 只读显示必须反映预留和可用值；解绑与来源销毁不能写回资源或访问失效节点。
var failures: Array[String] = []
func _initialize() -> void: call_deferred(&"_run")
func _run() -> void:
	var path = "res://UnitSystem/Components/UI/SquadFocusDebugDisplay.tscn"
	if not ResourceLoader.exists(path):
		failures.append("focus debug scene missing")
		_finish()
		return
	_expect(ResourceLoader.get_resource_uid(path) != ResourceUID.INVALID_ID, "display saved UID")
	var focus = SquadFocusComponent.new()
	focus.auto_bind_parent = false
	focus.initial_focus = 50.0
	root.add_child(focus)
	var display = load(path).instantiate()
	display.debug_enabled = true
	root.add_child(display)
	display.bind_focus(focus)
	_expect(display.get_node("Panel/VBox/Values").text.contains("50.0"), "initial readout")
	focus.reserve(9, 20.0)
	_expect(display.get_node("Panel/VBox/Values").text.contains("30.0") and focus.get_current_focus() == 50.0, "available readout not spend")
	display.debug_enabled = false
	_expect(not display.visible, "runtime disable immediately hides")
	display.debug_enabled = true
	_expect(display.visible, "runtime enable immediately shows")
	focus.maximum_focus = 200.0
	focus.refund(9)
	_expect(display.get_node("Panel/VBox/Bar").max_value == 100.0, "display uses effective initialized capacity")
	focus.reset_focus()
	_expect(display.get_node("Panel/VBox/Bar").max_value == 200.0, "capacity-only reset notifies display")
	focus.free()
	_expect(not display.visible, "invalid source safely hidden")
	display.free()
	_finish()
func _expect(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
func _finish() -> void:
	for f in failures: push_error(f)
	if failures.is_empty(): print("SquadFocusDebugDisplayTest: PASS")
	quit(0 if failures.is_empty() else 1)
