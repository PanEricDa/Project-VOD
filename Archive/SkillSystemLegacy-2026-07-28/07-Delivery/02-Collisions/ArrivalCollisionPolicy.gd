class_name IndependentArrivalCollisionPolicy
extends "res://SkillSystem/07-Delivery/02-Collisions/SkillCollisionPolicyBase.gd"

## 为 true 时，目标在到达前被删除会产生明确失败结果。
@export var require_valid_target_on_arrival: bool = true


## 基础碰撞实现不查询物理世界，只在弹道完成时生成目标到达结果。
func evaluate(
	context: SkillContextType,
	previous_transform: Transform3D,
	current_transform: Transform3D,
	progress: float
) -> SkillDeliveryResultType:
	if progress < 1.0:
		return null
	var result: SkillDeliveryResultType = SkillDeliveryResultType.new()
	result.original_target = context.resolved_target
	result.origin_position = context.cast_origin
	result.intended_position = context.target_position
	result.impact_position = current_transform.origin
	var travel_direction: Vector3 = current_transform.origin - previous_transform.origin
	if travel_direction.length_squared() > 0.000001:
		result.impact_direction = travel_direction.normalized()
	if require_valid_target_on_arrival and not is_instance_valid(context.resolved_target):
		result.succeeded = false
		result.failure_reason = &"invalid_target_on_arrival"
		return result
	result.succeeded = true
	result.collision_target = context.resolved_target
	return result
