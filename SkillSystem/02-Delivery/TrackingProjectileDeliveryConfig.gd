@tool
class_name TrackingProjectileDeliveryConfig
extends "res://SkillSystem/02-Delivery/SkillDeliveryConfig.gd"

## 追踪投射物交付需要的全部静态参数。
##
## 命中对象、碰撞规则、伤害和飞行/爆炸表现仍由 projectile_scene 自身负责；
## 本配置只描述“怎样把投射物从角色发射出去”。

@export_category("Projectile")
## 释放时实例化的投射物场景；场景自身负责命中规则、伤害效果与飞行视觉。
@export var projectile_scene: PackedScene
@export_range(0.1, 100.0, 0.1, "or_greater")
## 投射物飞行速度，单位为米每秒；只影响交付过程，不改变伤害数值。
var projectile_speed: float = 12.0
@export_range(0.0, 2160.0, 1.0, "or_greater")
## 投射物每秒最大转向角度，单位为度；设为 0 时保持初始方向直线飞行。
var turn_speed_degrees: float = 540.0
@export_range(0.1, 60.0, 0.1, "or_greater")
## 投射物最长存活时间，单位为秒；超时后由交付流程结束并清理实例。
var maximum_lifetime: float = 5.0
@export_range(-10.0, 10.0, 0.05)
## 瞄准目标原点时附加的垂直高度，单位为米；用于让弹道朝向角色身体而非地面原点。
var aim_height: float = 0.25
@export_range(0.0, 30.0, 0.05, "or_greater")
## 判定投射物到达目标的水平命中半径，单位为米；0 表示仅依赖投射物自身碰撞或其他交付规则。
var impact_radius: float = 0.0


func validate_configuration() -> PackedStringArray:
	var warnings := PackedStringArray()
	if projectile_scene == null:
		warnings.append("Tracking projectile delivery requires a projectile scene.")
	if not is_finite(projectile_speed) or projectile_speed <= 0.0:
		warnings.append("Projectile speed must be finite and greater than zero.")
	if not is_finite(turn_speed_degrees) or turn_speed_degrees < 0.0:
		warnings.append("Turn speed must be finite and non-negative.")
	if not is_finite(maximum_lifetime) or maximum_lifetime <= 0.0:
		warnings.append("Maximum lifetime must be finite and greater than zero.")
	if not is_finite(aim_height):
		warnings.append("Aim height must be finite.")
	if not is_finite(impact_radius) or impact_radius < 0.0:
		warnings.append("Impact radius must be finite and non-negative.")
	return warnings
