class_name MeleeSkillAction
extends Node

## 近战技能的动作与命中数据组件；只提供数据，由 AICombatSystem 和 CombatValueResolver 统一执行。

@export_category("Animation")
## 要从当前武器动画库播放的动作名称；例如 action_skill_1，必须含 release_action、open_hit_window 与 finish_action 方法轨道。
@export var action_animation_name: StringName = &"action_skill_1"

@export_category("Hitbox")
## 技能命中盒的世界局部尺寸，单位为米；独立于武器普攻的 Hitbox 配置。
@export var hitbox_size: Vector3 = Vector3(1.0, 0.7, 0.75)
## 技能命中盒相对于施法者前方的局部偏移，单位为米；Z 为正表示向角色正前方延伸。
@export var hitbox_center_offset: Vector3 = Vector3(0.0, 0.25, 0.45)

@export_category("Damage")
## 本技能命中时提供给统一伤害结算器的基础伤害；不直接扣血。
@export_range(0.0, 10000.0, 0.1, "or_greater") var base_damage: float = 12.0
## 本技能命中时攻击力的换算倍率；最终伤害仍由 CombatValueResolver 计算防御和其他统一规则。
@export_range(0.0, 100.0, 0.05, "or_greater") var power_ratio: float = 1.0
## 本技能的额外伤害倍率；默认 1 表示不额外放大。
@export_range(0.0, 100.0, 0.05, "or_greater") var damage_multiplier: float = 1.0


## 返回动作控制器需要的只读数据快照；参数均从该技能自身读取，不复用普通攻击配置。
func get_action_payload(threat_multiplier: float) -> Dictionary:
	return {"animation_name": action_animation_name, "hitbox_size": hitbox_size, "hitbox_center_offset": hitbox_center_offset, "base_damage": base_damage, "power_ratio": power_ratio, "damage_multiplier": damage_multiplier, "threat_multiplier": maxf(threat_multiplier, 0.0)}
