class_name HitFeedbackProfile
extends Resource

## 单次近战命中的局部卡刀与摄像机震动配置资源。
## 不同武器只需创建新的 .tres 并替换 Hero Inspector 中的资源，无需修改效果脚本。

@export_category("Hit Stop")
## 是否在命中时暂停当前攻击模块。
@export var hit_stop_enabled: bool = true

## 基础卡刀时间，单位为秒；实际值会乘以当前连击段的强度倍率。
@export_range(0.0, 0.5, 0.001) var hit_stop_duration: float = 0.045

@export_category("Camera Shake")
## 是否在命中时震动当前 Viewport 的 Camera3D。
@export var camera_shake_enabled: bool = true

## 基础震动持续时间，单位为秒。
@export_range(0.0, 2.0, 0.01) var shake_duration: float = 0.16

## 摄像机局部 X/Y 平面上的最大随机位移，单位为米。
@export_range(0.0, 1.0, 0.005) var shake_amplitude: float = 0.08

## 每秒重新生成随机震动目标的次数。
@export_range(1.0, 120.0, 1.0, "or_greater") var shake_frequency: float = 30.0

## 震动振幅衰减指数；数值越高，尾段衰减越快。
@export_range(0.1, 8.0, 0.1, "or_greater") var shake_decay_power: float = 2.0

@export_category("Retrigger")
## 两次视觉反馈之间的最短间隔；同一帧多目标命中只播放一次反馈。
@export_range(0.0, 1.0, 0.005) var minimum_feedback_interval: float = 0.03

## 第一、第二、第三击分别使用的反馈强度倍率。
@export var combo_intensity_multipliers: Array[float] = [0.85, 1.0, 1.3]


## 返回指定连击段的安全强度倍率；配置不足或无效时回退到 1.0。
func get_combo_intensity(combo_index: int) -> float:
	var array_index: int = combo_index - 1
	if array_index < 0 or array_index >= combo_intensity_multipliers.size():
		return 1.0
	return max(combo_intensity_multipliers[array_index], 0.0)
