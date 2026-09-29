class_name TargetHealthCondition
extends "res://SkillSystem/03-Extensions/SkillConditionBase.gd"

## 只判断本次已解析技能目标的生命比例，不重新选目标或修改目标生命。

## 自动施放所要求的目标生命上限，单位为百分比，合法范围 0～100。
## 默认 100 表示目标受伤才通过；必须严格低于阈值，等于阈值不通过，0 表示不会通过。
## 仅影响本条件；适用请求范围由继承的 Application Scope 决定。
@export_range(0.0, 100.0, 1.0, "suffix:%")
var health_threshold_percent: float = 100.0


## 检查 context.resolved_target 的 get_health_ratio() 返回值；要求有效、在树内且具有生命查询接口。
## 不接受空上下文、无效数值或超出范围的配置；不改变请求和目标状态。
func evaluate(context: SkillContext) -> bool:
	if context == null or not is_finite(health_threshold_percent):
		return false
	if health_threshold_percent < 0.0 or health_threshold_percent > 100.0:
		return false
	var target := context.resolved_target
	if not is_instance_valid(target) or not target.is_inside_tree():
		return false
	if not target.has_method(&"get_health_ratio"):
		return false
	var value: Variant = target.call(&"get_health_ratio")
	if not (value is float or value is int):
		return false
	var ratio := float(value)
	return is_finite(ratio) and ratio >= 0.0 and ratio <= 1.0 and ratio < health_threshold_percent / 100.0


## 返回本条件未通过的稳定原因标识；context 为被检查的请求，不修改它。
func get_failure_reason(_context: SkillContext) -> StringName:
	return &"target_health_condition_not_met"
