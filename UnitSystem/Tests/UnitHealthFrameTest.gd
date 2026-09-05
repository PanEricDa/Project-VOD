extends SceneTree

## 验证 UnitHealthFrame 对单个 UnitBase 的绑定、信号驱动更新与生命周期契约。
## 本测试只使用公开方法与稳定节点路径，不访问组件私有字段。

const FRAME_PATH := "res://UnitSystem/Components/UI/UnitHealthFrame.tscn"
const UNIT_PATH := "res://UnitSystem/Base/00_UnitBase.tscn"

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	_expect(ResourceLoader.exists(FRAME_PATH), "UnitHealthFrame scene exists")
	if not ResourceLoader.exists(FRAME_PATH):
		_finish()
		return

	var frame_scene := load(FRAME_PATH) as PackedScene
	var unit_scene := load(UNIT_PATH) as PackedScene
	_expect(frame_scene != null and unit_scene != null, "fixtures load")
	if frame_scene == null or unit_scene == null:
		_finish()
		return

	var frame := frame_scene.instantiate() as Control
	var first_unit := unit_scene.instantiate() as UnitBase
	first_unit.name = "测试玩家"
	first_unit.maximum_health = 200.0
	first_unit.starting_health_percentage = 75.0
	root.add_child(first_unit)
	root.add_child(frame)
	await process_frame

	_expect(frame.has_method(&"bind_unit"), "bind_unit is public")
	_expect(frame.has_method(&"unbind_unit"), "unbind_unit is public")
	_expect(frame.has_method(&"set_presentation_mode"), "presentation mode is public")
	_expect(frame.has_method(&"refresh_immediately"), "refresh is public")
	_expect(frame.has_method(&"is_bound"), "binding query is public")
	frame.call(&"bind_unit", first_unit)
	await process_frame

	var name_label := frame.get_node(^"FrameContent/CoreInfo/Header/NameLabel") as Label
	var state_label := frame.get_node(^"FrameContent/CoreInfo/Header/StateLabel") as Label
	var health_bar := frame.get_node(^"FrameContent/CoreInfo/HealthBar") as ProgressBar
	var health_value := frame.get_node(^"FrameContent/CoreInfo/HealthValue") as Label
	var extension_slot := frame.get_node(^"FrameContent/ExtensionSlot") as Control
	_expect(frame.visible and bool(frame.call(&"is_bound")), "binding shows frame")
	_expect(name_label.text == "测试玩家", "node name is the display-name fallback")
	_expect(health_value.text == "150 / 200", "initial health text is current over maximum")
	_expect(is_equal_approx(health_bar.value, 0.75), "initial ratio is correct")
	_expect(not state_label.visible and not extension_slot.visible, "unused state and extension stay collapsed")

	first_unit.apply_damage(50.0)
	await process_frame
	_expect(health_value.text == "100 / 200", "damage updates text from signal")
	_expect(is_equal_approx(health_bar.value, 0.5), "damage updates ratio from signal")

	first_unit.apply_healing(20.0)
	await process_frame
	_expect(health_value.text == "120 / 200", "healing updates text from signal")

	first_unit.apply_damage(9999.0)
	await process_frame
	_expect(frame.visible, "dead unit keeps its stable frame")
	_expect(state_label.visible and state_label.text == "倒下", "death state is explicit")
	_expect(health_value.text == "0 / 200", "lethal damage displays zero")
	_expect(first_unit.revive(40.0), "fixture revives")
	await process_frame
	_expect(not state_label.visible, "revive clears death state")
	_expect(health_value.text == "40 / 200", "revive restores health display")

	frame.call(&"unbind_unit")
	first_unit.apply_healing(10.0)
	await process_frame
	_expect(not frame.visible and not bool(frame.call(&"is_bound")), "unbind hides and clears")
	_expect(health_value.text == "0 / 0", "unbind resets the visible data")
	first_unit.apply_healing(10.0)
	await process_frame
	_expect(health_value.text == "0 / 0", "old source no longer updates after unbind")

	var second_unit := unit_scene.instantiate() as UnitBase
	second_unit.name = "第二单位"
	second_unit.maximum_health = 80.0
	root.add_child(second_unit)
	await process_frame
	frame.call(&"bind_unit", second_unit)
	frame.call(&"bind_unit", second_unit)
	second_unit.apply_damage(10.0)
	await process_frame
	_expect(health_value.text == "70 / 80", "repeat binding does not duplicate signal behavior")
	second_unit.queue_free()
	await process_frame
	_expect(not frame.visible and not bool(frame.call(&"is_bound")), "source tree exit unbinds safely")

	frame.queue_free()
	first_unit.queue_free()
	await process_frame
	_finish()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("UnitHealthFrameTest: PASS")
		quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	print("UnitHealthFrameTest: FAIL (%d)" % _failures.size())
	quit(1)
