class_name PlayerThreatFocusController
extends Node

## 玩家锁定敌人的仇恨提示协调器。
## 本组件只读取 PlayerBase、EnemyThreatComponent 和 AITargetingComponent 已有的状态，向各单位 WorldHealthBar 写入纯视觉外框；绝不提交仇恨、修改锁定目标或驱动 AI。
const WORLD_HEALTH_BAR_PATH: NodePath = ^"WorldUIRoot/WorldHealthBar"

## 当前由玩家锁定、且正在提供本地仇恨数据的敌人。
## 只在该敌人有效且仍位于场景树中时保留，切换玩家锁定后会先解除旧敌人的信号连接。
var _focused_enemy: UnitBase
## 焦点敌人的本地仇恨组件，只通过公开快照和查询接口读取。
var _focused_threat_component: Node
## 焦点敌人的 AI 锁定组件，只读取其已经确定的当前目标。
var _focused_targeting_component: Node
## 本次刷新曾写入外框的单位集合。
## 每次重算前统一清除，保证玩家解锁、仇恨清表、目标死亡或焦点切换后不会留下陈旧提示。
var _outlined_units_by_id: Dictionary = {}


func _ready() -> void:
	_connect_player()
	_refresh_focus()


func _exit_tree() -> void:
	_disconnect_focused_enemy()
	_clear_outlined_units()


## 接收玩家已完成的锁定结果。
## target 为玩家新锁定的 UnitBase，可能为 null；本组件不验证或改写玩家锁定规则，只据此刷新表现层。
func _on_player_locked_target_changed(_target: UnitBase) -> void:
	_refresh_focus()


## 接收焦点敌人的仇恨条目变化。
## 参数仅用于满足 EnemyThreatComponent 信号约定；每次变化均重新读取完整只读快照，避免维护第二份仇恨表。
func _on_focused_threat_changed(
	_source: UnitBase,
	_previous_value: float,
	_current_value: float
) -> void:
	_refresh_outlines()


## 接收焦点敌人的仇恨表清空通知。
## 清表后没有当前仇恨目标，必须立即移除本轮所有红色与黄色外框。
func _on_focused_threat_cleared() -> void:
	_refresh_outlines()


## 接收焦点敌人已经确定的 AI 锁定结果。
## previous_target 与 current_target 只由 AITargetingComponent 管理；本组件仅据此决定哪一个单位显示红框。
func _on_focused_enemy_locked_target_changed(
	_previous_target: UnitBase,
	_current_target: UnitBase
) -> void:
	_refresh_outlines()


func _connect_player() -> void:
	var player := get_parent() as PlayerBase
	if not is_instance_valid(player):
		push_warning(
			"PlayerThreatFocusController: parent must be PlayerBase. Node="
			+ str(get_path())
		)
		return
	if not player.locked_target_changed.is_connected(_on_player_locked_target_changed):
		player.locked_target_changed.connect(_on_player_locked_target_changed)


func _refresh_focus() -> void:
	var player := get_parent() as PlayerBase
	var player_target: UnitBase = player.get_locked_target() if is_instance_valid(player) else null
	if player_target == _focused_enemy and _has_valid_focus_interfaces():
		_refresh_outlines()
		return

	_disconnect_focused_enemy()
	_clear_outlined_units()
	if not is_instance_valid(player_target) or not player_target.is_inside_tree():
		return
	if not player_target.has_method(&"get_threat_component"):
		return

	var threat_component: Node = player_target.call(&"get_threat_component") as Node
	var targeting_component: Node = (
		player_target.call(&"get_targeting_component") as Node
		if player_target.has_method(&"get_targeting_component")
		else null
	)
	if (
		not is_instance_valid(threat_component)
		or not threat_component.has_method(&"get_threat_snapshot")
		or not threat_component.has_method(&"get_threat_for")
		or not threat_component.has_signal(&"threat_changed")
		or not threat_component.has_signal(&"threat_cleared")
		or not is_instance_valid(targeting_component)
		or not targeting_component.has_method(&"get_locked_target")
		or not targeting_component.has_signal(&"locked_target_changed")
	):
		return

	_focused_enemy = player_target
	_focused_threat_component = threat_component
	_focused_targeting_component = targeting_component
	_focused_threat_component.connect(&"threat_changed", _on_focused_threat_changed)
	_focused_threat_component.connect(&"threat_cleared", _on_focused_threat_cleared)
	_focused_targeting_component.connect(
		&"locked_target_changed",
		_on_focused_enemy_locked_target_changed
	)
	_refresh_outlines()


