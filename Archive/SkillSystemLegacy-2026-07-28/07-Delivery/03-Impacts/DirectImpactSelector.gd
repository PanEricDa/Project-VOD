class_name IndependentDirectImpactSelector
extends "res://SkillSystem/07-Delivery/03-Impacts/SkillImpactSelectorBase.gd"

## 选择直接碰撞目标；若碰撞策略未提供，则回退到技能解析目标。
func select_targets(
	context: SkillContextType,
	result: SkillDeliveryResultType
) -> Array[Node3D]:
	var selected: Node3D
	if is_instance_valid(result) and is_instance_valid(result.collision_target):
		selected = result.collision_target
	elif is_instance_valid(context) and is_instance_valid(context.resolved_target):
		selected = context.resolved_target
	if not is_instance_valid(selected) or not selected.is_inside_tree():
		return []
	return [selected]
