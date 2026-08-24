class_name IndependentNearestValidTargetSelector
extends "res://SkillSystem/03-Targeting/SkillTargetSelectorBase.gd"

## 开启后不会把施法者自身作为候选目标。
## FRIENDLY 只表示相同队伍，本身包含施法者，因此“是否允许自己”必须作为独立策略显式配置。
@export var exclude_caster: bool = true


## 在当前场景树中寻找符合技能 Definition 规则、且水平距离最近的单位。
## 当前基础版本以直接子节点 FactionComponent 识别战斗单位；未来可以替换为注册表而不改变本接口。
func resolve_target(context: SkillContextType) -> bool:
	if context == null or not is_instance_valid(context.caster) or not context.caster.is_inside_tree():
		return false

	var scene_tree: SceneTree = context.caster.get_tree()
	if scene_tree == null or scene_tree.root == null:
		return false

	var candidates: Array[Node3D] = []
	_collect_combatants(scene_tree.root, candidates)
	var nearest_target: Node3D
	var nearest_distance_squared := INF
	for candidate: Node3D in candidates:
		if exclude_caster and candidate == context.caster:
			continue
		if not is_candidate_valid(context, candidate, true):
			continue
		var offset: Vector3 = candidate.global_position - context.caster.global_position
		offset.y = 0.0
		var distance_squared: float = offset.length_squared()
		if distance_squared < nearest_distance_squared:
			nearest_distance_squared = distance_squared
			nearest_target = candidate

	if not is_instance_valid(nearest_target):
		context.resolved_target = null
		return false
	context.resolved_target = nearest_target
	context.target_position = nearest_target.global_position
	return true


func get_failure_reason(_context: SkillContextType) -> StringName:
	return &"no_valid_target"


## 递归只负责发现具有 FactionComponent 的 Node3D，不在这里重复任何阵营或距离规则。
func _collect_combatants(parent: Node, output: Array[Node3D]) -> void:
	if parent is Node3D and parent.has_node(^"FactionComponent"):
		output.append(parent as Node3D)
	for child: Node in parent.get_children():
		_collect_combatants(child, output)
