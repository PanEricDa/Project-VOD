class_name TargetSelectionPolicy
extends Resource

## AI 目标选择策略的统一数据与算法载体。
##
## 所有目标策略 `.tres` 都引用本脚本，通过 Inspector 参数表达差异。只有未来确实
## 出现新的抽象共性时，才需要在此统一增加字段或枚举，不为每个配置创建独立脚本。

enum TargetRelation {
	HOSTILE,
	FRIENDLY,
	ANY,
}

enum PriorityMode {
	NEAREST,
	PROTECT_ALLIES,
}

## 候选目标与持有者之间必须满足的阵营关系。
@export var target_relation: TargetRelation = TargetRelation.HOSTILE
## 启用后，候选单位必须允许被目标系统选中。
@export var require_targetable: bool = true
## 启用后，已经死亡的候选单位会被排除。
@export var require_alive: bool = true
## 当前使用的评分方式。第一版只提供最近目标，后续按实际需求统一扩充。
@export var priority_mode: PriorityMode = PriorityMode.NEAREST

@export_category("Protect Allies")
## 保护模式下对不打自己的敌人的介入意愿。数值越低越激进；1.0 表示不介入。
@export_range(0.0, 2.0, 0.05)
var intervention_response: float = 1.0


## 判断一个单位是否满足当前策略的基础资格和最大水平距离限制。
func is_candidate_valid(
	owner_unit: UnitBase,
	candidate: UnitBase,
	maximum_distance: float
) -> bool:
	if (
		not is_instance_valid(owner_unit)
		or not is_instance_valid(candidate)
		or candidate == owner_unit
		or not candidate.is_inside_tree()
	):
		return false
	if require_targetable and not candidate.is_targetable():
		return false
	if require_alive and candidate.is_dead():
		return false
	if not _matches_target_relation(owner_unit, candidate):
		return false

	var safe_maximum_distance: float = maxf(maximum_distance, 0.0)
	return (
		_get_horizontal_distance_squared(owner_unit, candidate)
		<= safe_maximum_distance * safe_maximum_distance
	)


## 返回候选单位的评分；数值越小，优先级越高。
func calculate_priority(
	owner_unit: UnitBase,
	candidate: UnitBase
) -> float:
	match priority_mode:
		PriorityMode.NEAREST:
			return _get_horizontal_distance_squared(owner_unit, candidate)
		PriorityMode.PROTECT_ALLIES:
			return _calculate_protect_priority(owner_unit, candidate)
	return INF


## 从候选集合中返回评分最低的有效目标。该方法不会修改传入数组。
func select_target(
	owner_unit: UnitBase,
	candidates: Array[UnitBase],
	maximum_distance: float
) -> UnitBase:
	var selected_target: UnitBase
	var selected_priority: float = INF
	for candidate: UnitBase in candidates:
		if not is_candidate_valid(owner_unit, candidate, maximum_distance):
			continue
		var candidate_priority: float = calculate_priority(owner_unit, candidate)
		if candidate_priority < selected_priority:
			selected_priority = candidate_priority
			selected_target = candidate
	return selected_target


## 返回 true 表示即使当前锁定目标仍然有效，策略也希望在下次 refresh 时重新选一次。
func wants_target_re_evaluation() -> bool:
	return priority_mode == PriorityMode.PROTECT_ALLIES


## 返回 owner 对候选敌人的威胁占该敌人最高威胁的比例，范围 0~1。
func get_threat_ratio(owner_unit: UnitBase, candidate: UnitBase) -> float:
	if not is_instance_valid(owner_unit) or not is_instance_valid(candidate):
		return 0.0
	var threat_component: Node = candidate.get_node_or_null(^"ThreatComponent")
	if not is_instance_valid(threat_component) or not threat_component.has_method(&"get_threat_for"):
		return 0.0
	var my_threat: float = float(threat_component.call("get_threat_for", owner_unit))
	var snapshot: Array = threat_component.call("get_threat_snapshot") as Array
	var highest_threat: float = 0.0
	for entry: Dictionary in snapshot:
		highest_threat = maxf(highest_threat, float(entry.get("value", 0.0)))
	if highest_threat <= 0.0:
		return 0.0
	return clampf(my_threat / highest_threat, 0.0, 1.0)


func _calculate_protect_priority(
	owner_unit: UnitBase,
	candidate: UnitBase
) -> float:
	var base_priority := _get_horizontal_distance_squared(owner_unit, candidate)
	if not is_instance_valid(owner_unit) or not is_instance_valid(candidate):
		return base_priority
	var candidate_target: Variant
	var targeting_component: Node = candidate.get_node_or_null(^"AITargetingComponent")
	if is_instance_valid(targeting_component) and targeting_component.has_method(&"get_locked_target"):
		candidate_target = targeting_component.call("get_locked_target")
		if candidate_target == owner_unit:
			var sticky_ratio := get_threat_ratio(owner_unit, candidate)
			if sticky_ratio > 0.0:
				var sticky_factor: float = maxf(1.0 - sticky_ratio * 0.3, 0.85)
				return base_priority * sticky_factor
			return base_priority
	var ratio := get_threat_ratio(owner_unit, candidate)
	var ir: float = clampf(intervention_response, 0.0, 2.0)
	var factor: float = ir + (1.0 - ir) * ratio
	print("[PROTECT] ", owner_unit.name, " sees ", candidate.name,
		" | target=", candidate_target if is_instance_valid(candidate_target) else "null",
		" | ratio=", ratio, " ir=", ir, " factor=", factor)
	# if is_instance_valid(owner_unit) and owner_unit.is_inside_tree():
	# 	owner_unit.get_tree().paused = true
	return base_priority * clampf(factor, 0.0, 1.0)


func _matches_target_relation(
	owner_unit: UnitBase,
	candidate: UnitBase
) -> bool:
	match target_relation:
		TargetRelation.HOSTILE:
			return owner_unit.is_hostile_to(candidate)
		TargetRelation.FRIENDLY:
			return owner_unit.is_friendly_to(candidate)
		TargetRelation.ANY:
			return true
	return false


func _get_horizontal_distance_squared(
	owner_unit: UnitBase,
	candidate: UnitBase
) -> float:
	var offset: Vector3 = candidate.global_position - owner_unit.global_position
	offset.y = 0.0
	return offset.length_squared()
