class_name SkillConditionBase
extends Node

const SkillContextType = preload(
	"res://SkillSystem/01-Core/SkillContext.gd"
)

## 特殊技能条件组件的抽象父类。
##
## 阵营、目标有效性、距离与冷却由 SkillBase 统一处理；只有生命阈值、
## 装备要求等真正特殊的规则才需要继承本组件。


func evaluate(_context: SkillContextType) -> bool:
	return false


func get_failure_reason(_context: SkillContextType) -> StringName:
	return &"condition_not_implemented"
