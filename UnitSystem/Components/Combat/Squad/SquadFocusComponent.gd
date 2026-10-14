class_name SquadFocusComponent
extends Node
## 场景级专注池；只消费实际事件，不决定技能或连携窗口，不依赖玩家存活。
## 三个资源参数与一个装配开关；账目、身份和监听连接均为内部运行状态。

@export_category("Focus")
## 专注容量，单位为专注点，默认 100；有限正数。初始化/reset 时生效，不改变正在预留的事务。
@export_range(0.01, 1000000.0, 0.1, "or_greater") var maximum_focus: float = 100.0
## 初始化专注点，默认 0，限制在容量内；只在新绑定或 reset 时应用，不随 UI 刷新重置。
@export_range(0.0, 1000000.0, 0.1, "or_greater") var initial_focus: float = 0.0
## 每点有效常规伤害换算的专注点，默认 0.1 仅为开发占位；0 关闭收益。只影响本队资源，不改变伤害。
@export_range(0.0, 100.0, 0.01, "or_greater") var damage_to_focus_ratio: float = 0.1
@export_category("Assembly")
## 默认自动绑定父场景的唯一玩家及同队伙伴；关闭用于代码显式 bind_scope，不影响资源事务。
@export var auto_bind_parent: bool = true

## 资源实际改变后通知只读 UI；current 包括未提交预留，available=current-reserved。
signal focus_changed(current: float, reserved: float, available: float)
## 绑定世界改变；解绑在reset前通知null，所有者可先归还旧预留，重复绑定不通知。
signal scope_changed(scope_root: Node)

var _capacity: float = 100.0
var _current: float = 0.0
var _transactions: Dictionary = {}
var _scope: Node
var _party: Dictionary = {}
var _observed: Dictionary = {}
var _generation: int = 0
var _consumer_key: StringName
# 新绑定仅接收此水位之后发布的事件；不保存全部历史事件。
var _event_floor: int = 0
var _last_values: Array = []
var _party_team: int = 0
var _automatic: bool = false
# 解绑同步通知期间不接受重入绑定；旧监听与事务先完整清理。
var _unbinding: bool = false

func _ready() -> void:
	reset_focus()
	if auto_bind_parent: call_deferred(&"_auto_bind")

func _exit_tree() -> void:
	unbind_scope()

## 绑定一处有效世界和明确队伍；party 内单位须为 scope 后代且同一非中立队伍，重复项去重。
## 重复绑定相同世界/名单不重置资源；新世界先解绑旧监听和预留，失败关闭。
## 解绑同步回调中重入绑定返回false，须在外层解绑完成后再调用；不报告尚未成立的新会话。
func bind_scope(scope_root: Node, party: Array[UnitBase]) -> bool:
	if _unbinding: return false
	var ids: Dictionary = {}
	var team: int = 0
	if not is_instance_valid(scope_root) or not scope_root.is_inside_tree():
		unbind_scope()
		return false
	for unit in party:
		if not is_instance_valid(unit) or not unit.is_inside_tree() or not scope_root.is_ancestor_of(unit) or unit.team_id == 0:
			unbind_scope()
			return false
		if team != 0 and team != unit.team_id:
			unbind_scope()
			return false
		team = unit.team_id
		ids[unit.get_instance_id()] = unit.team_id
	if ids.is_empty():
		unbind_scope()
		return false
	if _scope == scope_root and _party == ids: return true
	unbind_scope()
	_scope = scope_root
	_party = ids
	_party_team = team
	_generation += 1
	if _consumer_key.is_empty(): _consumer_key = StringName("focus:%d" % get_instance_id())
	_event_floor = CombatDamageContext.allocate_id()
	_scan_units(_scope)
	get_tree().node_added.connect(_on_node_added)
	_scope.tree_exiting.connect(_on_scope_exiting)
	scope_changed.emit(_scope)
	return true

