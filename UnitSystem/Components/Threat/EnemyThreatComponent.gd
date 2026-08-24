class_name EnemyThreatComponent
extends Node

## 敌方单位的本地仇恨表与统一结算入口。
## 本组件只记录威胁并在候选者之间给出优先级；唯一 locked_target 仍由 AITargetingComponent 保存。

## 某个有效来源的本地仇恨值发生变化时发送。
## source 是提交事件的单位；previous_value 与 current_value 均为该敌人本地表中的最终仇恨点数。
signal threat_changed(
	source: UnitBase,
	previous_value: float,
	current_value: float
)

## 本地仇恨表从非空状态被清空时发送。
## 该信号仅供血条提示、调试显示等只读表现层清除缓存；不会要求或允许接收者修改目标选择结果。
signal threat_cleared()

## 未覆盖单位配置时使用的默认夺回仇恨倍率。
## 默认 1.25 表示普通挑战者必须严格超过当前目标的 125%；实际比较读取挑战者 UnitBase 的倍率，本常量继续供默认值与风险提示 UI 共用。
const TARGET_SWITCH_THREAT_RATIO: float = 1.25
## 衰减曲线在峰值（r=0.5）之外的保留速度比例，防止 r 接近 0 或 1 时完全停止。
const DECAY_FLOOR_RATIO: float = 0.1
## 数值低于该值时视为无仇恨并从表中移除，避免无穷小值长期残留。
const DECAY_CLEAR_THRESHOLD: float = 0.01
## 在 S 形曲线中，单位速率（k=1）从峰值衰减到一半所需的时间（秒）。
## 用于把半衰期参数校准为真实的"降到一半"时间，而不是使用峰值速率的理想化假设。
const DECAY_CURVE_HALF_TIME_AT_UNIT_RATE: float = 1.193333333

@export_category("Threat Decay")
## 来源停止产生新仇恨后，其仇恨值衰减到峰值一半所需的时间，单位为秒。
## 0 表示关闭衰减；新仇恨贡献会刷新该来源的衰减起点。
@export_range(0.0, 600.0, 5.0, "or_greater")
var threat_half_life: float = 60.0

## 该组件挂载的敌方单位。
## 仅可通过 configure() 写入；运行时不导出，避免设计师把仇恨表意外绑定到错误单位。
var _owner_enemy: UnitBase
## 以实例 ID 为键保存的最终本地仇恨值。
## 只有 submit_threat() 可以修改该表，确保普通伤害、技能和嘲讽未来使用同一结算标准。
var _threat_by_source_id: Dictionary = {}
## 与仇恨值并行保存的来源引用。
## 读取与清理时始终先检查 is_instance_valid()，避免已释放单位参与目标选择。
var _source_by_id: Dictionary = {}
## 以来源实例 ID 为键保存的衰减参考值（最近一次刷新时的峰值）。
## 来源收到新仇恨时刷新；衰减期间保持不变，用于计算当前剩余比例。
var _threat_reference_by_source_id: Dictionary = {}


## 注入本地仇恨表所属的敌方单位。
## owner_enemy 必须是有效 UnitBase；重复配置同一持有者安全重置表，配置失败时不保留旧引用。
func configure(owner_enemy: UnitBase) -> bool:
	if not is_instance_valid(owner_enemy):
		push_error(
			"EnemyThreatComponent: configure() requires a valid UnitBase owner. Node="
			+ str(get_path())
		)
		_owner_enemy = null
		clear_threat()
		return false
	_owner_enemy = owner_enemy
	clear_threat()
	return true


## 向唯一仇恨结算入口提交一个运行时事件。
## event 必须携带存活的敌对 UnitBase 来源和正基础量；接受 DAMAGE 与 SKILL_BONUS，并把基础量作为最终增加的本地仇恨。
func submit_threat(event: Variant) -> bool:
	if not _is_event_valid(event):
		return false
	var event_kind: int = int(event.get("kind"))
	if event_kind != ThreatEvent.Kind.DAMAGE and event_kind != ThreatEvent.Kind.SKILL_BONUS:
		return false

	var source_id: int = event.source.get_instance_id()
	var previous_value: float = float(_threat_by_source_id.get(source_id, 0.0))
	var contributed_threat: float = maxf(event.base_amount, 0.0) * maxf(
		float(event.threat_multiplier),
		0.0
	)
	var current_value: float = previous_value + contributed_threat
	_threat_by_source_id[source_id] = current_value
	_threat_reference_by_source_id[source_id] = current_value
	_source_by_id[source_id] = event.source
	threat_changed.emit(event.source, previous_value, current_value)
	return true


