class_name IndependentProvidedTargetSelector
extends "res://SkillSystem/03-Targeting/SkillTargetSelectorBase.gd"

## 使用外部调用方已经提供的目标，不主动搜索场景树。
func resolve_target(context: SkillContextType) -> bool:
	if not is_instance_valid(context) or not is_instance_valid(context.requested_target):
		return false
	if not context.requested_target.is_inside_tree():
		return false
	context.resolved_target = context.requested_target
	context.target_position = context.requested_target.global_position
	return true


func get_failure_reason(_context: SkillContextType) -> StringName:
	return &"target_resolution_failed"