## 断开当前世界监听、清空本会话承诺；不携带旧专注或事件到下一场景。
func unbind_scope() -> void:
	if _unbinding: return
	_unbinding = true
	var old_scope: Node = _scope
	var was_bound: bool = is_instance_valid(old_scope)
	_scope = null
	_generation += 1
	if was_bound: scope_changed.emit(null)
	if is_inside_tree() and get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.disconnect(_on_node_added)
	if is_instance_valid(old_scope) and old_scope.tree_exiting.is_connected(_on_scope_exiting):
		old_scope.tree_exiting.disconnect(_on_scope_exiting)
	for record in _observed.values():
		var unit = record.ref.get_ref()
		if is_instance_valid(unit):
			if unit.damage_resolved.is_connected(record.callback): unit.damage_resolved.disconnect(record.callback)
			if unit.tree_exiting.is_connected(record.exit): unit.tree_exiting.disconnect(record.exit)
	_observed.clear()
	_party.clear()
	_party_team = 0
	_scope = null
	_automatic = false
	reset_focus()
	_unbinding = false

## 当前仍有效且在树中的绑定世界；空表示已解绑，不能由调用方修改绑定状态。
func get_bound_scope() -> Node:
	return _scope if is_instance_valid(_scope) and _scope.is_inside_tree() else null

## 检查当前单位是否属于绑定队伍及世界；不把存活/施法许可混入成员身份。
func is_party_member(unit: UnitBase) -> bool:
	return is_instance_valid(unit) and unit.is_inside_tree() and get_bound_scope() != null and _scope.is_ancestor_of(unit) and _party.get(unit.get_instance_id(), 0) == unit.team_id and unit.team_id != 0

## 返回当前会话实际容量；Inspector 容量变更须 reset 后生效，供只读 UI 使用。
func get_maximum_focus() -> float: return _capacity

## 返回池内总专注，包含已预留但未提交的金额。
func get_current_focus() -> float: return _current
## 返回全部有效预留总额，终态不计入。
func get_reserved_focus() -> float:
	var total: float = 0.0
	for t in _transactions.values():
		if t.state == 0: total += t.amount
	return total
## 返回可供新指令承诺的余额，不为负。
func get_available_focus() -> float: return maxf(_current - get_reserved_focus(), 0.0)

## 正 request_id 对应唯一资源事务，amount 为有限非负专注点；同 ID 同金额预留幂等。
func reserve(request_id: int, amount: float) -> bool:
	if request_id <= 0 or not is_finite(amount) or amount < 0.0: return false
	if _transactions.has(request_id):
		var old = _transactions[request_id]
		return old.state == 0 and old.amount == amount
	if amount > get_available_focus(): return false
	_transactions[request_id] = {"amount": amount, "state": 0}
	_notify()
	return true

## 查询本request是否仍有可提交承诺；纯读，金额有限非负且不超过本请求预留，不借其他请求余额。
func can_commit(request_id: int, final_amount: float) -> bool:
	if not is_finite(final_amount) or final_amount < 0.0 or not _transactions.has(request_id): return false
	var t = _transactions[request_id]
	return t.state == 0 and final_amount <= t.amount

## 提交本request最终费用，不超过其预留；重复提交拒绝，成功不提供提交后退款。
func commit(request_id: int, final_amount: float) -> bool:
	if not can_commit(request_id, final_amount): return false
	var t = _transactions[request_id]
	t.state = 1
	_current -= final_amount
	_notify()
	return true

## 释放前失败归还未提交承诺，不向池里加钱；重复退款无副作用。
func refund(request_id: int) -> bool:
	if not _transactions.has(request_id) or _transactions[request_id].state != 0: return false
	_transactions[request_id].state = 2
	_notify()
	return true

## 回调生命周期结束后清理终态，尚有预留时拒绝，调用方须先 commit/refund。
func release_request(request_id: int) -> bool:
	if not _transactions.has(request_id) or _transactions[request_id].state == 0: return false
	_transactions.erase(request_id)
	return true

