class_name PlayerSkillInputComponent
extends Node

## 只将InputMap输入转换为静态槽号；按下预选，松开才发送一次施法意图。
## slot_index从零开始；技能合法性、目标和普攻抢占仍由PlayerSkillController处理。
signal slot_requested(slot_index: int)

@export_category("Skill Input")
## 第一常规技能的InputMap动作名；默认player_skill_1（Q），只影响玩家槽0的新请求。
@export var skill_1_action: StringName = &"player_skill_1"
## 第二常规技能的InputMap动作名；默认player_skill_2（E），只影响玩家槽1的新请求。
@export var skill_2_action: StringName = &"player_skill_2"

const Interaction = preload("res://UnitSystem/Components/Input/PressReleaseInputComponent.gd")
const INTERACTION_SCENE: PackedScene = preload("res://UnitSystem/Components/Input/PressReleaseInputComponent.tscn")
var _input_enabled: bool = true
var _interaction: Interaction
var _held: Array[bool] = [false,false]
var _pressed_action: StringName = &""

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_interaction = get_node_or_null("PressReleaseInputComponent") as Interaction
	# 场景装配是常规入口；直接new本适配器时也使用相同模板，不创建另一套状态机。
	if _interaction == null:
		_interaction = INTERACTION_SCENE.instantiate() as Interaction
		add_child(_interaction)

## enabled仅控制新输入，默认true；false清空尚未确认的预选，不取消已开始的动作。
func set_input_enabled(enabled: bool) -> void:
	_input_enabled = enabled
	if not enabled: _cancel_selection()

## 只读反馈槽，-1代表没有预选；不发施法请求，UI可以独立卸载。
func get_pressed_slot() -> int:
	return _interaction.get_pressed_slot() if is_instance_valid(_interaction) else -1

func _process(_delta: float) -> void:
	# GUI可能消费松开事件，失焦也只清Input状态；丢失release时取消，不补发施法。
	for index in range(2):
		var action := _action(index)
		if _held[index] and (not InputMap.has_action(action) or not Input.is_action_pressed(action)):
			_held[index] = false
			if get_pressed_slot() == index: _cancel_selection()
	var slot := get_pressed_slot()
	if slot < 0: return
	if not _can_input() or _pressed_action != _action(slot) or not _interaction.matches_selection(slot,_slot_identity(slot)):
		_cancel_selection()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo(): return
	for slot in range(2):
		var action := _action(slot)
		if not InputMap.has_action(action) or not event.is_action(action): continue
		var released := event.is_action_released(action)
		if released: _held[slot] = false
		if not _can_input():
			_cancel_selection()
			return
		get_viewport().set_input_as_handled()
		if event.is_action_pressed(action):
			if _held[slot]: return
			_held[slot] = true
			if _interaction.begin_press(slot,_slot_identity(slot)): _pressed_action = action
		elif released:
			if _pressed_action != action: return
			_pressed_action = &""
			if _interaction.end_press(slot,_slot_identity(slot)): slot_requested.emit(slot)
		return

func _can_input() -> bool:
	var unit := get_parent() as PlayerBase
	return _input_enabled and is_inside_tree() and not get_tree().paused and unit != null and not unit.is_dead() and unit.is_player_input_enabled()

func _action(slot: int) -> StringName:
	return skill_1_action if slot == 0 else skill_2_action

func _slot_identity(slot: int) -> int:
	# 仅取只读数字身份防止按住期间换装；不缓存技能，也不复制合法性规则。
	var controller := get_parent().get_node_or_null("PlayerSkillController") as PlayerSkillController
	return int(controller.get_slot_status(slot).get("skill_instance_id",0)) if controller != null else 0

func _cancel_selection() -> void:
	_pressed_action = &""
	if is_instance_valid(_interaction): _interaction.cancel_selection()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_held.fill(false)
		_cancel_selection()

func _exit_tree() -> void:
	_cancel_selection()
