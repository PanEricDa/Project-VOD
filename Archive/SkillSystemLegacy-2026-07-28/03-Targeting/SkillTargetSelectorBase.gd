class_name IndependentSkillTargetSelectorBase
extends Resource

const SkillContextType = preload("res://SkillSystem/01-Core/SkillContext.gd")

const TARGET_RELATION_ANY := 0
const TARGET_RELATION_SELF := 1
const TARGET_RELATION_FRIENDLY := 2
const TARGET_RELATION_HOSTILE := 3
const TARGET_RELATION_NEUTRAL := 4

## 目标选择策略抽象基类。实现类负责把结果写入 context.resolved_target。
func resolve_target(_context: SkillContextType) -> bool:
	return false


func get_failure_reason(_context: SkillContextType) -> StringName:
	return &"target_selector_not_implemented"


## 使用上下文中的 Definition 规则快照验证一个候选目标。
## 搜索型选择器和 SkillBase 的最终复验都调用这里，确保阵营、可选中状态和距离规则只有一个实现来源。
func is_candidate_valid(
	context: SkillContextType,
	candidate: Node3D,
	include_range: bool = true
) -> bool:
	if context == null or not is_instance_valid(context.caster):
		return false
	if not is_instance_valid(candidate) or not candidate.is_inside_tree():
		return false

	if context.target_relation == TARGET_RELATION_SELF:
		return candidate == context.caster and _is_candidate_in_range(context, candidate, include_range)

	## 新 UnitSystem 将阵营信息收敛到 UnitBase 根节点；旧技能测试和旧场景仍使用
	## FactionComponent。这里优先走 UnitBase 的公开关系接口，再兼容旧组件，技能层
	## 因而不依赖任意一套具体单位场景结构。
	var caster_unit := context.caster as UnitBase
	var target_unit := candidate as UnitBase
	if caster_unit != null and target_unit != null:
		if context.require_targetable and not target_unit.is_targetable():
			return false
		return _matches_unit_relation(
			caster_unit,
			target_unit,
			context.target_relation
		) and _is_candidate_in_range(context, candidate, include_range)

	var target_faction: Node = candidate.get_node_or_null(^"FactionComponent")
	if context.require_targetable:
		if not is_instance_valid(target_faction) or not bool(target_faction.get("targetable")):
			return false

	var relation_valid := false
	if context.target_relation == TARGET_RELATION_ANY:
		relation_valid = true
	else:
		var caster_faction: Node = context.caster.get_node_or_null(^"FactionComponent")
		if not is_instance_valid(caster_faction) or not is_instance_valid(target_faction):
			return false
		match context.target_relation:
			TARGET_RELATION_FRIENDLY:
				relation_valid = bool(caster_faction.call("is_friendly_to", target_faction))
			TARGET_RELATION_HOSTILE:
				relation_valid = bool(caster_faction.call("is_hostile_to", target_faction))
			TARGET_RELATION_NEUTRAL:
				relation_valid = bool(caster_faction.call("is_neutral_to", target_faction))
			_:
				relation_valid = false

	return relation_valid and _is_candidate_in_range(context, candidate, include_range)


## 使用 UnitBase 已公开的阵营关系判断，避免 SkillSystem 读取角色内部字段或节点路径。
func _matches_unit_relation(
	caster: UnitBase,
	target: UnitBase,
	relation: int
) -> bool:
	match relation:
		TARGET_RELATION_ANY:
			return true
		TARGET_RELATION_FRIENDLY:
			return caster.is_friendly_to(target)
		TARGET_RELATION_HOSTILE:
			return caster.is_hostile_to(target)
		TARGET_RELATION_NEUTRAL:
			return caster.is_neutral_to(target)
	return false


## 技能距离统一使用水平 XZ 平面，避免角色高度或地形细小落差改变施法判断。
func _is_candidate_in_range(
	context: SkillContextType,
	candidate: Node3D,
	include_range: bool
) -> bool:
	if not include_range:
		return true
	var offset: Vector3 = candidate.global_position - context.caster.global_position
	offset.y = 0.0
	return offset.length() <= maxf(context.cast_range, 0.0) + maxf(context.cast_range_tolerance, 0.0)
