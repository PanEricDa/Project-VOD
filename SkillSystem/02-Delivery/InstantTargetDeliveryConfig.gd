@tool
class_name InstantTargetDeliveryConfig
extends "res://SkillSystem/02-Delivery/SkillDeliveryConfig.gd"

## 目标瞬发交付不需要额外参数。
##
## 该类型只表达“释放时立即把结果交给当前目标”；治疗、Buff 或其他最终效果
## 由同一 Skill 场景中的 SkillEffectBase 组件负责。


func validate_configuration() -> PackedStringArray:
	return PackedStringArray()