## 显式初始化新资源会话；清理事务，重新读取容量与初始值，不是游戏输入操作。
func reset_focus() -> void:
	_capacity = maximum_focus if is_finite(maximum_focus) and maximum_focus > 0.0 else 100.0
	_current = clampf(initial_focus, 0.0, _capacity) if is_finite(initial_focus) else 0.0
	_transactions.clear()
	_notify()

func _notify() -> void:
	var values = [_current, get_reserved_focus(), get_available_focus(), _capacity]
	if values == _last_values: return
	_last_values = values
	focus_changed.emit(values[0], values[1], values[2])

func _auto_bind() -> void:
	if not auto_bind_parent or is_instance_valid(_scope): return
	var parent = get_parent()
	if not is_instance_valid(parent): return
	var units: Array[UnitBase] = []
	_collect_units(parent, units)
	var players = units.filter(func(u): return u.faction_id == "Player")
	if players.size() != 1:
		push_warning("SquadFocusComponent: automatic binding requires exactly one Player.")
		return
	var party: Array[UnitBase] = [players[0]]
	for u in units:
		if u.faction_id == "Ally" and u.team_id == players[0].team_id: party.append(u)
	if bind_scope(parent, party): _automatic = true

func _collect_units(node: Node, units: Array[UnitBase]) -> void:
	if node is UnitBase: units.append(node)
	for child in node.get_children(): _collect_units(child, units)

func _scan_units(node: Node) -> void:
	if node is UnitBase: _observe(node)
	for child in node.get_children(): _scan_units(child)

func _observe(unit: UnitBase) -> void:
	var id = unit.get_instance_id()
	if _observed.has(id): return
	var callback = _on_damage_resolved.bind(_generation)
	var exiting = _on_unit_exiting.bind(id)
	_observed[id] = {"ref": weakref(unit), "callback": callback, "exit": exiting}
	unit.damage_resolved.connect(callback)
	unit.tree_exiting.connect(exiting)
	if _automatic and unit.faction_id == "Ally" and unit.team_id == _party_team:
		_party[id] = unit.team_id

func _on_node_added(node: Node) -> void:
	if node is UnitBase and is_instance_valid(_scope) and _scope.is_ancestor_of(node): _observe(node)

func _on_unit_exiting(id: int) -> void:
	if not _observed.has(id): return
	var record = _observed[id]
	var unit = record.ref.get_ref()
	if is_instance_valid(unit):
		if unit.damage_resolved.is_connected(record.callback): unit.damage_resolved.disconnect(record.callback)
		if unit.tree_exiting.is_connected(record.exit): unit.tree_exiting.disconnect(record.exit)
	_observed.erase(id)
	# 队伍来源身份快照保留到解绑，已发出的伤害不因角色死亡而丢失归属。

func _on_scope_exiting() -> void:
	unbind_scope()

func _on_damage_resolved(event: CombatDamageEvent, generation: int) -> void:
	if generation != _generation or not is_instance_valid(_scope) or event == null: return
	if event.event_id <= _event_floor: return
	if event.scene_scope_id != _scope.get_instance_id() or not _party.has(event.source_instance_id) or not _observed.has(event.target_instance_id): return
	if event.source_team_id == 0 or event.source_team_id != _party[event.source_instance_id] or event.target_team_id == 0 or event.target_team_id == event.source_team_id: return
	if not is_finite(damage_to_focus_ratio) or damage_to_focus_ratio <= 0.0 or not is_finite(event.actual_damage) or event.actual_damage <= 0.0: return
	if event.focus_yield_multiplier <= 0.0 or not event.claim(_consumer_key): return
	var gain = event.actual_damage * event.focus_yield_multiplier * damage_to_focus_ratio
	if not is_finite(gain): return
	_current = minf(_current + gain, _capacity)
	_notify()
