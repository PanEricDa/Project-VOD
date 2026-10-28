class_name PressReleaseInputComponent
extends Node
## 单个输入域的按下／松开状态；不监听InputMap，不持有技能、UI、冷却或时间。
## 每个适配器各装一个实例；不同实例不共享运行时状态。

## slot_index为当前预选槽，-1表示清空；这是反馈通知，不代表技能已经受理。
signal selection_changed(slot_index: int)

var _pressed_slot: int = -1
var _identity: int = 0

## slot_index须>=0，由适配器保证槽上限；identity是原内容的数字身份，默认0表示不校验内容身份。
## 已有预选时不接受重复或其他槽，避免同时按键覆盖原意图。
func begin_press(slot_index: int, identity: int = 0) -> bool:
	if slot_index < 0 or _pressed_slot >= 0: return false
	_pressed_slot = slot_index
	_identity = identity
	selection_changed.emit(slot_index)
	return true

## 只有同槽松开才清空预选；identity须与按下时相同。
## true仅代表一次确认意图，调用者仍须检查当前合法性；错槽不影响原预选，身份改变只取消。
func end_press(slot_index: int, identity: int = 0) -> bool:
	if slot_index < 0 or slot_index != _pressed_slot: return false
	var confirmed := identity == _identity
	cancel_selection()
	return confirmed

## 幂等清空预选；不发送确认，不取消已经执行的技能。
func cancel_selection() -> void:
	if _pressed_slot < 0: return
	_pressed_slot = -1
	_identity = 0
	selection_changed.emit(-1)

## 只读预选槽；-1表示没有预选，不推进任何流程。
func get_pressed_slot() -> int:
	return _pressed_slot

## 只读验证原槽和不透明身份；用于适配器在内容被拆卸／替换时取消旧输入。
func matches_selection(slot_index: int, identity: int) -> bool:
	return _pressed_slot >= 0 and _pressed_slot == slot_index and _identity == identity

func _exit_tree() -> void:
	_pressed_slot = -1
	_identity = 0
