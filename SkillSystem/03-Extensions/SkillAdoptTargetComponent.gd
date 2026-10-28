class_name SkillAdoptTargetComponent
extends Node

## 挂在 SkillBase 的直接子节点：成功开始交付时，把本次实际技能目标交给施法者的索敌组件。
## 无独立参数、计时或锁定状态；删除/移除此组件即可取消该技能的目标切换效果。

func _ready() -> void:
	var skill := get_parent() as SkillBase
	if skill != null:
		skill.delivery_started.connect(_on_delivery_started)

# context 是本次已经接受交付的请求；只读取 resolved_target，不重读玩家锁定或遍历范围命中目标。
func _on_delivery_started(context: SkillContext) -> void:
	if context == null or not is_instance_valid(context.caster):
		return
	var target := context.resolved_target as UnitBase
	if not is_instance_valid(target) or not context.caster.has_method(&"get_targeting_component"):
		return
	var targeting := context.caster.call(&"get_targeting_component") as AITargetingComponent
	if is_instance_valid(targeting):
		targeting.adopt_target(target)
