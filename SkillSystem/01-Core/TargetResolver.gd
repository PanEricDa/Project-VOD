class_name TargetResolver
extends RefCounted

## 技能系统统一使用的临时目标解析算法。
##
## 本类型不保存运行时状态，也不依赖 UnitBase。调用者只需提供 Node3D 以及
## 目标公开的能力方法，便可以完成关系过滤和选择。持续锁定仍由外部索敌组件负责。

enum TargetRelationFlag {
	SELF = 1,
	FRIENDLY = 2,
	HOSTILE = 4,
	NEUTRAL = 8,
}

enum TargetSelectionMode {
	CURRENT_COMBAT_TARGET,
	NEAREST,
	RANDOM,
	LOWEST_HEALTH_RATIO,
}


## 从一次请求的候选快照中解析最终目标。
##
## CURRENT_COMBAT_TARGET 只验证调用方提供的当前战斗目标，不会静默回退到其他
## 候选；其余模式先统一过滤和去重，再执行各自的选择算法。
static func resolve_target(
	owner: Node3D,
	candidates: Array[Node3D],
	current_combat_target: Node3D,
	relation_flags: int,
	selection_mode: TargetSelectionMode,
	require_targetable: bool,
	require_alive: bool,
	random: RandomNumberGenerator = null
) -> Node3D:
	if not is_instance_valid(owner):
		return null
	if selection_mode == TargetSelectionMode.CURRENT_COMBAT_TARGET:
		return (
			current_combat_target
			if is_candidate_valid(
				owner,
				current_combat_target,
				relation_flags,
				require_targetable,
				require_alive
			)
			else null
		)

	var valid_candidates := _collect_valid_candidates(
		owner,
		candidates,
		relation_flags,
		require_targetable,
		require_alive
	)
	match selection_mode:
		TargetSelectionMode.NEAREST:
			return _select_nearest(owner, valid_candidates)
		TargetSelectionMode.RANDOM:
			return _select_random(valid_candidates, random)
		TargetSelectionMode.LOWEST_HEALTH_RATIO:
			return _select_lowest_health_ratio(valid_candidates)
	return null


## 验证单个候选是否符合关系、存活和可选取条件。
##
## 参数使用 Variant，确保已经释放或类型错误的目标会在任何强类型转换前被拒绝。
static func is_candidate_valid(
	owner: Node3D,
	candidate_value: Variant,
	relation_flags: int,
	require_targetable: bool,
	require_alive: bool
) -> bool:
	if (
		not is_instance_valid(owner)
		or not is_instance_valid(candidate_value)
		or not candidate_value is Node3D
	):
		return false
	var candidate := candidate_value as Node3D
	if not owner.is_inside_tree() or not candidate.is_inside_tree():
		return false

	if require_targetable:
		if not candidate.has_method(&"is_targetable"):
			return false
		if not bool(candidate.call(&"is_targetable")):
			return false
	if require_alive:
		if not candidate.has_method(&"is_dead"):
			return false
		if bool(candidate.call(&"is_dead")):
			return false

	if (
		candidate == owner
		and relation_flags & TargetRelationFlag.SELF
	):
		return true
	if candidate == owner:
		return false
	if (
		relation_flags & TargetRelationFlag.FRIENDLY
		and owner.has_method(&"is_friendly_to")
		and bool(owner.call(&"is_friendly_to", candidate))
	):
		return true
	if (
		relation_flags & TargetRelationFlag.HOSTILE
		and owner.has_method(&"is_hostile_to")
		and bool(owner.call(&"is_hostile_to", candidate))
	):
		return true
	if (
		relation_flags & TargetRelationFlag.NEUTRAL
		and owner.has_method(&"is_neutral_to")
		and bool(owner.call(&"is_neutral_to", candidate))
	):
		return true
	return false


static func _collect_valid_candidates(
	owner: Node3D,
	candidates: Array[Node3D],
	relation_flags: int,
	require_targetable: bool,
	require_alive: bool
) -> Array[Node3D]:
	var valid_candidates: Array[Node3D] = []
	var seen_ids: Dictionary = {}
	for candidate: Node3D in candidates:
		if not is_candidate_valid(
			owner,
			candidate,
			relation_flags,
			require_targetable,
			require_alive
		):
			continue
		var instance_id: int = candidate.get_instance_id()
		if seen_ids.has(instance_id):
			continue
		seen_ids[instance_id] = true
		valid_candidates.append(candidate)
	return valid_candidates


static func _select_nearest(
	owner: Node3D,
	candidates: Array[Node3D]
) -> Node3D:
	var selected: Node3D
	var selected_distance_squared: float = INF
	for candidate: Node3D in candidates:
		var offset: Vector3 = candidate.global_position - owner.global_position
		offset.y = 0.0
		var distance_squared: float = offset.length_squared()
		if distance_squared < selected_distance_squared:
			selected_distance_squared = distance_squared
			selected = candidate
	return selected


static func _select_random(
	candidates: Array[Node3D],
	random: RandomNumberGenerator
) -> Node3D:
	if candidates.is_empty():
		return null
	var active_random := random
	if active_random == null:
		active_random = RandomNumberGenerator.new()
		active_random.randomize()
	return candidates[active_random.randi_range(0, candidates.size() - 1)]


static func _select_lowest_health_ratio(
	candidates: Array[Node3D]
) -> Node3D:
	var selected: Node3D
	var selected_ratio: float = INF
	for candidate: Node3D in candidates:
		if not candidate.has_method(&"get_health_ratio"):
			continue
		var ratio: float = float(candidate.call(&"get_health_ratio"))
		if not is_finite(ratio) or ratio >= selected_ratio:
			continue
		selected_ratio = ratio
		selected = candidate
	return selected
