class_name IndependentSkillConditionBase
extends Resource

const SkillContextType = preload("res://SkillSystem/01-Core/SkillContext.gd")

## 条件策略抽象基类。父类默认拒绝，确保误用未实现策略时不会静默放行技能。
func evaluate(_context: SkillContextType) -> bool:
	return false


## 返回稳定的失败原因，供 SkillBase 信号、测试和未来调试界面使用。
func get_failure_reason(_context: SkillContextType) -> StringName:
	return &"condition_not_implemented"
