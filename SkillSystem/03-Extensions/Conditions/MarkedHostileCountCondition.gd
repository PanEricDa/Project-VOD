@tool
class_name MarkedHostileCountCondition
extends SkillConditionBase

## 统计当前战斗敌人身上命名状态的通用 AI 软条件。

## 用于查询被标记敌人的目标策略；默认空会使条件不通过，仅影响本条件。
@export var target_query: MarkedHostileTargetExpansion
## AI 允许释放所需的最少标记敌人数；默认 2，单位为存活敌人个数，
## 不限制显式请求，也不改变技能基础合法性和技能本身的附加目标数量。
@export_range(1, 100, 1, "or_greater") var minimum_count: int = 2


## 判断 context 对应战斗中是否有足够的标记敌人；仅做只读查询，
## 是否对显式请求生效仍由继承的 application_scope 决定。
func evaluate(context: SkillContext) -> bool:
	return (
		context != null and target_query != null and minimum_count > 0
		and target_query.marked_targets(context).size() >= minimum_count
	)


## 返回稳定的门槛失败原因；context 是本次请求，不修改它。
func get_failure_reason(_context: SkillContext) -> StringName:
	return &"marked_hostile_count_condition_not_met"
