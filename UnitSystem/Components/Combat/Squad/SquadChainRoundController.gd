@tool
class_name SquadChainRoundController
extends Node
## 关卡级连携评价；仅消费真实伤害，不支付费用、不控制技能或暂停。
enum Phase { IDLE, PENDING, ACTIVE }
@export_category("Assembly")
## 本关卡原伙伴指令源，默认空；世界、请求与队伍均沿用此源，不重复配置。
@export var command_source: SquadChainCommandController
@export_category("Evaluation")
## 评分难度，无单位，默认5为曲线评分的标准倍率，并不沿用旧线性分数；须有限且大于0，Inspector最低0.1。曲线总分乘5/本值，越低越容易达100分；本轮受理时捕获，编辑只影响下一轮，不改变实际伤害或连击；评分达到100后会影响动态伤害间隔。
@export_range(0.1, 10.0, 0.1, "or_greater") var score_difficulty: float = 5.0
## 基础伤害间隔，单位正常战斗秒，默认2.5；评分不超过100时完整保留，超过100后按指数曲线缩短。须有限且正，本轮受理时捕获，下一轮生效，不是整轮总时限。
@export_range(0.01, 30.0, 0.01, "or_greater") var damage_interval_seconds: float = 2.5
## 达标后可缩短到的最短伤害间隔，单位正常战斗秒，默认0.8；须有限且正。高于基础间隔时按基础值处理，不反向延长窗口；本轮受理时捕获，只影响连携闭窗与倒数显示。
@export_range(0.01, 30.0, 0.01, "or_greater") var minimum_damage_interval_seconds: float = 0.8
## 达到最短间隔所需的综合评分，默认150；须有限且大于100。100到本值之间先陡后缓地指数缩短，到达后保持最短间隔；本轮受理时捕获，不改变评分公式或终结伤害。
@export_range(100.01, 10000.0, 0.1, "or_greater") var minimum_interval_score: float = 150.0
## 连击曲线基准H0，单位次，默认10且至少1；达到本基准时贡献40分（难度5），之后仍加分但边际递减。下一轮生效，不改变实际命中计数。
@export_range(1, 10000, 1, "or_greater") var hit_score_scale: int = 10
## 伤害曲线基准D0，单位实际生命损失，默认100且有限正；累计达到本基准时贡献60分（难度5），按1.1次幂温和加速。下一轮生效，不读取面板或过量伤害，不按单笔伤害分别取幂。
@export_range(0.01, 1000000.0, 0.1, "or_greater") var damage_score_scale: float = 100.0
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
var _base_interval: float = 0.0
var _minimum_interval: float = 0.0
var _minimum_interval_score: float = 150.0
var _hit_scale: int = 1
var _damage_scale: float = 1.0
var _score_multiplier: float = 1.0
var _hits: int = 0
var _damage: float = 0.0
var _score: float = 0.0
var _last_result: Dictionary = {}
var _root_teams: Dictionary = {}
var _detaching: bool = false
var _clock_usec: int = 0
var _clock_fraction: float = 0.0
var _clock_frame: int = 0
var _deadline_usec: int = 0
var _observed: Dictionary = {}
var _events: Dictionary = {}
var _hit_keys: Dictionary = {}

func _ready() -> void:
	if Engine.is_editor_hint(): return
	process_mode = Node.PROCESS_MODE_PAUSABLE
	process_physics_priority = -1000
	_refresh_binding()

func _process(_delta: float) -> void:
	if not Engine.is_editor_hint(): _refresh_binding()

## 无副作用报价查询；0表示没有可加入的新批次，不创建/结算轮次或修改账本。
func peek_current_round() -> int:
	return _round_id if _usable() and not _expired() else 0

## 原指令真实受理路径调用；已有轮沿用，否则捕获合法配置并分配全局单调身份，不可用返回0。
func acquire_round() -> int:
	if not _usable(): return 0
	var generation := _generation
	_close_expired()
	if generation != _generation or not _usable(): return 0
	if _round_id != 0: return _round_id
	if not _configuration_valid():
		push_warning("连携评分/窗口配置无效：难度、基础/最短间隔和H0/D0须为有限正数，最短间隔评分须大于100；拒绝新轮，不取消旧请求。")
		return 0
	_round_id = CombatDamageContext.allocate_id()
	_base_interval = damage_interval_seconds
	_minimum_interval = minf(minimum_damage_interval_seconds,_base_interval)
	_minimum_interval_score = minimum_interval_score
	_interval = _base_interval
	_hit_scale = hit_score_scale
	_damage_scale = damage_score_scale
	_score_multiplier = 5.0/score_difficulty
	_phase = Phase.PENDING
	_publish()
	return _round_id

