@tool
class_name InstantTargetDeliveryConfig
extends "res://SkillSystem/02-Delivery/SkillDeliveryConfig.gd"

## 目标瞬发交付配置。
##
## 默认 SINGLE 只表达“释放时立即把结果交给当前已解析目标”；CASTER_RADIUS 以施法者
## 为圆心，从本次请求的候选快照中筛选指定关系与水平半径内的多个目标，并对每个目标
## 复用同一组 SkillEffectBase。治疗、仇恨或其他最终效果仍由同一 Skill 场景中的
## SkillEffectBase 组件负责，本配置不保存任何运行时目标或节点引用。

enum TargetCollectionMode {
	SINGLE,
	CASTER_RADIUS,
}

## 瞬发交付的效果目标收集方式。
## SINGLE 维持原有行为，只对 SkillContext.resolved_target 交付；CASTER_RADIUS 以施法者为圆心筛选候选快照。
## 默认 SINGLE，影响所有使用本配置实例的瞬发技能，不改变技能自身的触发目标解析。
@export var target_collection_mode: TargetCollectionMode = TargetCollectionMode.SINGLE

## CASTER_RADIUS 模式下的水平作用半径，单位为米；必须为有限且大于 0 的数值。
## 默认 5.0；SINGLE 模式忽略本字段，只影响瞬发交付的效果目标集合。
@export_range(0.0, 100.0, 0.1, "or_greater")
var effect_radius: float = 5.0

## CASTER_RADIUS 模式允许接收效果的单位关系复选集合；默认 HOSTILE，只影响范围目标过滤。
## SINGLE 模式继续使用 SkillBase 已解析目标并忽略本字段，避免改变现有单体技能契约。
@export_flags("Self", "Friendly", "Hostile", "Neutral")
var affected_relations: int = TargetResolver.TargetRelationFlag.HOSTILE


func validate_configuration() -> PackedStringArray:
	var issues := PackedStringArray()
	if target_collection_mode == TargetCollectionMode.CASTER_RADIUS:
		if not is_finite(effect_radius) or effect_radius <= 0.0:
			issues.append(
				"InstantTargetDeliveryConfig: effect_radius must be finite "
				+ "and positive in CASTER_RADIUS mode."
			)
		if affected_relations == 0:
			issues.append(
				"InstantTargetDeliveryConfig: affected_relations must not "
				+ "be empty in CASTER_RADIUS mode."
			)
	return issues
