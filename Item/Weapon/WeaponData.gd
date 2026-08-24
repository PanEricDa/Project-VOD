class_name WeaponData
extends Resource

## 所有武器共用的最小数据载体。
## 只保存视觉、动画库与攻击距离等共性数据。近战与远程的交付参数由派生资源维护。

## 在 Inspector、调试输出与未来 UI 中使用的可读名称。
@export var display_name: String = "Weapon"

## 装备后实例化到角色 WeaponSocket 下的纯视觉场景。
@export var visual_scene: PackedScene

## 基于角色视觉层级制作的攻击 AnimationLibrary。
@export var animation_library: AnimationLibrary

@export_category("Attack Range")
## 武器允许普通攻击开始的水平中心距离，单位为米。
@export_range(0.1, 10.0, 0.1, "or_greater")
var attack_range: float = 1.0

## 攻击距离两侧的迟滞容差，避免 AI 在边界反复切换。
@export_range(0.0, 2.0, 0.05)
var attack_range_tolerance: float = 0.1

@export_category("Basic Attack")
## 普攻动作处于激活状态时允许保留的水平移动速度比例，取值 0 至 1；默认 1 保持原有移动，0 表示完全站立，0.4 表示仅以 40% 速度移动。
## 此参数由 AI 战斗行为在攻击动作期间读取；不影响攻击间隙移动、玩家输入、动画播放速度、攻击距离、伤害或投射物飞行。
@export_range(0.0, 1.0, 0.05)
var attack_movement_speed_multiplier: float = 1.0

## 普攻基础伤害，在攻击力加成前生效。
@export_range(0.0, 1000000.0, 0.1, "or_greater")
var basic_attack_base_damage: float = 5.0

## 普攻继承攻击力的比例。
@export_range(0.0, 100.0, 0.05, "or_greater")
var basic_attack_power_ratio: float = 1.0

## 每次普通攻击相对基础伤害的随机浮动比例，取值 0 至 1。
## 例如 0.10 表示本次命中会在基础伤害的 90% 至 110% 间随机结算；默认 0 保持固定伤害。
## 此参数只影响装备该武器的普通攻击，不影响技能伤害、命中率、动画或攻击距离。
@export_range(0.0, 1.0, 0.01)
var basic_attack_damage_variance: float = 0.0

@export_category("Threat")
## 普通攻击造成实际伤害后提交给敌方仇恨表的倍率。
## 1 表示实际扣血与仇恨一比一；大于 1 适合坦克武器，小于 1 可降低武器的仇恨贡献。
## 此参数只影响普通攻击的仇恨，不改变伤害、生命扣除、技能仇恨倍率或目标选择规则。
@export_range(0.0, 100.0, 0.05, "or_greater")
var basic_attack_threat_multiplier: float = 1.0

## 每段连击的伤害倍率，第一段对应索引零。
@export var combo_damage_multipliers: Array[float] = []


func get_combo_damage_multiplier(attack_index: int) -> float:
	var array_index := attack_index - 1
	if array_index < 0 or array_index >= combo_damage_multipliers.size():
		return 1.0
	return maxf(combo_damage_multipliers[array_index], 0.0)
