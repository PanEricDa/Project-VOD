class_name SkillEffectBase
extends Node

const SkillContextType = preload(
	"res://SkillSystem/01-Core/SkillContext.gd"
)
const SkillDeliveryResultType = preload(
	"res://SkillSystem/01-Core/SkillDeliveryResult.gd"
)

## 目标瞬发或其他非投射物技能的最终效果接口。
##
## 投射物技能通常不挂载本组件，因为投射物自己负责命中与 Gameplay Payload。


func apply(
	_context: SkillContextType,
	_result: SkillDeliveryResultType,
	_target: Node3D
) -> bool:
	return false