func _disconnect_focused_enemy() -> void:
	if is_instance_valid(_focused_threat_component):
		if _focused_threat_component.is_connected(&"threat_changed", _on_focused_threat_changed):
			_focused_threat_component.disconnect(&"threat_changed", _on_focused_threat_changed)
		if _focused_threat_component.is_connected(&"threat_cleared", _on_focused_threat_cleared):
			_focused_threat_component.disconnect(&"threat_cleared", _on_focused_threat_cleared)
	if is_instance_valid(_focused_targeting_component):
		if _focused_targeting_component.is_connected(
			&"locked_target_changed",
			_on_focused_enemy_locked_target_changed
		):
			_focused_targeting_component.disconnect(
				&"locked_target_changed",
				_on_focused_enemy_locked_target_changed
			)
	_focused_enemy = null
	_focused_threat_component = null
	_focused_targeting_component = null


func _refresh_outlines() -> void:
	_clear_outlined_units()
	if not _has_valid_focus_interfaces():
		return

	var current_target := _focused_targeting_component.call(&"get_locked_target") as UnitBase
	if not _is_valid_display_unit(current_target):
		return
	var current_threat: float = float(
		_focused_threat_component.call(&"get_threat_for", current_target)
	)
	if current_threat <= 0.0:
		return

	_set_outline(
		current_target,
		WorldHealthBar.ThreatIndicatorState.CURRENT_TARGET
	)
	var warning_limit: float = current_threat * EnemyThreatComponent.TARGET_SWITCH_THREAT_RATIO
	var threat_snapshot: Array = _focused_threat_component.call(
		&"get_threat_snapshot"
	) as Array
	for entry: Dictionary in threat_snapshot:
		var source := entry.get("source") as UnitBase
		var threat_value: float = float(entry.get("value", 0.0))
		if (
			source == current_target
			or not _is_valid_display_unit(source)
			or threat_value < current_threat
			or threat_value > warning_limit
		):
			continue
		_set_outline(source, WorldHealthBar.ThreatIndicatorState.WARNING)


func _has_valid_focus_interfaces() -> bool:
	return (
		is_instance_valid(_focused_enemy)
		and _focused_enemy.is_inside_tree()
		and is_instance_valid(_focused_threat_component)
		and is_instance_valid(_focused_targeting_component)
	)


func _is_valid_display_unit(unit: UnitBase) -> bool:
	return (
		is_instance_valid(unit)
		and unit.is_inside_tree()
		and not unit.is_dead()
	)


func _set_outline(unit: UnitBase, state: int) -> void:
	var health_bar := unit.get_node_or_null(WORLD_HEALTH_BAR_PATH) as WorldHealthBar
	if not is_instance_valid(health_bar):
		return
	health_bar.set_threat_indicator_state(state)
	_outlined_units_by_id[unit.get_instance_id()] = unit


func _clear_outlined_units() -> void:
	for outlined_unit: Variant in _outlined_units_by_id.values():
		var unit := outlined_unit as UnitBase
		if not is_instance_valid(unit):
			continue
		var health_bar := unit.get_node_or_null(WORLD_HEALTH_BAR_PATH) as WorldHealthBar
		if is_instance_valid(health_bar):
			health_bar.clear_threat_indicator()
	_outlined_units_by_id.clear()
