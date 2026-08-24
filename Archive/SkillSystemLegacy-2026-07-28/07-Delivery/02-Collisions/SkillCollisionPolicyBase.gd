class_name IndependentSkillCollisionPolicyBase
extends Resource

const SkillContextType = preload("res://SkillSystem/01-Core/SkillContext.gd")
const SkillDeliveryResultType = preload("res://SkillSystem/01-Core/SkillDeliveryResult.gd")

## 碰撞策略抽象基类。返回 null 表示本帧尚未产生到达或碰撞结果。
func evaluate(
	_context: SkillContextType,
	_previous_transform: Transform3D,
	_current_transform: Transform3D,
	_progress: float
) -> SkillDeliveryResultType:
	return null
