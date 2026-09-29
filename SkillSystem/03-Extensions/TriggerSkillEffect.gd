@tool
class_name TriggerSkillEffect
extends SkillEffectBase

## 在一次有效命中后，按命中点附近目标查询结果逐个创建独立的 SkillBase 实例。
## 本组件不定义子技能的伤害、冷却、成本或弹道；这些都由引用的技能场景自行配置。

## 被触发的完整 SkillBase 场景；默认空表示不触发，任意普通技能场景均可引用，不能引用自身或祖先场景。
@export var child_skill_scene: PackedScene
## 仅当受击目标在本次命中前已有此命名状态时才触发；空标识表示不检查状态。
@export var required_status_id: StringName = &""
## 为 true 时要求本次命中实际扣血大于 0；默认开启，仅影响是否创建子技能，不改变父技能伤害。
@export var require_positive_damage: bool = true
## 以本次命中世界位置为中心的水平查询半径，单位米；默认 3 米，须为有限正数。
@export_range(0.0, 100.0, 0.1, "or_greater") var radius_m: float = 3.0
## 每次命中最多创建的子技能目标数量；默认 3，0 表示不创建，不修改子技能自身范围。
@export_range(0, 100, 1, "or_greater") var max_targets: int = 3
## 附近目标相对原施法者的关系位掩码；默认只选敌方，影响本次子技能目标查询。
@export_flags("Self", "Friendly", "Hostile", "Neutral") var relation_flags: int = TargetResolver.TargetRelationFlag.HOSTILE
## 默认排除本次受击目标，使子技能只向其他附近单位扩散；关闭后本目标也可被再次选取。
@export var exclude_hit_target: bool = true


## 读取本目标命中前状态与实际伤害，按命中点附近查询生成子技能；未满足条件、无目标或单个子技能失败均视为父效果成功。
func apply(context: SkillContext, result: SkillDeliveryResult, target: Node3D) -> bool:
	if (
		context == null or result == null or result.current_hit == null
		or not is_instance_valid(target) or result.current_hit.target != target
		or child_skill_scene == null or not is_instance_valid(context.caster)
		or not is_instance_valid(context.delivery_parent)
		or not context.delivery_parent.is_inside_tree()
		or not is_finite(radius_m) or radius_m <= 0.0 or max_targets <= 0
		or relation_flags == 0
	):
		return true
	var hit := result.current_hit
	if require_positive_damage and hit.actual_damage <= 0.0:
		return true
	if not required_status_id.is_empty() and not hit.statuses_before_hit.has(required_status_id):
		return true
	var child_path := child_skill_scene.resource_path
	var parent_path := _parent_skill_scene_path()
	if not child_path.is_empty() and (child_path == parent_path or context.trigger_scene_paths.has(child_path)):
		return true
	var descendants: Array[String] = context.trigger_scene_paths.duplicate()
	if not parent_path.is_empty() and not descendants.has(parent_path):
		descendants.append(parent_path)
	var excluded: Node3D = target if exclude_hit_target else null
	var candidates := NearbySkillTargetQuery.select_targets(
		target.get_world_3d(), context.caster, hit.impact_position,
		radius_m, max_targets, relation_flags, excluded
	)
	for candidate: Node3D in candidates:
		var instance: Node = child_skill_scene.instantiate()
		if not instance is SkillBase:
			if is_instance_valid(instance):
				instance.free()
			continue
		var child := instance as SkillBase
		context.delivery_parent.add_child(child)
		child.configure_owner(context.caster, context.host, context.delivery_parent)
		child.delivery_finished.connect(_release_child.bind(child), CONNECT_ONE_SHOT)
		child.skill_failed.connect(_release_failed_child.bind(child), CONNECT_ONE_SHOT)
		child.skill_cancelled.connect(_release_failed_child.bind(child), CONNECT_ONE_SHOT)
		var child_context := SkillContext.new()
		child_context.caster = context.caster
		child_context.host = context.host
		child_context.delivery_parent = context.delivery_parent
		child_context.requested_target = candidate
		child_context.explicit_target_requested = true
		child_context.execution_mode = SkillContext.ExecutionMode.DIRECT_TRIGGER
		child_context.activation_transform = Transform3D(Basis.IDENTITY, hit.impact_position)
		child_context.trigger_scene_paths.assign(descendants)
		if not child.activate(child_context):
			child.queue_free()
	return true


func _parent_skill_scene_path() -> String:
	var parent := get_parent()
	return parent.scene_file_path if parent is SkillBase else ""


func _release_child(_context: SkillContext, _result: SkillDeliveryResult, child: SkillBase) -> void:
	if is_instance_valid(child):
		child.queue_free()


func _release_failed_child(_context: SkillContext, _reason: StringName, child: SkillBase) -> void:
	if is_instance_valid(child):
		child.queue_free()


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if child_skill_scene == null:
		warnings.append("Trigger effect needs a child SkillBase scene.")
	elif not child_skill_scene.resource_path.is_empty() and child_skill_scene.resource_path == _parent_skill_scene_path():
		warnings.append("Trigger effect cannot reference its own skill scene.")
	if not is_finite(radius_m) or radius_m <= 0.0:
		warnings.append("Nearby radius must be finite and positive.")
	return warnings
