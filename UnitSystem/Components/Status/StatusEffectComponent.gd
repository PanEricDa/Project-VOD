class_name StatusEffectComponent
extends Node

## 单位临时 Buff 与 Debuff 的统一运行时管理器。## 本组件不保存角色基础属性，也不参与死亡生命周期；它只维护可叠加、可刷新、可到期的属性修正，并由 UnitBase 的 getter 汇总为有效属性。

## 可由临时状态修正的基础属性类型。## 第一版先提供攻击与防御的有效数值接入；移动速度枚举为后续移动系统预留，当前不会自动改写任何角色移动字段。
enum ModifierStat {
	ATTACK_POWER,
	DEFENSE,
	MOVEMENT_SPEED,
}

## 同一效果再次施加时的处理规则。## REFRESH 更新同来源同属性的数值与剩余时间；STACK 保留多个独立层；REPLACE 清除该属性的全部旧修正后写入新修正。
enum StackingRule {
	REFRESH,
	STACK,
	REPLACE,
}

## 临时效果被添加或刷新后发送。## source 为运行时效果来源，stat 表示修正属性，amount 是固定增减值，remaining_duration 为剩余秒数；-1 表示永久直到被主动移除。
signal modifier_changed(source: Object, stat: ModifierStat, amount: float, remaining_duration: float)
## 临时效果被移除、到期或因单位死亡清理时发送。## source 可能已失效，调用方不得依赖其仍处于场景树。
signal modifier_removed(source: Object, stat: ModifierStat)


class ModifierRecord extends RefCounted:
	## 创建此修正的运行时对象实例 ID；用于同来源刷新和主动清理，不作为 Inspector 配置。
	var source_instance_id: int = 0
	## 创建此修正的对象弱引用；仅用于信号通知，失效后仍可安全完成数值清理。
	var source: Object
	## 被修正的属性枚举。
	var stat: ModifierStat
	## 固定的属性增减值；允许负数以表达 Debuff。
	var amount: float = 0.0
	## 剩余持续秒数；-1 表示永久效果。
	var remaining_duration: float = -1.0


## 被挂载的单位。## 仅能通过 configure_owner() 设置，防止 Buff 容器意外管理错误的角色。
var _owner_unit: UnitBase
## 当前全部生效中的修正记录；只由本组件改写，外部只能经公开接口施加或清除效果。
var _active_modifiers: Array[ModifierRecord] = []


func _ready() -> void:
	if get_parent() is UnitBase:
		configure_owner(get_parent() as UnitBase)


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	advance_effects(delta)


## 注入本组件所属单位。## owner_unit 必须有效；更换持有者会断开旧死亡信号并清空旧单位残留的全部修正。
func configure_owner(owner_unit: UnitBase) -> bool:
	if _owner_unit == owner_unit:
		return is_instance_valid(_owner_unit)
	_disconnect_owner()
	clear_all_modifiers()
	if not is_instance_valid(owner_unit):
		_owner_unit = null
		return false
	_owner_unit = owner_unit
	if not _owner_unit.died.is_connected(_on_owner_died):
		_owner_unit.died.connect(_on_owner_died)
	return true


## 添加或刷新一个临时属性修正。## source 用于识别同一效果来源；duration_seconds 大于等于 0 表示限时，负数表示永久；REFRESH 不会重复叠加同来源同属性。
func apply_modifier(
	source: Object,
	stat: ModifierStat,
	amount: float,
	duration_seconds: float,
	stacking_rule: StackingRule = StackingRule.REFRESH
) -> bool:
	if not is_instance_valid(_owner_unit) or source == null:
		return false
	var source_id: int = source.get_instance_id()
	var normalized_duration: float = duration_seconds if duration_seconds < 0.0 else maxf(duration_seconds, 0.0)
	if stacking_rule == StackingRule.REFRESH:
		for record: ModifierRecord in _active_modifiers:
			if record.source_instance_id == source_id and record.stat == stat:
				record.amount = amount
				record.remaining_duration = normalized_duration
				record.source = source
				modifier_changed.emit(source, stat, amount, normalized_duration)
				return true
	elif stacking_rule == StackingRule.REPLACE:
		_remove_matching_stat(stat)

	var created := ModifierRecord.new()
	created.source_instance_id = source_id
	created.source = source
	created.stat = stat
	created.amount = amount
	created.remaining_duration = normalized_duration
	_active_modifiers.append(created)
	modifier_changed.emit(source, stat, amount, normalized_duration)
	return true


## 推进全部限时修正的倒计时。## delta 必须为非负秒数；到期修正将在本次调用内移除，永久效果不会被推进。
func advance_effects(delta: float) -> void:
	if delta <= 0.0:
		return
	for index: int in range(_active_modifiers.size() - 1, -1, -1):
		var record := _active_modifiers[index]
		if record.remaining_duration < 0.0:
			continue
		record.remaining_duration = maxf(record.remaining_duration - delta, 0.0)
		if record.remaining_duration <= 0.0:
			_remove_at(index)


## 返回指定属性在所有生效状态下的固定修正总和。## 正值为 Buff、负值为 Debuff；未存在任何修正时返回 0。
func get_modifier_total(stat: ModifierStat) -> float:
	var total: float = 0.0
	for record: ModifierRecord in _active_modifiers:
		if record.stat == stat:
			total += record.amount
	return total


## 返回当前效果数量，仅供 Inspector 调试、测试与未来状态栏读取。## 不返回内部记录，避免外部绕过叠加和清理规则。
func get_active_modifier_count() -> int:
	return _active_modifiers.size()


## 清理指定来源创建的全部效果。## source 必须是原始效果对象；适用于驱散、技能卸载或外部状态结束。
func remove_modifiers_from_source(source: Object) -> void:
	if source == null:
		return
	var source_id: int = source.get_instance_id()
	for index: int in range(_active_modifiers.size() - 1, -1, -1):
		if _active_modifiers[index].source_instance_id == source_id:
			_remove_at(index)


## 清空全部临时与永久属性修正。## 单位死亡或状态容器更换持有者时调用；不会改写 UnitBase 的基础属性配置。
func clear_all_modifiers() -> void:
	for index: int in range(_active_modifiers.size() - 1, -1, -1):
		_remove_at(index)


func _on_owner_died(_source: Node) -> void:
	clear_all_modifiers()


func _remove_matching_stat(stat: ModifierStat) -> void:
	for index: int in range(_active_modifiers.size() - 1, -1, -1):
		if _active_modifiers[index].stat == stat:
			_remove_at(index)


func _remove_at(index: int) -> void:
	if index < 0 or index >= _active_modifiers.size():
		return
	var record := _active_modifiers[index]
	_active_modifiers.remove_at(index)
	modifier_removed.emit(record.source, record.stat)


func _disconnect_owner() -> void:
	if is_instance_valid(_owner_unit) and _owner_unit.died.is_connected(_on_owner_died):
		_owner_unit.died.disconnect(_on_owner_died)
	_owner_unit = null
