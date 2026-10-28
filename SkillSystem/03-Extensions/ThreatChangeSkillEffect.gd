class_name ThreatChangeSkillEffect
extends "res://SkillSystem/03-Extensions/SkillEffectBase.gd"

const THREAT_EVENT_SCRIPT := preload("res://UnitSystem/Components/Threat/ThreatEvent.gd")
const TEMPORARY_STATUS: StringName = &"temporary_threat"

## 固定基础仇恨点数；默认200，须有限正数。不读取最高仇恨，也不受技能根threat_multiplier影响。
## 普通分支计入SKILL_BONUS；限时分支创建同数值的可撤销贡献。
## 开启继承的use_finisher_bonus时，先将本值乘本次评分倍率，不放大已有仇恨池或延长时限。
@export_range(0.0, 999999.0, 0.1, "or_greater") var threat_amount: float = 200.0
## 临时贡献的持续战斗秒数；默认0保持原普通入池/自然衰减。正数由目标StatusEffect统一计时，到期只移除本贡献。
## 负数或非有限值拒绝；只影响此Effect，不改变Guardian既有duration=0配置、目标规则或技能冷却。
@export_range(0.0, 120.0, 0.1, "or_greater") var duration_seconds: float = 0.0

@export_category("Presentation")
## 可选的临时仇恨状态视觉，须为Node3D场景；默认空。仅duration_seconds>0时生效，成功绑定后显示，刷新复用，到期/清除/死亡收尾。
## 不改变仇恨、目标锁定或状态时间；duration_seconds=0的普通仇恨分支忽略本项。
@export var status_visual_scene: PackedScene

## 仅查询目标是否具备此分支的接收能力；不校正参数、不创建记录。参数错误仍由apply返回真正失败。
func can_apply_to(_context: SkillContext, _result: SkillDeliveryResult, target: Node3D) -> bool:
	var receiver := _threat_receiver(target)
	return receiver != null and (duration_seconds == 0.0 or (receiver is EnemyThreatComponent and target is UnitBase and (target as UnitBase).get_status_effect_component() is StatusEffectComponent))

## context.caster须为存活敌对UnitBase，target提供仇恨接收器；result不修改。0秒提交普通固定仇恨，正秒绑定状态和可撤销贡献。
## 限时身份来自已有damage_context.skill_id；无该快照使用稳定Effect类别，不持有技能/Context作为持续引用。
func apply(context: SkillContext, _result: SkillDeliveryResult, target: Node3D) -> bool:
	if context == null or not is_finite(threat_amount) or threat_amount <= 0.0 or not is_finite(duration_seconds) or duration_seconds < 0.0:
		return false
	var caster := context.caster as UnitBase
	var enemy := target as UnitBase
	if not is_instance_valid(caster) or not caster.is_inside_tree() or caster.is_dead() or not is_instance_valid(enemy) or not caster.is_hostile_to(enemy):
		return false
	var receiver := _threat_receiver(enemy)
	if receiver == null: return false
	var effective_amount := scale_effect_value(threat_amount, context)
	if duration_seconds == 0.0:
		var event: Variant = THREAT_EVENT_SCRIPT.new()
		event.source = caster
		event.kind = ThreatEvent.Kind.SKILL_BONUS
		event.base_amount = effective_amount
		event.threat_multiplier = 1.0
		return bool(receiver.call("submit_threat",event))
	var threat := receiver as EnemyThreatComponent
	var status := enemy.get_status_effect_component() as StatusEffectComponent
	if threat == null or status == null: return false
	var key: StringName = context.damage_context.skill_id if context.damage_context != null else &""
	if key == &"": key = &"threat_change"
	var contribution := threat.prepare_temporary_threat(caster,key,effective_amount)
	if contribution <= 0: return false
	var bound := status.prepare_bound_status(TEMPORARY_STATUS,caster,key,duration_seconds,Callable(threat,"remove_temporary_threat").bind(contribution))
	if bound <= 0:
		threat.discard_temporary_threat(contribution)
		return false
	var linked := status.bind_external_status_removal(bound,threat.temporary_threat_removed,contribution)
	if linked and status.commit_bound_status(bound,Callable(threat,"commit_temporary_threat").bind(contribution),status_visual_scene):
		return true
	status.discard_bound_status(bound)
	status.remove_bound_status(bound)
	threat.discard_temporary_threat(contribution)
	threat.remove_temporary_threat(contribution)
	return false

func _threat_receiver(target: Node3D) -> Node:
	if not is_instance_valid(target) or not target is UnitBase or not target.is_inside_tree() or target.is_queued_for_deletion() or (target as UnitBase).is_dead() or not target.has_method("get_threat_component"):
		return null
	var receiver := target.call("get_threat_component") as Node
	return receiver if is_instance_valid(receiver) and receiver.has_method("submit_threat") else null
