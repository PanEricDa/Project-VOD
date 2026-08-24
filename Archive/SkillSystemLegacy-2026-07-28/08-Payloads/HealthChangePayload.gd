class_name IndependentHealthChangePayload
extends "res://SkillSystem/08-Payloads/SkillPayloadBase.gd"

enum Operation {
	DAMAGE,
	HEAL,
}

@export_category("Health Change")
## DAMAGE 调用 apply_damage，HEAL 调用 apply_healing。
@export var operation: Operation = Operation.DAMAGE
## 请求应用的正数生命变化量；实际变化仍由 HealthComponent 限制。
@export_range(0.0, 999999.0, 0.1, "or_greater") var amount: float = 10.0
## 相对于目标根节点的标准生命组件路径。
@export_node_path("Node") var health_component_path: NodePath = ^"HealthComponent"


## 通过 HealthComponent 公共接口执行生命变化，不读取组件内部字段。
func apply(
	context: SkillContextType,
	_result: SkillDeliveryResultType,
	target: Node3D
) -> bool:
	if not is_instance_valid(target) or amount < 0.0:
		return false
	var health: Node = target.get_node_or_null(health_component_path)
	if not is_instance_valid(health):
		return false
	var source: Node = context.caster if is_instance_valid(context) else null
	match operation:
		Operation.DAMAGE:
			if not health.has_method(&"apply_damage"):
				return false
			health.call("apply_damage", amount, source)
		Operation.HEAL:
			if not health.has_method(&"apply_healing"):
				return false
			health.call("apply_healing", amount, source)
	return true
