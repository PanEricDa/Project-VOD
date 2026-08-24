class_name MeleeWeaponData
extends WeaponData

## 近战普通攻击专用数据。
## 只在近战战斗组件与玩家近战判定中读取；法杖、法球也可使用本类型作为兜底敲击。

@export_category("Attack Motion")
## 按 basic_attack_1、basic_attack_2……顺序保存每段真实前进距离，单位为米。
## 缺少对应项或数值不大于零时，动画仍播放，但该段不会请求角色实际位移。
@export var attack_forward_distances: Array[float] = []

## 整把武器执行攻击前移的速度，单位为米/秒。
@export_range(0.01, 30.0, 0.01, "or_greater")
var attack_motion_speed: float = 2.0

@export_category("Melee Hitbox")
## 每段近战攻击的盒形命中区域尺寸，按 basic_attack 编号对应。
@export var hitbox_sizes: Array[Vector3] = []

## 每段近战攻击的盒体中心偏移。Z 正数表示角色前方，检测组件内部会转换为 Godot 本地 -Z。
@export var hitbox_center_offsets: Array[Vector3] = []