## 返回独立纯值快照；interval_seconds为当前评分下的实际伤害间隔，remaining_seconds为其业务剩余秒数。查询不创建/结算轮次，不包含Node、Request或内部字典引用。
func get_round_status() -> Dictionary:
	return {"bound":_usable(),"phase":_phase,"round_id":_round_id,
		"hit_count":_hits,"total_damage":_damage,"score":_score,
		"progress_ratio":clampf(_score/100.0,0.0,1.0),
		"interval_seconds":_interval if _round_id > 0 else 0.0,
		"remaining_seconds":maxf(float(_deadline_usec-_clock_usec)/1000000.0,0.0) if _phase == Phase.ACTIVE else 0.0,"finisher_ready":_phase == Phase.ACTIVE and _score >= 100.0,
		"last_result":_last_result.duplicate(true)}

func _configuration_valid() -> bool:
	return (
		is_finite(score_difficulty) and score_difficulty > 0.0
		and is_finite(damage_interval_seconds) and damage_interval_seconds > 0.0
		and is_finite(minimum_damage_interval_seconds) and minimum_damage_interval_seconds > 0.0
		and is_finite(minimum_interval_score) and minimum_interval_score > 100.0
		and hit_score_scale >= 1 and is_finite(damage_score_scale) and damage_score_scale > 0.0
	)

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
	scope.tree_exiting.connect(_on_scope_exiting)
	get_tree().node_added.connect(_on_node_added)
	_scan_units(scope)
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
	_base_interval = 0.0
	_minimum_interval = 0.0
	_minimum_interval_score = 150.0
	_deadline_usec = 0
	_events.clear()
	_hit_keys.clear()

func _clear_scope() -> void:
	_generation += 1
	var old_scope := _scope()
	if old_scope != null and old_scope.tree_exiting.is_connected(_on_scope_exiting):
		old_scope.tree_exiting.disconnect(_on_scope_exiting)
	if is_inside_tree() and get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.disconnect(_on_node_added)
	for id in _observed.keys(): _on_unit_exiting(id)
	_scope_ref = null
	_clock_usec = 0
	_clock_fraction = 0.0
	_clock_frame = 0
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


# 唯一正常战斗时基；暂停时Godot不调度本节点。帧身份只防重复，不用于换算时间。
func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or not _usable() or not is_finite(delta) or delta < 0.0: return
	var microseconds := delta*1000000.0+_clock_fraction
	var whole := floori(microseconds+0.0000001)
	_clock_fraction = maxf(microseconds-float(whole),0.0)
	_clock_usec += whole
	_clock_frame += 1
	_finish_frame.call_deferred(_clock_frame,_generation)
	if _phase == Phase.ACTIVE: _publish()

# 只处理本会话本帧；落后/重复帧无效，严格超过deadline才闭窗。
func _finish_frame(frame_id: int, generation: int) -> void:
	if generation != _generation or frame_id != _clock_frame or not _usable(): return
	_close_expired()

func _expired() -> bool:
	return _phase == Phase.ACTIVE and _clock_usec > _deadline_usec

func _close_expired() -> void:
	if not _expired(): return
	var scope := _scope()
	if scope == null: return
	var result := {"round_id":_round_id,"scene_scope_id":scope.get_instance_id(),
		"hit_count":_hits,"total_damage":_damage,"score":_score,
		"qualified":_score >= 100.0,"close_reason":&"damage_gap"}
	var generation := _generation
	_reset_round()
	_last_result = result.duplicate(true)
	var source := _source()
	if source != null: source.close_round(result.round_id)
	if generation != _generation or not _usable(): return
	round_finished.emit(result.duplicate(true))
	if generation != _generation or not _usable(): return
	if result.qualified: finisher_qualified.emit(result.duplicate(true))
	if generation == _generation and _usable(): _publish()

