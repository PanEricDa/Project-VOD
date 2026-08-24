class_name ThreatDebugDisplay
extends Node3D

## 仅用于测试的敌方本地仇恨表显示器。
## 它只订阅同级现有组件的公开信号并保存显示缓存，绝不计算、提交或修改任何仇恨与锁定结果。

const THREAT_COMPONENT_NAME: StringName = &"ThreatComponent"
const TARGETING_COMPONENT_NAME: StringName = &"AITargetingComponent"

## 是否显示运行时仇恨调试文本；关闭后仅隐藏标签，不会暂停或影响任意核心战斗逻辑。
@export var debug_display_enabled: bool = true:
	set(value):
		debug_display_enabled = value
		_refresh_label()


## 是否在调试标签的原始仇恨数值后附加相对百分比；基准为当前锁定目标的正仇恨，缺失时退回本地最高值，默认开启且只影响调试文本。
@export var show_threat_percentage: bool = true:
	set(value):
		show_threat_percentage = value
		_refresh_label()

## 调试标签相对敌人根节点的本地高度与偏移，单位为米；默认位于血条上方。
@export var local_offset: Vector3 = Vector3(0.0, 1.45, 0.0):
	set(value):
		local_offset = value
		if is_instance_valid(_label):
			_label.position = local_offset

## 最多显示的正仇恨来源数量；超出部分只隐藏显示，不会影响真实仇恨表或目标选择。
@export_range(1, 12, 1) var maximum_entries: int = 4:
	set(value):
		maximum_entries = max(value, 1)
		_refresh_label()

@onready var _label: Label3D = $ThreatLabel

## 同级真实仇恨组件的只读信号来源；以 Node 保存以避免调试组件成为核心系统的类型依赖。
var _threat_component: Node
## 同级真实目标组件的只读锁定来源；仅用来读取当前已经确定的目标。
var _targeting_component: Node
## 由 threat_changed 事件建立的显示缓存，键为来源实例 ID；它不是核心仇恨表的副本或写入入口。
var _display_threat_by_source_id: Dictionary = {}
## 与显示数值对应的来源引用；刷新时会主动排除已释放实例。
var _source_by_id: Dictionary = {}


func _ready() -> void:
	_label.position = local_offset
	_label.visible = false
	_connect_observed_components()
	_refresh_label()


## 查找 EnemyBase 下约定名称的同级组件并订阅其现有公开信号。
## 缺少任一组件时安静地保持隐藏，使该调试场景可被独立预览而不产生核心配置警告。
func _connect_observed_components() -> void:
	var owner_node := get_parent()
	if not is_instance_valid(owner_node):
		return
	_threat_component = owner_node.get_node_or_null(NodePath(THREAT_COMPONENT_NAME))
	_targeting_component = owner_node.get_node_or_null(NodePath(TARGETING_COMPONENT_NAME))
	if is_instance_valid(_threat_component) and _threat_component.has_signal(&"threat_changed"):
		_threat_component.connect(&"threat_changed", _on_threat_changed)
		if _threat_component.has_signal(&"threat_cleared"):
			_threat_component.connect(&"threat_cleared", _on_threat_cleared)
	if is_instance_valid(_targeting_component) and _targeting_component.has_signal(&"locked_target_changed"):
		_targeting_component.connect(&"locked_target_changed", _on_locked_target_changed)


## 接收真实仇恨组件的变动通知，仅把结果用于调试文本缓存。
## source 必须是有效 UnitBase；current_value 不大于零时从显示列表移除。
func _on_threat_changed(
	source: UnitBase,
	_previous_value: float,
	current_value: float
) -> void:
	if not is_instance_valid(source):
		return
	var source_id: int = source.get_instance_id()
	if current_value <= 0.0:
		_display_threat_by_source_id.erase(source_id)
		_source_by_id.erase(source_id)
	else:
		_display_threat_by_source_id[source_id] = current_value
		_source_by_id[source_id] = source
	_refresh_label()


## 接收真实目标组件已经做出的锁定结果；本组件不会自行选择或变更任何目标。
func _on_locked_target_changed(
	_previous_target: UnitBase,
	_current_target: UnitBase
) -> void:
	_refresh_label()


