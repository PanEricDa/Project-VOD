extends SceneTree

## 仇恨调试显示的独立契约测试。
## 使用测试专用的信号节点验证显示组件只消费既有事件，避免对核心仇恨逻辑产生写入依赖。
const DISPLAY_SCENE_PATH := "res://UnitSystem/Debug/Threat/ThreatDebugDisplay.tscn"
const UNIT_SCENE_PATH := "res://UnitSystem/Base/00_UnitBase.tscn"

var _failures: Array[String] = []
var _world: Node3D


class FakeThreatComponent extends Node:
	## 模拟既有 ThreatComponent 对外发送的只读变化事件。
	signal threat_changed(source: UnitBase, previous_value: float, current_value: float)


class FakeTargetingComponent extends Node:
	## 模拟既有 AITargetingComponent 对外发送的锁定目标变化事件。
	signal locked_target_changed(previous_target: UnitBase, current_target: UnitBase)
	var locked_target: UnitBase

	## 返回当前锁定目标；接口与真实目标组件一致。
	func get_locked_target() -> UnitBase:
		return locked_target if is_instance_valid(locked_target) else null


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_world = Node3D.new()
	_world.name = "ThreatDebugDisplayTestWorld"
	root.add_child(_world)

	var display_scene := load(DISPLAY_SCENE_PATH) as PackedScene
	_expect(display_scene != null, "ThreatDebugDisplay scene exists")
	if display_scene == null:
		_finish()
		return

	var enemy := Node3D.new()
	enemy.name = "Enemy"
	_world.add_child(enemy)
	var fake_threat := FakeThreatComponent.new()
	fake_threat.name = "ThreatComponent"
	enemy.add_child(fake_threat)
	var fake_targeting := FakeTargetingComponent.new()
	fake_targeting.name = "AITargetingComponent"
	enemy.add_child(fake_targeting)
	var display := display_scene.instantiate()
	enemy.add_child(display)

	var hero := _create_unit("Hero")
	var guardian := _create_unit("Guardian")
	await process_frame

	var label := display.get_node_or_null("ThreatLabel") as Label3D
	_expect(label != null, "display contains a ThreatLabel")
	if label == null:
		_finish()
		return
	_expect(not label.visible, "display remains hidden when no threat exists")

	fake_threat.threat_changed.emit(guardian, 0.0, 13.0)
	fake_threat.threat_changed.emit(hero, 0.0, 17.0)
	fake_targeting.locked_target = guardian
	fake_targeting.locked_target_changed.emit(null, guardian)
	await process_frame

	_expect(label.visible, "positive threat makes the debug display visible")
	_expect(label.text.contains("Target: Guardian 13.0"), "locked target and current threat are shown")
	_expect(label.text.contains("> Guardian 13.0"), "locked table entry receives a marker")
	_expect(label.text.contains("Guardian 13.0"), "other threat sources remain visible")
	_expect(label.text.contains("Guardian 13.0 (100%)"), "locked target is the 100 percent threat reference")
	_expect(label.text.contains("Hero 17.0 (131%)"), "challenger percentage can exceed the 125 percent switch threshold")
	_expect(
		label.text.find("Hero 17.0") < label.text.find("> Guardian 13.0"),
		"entries are sorted by threat from high to low"
	)

	display.show_threat_percentage = false
	await process_frame
	_expect(not label.text.contains("%"), "percentage display can be disabled without changing cached threat values")

	_finish()


## 创建用于发送仇恨事件的最小 UnitBase 实例。
func _create_unit(unit_name: String) -> UnitBase:
	var scene := load(UNIT_SCENE_PATH) as PackedScene
	var unit := scene.instantiate() as UnitBase
	unit.name = unit_name
	_world.add_child(unit)
	return unit


## 记录失败信息，全部断言结束后统一以非零退出码报告。
func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


## 清理测试世界并输出唯一的测试结论。
func _finish() -> void:
	if is_instance_valid(_world):
		_world.queue_free()
	if _failures.is_empty():
		print("ThreatDebugDisplayTest: PASS")
		quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	print("ThreatDebugDisplayTest: FAIL (%d)" % _failures.size())
	quit(1)
