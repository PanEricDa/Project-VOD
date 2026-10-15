@tool
class_name SquadChainRoundController
extends Node
## 关卡级连携评价；仅消费真实伤害，不支付费用、不控制技能或暂停。
enum Phase { IDLE, PENDING, ACTIVE }
@export_category("Assembly")
## 本关卡原伙伴指令源，默认空；世界、请求与队伍均沿用此源，不重复配置。
@export var command_source: SquadChainCommandController
@export_category("Evaluation")
## 距最后一次有效连携伤害的正常战斗秒数，默认2；须有限且正，下一轮生效，不是整轮总时限。
@export_range(0.01, 30.0, 0.01, "or_greater") var damage_interval_seconds: float = 2.0
## 连击换算尺度H0，单位次，默认20且至少1；下一轮生效，与伤害贡献相加。
@export_range(1, 10000, 1, "or_greater") var hit_score_scale: int = 20
## 实际扣血换算尺度D0，单位生命点，默认500且有限正；下一轮生效，不读取面板或过量伤害。
@export_range(0.01, 1000000.0, 0.1, "or_greater") var damage_score_scale: float = 500.0
## snapshot为纯值副本；状态/评分/业务剩余时间改变后通知，消费者只读使用。
signal round_state_changed(snapshot: Dictionary)
## result为曾ACTIVE轮次的结算纯值副本；每轮最多一次，空批次与解绑不发送。
signal round_finished(result: Dictionary)
## 达分轮次正常闭窗后的一次事实通知；result不拥有资格库存、暂停或技能执行权。
signal finisher_qualified(result: Dictionary)

const OWNER: StringName = &"_chain_round_owner"
var _source_ref: WeakRef
var _scope_ref: WeakRef
var _generation: int = 0
var _round_id: int = 0
var _closed_round_id: int = 0
var _phase: Phase = Phase.IDLE
var _interval: float = 0.0
var _hit_scale: int = 1
var _damage_scale: float = 1.0
var _hits: int = 0
var _damage: float = 0.0
var _score: float = 0.0
var _last_result: Dictionary = {}
var _root_teams: Dictionary = {}
var _detaching: bool = false

func _ready() -> void:
	if Engine.is_editor_hint(): return
	process_mode = Node.PROCESS_MODE_PAUSABLE
	process_physics_priority = -1000
	_refresh_binding()

func _process(_delta: float) -> void:
	if not Engine.is_editor_hint(): _refresh_binding()

## 无副作用报价查询；0表示没有可加入的新批次，不创建/结算轮次或修改账本。
func peek_current_round() -> int:
	return _round_id if _usable() else 0

## 原指令真实受理路径调用；已有轮沿用，否则捕获合法配置并分配全局单调身份，不可用返回0。
func acquire_round() -> int:
	if not _usable(): return 0
	if _round_id != 0: return _round_id
	if not _configuration_valid():
		push_warning("连携评价间隔/H0/D0必须有限且为正；拒绝建立新轮，不取消旧请求。")
		return 0
	_round_id = CombatDamageContext.allocate_id()
	_interval = damage_interval_seconds
	_hit_scale = hit_score_scale
	_damage_scale = damage_score_scale
	_phase = Phase.PENDING
	_publish()
	return _round_id

## 返回独立纯值快照；不会触发轮次创建/结算，不包含Node、Request或内部字典引用。
func get_round_status() -> Dictionary:
	return {"bound":_usable(),"phase":_phase,"round_id":_round_id,
		"hit_count":_hits,"total_damage":_damage,"score":_score,
		"progress_ratio":clampf(_score/100.0,0.0,1.0),
		"interval_seconds":_interval if _round_id > 0 else 0.0,
		"remaining_seconds":0.0,"finisher_ready":_phase == Phase.ACTIVE and _score >= 100.0,
		"last_result":_last_result.duplicate(true)}

func _configuration_valid() -> bool:
	return is_finite(damage_interval_seconds) and damage_interval_seconds > 0.0 and hit_score_scale >= 1 and is_finite(damage_score_scale) and damage_score_scale > 0.0

