# 玩家统一命中反馈设计

日期：2026-07-22

## 目标

为新 PlayerBase 玩家攻击系统加入局部卡刀与摄像机震动，并把玩家视觉/反馈组件统一装载到固定 `Effects` 插槽。复用旧系统的 `HitFeedbackBridge.tscn`、`HitFeedbackBridge.gd`、`HitFeedbackProfile.gd` 与 `DefaultMeleeHitFeedback.tres`，不创建第二套参数资源。

本系统只响应已有 `PlayerAttackController.attack_hit` 信号，不修改 Hitbox 判定、伤害、生命值或 TestScene 单位实例。

## 节点架构

```text
PlayerBase
├── Visual
├── TargetingSystem
├── AttackController
├── MeleeHitbox
└── Effects
    └── HitFeedbackBridge
```

- `Effects` 使用 `Node3D`，作为玩家效果组件的固定插槽。
- `HitFeedbackBridge` 直接实例化旧场景 `res://Effects/Combat/HitFeedbackBridge.tscn`。
- 实例参数：

```text
attack_source_path = ../../AttackController
effect_profile = res://Effects/Combat/DefaultMeleeHitFeedback.tres
```

- 删除 `Effects/HitFeedbackBridge` 后，攻击、命中信号和移动系统保持正常。
- 世界法术、敌人效果和独立粒子仍保留在各自 `Effects` 文件目录，不由玩家插槽集中管理。

## 复用资源

继续使用：

- `Effects/Combat/HitFeedbackBridge.tscn`
- `Effects/Combat/HitFeedbackBridge.gd`
- `Effects/Combat/HitFeedbackProfile.gd`
- `Effects/Combat/DefaultMeleeHitFeedback.tres`

当前玩家资源实际参数：

```text
hit_stop_enabled = true
hit_stop_duration = 0.045s
camera_shake_enabled = true
shake_duration = 0.16s
shake_amplitude = 0.08m
shake_frequency = 30Hz
shake_decay_power = 2.0
minimum_feedback_interval = 0.03s
combo_intensity_multipliers = 1.2 / 1.3 / 1.5
```

`.tres` 未显式写入的字段继续使用 `HitFeedbackProfile.gd` 默认值。旧、新攻击系统在过渡期共享该资源，修改参数会同时影响两边，这是本阶段的明确约定。

## PlayerAttackController 接口

新增：

```gdscript
func set_hit_stop_active(active: bool) -> void
func is_hit_stop_active() -> bool
```

控制器维护：

- 当前是否处于局部卡刀。
- 暂停前 AnimationPlayer 是否正在播放攻击动画。

开启卡刀时：

1. 暂停当前 `CharacterAnimationPlayer`。
2. 暂停攻击状态计时。
3. 调用 PlayerBase 暂停攻击位移。
4. 调用 PlayerMeleeHitbox 暂停新的物理查询。
5. 保留当前连击段、动画时间、输入缓存、剩余位移和 Hitbox 单窗口去重记录。

关闭卡刀时：

- 仅在暂停前确实播放攻击动画且当前仍为 `ATTACKING` 时恢复播放。
- 恢复攻击位移和 Hitbox 查询。
- 不重新播放动画，不重新开启窗口，也不清空连击状态。

`cancel_combo()`、卸装、换装和退出场景必须先解除卡刀，再进行既有清理。

## PlayerBase 攻击位移接口

新增：

```gdscript
func set_attack_motion_suspended(active: bool) -> void
func is_attack_motion_suspended() -> bool
```

暂停期间：

- 不向最终水平速度叠加攻击位移速度。
- 不消耗 `_attack_motion_remaining_distance`。
- WASD、重力与目标锁定继续正常处理。
- 冲刺开始仍会调用已有 `cancel_attack_motion()`，清除本次攻击推进。

PlayerBase 不引用 HitFeedbackBridge 或 HitFeedbackProfile。

