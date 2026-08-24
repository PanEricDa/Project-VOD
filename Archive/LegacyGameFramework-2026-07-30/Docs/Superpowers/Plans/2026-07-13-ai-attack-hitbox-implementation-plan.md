# AI 攻击模块通用 Hitbox 实施记录

## 实施目标

在 `AttackModuleBase` 父场景内建立所有子攻击模块都能继承的 ShapeCast 命中检测组件。父模块统一驱动命中窗口并转发事件，ShieldAttack 只覆盖近战盒体配置。

## 已实施结构

```text
AttackModuleBase
└── DeliveryRoot
    └── HitboxDetector (AIAttackHitbox.gd)
        ├── HitboxShapeCast (ShapeCast3D)
        └── DebugHitbox (MeshInstance3D)
```

- `AIAttackHitbox` 负责物理层与分组过滤、持有者排除、单窗口去重、多目标命中和调试显示。
- `AIAttackModuleBase` 在动画方法轨道打开/关闭窗口时同步启停检测，并将 `hit_detected` 转发为 `attack_hit`。
- `AllyBase.set_attack_module()` 在装卸时注入或清除持有者，不承担任何命中检测逻辑。
- 父模块默认 `hitbox_enabled=false`，尚未配置 Delivery 的远程模块不会误触发近战检测。

## ShieldAttack 配置

```text
hitbox_enabled = true
HitboxDetector.position = Vector3(0.12, 0.30, -0.55)
BoxShape3D.size = Vector3(0.75, 0.55, 0.65)
collision_mask = 4
target_group = enemy_targets
debug_hitbox_enabled = true
```

有效窗口继续由动画在 `0.14s` 打开、`0.27s` 关闭。检测盒固定在角色正前方偏右，不跟随当前临时盾牌动画。

## 公共接口

```gdscript
# AIAttackModuleBase
signal attack_hit(
    target: CharacterBody3D,
    hit_position: Vector3,
    hit_direction: Vector3
)
func configure_attack_owner(body: CharacterBody3D) -> void

# AIAttackHitbox
signal hit_detected(
    target: CharacterBody3D,
    hit_position: Vector3,
    hit_direction: Vector3
)
func configure(owner_body: CharacterBody3D) -> void
func begin_detection() -> void
func end_detection() -> void
func is_detecting() -> bool
```

## 当前范围

Hitbox 只发送检测事件，不修改目标生命值、速度、状态或动画。伤害、击退、受击反馈和音效仍由未来独立系统连接 `attack_hit` 实现。

本次没有修改或添加 `res://Scenes/TestScene.tscn` 中的任何单位实例。
