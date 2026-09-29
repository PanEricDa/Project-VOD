class_name GuardianTauntNeededCondition
extends "res://SkillSystem/03-Extensions/SkillConditionBase.gd"

## 判断 Guardian 群体嘲讽当前是否能从任意友方身上接管至少一个敌人。
## 作用范围直接读取父技能的 CASTER_RADIUS Delivery，不额外暴露重复配置。


## 检查候选快照中是否存在位于嘲讽范围内、当前锁定其他友方的敌人。
## 玩家与 AI 友方采用同一判断；只排除施法者自己，不修改敌人锁定或仇恨池。
func evaluate(context: SkillContext) -> bool:
	if context == null:
		return false
	var caster := context.caster as UnitBase
	if not is_instance_valid(caster) or not caster.is_inside_tree():
		return false
	var skill := get_parent() as SkillBase
	if not is_instance_valid(skill):
		return false
	var config := skill.delivery as InstantTargetDeliveryConfig
	if (
		config == null
		or config.target_collection_mode
			!= InstantTargetDeliveryConfig.TargetCollectionMode.CASTER_RADIUS
		or not is_finite(config.effect_radius)
		or config.effect_radius <= 0.0
	):
		return false
	var candidates: Array[Node3D] = context.candidate_targets.duplicate()
	if (
		is_instance_valid(context.resolved_target)
		and context.resolved_target not in candidates
	):
		candidates.append(context.resolved_target)
	for candidate: Node3D in candidates:
		if not TargetResolver.is_candidate_valid(
			caster,
			candidate,
			config.affected_relations,
			true,
			true
		):
			continue
		var offset: Vector3 = candidate.global_position - caster.global_position
		offset.y = 0.0
		if offset.length() > config.effect_radius + 0.05:
			continue
		if not candidate.has_method(&"get_targeting_component"):
			continue
		var targeting := candidate.call(&"get_targeting_component") as Node
		if (
			not is_instance_valid(targeting)
			or not targeting.has_method(&"get_locked_target")
		):
			continue
		var locked_target := targeting.call(&"get_locked_target") as UnitBase
		if (
			is_instance_valid(locked_target)
			and locked_target != caster
			and TargetResolver.is_candidate_valid(
				caster,
				locked_target,
				TargetResolver.TargetRelationFlag.FRIENDLY,
				true,
				true
			)
		):
			return true
	return false


## 返回当前没有范围内敌人需要从其他友方身上接管的稳定原因标识。
## context 仅对应本次失败请求，本方法不读取或修改其中内容。
func get_failure_reason(_context: SkillContext) -> StringName:
	return &"guardian_taunt_not_needed"