func _refresh_binding() -> void:
	if _detaching: return
	var previous := _source()
	if previous == command_source and previous != null: return
	_detach()
	if not is_instance_valid(command_source) or not command_source.is_inside_tree(): return
	var holder = command_source.get_meta(OWNER) if command_source.has_meta(OWNER) else null
	if holder is WeakRef and is_instance_valid(holder.get_ref()) and holder.get_ref() != self:
		push_warning("同一伙伴指令源只允许一个连携评价组件；重复装配不接管。")
		return
	_source_ref = weakref(command_source)
	command_source.set_meta(OWNER, weakref(self))
	command_source.scope_changed.connect(_on_scope_changed)
	command_source.request_activity_changed.connect(_on_activity)
	command_source.command_accepted.connect(_on_accepted)
	command_source.command_lifetime_finished.connect(_on_lifetime_finished)
	_on_scope_changed(command_source.get_bound_scope())
	if _source() != null:
		_source().set_round_source(Callable(self,"peek_current_round"), Callable(self,"acquire_round"))

func _on_scope_changed(scope: Node) -> void:
	_clear_scope()
	if not is_instance_valid(scope) or not scope.is_inside_tree() or not scope.is_ancestor_of(self): return
	_scope_ref = weakref(scope)
	_publish()

func _on_accepted(request: SkillCommandRequest) -> void:
	var scope := _scope()
	if request == null or scope == null or request.scene_scope_id != scope.get_instance_id(): return
	var actor := request.get_caster()
	if actor is UnitBase: _root_teams[request.request_id] = actor.team_id

func _on_lifetime_finished(id: int, _batch: int) -> void:
	_root_teams.erase(id)

func _on_activity(batch: int, live_requests: int) -> void:
	if batch == _round_id and _phase == Phase.PENDING and live_requests == 0:
		var old := _round_id
		_reset_round()
		var source := _source()
		if source != null: source.close_round(old)
		_publish()

func _reset_round() -> void:
	_closed_round_id = maxi(_closed_round_id, _round_id)
	_round_id = 0
	_phase = Phase.IDLE
	_hits = 0
	_damage = 0.0
	_score = 0.0
	_interval = 0.0

func _clear_scope() -> void:
	_generation += 1
	_scope_ref = null
	var old := _round_id
	_reset_round()
	_root_teams.clear()
	_last_result.clear()
	var source := _source()
	if old > 0 and source != null: source.close_round(old)

func _detach() -> void:
	if _detaching: return
	_detaching = true
	_clear_scope()
	var source := _source()
	if source != null:
		for pair in [[source.scope_changed,_on_scope_changed],[source.request_activity_changed,_on_activity],
				[source.command_accepted,_on_accepted],[source.command_lifetime_finished,_on_lifetime_finished]]:
			if pair[0].is_connected(pair[1]): pair[0].disconnect(pair[1])
		var holder = source.get_meta(OWNER) if source.has_meta(OWNER) else null
		if holder is WeakRef and holder.get_ref() == self:
			source.remove_meta(OWNER)
			source.clear_round_source(Callable(self,"peek_current_round"),Callable(self,"acquire_round"))
	_source_ref = null
	_detaching = false

func _publish() -> void:
	if not _detaching: round_state_changed.emit(get_round_status())

func _source() -> SquadChainCommandController:
	var node = _source_ref.get_ref() if _source_ref != null else null
	return node as SquadChainCommandController if is_instance_valid(node) and node.is_inside_tree() else null

func _scope() -> Node:
	var node = _scope_ref.get_ref() if _scope_ref != null else null
	return node if is_instance_valid(node) and node.is_inside_tree() and not node.is_queued_for_deletion() else null

func _usable() -> bool:
	return not _detaching and _source() != null and _scope() != null and _source().get_bound_scope() == _scope()

func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if command_source == null: warnings.append("请连接本关卡原伙伴指令源。")
	if not _configuration_valid(): warnings.append("伤害间隔/H0/D0必须有限且为正。")
	return warnings

func _exit_tree() -> void:
	if not Engine.is_editor_hint(): _detach()
