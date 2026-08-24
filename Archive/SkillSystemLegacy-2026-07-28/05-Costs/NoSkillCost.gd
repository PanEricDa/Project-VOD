class_name IndependentNoSkillCost
extends "res://SkillSystem/05-Costs/SkillCostBase.gd"

## 第一版基础费用实现：技能不消耗任何资源。
func can_pay(_context: SkillContextType) -> bool:
	return true


func commit(_context: SkillContextType) -> bool:
	return true


func refund(_context: SkillContextType) -> void:
	pass


func get_failure_reason(_context: SkillContextType) -> StringName:
	return &""
