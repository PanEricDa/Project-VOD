# AI 普通攻击命中停顿设计

## 目标

为所有继承 `AttackModuleBase.tscn` 的 AI 攻击模块提供通用、可拆卸的命中短暂停顿。系统复用玩家已经使用的 `HitFeedbackBridge.tscn` 与 `HitFeedbackProfile`，但通过 AI 专用资源关闭摄像机震动。

## 结构

```text
AttackModuleBase
├── AttackAnimationPlayer
├── DeliveryRoot/HitboxDetector
└── HitFeedbackBridge（现有 Effect 场景实例）
```

- `AIAttackModuleBase` 继续发送三参数 `attack_hit(target, hit_position, hit_direction)`。
- `HitFeedbackBridge` 的 `combo_index` 改为可选参数，默认值为 `1`，因此同时兼容玩家四参数信号和 AI 三参数信号。
- 父攻击场景统一实例化效果桥；继承攻击场景无需重复装配。
- `DefaultAIHitFeedback.tres` 只启用 Hit Stop，禁用 Camera Shake。

## 局部暂停范围

AI 命中停顿只冻结当前攻击模块：

- 暂停 `AttackAnimationPlayer` 当前动画进度。
- 暂停当前 Hitbox 的物理查询，同时保留本窗口已命中目标的去重记录。

以下内容继续运行：

- `AllyBase` 移动、转向、重力与 AI 决策。
- 普通攻击公共冷却。
- 其他角色、场景物理与整个游戏世界。

暂停解除后，攻击动画从原进度继续，Hitbox 在命中窗口仍有效时继续检测；若窗口已经关闭、攻击已取消或模块已复位，则不得重新启用检测。

## 公共接口

`AIAttackModuleBase`：

```gdscript
@export var hit_feedback_enabled: bool = true

func set_hit_stop_active(active: bool) -> void
func is_hit_stop_active() -> bool
```

`HitFeedbackBridge`：

```gdscript
func play_hit_feedback(
    target: CharacterBody3D,
    hit_position: Vector3,
    hit_direction: Vector3,
    combo_index: int = 1
) -> void
```

## 默认配置

`Effects/Combat/DefaultAIHitFeedback.tres`：

```text
hit_stop_enabled = true
hit_stop_duration = 0.06
camera_shake_enabled = false
minimum_feedback_interval = 0.03
combo_intensity_multipliers = [1.0]
```

同一帧或最小反馈间隔内的多目标命中仍分别发送 `attack_hit`，但只产生一次停顿，避免停顿按目标数量叠加。

## 生命周期与边界

- `cancel_attack()`、`reset_module()`、动画完成和节点退出场景时必须解除暂停。
- 模块在停顿期间被取消时，效果桥随后解除暂停也必须保持幂等。
- `hit_feedback_enabled=false` 时效果桥仍可被继承，但不会产生停顿。
- 本阶段不加入伤害、生命值、击退、音效、粒子或摄像机反馈。
- 不修改 `res://Scenes/TestScene.tscn`。