## 每帧对表内所有来源执行 S 形衰减。
## 剩余比例接近 1 或 0 时衰减慢，比例在 0.5 附近时衰减最快。
func _process(delta: float) -> void:
	if not is_instance_valid(_owner_enemy) or _owner_enemy.is_dead():
		return
	if threat_half_life <= 0.0 or _threat_by_source_id.is_empty():
		return
	var base_rate: float = DECAY_CURVE_HALF_TIME_AT_UNIT_RATE / threat_half_life
	var safe_delta: float = maxf(delta, 0.0)
	for source_id: Variant in _threat_by_source_id.keys():
		var current_value: float = float(_threat_by_source_id[source_id])
		var reference_value: float = float(
			_threat_reference_by_source_id.get(source_id, current_value)
		)
		if reference_value <= 0.0:
			continue
		var ratio: float = clampf(current_value / reference_value, 0.0, 1.0)
		var curve: float = (
			DECAY_FLOOR_RATIO
			+ (1.0 - DECAY_FLOOR_RATIO)
				* 4.0 * ratio * (1.0 - ratio)
		)
		var next_value: float = current_value * exp(-base_rate * curve * safe_delta)
		if next_value <= DECAY_CLEAR_THRESHOLD:
			_threat_by_source_id.erase(source_id)
			_source_by_id.erase(source_id)
			_threat_reference_by_source_id.erase(source_id)
		else:
			_threat_by_source_id[source_id] = next_value


## 在索敌组件提供的可见候选者中选择仇恨优先级最高的有效单位。
## 本方法绝不写入 locked_target；owner_unit、policy 和距离参数由 AITargetingComponent 传入并保持其既有筛选规范。
func resolve_target(
	owner_unit: UnitBase,
	current_target: UnitBase,
	candidates: Array[UnitBase],
	policy: TargetSelectionPolicy,
	acquisition_radius: float,
	retention_radius: float
) -> UnitBase:
	if (
		not is_instance_valid(_owner_enemy)
		or owner_unit != _owner_enemy
		or policy == null
	):
		return _select_policy_fallback(owner_unit, candidates, policy, acquisition_radius)

	_prune_invalid_records()
	var highest_threat_target: UnitBase
	var highest_threat_value: float = 0.0
	for candidate: UnitBase in candidates:
		if not policy.is_candidate_valid(owner_unit, candidate, acquisition_radius):
			continue
		var candidate_threat: float = get_threat_for(candidate)
		if candidate_threat > highest_threat_value:
			highest_threat_value = candidate_threat
			highest_threat_target = candidate

	if highest_threat_target == null:
		return _select_policy_fallback(owner_unit, candidates, policy, acquisition_radius)

	if (
		is_instance_valid(current_target)
		and policy.is_candidate_valid(owner_unit, current_target, retention_radius)
	):
		var current_threat: float = get_threat_for(current_target)
		var challenger_takeover_ratio: float = highest_threat_target.get_threat_takeover_ratio()
		# 已有目标仍有效时，只有新的挑战者严格超过自身的夺回仇恨倍率才允许切换。
		# 当前仇恨为零时不建立无意义保护，保留原本按最高仇恨/策略重新选择的行为。
		if (
			current_threat > 0.0
			and highest_threat_value <= current_threat * challenger_takeover_ratio
		):
			return current_target
	return highest_threat_target


## 清空该敌人的全部本地仇恨记录。
## 用于敌人死亡、开始归位或复活重置；不会修改 AITargetingComponent 的 locked_target。
func clear_threat() -> void:
	var had_records: bool = not _threat_by_source_id.is_empty()
	_threat_by_source_id.clear()
	_source_by_id.clear()
	_threat_reference_by_source_id.clear()
	if had_records:
		threat_cleared.emit()


