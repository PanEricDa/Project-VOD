@tool
class_name InstantTargetDeliveryConfig
extends "res://SkillSystem/02-Delivery/SkillDeliveryConfig.gd"

## 目标瞬发交付配置。
##
## 默认 SINGLE 只表达“释放时立即把结果交给当前已解析目标”；CASTER_RADIUS 以施法者
## 为基点（可沿稳定朝向前移圆心），TARGET_RADIUS以技能目标释放位置为基点。范围模式按Candidate Source取得候选，筛选关系与半径并对每个目标
## 复用同一组 SkillEffectBase。治疗、仇恨或其他最终效果仍由同一 Skill 场景中的
## SkillEffectBase 组件负责，本配置不保存任何运行时目标或节点引用。

enum TargetCollectionMode {
	SINGLE,
	CASTER_RADIUS,
	TARGET_RADIUS,
}

## 范围候选来源：请求快照保留旧行为；当前场景在实际释放时收集，不受感知半径限制。
enum CandidateSource { REQUEST_SNAPSHOT, WORLD_SCOPE }
## 默认请求快照；当前场景只遍历context.delivery_parent下单位，再按关系、存活与Effect Radius筛选。
## 只影响范围模式的受益/命中集合，不改变启动目标、施法距离或普通AI索敌。
@export var candidate_source: CandidateSource = CandidateSource.REQUEST_SNAPSHOT

## 瞬发交付的效果目标收集方式。
## SINGLE只对SkillContext.resolved_target交付；CASTER_RADIUS以施法者位置加前移偏移为圆心，按Candidate Source收集并筛选候选。
## TARGET_RADIUS以本次技能目标的释放位置为圆心，不受施法者朝向影响。默认SINGLE，不改变启动目标解析。
@export var target_collection_mode: TargetCollectionMode = TargetCollectionMode.SINGLE

## 范围模式下的水平作用半径，单位为米；必须为有限且大于 0 的数值。
## 默认 5.0；SINGLE 模式忽略本字段，只影响瞬发交付的效果目标集合。
@export_range(0.0, 100.0, 0.1, "or_greater")
var effect_radius: float = 5.0

## CASTER_RADIUS 范围中心沿施法者水平朝向前移的距离，单位米，默认0即以施法者为圆心。
## 优先使用实际释放的位置/朝向快照；无快照时使用当前稳定朝向。仅影响CASTER_RADIUS范围选取，不改变效果落点；其他模式忽略。
@export_range(0.0, 100.0, 0.1, "or_greater")
var center_forward_offset_m: float = 0.0

## 范围模式允许接收效果的单位关系复选集合；默认 HOSTILE，只影响范围目标过滤.
## SINGLE 模式继续使用 SkillBase 已解析目标并忽略本字段，避免改变现有单体技能契约。
@export_flags("Self", "Friendly", "Hostile", "Neutral")
var affected_relations: int = TargetResolver.TargetRelationFlag.HOSTILE


func validate_configuration() -> PackedStringArray:
	var issues := PackedStringArray()
	if candidate_source not in [CandidateSource.REQUEST_SNAPSHOT, CandidateSource.WORLD_SCOPE]:
		issues.append("InstantTargetDeliveryConfig: invalid candidate source.")
	if target_collection_mode not in [TargetCollectionMode.SINGLE,TargetCollectionMode.CASTER_RADIUS,TargetCollectionMode.TARGET_RADIUS]:
		issues.append("InstantTargetDeliveryConfig: invalid collection mode.")
	if target_collection_mode != TargetCollectionMode.SINGLE:
		if not is_finite(effect_radius) or effect_radius <= 0.0:
			issues.append(
				"InstantTargetDeliveryConfig: effect_radius must be finite "
				+ "and positive in radius modes."
			)
		if target_collection_mode == TargetCollectionMode.CASTER_RADIUS and (not is_finite(center_forward_offset_m) or center_forward_offset_m < 0.0):
			issues.append("InstantTargetDeliveryConfig: center_forward_offset_m must be finite and non-negative.")
		if affected_relations == 0:
			issues.append(
				"InstantTargetDeliveryConfig: affected_relations must not "
				+ "be empty in radius modes."
			)
	return issues
