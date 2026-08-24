class_name IndependentSkillDeliveryResult
extends RefCounted

## Delivery 到达或碰撞后的统一结果载体。
## 结果不直接执行伤害；ImpactSelector 与 Payload 根据这些数据继续处理。

var succeeded: bool = false
var failure_reason: StringName = &""
var original_target: Node3D
var collision_target: Node3D
var affected_targets: Array[Node3D] = []
var origin_position: Vector3 = Vector3.ZERO
var intended_position: Vector3 = Vector3.ZERO
var impact_position: Vector3 = Vector3.ZERO
var impact_direction: Vector3 = Vector3.ZERO
