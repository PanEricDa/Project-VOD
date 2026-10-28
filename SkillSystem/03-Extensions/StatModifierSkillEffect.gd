class_name StatModifierSkillEffect
extends "res://SkillSystem/03-Extensions/SkillEffectBase.gd"

## 向目标单位的 StatusEffectComponent 交付临时属性修正。## 本效果不直接修改 UnitBase 的基础数值；所有计时、刷新、叠加与死亡清理由状态效果组件统一处理。

## 本技能效果接收数值修正的对象。## CASTER 用于自我强化；DELIVERY_TARGET 使用本次技能交付确定的目标。
enum TargetMode {
	CASTER,
	DELIVERY_TARGET,
}

## 与 StatusEffectComponent 保持数值对齐的可修正属性。## 新增属性时必须同步扩展两边枚举，避免 Inspector 配置传递到错误的属性槽。
enum ModifierStat {
	ATTACK_POWER,
	DEFENSE,
	MOVEMENT_SPEED,
	OUTGOING_DAMAGE,
}

## 与状态容器对齐的运算方式；固定点数与百分比点共用同一生命周期。
enum ModifierMode {
	FLAT,
	PERCENT,
}

## 与 StatusEffectComponent 保持数值对齐的叠加方式。## REFRESH 是默认行为，适合 Guardian 这类重复施放时只刷新持续时间的自我 Buff。
enum StackingRule {
	REFRESH,
	STACK,
	REPLACE,
}

@export_category("Target")
## 此临时效果修正的接收对象。## 默认 CASTER 让技能强化施法者自身；选择 DELIVERY_TARGET 时必须保证交付阶段提供有效 UnitBase 目标。
@export var target_mode: TargetMode = TargetMode.CASTER

@export_category("Modifier")
## 需要临时修正的属性，默认DEFENSE。OUTGOING_DAMAGE以1为基础倍率，通常配合PERCENT：30表示伤害×1.3，不增强治疗。
@export var modifier_stat: ModifierStat = ModifierStat.DEFENSE
## 修正运算方式，默认FLAT兼容既有固定Buff；PERCENT将amount解释为百分比点，影响目标该属性的最终倍率。
@export var modifier_mode: ModifierMode = ModifierMode.FLAT
## 修正量：FLAT为固定属性点，PERCENT为百分比点（-25表示降低25%）；正值强化、负值弱化。
## 只在持续期间由UnitBase getter动态计算，不改写基础配置；百分比作用于基础值与固定修正之和。
## 开启继承的use_finisher_bonus时，仅本修正量乘本次评分倍率，负号保留，持续时间不变。
@export_range(-1000000.0, 1000000.0, 0.1, "or_greater", "or_less")
var amount: float = 20.0
## 临时修正的持续时间，单位为秒。## 大于等于 0 时自动倒计时移除；小于 0 表示永久保留至主动清理或单位死亡。
@export_range(-1.0, 600.0, 0.05, "or_greater")
var duration_seconds: float = 5.0
## 同一效果再次交付时的处理方式。## 默认 REFRESH 仅刷新本效果同一属性的数值与持续时间；STACK 与 REPLACE 的实际合并规则由目标状态组件统一执行。
@export var stacking_rule: StackingRule = StackingRule.REFRESH

@export_category("Presentation")
## 可选的受益单位持续视觉，须为Node3D场景；默认空不生成。与真实状态同步刷新/移除，无独立时长。
@export var status_visual_scene: PackedScene


## 将本效果配置发送给目标的 StatusEffectComponent。## context 必须包含有效施法者；_result 只满足标准技能效果接口，不参与属性修正；target 仅在 DELIVERY_TARGET 模式下使用。
func apply(
	context: SkillContext,
	_result: SkillDeliveryResult,
	target: Node3D
) -> bool:
	if context == null:
		return false
	var recipient: UnitBase = _resolve_recipient(context, target)
	if not is_instance_valid(recipient):
		return false
	# 前序伤害已击杀目标时无需添加状态，但不应中断同次范围交付的其他目标。
	if recipient.is_dead():
		return true
	var status_effects: Node = recipient.get_status_effect_component()
	if not is_instance_valid(status_effects) or not status_effects.has_method(&"apply_modifier"):
		return false
	return bool(
		status_effects.call(
			&"apply_modifier",
			self,
			int(modifier_stat),
			scale_effect_value(amount, context),
			duration_seconds,
			int(stacking_rule),
			int(modifier_mode),
			status_visual_scene
		)
	)


func _resolve_recipient(context: SkillContext, target: Node3D) -> UnitBase:
	match target_mode:
		TargetMode.CASTER:
			return context.caster as UnitBase
		TargetMode.DELIVERY_TARGET:
			return target as UnitBase
	return null