## PlayerMeleeHitbox 查询暂停接口

新增：

```gdscript
func set_detection_suspended(active: bool) -> void
func is_detection_suspended() -> bool
```

暂停期间：

- 保留检测窗口、连击段、锁定方向与已命中目标集合。
- 继续用当前共享 `query_transform` 更新调试盒位置。
- 不执行 `intersect_shape()`，因此不会在卡刀期间命中新进入范围的目标。
- `end_detection()` 会同时清除暂停状态。

## 运行流程

```text
PlayerMeleeHitbox
        ↓ attack_hit
PlayerAttackController
        ↓ 原样转发
Effects/HitFeedbackBridge
        ├── set_hit_stop_active(true)
        └── Camera3D 随机衰减震动
```

同一攻击窗口命中多个敌人时，每个目标仍获得独立 `attack_hit` 信号，但 `minimum_feedback_interval` 内只播放一次卡刀与震动。

重复有效反馈不会创建多个协程或计时器：

- 卡刀剩余时间取现有值与新请求值中的较大值。
- 摄像机震动刷新剩余时间和当前强度。

## 卡刀期间输入与优先级

优先级：

```text
冲刺 > 卡刀 > 普通攻击流程
```

- 卡刀期间攻击输入仍可写入现有输入缓存，避免吞输入。
- 输入缓存、连击续接和轮次等待的剩余时间停止递减。
- 玩家常规移动、重力、目标锁定、AI 与游戏世界继续更新。
- 冲刺期间控制器立即取消当前攻击、解除卡刀、关闭 Hitbox 并清除剩余攻击位移。

## 摄像机震动

继续使用旧桥的局部加法式震动：

- 每帧获取当前 Viewport 的 Camera3D。
- 只修改 Camera3D 局部 X/Y 位置，不修改 CameraRig、旋转、FOV 或跟随参数。
- 每帧先移除上一帧偏移，再叠加新偏移。
- 震动按 `shake_decay_power` 衰减。
- 换镜头、效果结束或节点退出时精确移除最后偏移，避免位置漂移。

CameraRig 的现有平滑跟随继续独立运行。

## 故障安全

- 未装载 HitFeedbackBridge：攻击系统无反馈但正常运行。
- Profile 为空：桥禁用反馈，不改变攻击行为。
- 攻击来源无效：输出明确配置错误并停止桥处理。
- 重复启用或解除卡刀：幂等操作。
- 卡刀中目标失效：按既有剩余时间恢复，不依赖目标继续存在。
- 组件或场景退出：恢复 AnimationPlayer、攻击位移、Hitbox 查询与 Camera3D 偏移。

## 测试范围

- PlayerBase 存在稳定 `Effects` 插槽并正确装载旧 HitFeedbackBridge。
- 桥正确解析 `../../AttackController` 和旧 DefaultMeleeHitFeedback 资源。
- PlayerAttackController 提供旧桥所需卡刀接口。
- 三段命中分别使用 `1.2 / 1.3 / 1.5` 强度。
- 命中后动画、攻击位移和 Hitbox 查询同步暂停。
- 玩家 WASD、重力和摄像机震动继续运行。
- 恢复后动画从原位置继续，剩余攻击距离保持。
- 卡刀期间输入可以缓存，但各攻击状态计时不递减。
- 同帧多目标命中只触发一次反馈。
- 冲刺取消卡刀和当前攻击。
- 震动结束后 Camera3D 恢复准确局部位置。
- 删除桥后攻击系统保持独立可用。
- Godot 4.7 全部 UnitSystem 回归、编辑器扫描和运行扫描无错误或警告。
- 不修改或自动添加 TestScene 中的单位实例。

## 本阶段不实施

- 全局 `EffectsManager`。
- 伤害、击退、硬直、受击动画、音效或粒子。
- AI 新攻击系统的反馈迁移。
- 修改 CameraFollowController 或 TestScene 摄像机节点结构。
