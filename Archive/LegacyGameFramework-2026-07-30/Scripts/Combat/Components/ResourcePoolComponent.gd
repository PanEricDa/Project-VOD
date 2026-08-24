class_name ResourcePoolComponent
extends Node

## 通用数值资源池。
##
## 该组件只负责维护一个处于 0 到最大值之间的浮点资源，可复用于生命、法力、
## 体力或饱腹度。它不理解伤害、施法、角色类型等上层游戏语义。

## 当资源的实际数值发生变化时发送。
## source 用于把本次数值变化追溯到技能、单位或其他发起节点；允许为空。
signal value_changed(
	previous_value: float,
	current_value: float,
	maximum_value: float,
	source: Node
)

## 资源从正数首次降到 0 时发送，重复写入 0 不会再次发送。
signal depleted(source: Node)

## 资源从 0 恢复为正数时发送，便于上层系统监听恢复边界。
signal restored_from_empty(source: Node)

@export_category("Resource Pool")
## 资源的稳定标识。未来通用消耗或效果系统可通过该字段查找 mana、stamina 等资源。
@export var resource_id: StringName = &"resource"

## 资源最大值。进入场景树时会确保其不小于 0。
@export_range(0.0, 999999.0, 0.1, "or_greater") var maximum_value: float = 100.0

## 每次实例进入运行状态时使用的初始值，并自动限制在 0 到最大值之间。
@export_range(0.0, 999999.0, 0.1, "or_greater") var starting_value: float = 100.0

## 当前运行时资源值。该字段不导出，避免把运行时变化误写回场景配置。
var current_value: float = 0.0


## 规范化 Inspector 配置并建立初始运行值；初始化本身不发送变化信号。
func _ready() -> void:
	maximum_value = maxf(maximum_value, 0.0)
	starting_value = clampf(starting_value, 0.0, maximum_value)
	current_value = starting_value


## 返回当前资源值。
func get_current_value() -> float:
	return current_value


## 返回当前最大值。通过方法读取可让未来最大值修正逻辑不影响调用方接口。
func get_maximum_value() -> float:
	return maximum_value


## 返回 0 到 1 的资源比例；最大值为 0 时安全返回 0，避免除零错误。
func get_value_ratio() -> float:
	if maximum_value <= 0.0:
		return 0.0
	return clampf(current_value / maximum_value, 0.0, 1.0)


## 判断资源是否已经耗尽。
func is_empty() -> bool:
	return current_value <= 0.0


## 把资源直接设置为指定值，并返回经过边界限制后实际应用的有符号变化量。
## 正数返回值代表增加，负数代表减少，0 代表没有发生有效变化。
func set_current_value(value: float, source: Node = null) -> float:
	var previous_value: float = current_value
	var next_value: float = clampf(value, 0.0, maxf(maximum_value, 0.0))
	if next_value == previous_value:
		return 0.0

	current_value = next_value
	var applied_delta: float = current_value - previous_value
	value_changed.emit(previous_value, current_value, maximum_value, source)
	if previous_value > 0.0 and current_value <= 0.0:
		depleted.emit(source)
	elif previous_value <= 0.0 and current_value > 0.0:
		restored_from_empty.emit(source)
	return applied_delta


## 在当前值基础上增加或减少资源，并返回实际应用的有符号变化量。
func modify_value(amount: float, source: Node = null) -> float:
	return set_current_value(current_value + amount, source)


## 原子性消耗指定数量的资源。
## 数量为负或资源不足时返回 false 且完全不修改当前值；消耗 0 合法且不发送信号。
func try_consume(amount: float, source: Node = null) -> bool:
	if amount < 0.0 or amount > current_value:
		return false
	if is_zero_approx(amount):
		return true
	modify_value(-amount, source)
	return true


## 将资源恢复到最大值。已经满值时保持安静，不发送冗余信号。
func restore_full(source: Node = null) -> void:
	set_current_value(maximum_value, source)
