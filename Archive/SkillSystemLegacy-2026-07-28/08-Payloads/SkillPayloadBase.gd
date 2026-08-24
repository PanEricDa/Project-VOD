class_name IndependentSkillPayloadBase
extends Resource

const SkillContextType = preload("res://SkillSystem/01-Core/SkillContext.gd")
const SkillDeliveryResultType = preload("res://SkillSystem/01-Core/SkillDeliveryResult.gd")

## Gameplay Payload 抽象基类。父类不改变目标并返回失败。
func apply(
	_context: SkillContextType,
	_result: SkillDeliveryResultType,
	_target: Node3D
) -> bool:
	return false
