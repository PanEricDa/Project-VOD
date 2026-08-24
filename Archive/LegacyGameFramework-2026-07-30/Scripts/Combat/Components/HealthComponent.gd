class_name HealthComponent
extends "res://Scripts/Combat/Components/ResourcePoolComponent.gd"

## 生命资源专用组件。
##
## 该类复用 ResourcePoolComponent 的通用数值边界，只补充伤害、治疗、死亡和
## 复活语义。它不会删除持有者、停止 AI、修改碰撞或播放表现。

## 成功扣除生命时发送，amount 始终为正数并代表实际扣除量。
signal damaged(amount: float, source: Node)

## 成功恢复生命时发送，amount 始终为正数并代表实际恢复量。
signal healed(amount: float, source: Node)

## 生命从正数降到 0 时发送，每次死亡边界只发送一次。
signal died(source: Node)

## 通过 revive() 从死亡状态恢复时发送。
signal revived(current_health: float, source: Node)

## 复活所允许的最小正生命值，防止传入 0 时仍停留在死亡状态。
const MINIMUM_REVIVE_VALUE: float = 0.001


## 应用生命默认值并监听通用资源池的耗尽边界。
func _ready() -> void:
	resource_id = &"health"
	super._ready()
	if not depleted.is_connected(_on_health_depleted):
		depleted.connect(_on_health_depleted)


## 扣除生命并返回实际扣除量。负数、零值或已经死亡时不会产生变化。
func apply_damage(amount: float, source: Node = null) -> float:
	if amount <= 0.0 or is_dead():
		return 0.0
	var applied_delta: float = modify_value(-amount, source)
	var actual_damage: float = absf(minf(applied_delta, 0.0))
	if actual_damage > 0.0:
		damaged.emit(actual_damage, source)
	return actual_damage


## 恢复生命并返回实际恢复量。普通治疗不能让死亡目标复活，必须显式调用 revive()。
func apply_healing(amount: float, source: Node = null) -> float:
	if amount <= 0.0 or is_dead():
		return 0.0
	var applied_delta: float = modify_value(amount, source)
	var actual_healing: float = maxf(applied_delta, 0.0)
	if actual_healing > 0.0:
		healed.emit(actual_healing, source)
	return actual_healing


## 返回当前生命是否已经耗尽。
func is_dead() -> bool:
	return is_empty()


## 显式复活死亡目标。
## 仅在最大生命为正且目标当前死亡时成功；传入值会限制到最小正值与最大生命之间。
func revive(value: float = 1.0, source: Node = null) -> bool:
	if not is_dead() or maximum_value <= 0.0:
		return false
	var revive_value: float = clampf(maxf(value, MINIMUM_REVIVE_VALUE), 0.0, maximum_value)
	if set_current_value(revive_value, source) <= 0.0:
		return false
	revived.emit(current_value, source)
	return true


## 把通用耗尽边界转发为生命专用死亡语义。
func _on_health_depleted(source: Node) -> void:
	died.emit(source)
