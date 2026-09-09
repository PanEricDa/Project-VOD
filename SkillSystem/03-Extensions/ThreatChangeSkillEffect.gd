class_name ThreatChangeSkillEffect
extends "res://SkillSystem/03-Extensions/SkillEffectBase.gd"

const THREAT_EVENT_SCRIPT := preload(
	"res://UnitSystem/Components/Threat/ThreatEvent.gd"
)

## 向每个 Delivery 目标的现有仇恨池增加的固定仇恨点数。
## 单位为基础仇恨点；默认 200.0，必须为有限且大于 0 的数值。
## 本值不读取当前最高仇恨，也不受 SkillBase.threat_multiplier 影响，只影响本 Effect 的 SKILL_BONUS 事件。
@export_range(0.0, 999999.0, 0.1, "or_greater")
var threat_amount: float = 200.0


## 向一个有效敌方 UnitBase 提交固定 SKILL_BONUS 仇恨。
## context.caster 必须是存活的 UnitBase；target 必须暴露有效仇恨组件且与施法者敌对。
## 事件倍率固定为 1.0，不使用 context.threat_multiplier 或技能根节点的仇恨倍率。
## 返回值直接反映 EnemyThreatComponent.submit_threat() 是否接受事件。
func apply(
	context: SkillContext,
	_result: SkillDeliveryResult,
	target: Node3D
) -> bool:
	if context == null:
		return false
	if not is_finite(threat_amount) or threat_amount <= 0.0:
		return false
	var caster := context.caster as UnitBase
	if (
		not is_instance_valid(caster)
		or not caster.is_inside_tree()
		or caster.is_dead()
	):
		return false
	var enemy := target as UnitBase
	if not is_instance_valid(enemy) or not caster.is_hostile_to(enemy):
		return false
	if not enemy.has_method(&"get_threat_component"):
		return false
	var threat_component := enemy.call(&"get_threat_component") as Node
	if (
		not is_instance_valid(threat_component)
		or not threat_component.has_method(&"submit_threat")
	):
		return false
	var event: Variant = THREAT_EVENT_SCRIPT.new()
	event.source = caster
	event.kind = 1  # ThreatEvent.Kind.SKILL_BONUS
	event.base_amount = threat_amount
	event.threat_multiplier = 1.0
	return bool(threat_component.call(&"submit_threat", event))
