class_name ApplyNamedStatusSkillEffect
extends "res://SkillSystem/03-Extensions/SkillEffectBase.gd"

## 本效果施加的通用状态 ID；默认空表示未配置并拒绝执行，不包含灼烧特例。
@export var status_id: StringName = &""
## 状态持续时间，单位为秒；默认 4 秒，必须有限且大于零，只影响本效果命中的目标。
@export_range(0.01, 120.0, 0.01, "or_greater")
var duration_seconds: float = 4.0


## 向已解析目标的 StatusEffectComponent 施加配置的状态；context 为本次技能请求，result 为命中结果。
## 目标必须是有效 UnitBase 且有状态容器；失败返回 false，不修改其他目标。
func apply(context: SkillContext, _result: SkillDeliveryResult, target: Node3D) -> bool:
	if context == null or not target is UnitBase or not is_instance_valid(target):
		return false
	var status_component := (target as UnitBase).get_status_effect_component()
	if not is_instance_valid(status_component):
		return false
	return status_component.apply_named_status(status_id, duration_seconds)