## 接收真实仇恨组件的清表通知并清理调试缓存。
## 该显示器不保存第二份权威数据；清表后只保留空缓存并刷新标签。
func _on_threat_cleared() -> void:
	_display_threat_by_source_id.clear()
	_source_by_id.clear()
	_refresh_label()


## 清理失效来源、排序显示缓存，并将当前锁定目标和最高四项写入世界空间标签。
func _refresh_label() -> void:
	if not is_instance_valid(_label):
		return
	var entries := _get_sorted_valid_entries()
	_label.visible = debug_display_enabled and not entries.is_empty()
	if not _label.visible:
		_label.text = ""
		return

	var locked_target := _get_current_locked_target()
	var locked_value: float = _get_cached_threat(locked_target)
	var locked_name: String = str(locked_target.name) if is_instance_valid(locked_target) else "--"
	var relative_reference: float = _get_relative_reference(locked_value, entries)
	var lines: PackedStringArray = [
		"Target: %s%s" % [locked_name, _format_threat_value(locked_value, relative_reference)]
	]
	var displayed_count: int = min(entries.size(), maximum_entries)
	for entry_index: int in displayed_count:
		var entry: Dictionary = entries[entry_index]
		var source := entry["source"] as UnitBase
		var marker := ">" if source == locked_target else " "
		lines.append(
			"%s %s%s" % [
				marker,
				source.name,
				_format_threat_value(float(entry["value"]), relative_reference)
			]
		)
	_label.text = "\n".join(lines)


## 返回调试百分比的比较基准；有有效锁定目标时固定以该目标为 100%，从而直观显示超过 125% 换目标阈值的挑战者。
## locked_value 是当前锁定目标的本地缓存仇恨；entries 已按值降序排列，仅在锁定目标无有效仇恨时提供安全回退基准。
func _get_relative_reference(locked_value: float, entries: Array[Dictionary]) -> float:
	if locked_value > 0.0:
		return locked_value
	return float(entries[0]["value"])


## 将原始仇恨数值格式化为调试文本；relative_reference 必须来自同一敌人的锁定目标正仇恨或安全回退最高值，避免将百分比误作全局或结算数值。
func _format_threat_value(value: float, relative_reference: float) -> String:
	var formatted_value := " %.1f" % value
	if not show_threat_percentage or relative_reference <= 0.0:
		return formatted_value
	var relative_percentage: float = value / relative_reference * 100.0
	return "%s (%.0f%%)" % [formatted_value, relative_percentage]


## 返回按仇恨值从高到低排列的有效显示记录，并同步清理已失效的对象引用。
func _get_sorted_valid_entries() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for source_id: Variant in _source_by_id.keys():
		var source := _source_by_id.get(source_id) as UnitBase
		if not is_instance_valid(source):
			_display_threat_by_source_id.erase(source_id)
			_source_by_id.erase(source_id)
			continue
		var value: float = float(_display_threat_by_source_id.get(source_id, 0.0))
		if value <= 0.0:
			_display_threat_by_source_id.erase(source_id)
			_source_by_id.erase(source_id)
			continue
		entries.append({"source": source, "value": value})
	entries.sort_custom(_sort_entries_by_descending_threat)
	return entries


## 供 Array.sort_custom 使用的排序规则：数值高者排在前；相同数值以实例 ID 保持稳定顺序。
func _sort_entries_by_descending_threat(left: Dictionary, right: Dictionary) -> bool:
	var left_value: float = float(left["value"])
	var right_value: float = float(right["value"])
	if not is_equal_approx(left_value, right_value):
		return left_value > right_value
	var left_source := left["source"] as UnitBase
	var right_source := right["source"] as UnitBase
	return left_source.get_instance_id() < right_source.get_instance_id()


## 从真实目标组件读取已经锁定的目标；缺失接口或无效对象时安全返回 null。
func _get_current_locked_target() -> UnitBase:
	if (
		not is_instance_valid(_targeting_component)
		or not _targeting_component.has_method(&"get_locked_target")
	):
		return null
	return _targeting_component.call(&"get_locked_target") as UnitBase


## 返回显示缓存中的数值；没有记录或对象无效时使用零值，仅用于标签第一行。
func _get_cached_threat(source: UnitBase) -> float:
	if not is_instance_valid(source):
		return 0.0
	return float(_display_threat_by_source_id.get(source.get_instance_id(), 0.0))
