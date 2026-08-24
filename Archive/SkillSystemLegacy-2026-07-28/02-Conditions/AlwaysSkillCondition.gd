class_name IndependentAlwaysSkillCondition
extends "res://SkillSystem/02-Conditions/SkillConditionBase.gd"

## 最小条件实现：不附加任何限制，始终允许技能继续验证。
func evaluate(_context: SkillContextType) -> bool:
	return true


func get_failure_reason(_context: SkillContextType) -> StringName:
	return &""