## 返回指定来源在该敌人本地仇恨表中的最终值。
## 来源无效、未出现或已被清理时安全返回 0，不会尝试读取已释放实例的 ID。
func get_threat_for(source: UnitBase) -> float:
	if not is_instance_valid(source):
		return 0.0
	return float(_threat_by_source_id.get(source.get_instance_id(), 0.0))


## 返回指定来源相对“最高其他有效竞争者”的本地仇恨比率。
## source 必须是当前仇恨表中有效且存活的来源；没有其他有效竞争者、来源无效或来源仇恨不大于 0 时返回 0，
## 以避免单人战斗无意义地触发仇恨节流。该接口只读，不写入仇恨表或目标锁定结果。
func get_threat_ratio_against_highest_competitor(source: UnitBase) -> float:
	if not is_instance_valid(source):
		return 0.0
	_prune_invalid_records()
	var source_id := source.get_instance_id()
	var source_threat: float = float(_threat_by_source_id.get(source_id, 0.0))
	if source_threat <= 0.0:
		return 0.0
	var highest_competitor_threat: float = 0.0
	for competitor_id: Variant in _threat_by_source_id.keys():
		if int(competitor_id) == source_id:
			continue
		highest_competitor_threat = maxf(
			highest_competitor_threat,
			float(_threat_by_source_id.get(competitor_id, 0.0))
		)
	if highest_competitor_threat <= 0.0:
		return 0.0
	return source_threat / highest_competitor_threat


## 返回当前有效本地仇恨记录的只读副本。
## 每一项均为 `{ "source": UnitBase, "value": float }`；调用者只能用于展示或查询，修改返回数组或字典不会写回本组件的仇恨表。
func get_threat_snapshot() -> Array[Dictionary]:
	_prune_invalid_records()
	var snapshot: Array[Dictionary] = []
	for source_id: Variant in _source_by_id.keys():
		var source := _source_by_id.get(source_id) as UnitBase
		var threat_value: float = float(_threat_by_source_id.get(source_id, 0.0))
		if not is_instance_valid(source) or threat_value <= 0.0:
			continue
		snapshot.append({"source": source, "value": threat_value})
	return snapshot


## 判断事件是否可由本地敌人结算。
## 该验证统一约束来源存活、敌我关系和基础量，调用方不得绕过它直接写表。
func _is_event_valid(event: Variant) -> bool:
	if (
		event == null
		or not is_instance_valid(_owner_enemy)
		or not is_instance_valid(event.get("source"))
		or (event.get("source") as UnitBase).is_dead()
		or not (event.get("source") as UnitBase).is_inside_tree()
		or not _owner_enemy.is_hostile_to(event.get("source"))
		or float(event.get("base_amount")) <= 0.0
	):
		return false
	return true


## 清理死亡、离树或不再有效的来源记录。
## 每次进行目标决策前调用，保证旧表项不会参与后续优先级判断。
func _prune_invalid_records() -> void:
	var source_ids: Array = _source_by_id.keys()
	for source_id: Variant in source_ids:
		var source := _source_by_id.get(source_id) as UnitBase
		if (
			not is_instance_valid(source)
			or source.is_dead()
			or not source.is_inside_tree()
			or not is_instance_valid(_owner_enemy)
			or not _owner_enemy.is_hostile_to(source)
		):
			_threat_by_source_id.erase(source_id)
			_source_by_id.erase(source_id)
			_threat_reference_by_source_id.erase(source_id)


## 在不存在有效仇恨候选者时复用原始目标选择策略。
## policy 为空或持有者无效时返回 null，交由 AITargetingComponent 执行其已有的缺失策略处理。
func _select_policy_fallback(
	owner_unit: UnitBase,
	candidates: Array[UnitBase],
	policy: TargetSelectionPolicy,
	acquisition_radius: float
) -> UnitBase:
	if not is_instance_valid(owner_unit) or policy == null:
		return null
	return policy.select_target(owner_unit, candidates, acquisition_radius)
