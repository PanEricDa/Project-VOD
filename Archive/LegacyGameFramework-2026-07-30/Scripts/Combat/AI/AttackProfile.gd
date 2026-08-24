class_name AIAttackProfile
extends Resource

## AI 普通攻击模块使用的可复用静态配置资源。
## 资源只描述武器自身的攻击距离与接近方式，不保存当前目标、动画状态或公共冷却计时。

## Inspector 中显示的攻击名称，用于区分不同武器 Profile。
@export var display_name: String = "AI Attack"

## 武器允许发动普通攻击的水平中心距离，单位为米。
## 该距离与 AllyBase 的战斗警戒距离完全独立；近战武器通常小于警戒距离。
@export_range(0.1, 30.0, 0.1, "or_greater") var attack_range: float = 1.0

## 攻击距离两侧的迟滞容差，避免 AI 在范围边界反复切换接近与攻击状态。
@export_range(0.0, 5.0, 0.05) var attack_range_tolerance: float = 0.1

## 主人进入攻击接近阶段时，相对于普通 movement_speed 使用的速度倍率。
@export_range(0.1, 5.0, 0.05, "or_greater") var approach_speed_multiplier: float = 1.0

## 单次攻击结束后是否返回职业警戒距离。
## false 表示留在武器攻击距离附近等待公共冷却，适合持续贴身的近战攻击。
@export var return_to_guard_after_attack: bool = false
