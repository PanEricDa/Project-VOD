class_name RangedWeaponData
extends WeaponData

## 远程普通攻击专用数据。
## 投射物场景负责飞行和命中规则；本资源只描述普通攻击发射时的弹道参数。

@export_category("Projectile")
## 动画发射事件实例化的投射物场景。为空时远程武器仅播放动作，不创建投射物。
@export var projectile_scene: PackedScene
