class_name ConsumeNamedStatusSkillEffect
extends "res://SkillSystem/03-Extensions/SkillEffectBase.gd"

## 命中后要移除的通用状态 ID；默认空表示不移除任何状态，只影响本效果命中的目标。
@export var status_id: StringName = &""


## 从已解析的有效 UnitBase 目标移除配置状态；context 和 result 是本次交付上下文，
## 本效果不修改它们。目标未持有该状态仍返回 true，避免取消同次交付的其他命中。
func apply(_context: SkillContext, _result: SkillDeliveryResult, target: Node3D) -> bool:
	if not is_instance_valid(target) or not target is UnitBase or not target.is_inside_tree():
		return false
	if status_id.is_empty():
		return true
	var status := (target as UnitBase).get_status_effect_component()
	if not is_instance_valid(status):
		return false
	status.remove_named_status(status_id)
	return true
