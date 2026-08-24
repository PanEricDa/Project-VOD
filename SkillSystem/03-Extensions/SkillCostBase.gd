class_name SkillCostBase
extends Node

const SkillContextType = preload(
	"res://SkillSystem/01-Core/SkillContext.gd"
)

## 特殊技能消耗组件的抽象父类。
##
## 无消耗技能不挂载任何 Cost 组件。父类始终失败关闭，避免误把未实现的
## 消耗类型当成免费技能。具体实现负责保证 refund() 可以安全重复调用。


func can_pay(_context: SkillContextType) -> bool:
	return false


func commit(_context: SkillContextType) -> bool:
	return false


func refund(_context: SkillContextType) -> void:
	pass
