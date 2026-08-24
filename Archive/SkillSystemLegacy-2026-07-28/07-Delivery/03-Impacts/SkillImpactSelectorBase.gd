class_name IndependentSkillImpactSelectorBase
extends Resource

const SkillContextType = preload("res://SkillSystem/01-Core/SkillContext.gd")
const SkillDeliveryResultType = preload("res://SkillSystem/01-Core/SkillDeliveryResult.gd")

## Impact 策略抽象基类。父类不选择任何目标。
func select_targets(
	_context: SkillContextType,
	_result: SkillDeliveryResultType
) -> Array[Node3D]:
	return []
