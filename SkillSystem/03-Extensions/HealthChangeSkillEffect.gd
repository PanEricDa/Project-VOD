class_name HealthChangeSkillEffect
extends "res://SkillSystem/03-Extensions/SkillEffectBase.gd"

const THREAT_EVENT_SCRIPT := preload(
	"res://UnitSystem/Components/Threat/ThreatEvent.gd"
)

## 通过统一数值结算器向 UnitBase 交付一次伤害或治疗。
enum Operation {
	DAMAGE,
	HEAL,
}

## 本效果执行伤害或治疗；DAMAGE 经 CombatValueResolver 扣血并提交仇恨，HEAL 经同一结算器恢复生命。
@export var operation: Operation = Operation.HEAL
@export_range(0.0, 999999.0, 0.1, "or_greater")
## 进入统一数值结算前的基础伤害或治疗量；最终结果还会叠加施法者攻击力与下方倍率。
var base_amount: float = 10.0
@export_range(0.0, 100.0, 0.05, "or_greater")
## 施法者攻击力换算到本次伤害或治疗的倍率；0 表示只使用基础数值。
var power_ratio: float = 0.0


func apply(
	context: SkillContext,
	_result: SkillDeliveryResult,
	target: Node3D
) -> bool:
	if context == null or not target is UnitBase:
		return false
	var caster := context.caster as UnitBase
	var unit_target := target as UnitBase
	match operation:
		Operation.DAMAGE:
			CombatValueResolver.apply_damage(
				caster,
				unit_target,
				base_amount,
				power_ratio,
				1.0,
				maxf(context.threat_multiplier, 0.0)
			)
			return true
		Operation.HEAL:
			var applied: float = CombatValueResolver.apply_healing(
				caster,
				unit_target,
				base_amount,
				power_ratio
			)
			if applied > 0.0 and context.threat_multiplier > 0.0:
				_submit_heal_threat(applied, context, unit_target)
			return true
	return false


## 向当前战斗中敌人提交本次治疗产生的仇恨。
## 仅在治疗有效（applied > 0）且技能配置了 threat_multiplier > 0 时调用。
## 找不到 EncounterController 或没有 ENGAGED 敌人时静默跳过。
func _submit_heal_threat(
	applied: float,
	context: SkillContext,
	_healed_target: UnitBase
) -> void:
	if not is_instance_valid(context.delivery_parent):
		return
	var encounter_controller := context.delivery_parent.get_node_or_null(
		^"EncounterController"
	) as Node
	if not is_instance_valid(encounter_controller):
		return
	if not encounter_controller.has_method(&"get_engaged_enemies"):
		return
	var enemies: Array = encounter_controller.call(&"get_engaged_enemies") as Array
	var caster := context.caster as UnitBase
	if not is_instance_valid(caster):
		return
	for enemy_value: Variant in enemies:
		var enemy := enemy_value as Node
		if not is_instance_valid(enemy) or not enemy.has_method(&"get_threat_component"):
			continue
		var threat_component := enemy.call(&"get_threat_component") as Node
		if not is_instance_valid(threat_component) or not threat_component.has_method(&"submit_threat"):
			continue
		var event: Variant = THREAT_EVENT_SCRIPT.new()
		event.source = caster
		event.kind = 1  # Kind.SKILL_BONUS
		event.base_amount = maxf(applied, 0.0)
		event.threat_multiplier = maxf(context.threat_multiplier, 0.0)
		threat_component.call(&"submit_threat", event)
