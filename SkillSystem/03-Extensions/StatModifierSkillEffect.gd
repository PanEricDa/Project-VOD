class_name StatModifierSkillEffect
extends "res://SkillSystem/03-Extensions/SkillEffectBase.gd"

## 向目标单位的 StatusEffectComponent 交付临时固定属性修正。## 本效果不直接修改 UnitBase 的基础数值；所有计时、刷新、叠加与死亡清理由状态效果组件统一处理。

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
## 需要临时修正的属性。## 默认 DEFENSE；该枚举仅描述属性种类，不携带任何伤害、治疗或仇恨语义。
@export var modifier_stat: ModifierStat = ModifierStat.DEFENSE
## 对有效属性施加的固定增减值。## 正值为 Buff、负值为 Debuff；数值只在效果持续期间通过 UnitBase getter 生效，不改写基础配置。
@export_range(-1000000.0, 1000000.0, 0.1, "or_greater", "or_less")
var amount: float = 20.0
## 临时修正的持续时间，单位为秒。## 大于等于 0 时自动倒计时移除；小于 0 表示永久保留至主动清理或单位死亡。
@export_range(-1.0, 600.0, 0.05, "or_greater")
var duration_seconds: float = 5.0
## 同一效果再次交付时的处理方式。## 默认 REFRESH 仅刷新本效果同一属性的数值与持续时间；STACK 与 REPLACE 的实际合并规则由目标状态组件统一执行。
@export var stacking_rule: StackingRule = StackingRule.REFRESH


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
	var status_effects: Node = recipient.get_status_effect_component()
	if not is_instance_valid(status_effects) or not status_effects.has_method(&"apply_modifier"):
		return false
	return bool(
		status_effects.call(
			&"apply_modifier",
			self,
			int(modifier_stat),
			amount,
			duration_seconds,
			int(stacking_rule)
		)
	)


func _resolve_recipient(context: SkillContext, target: Node3D) -> UnitBase:
	match target_mode:
		TargetMode.CASTER:
			return context.caster as UnitBase
		TargetMode.DELIVERY_TARGET:
			return target as UnitBase
	return null
