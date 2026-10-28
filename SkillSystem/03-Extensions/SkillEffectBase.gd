class_name SkillEffectBase
extends Node

const SkillContextType = preload(
	"res://SkillSystem/01-Core/SkillContext.gd"
)
const SkillDeliveryResultType = preload(
	"res://SkillSystem/01-Core/SkillDeliveryResult.gd"
)

## 统一技能最终效果接口；瞬发、投射物及触发子技能均可复用，交付器负责调用。

@export_category("Finisher Reward")
## 是否接受本次终结评分威力加成，默认false保持原数值。仅支持数值加成的效果调用共用方法生效。
## 伤害/治疗增强完整数值，属性修正增强amount，仇恨增强threat_amount；不改变持续时间、范围、数量或子效果开关。
@export var use_finisher_bonus: bool = false

## value为本效果明确选定的数值，可为负数；context携带本次冻结倍率，空上下文或非法倍率按1倍处理。
## 只返回计算值，不修改配置、上下文或目标；调用方须避免将已增强的结果重复传入。
func scale_effect_value(value: float, context: SkillContextType) -> float:
	if not use_finisher_bonus or context == null: return value
	var multiplier: float = context.finisher_multiplier
	return value*multiplier if is_finite(multiplier) and multiplier >= 1.0 else value


## 预期适用性检查：context/result为本次交付只读信息，target为当前目标。
## 默认true兼容已有Effect；false只跳过本Effect，不替代apply的真实失败语义。
## 受理前预检和实际应用前均可能调用，必须保持无副作用，不能在此付款、计数或改变目标。
func can_apply_to(_context: SkillContextType, _result: SkillDeliveryResultType, _target: Node3D) -> bool:
	return true


## 返回本Effect供视觉读取的纯值配置；键按效果职责命名，默认空，不保存单位或运行时对象。
## 只用于创建只读表现快照，不能触发效果或覆盖战斗配置；同键由技能下最后一个Effect提供。
func get_presentation_data() -> Dictionary:
	return {}


## 执行对target的最终效果；context/result沿用本次交付，true代表应用成功，false代表真实执行失败。
func apply(
	_context: SkillContextType,
	_result: SkillDeliveryResultType,
	_target: Node3D
) -> bool:
	return false
