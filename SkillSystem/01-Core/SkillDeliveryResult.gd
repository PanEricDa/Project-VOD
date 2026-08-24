class_name SkillDeliveryResult
extends RefCounted

## Delivery 完成后的统一结果。
##
## 投射物、瞬发交付和地面交付都使用同一结果结构报告世界位置和失败原因，
## 使 SkillBase、表现层和未来调试 UI 不需要识别具体 Delivery 子类型。

var succeeded: bool = false
var original_target: Node3D
var affected_targets: Array[Node3D] = []
var origin_position: Vector3 = Vector3.ZERO
var intended_position: Vector3 = Vector3.ZERO
var impact_position: Vector3 = Vector3.ZERO
var impact_direction: Vector3 = Vector3.ZERO
var failure_reason: StringName = &""