# 接收时同步查原请求；不能延迟到帧末，瞬发交付届时可能已自然清理。
func _on_damage_resolved(event: CombatDamageEvent, generation: int) -> void:
	if generation != _generation or not _usable() or event == null: return
	_close_expired()
	if generation != _generation or not _usable(): return
	if event.round_id <= _closed_round_id or event.round_id != _round_id or _round_id == 0: return
	if event.origin != CombatDamageContext.Origin.CHAIN or not is_finite(event.actual_damage) or event.actual_damage <= 0.0: return
	if event.scene_scope_id != _scope().get_instance_id() or not _observed.has(event.target_instance_id): return
	if not _root_teams.has(event.request_id) or event.source_team_id == 0 or event.source_team_id != _root_teams[event.request_id]: return
	if event.target_team_id == 0 or event.target_team_id == event.source_team_id: return
	if not _source().is_released_request(event.request_id,event.round_id,event.source_instance_id,event.scene_scope_id): return
	if _events.has(event.event_id): return
	_events[event.event_id] = true
	var hit_key := "%d:%d:%d" % [event.request_id,event.hit_id,event.target_instance_id]
	if not _hit_keys.has(hit_key):
		_hit_keys[hit_key] = true
		_hits += 1
	_damage += event.actual_damage
	# 只对本轮累计H/D重算曲线；同一命中拆分多个伤害效果不会改变伤害项。
	var hit_points := 40.0*log(1.0+float(_hits)/float(_hit_scale))/log(2.0)
	var damage_points := 60.0*pow(_damage/_damage_scale,1.1)
	_score = (hit_points+damage_points)*_score_multiplier
	_phase = Phase.ACTIVE
	_interval = _interval_for_score(_score)
	_deadline_usec = _clock_usec+roundi(_interval*1000000.0)
	_publish()

# 只读本轮快照：100分连续衔接基础间隔，到指定分数精确落到下限；指数3为内部形状，不额外暴露调参。
# 仅在有效伤害计分后重设deadline；等待期间不因查询/Inspector编辑再次压缩倒计时。
func _interval_for_score(score: float) -> float:
	if score <= 100.0: return _base_interval
	if score >= _minimum_interval_score: return _minimum_interval
	var progress := (score-100.0)/(_minimum_interval_score-100.0)
	var tail := exp(-3.0)
	var weight := (exp(-3.0*progress)-tail)/(1.0-tail)
	return clampf(lerpf(_minimum_interval,_base_interval,weight),_minimum_interval,_base_interval)

func _scan_units(node: Node) -> void:
	if node is UnitBase: _observe(node)
	for child in node.get_children(): _scan_units(child)

func _observe(unit: UnitBase) -> void:
	var id := unit.get_instance_id()
	if _observed.has(id): return
	var damage_callback := _on_damage_resolved.bind(_generation)
	var exit_callback := _on_unit_exiting.bind(id)
	_observed[id] = {"ref":weakref(unit),"damage":damage_callback,"exit":exit_callback}
	unit.damage_resolved.connect(damage_callback)
	unit.tree_exiting.connect(exit_callback)

func _on_node_added(node: Node) -> void:
	var scope := _scope()
	if node is UnitBase and scope != null and scope.is_ancestor_of(node): _observe(node)

func _on_unit_exiting(id: int) -> void:
	if not _observed.has(id): return
	var record: Dictionary = _observed[id]
	var unit = record.ref.get_ref()
	if is_instance_valid(unit):
		if unit.damage_resolved.is_connected(record.damage): unit.damage_resolved.disconnect(record.damage)
		if unit.tree_exiting.is_connected(record.exit): unit.tree_exiting.disconnect(record.exit)
	_observed.erase(id)

func _on_scope_exiting() -> void:
	_clear_scope()
	_publish()

func _publish() -> void:
	if not _detaching: round_state_changed.emit(get_round_status())

func _source() -> SquadChainCommandController:
	var node = _source_ref.get_ref() if _source_ref != null else null
	return node as SquadChainCommandController if is_instance_valid(node) and node.is_inside_tree() else null

func _scope() -> Node:
	var node = _scope_ref.get_ref() if _scope_ref != null else null
	return node if is_instance_valid(node) and node.is_inside_tree() and not node.is_queued_for_deletion() else null

func _usable() -> bool:
	return is_inside_tree() and not is_queued_for_deletion() and not _detaching and _source() != null and _scope() != null and _source().get_bound_scope() == _scope()

func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if command_source == null: warnings.append("请连接本关卡原伙伴指令源。")
	if not _configuration_valid(): warnings.append("评分难度、基础/最短伤害间隔和H0/D0须为有限正数；最短间隔评分须有限且大于100。")
	return warnings

func _exit_tree() -> void:
	if not Engine.is_editor_hint(): _detach()
