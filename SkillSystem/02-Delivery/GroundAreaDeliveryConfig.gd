@tool
class_name GroundAreaDeliveryConfig
extends "res://SkillSystem/02-Delivery/SkillDeliveryConfig.gd"

## 地面区域交付的最小静态配置。
##
## 区域场景负责自身持续时间、范围检测和最终效果，本配置只负责选择区域场景
## 以及相对于目标落点的世界偏移。

@export_category("Ground Area")
## 释放时实例化的地面区域场景；该场景自行维护持续时间、范围检测和后续效果。
@export var area_scene: PackedScene
## 区域落点相对目标位置的世界偏移，单位为米；默认零向量即直接落在目标位置。
@export var ground_offset: Vector3 = Vector3.ZERO


func validate_configuration() -> PackedStringArray:
	var warnings := PackedStringArray()
	if area_scene == null:
		warnings.append("Ground-area delivery requires an area scene.")
	if not ground_offset.is_finite():
		warnings.append("Ground offset must be finite.")
	return warnings
