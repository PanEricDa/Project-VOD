class_name ThreatEvent
extends RefCounted

## 仇恨系统的统一运行时事件数据。
## 事件只描述“谁因何事提交了多少基础威胁”，不保存仇恨表、目标锁定或场景节点路径。

## 仇恨事件的语义类型。
## 第一版只结算 DAMAGE；其他类型用于让后续技能、嘲讽等来源继续经过同一入口，当前不会产生额外行为。
enum Kind {
	DAMAGE,
	SKILL_BONUS,
	TAUNT,
}

## 提交此事件的单位来源。
## 必须是存活、有效且与持有敌人敌对的 UnitBase；无效来源会被仇恨组件拒绝。
var source: UnitBase
## 事件的行为语义；默认 DAMAGE，表示已经实际结算到敌人的伤害。
var kind: Kind = Kind.DAMAGE
## 未经仇恨规则修正的基础量。
## 第一版 DAMAGE 直接使用该值；必须大于 0，单位为“基础仇恨点”，当前与实际伤害数值一一对应。
var base_amount: float = 0.0
## 此次伤害对敌人本地仇恨表的放大倍率。## 默认 1.0 表示仇恨与实际扣血一比一；只改变仇恨贡献，不改变伤害、减伤或命中。## 传入负值时会在最终结算前按 0 处理，防止用减仇恨参数意外逆向扣除既有仇恨。
var threat_multiplier: float = 1.0


## 根据已经实际结算的伤害创建统一仇恨事件。
## source_unit 必须是造成伤害的真实单位而非投射物节点；applied_amount 必须传入目标实际扣除的生命值，避免过量伤害虚增仇恨。
static func create_damage(
	source_unit: UnitBase,
	applied_amount: float,
	threat_multiplier_value: float = 1.0
) -> Variant:
	## 通过脚本自身的已登记资源创建事件，避免首次 headless 加载时依赖 class_name 缓存。
	var event: Variant = load("res://UnitSystem/Components/Threat/ThreatEvent.gd").new()
	event.source = source_unit
	event.kind = Kind.DAMAGE
	event.base_amount = maxf(applied_amount, 0.0)
	event.threat_multiplier = maxf(threat_multiplier_value, 0.0)
	return event
