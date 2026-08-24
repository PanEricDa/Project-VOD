# 临时近战命中检测与正式资产替换指南

## 当前临时措施

当前三连击的剑模型和挥动动画仅用于原型展示，剑刃位置不具备可靠的物理意义。因此命中检测没有挂在剑模型上，而是由独立的 `MeleeHitDetector` 按玩家稳定正前方执行盒形体积查询。

相关文件：

- `res://Scenes/Components/MeleeAttackModule.tscn`
- `res://Scripts/Combat/MeleeAttackModule.gd`
- `res://Scripts/Combat/MeleeHitDetector.gd`

当前三段临时攻击区域默认值：

| 连击段 | 宽 × 高 × 深 | 前向中心偏移 |
|---|---:|---:|
| 第一击 | 1.2 × 0.8 × 1.0 m | 0.65 m |
| 第二击 | 1.3 × 0.8 × 1.1 m | 0.70 m |
| 第三击 | 1.5 × 0.9 × 1.2 m | 0.80 m |

检测仅在 AnimationPlayer 方法轨道定义的 `hit_window_opened` 与 `hit_window_closed` 之间运行。检测方向读取 `Hero/Visual`，不会跟随临时剑位置，也不会受第三击 `AttackSpinPivot` 的视觉旋转影响。

同一攻击段使用目标实例 ID 去重，同一个敌人每段最多触发一次命中；进入下一段后允许再次命中。

## 当前公共接口

外部伤害、音效、特效或受击系统应只连接 `MeleeAttackModule.attack_hit`：

```gdscript
signal attack_hit(
    target: CharacterBody3D,
    hit_position: Vector3,
    hit_direction: Vector3,
    combo_index: int
)
```

- `target`：被命中的敌方根节点。
- `hit_position`：临时阶段通过玩家到目标的短射线估算；失败时回退到目标身体中心附近。
- `hit_direction`：玩家稳定正前方的水平单位向量。
- `combo_index`：当前连击段数，值为 1、2 或 3。

不要让后续伤害系统直接依赖 `BoxShape3D`、`DebugHitbox`、临时尺寸数组或当前剑节点路径。上述内容都是可替换实现细节。

## 调试显示

`MeleeHitDetector.debug_hitbox_enabled` 默认开启：

- 攻击窗口外隐藏。
- 有效窗口内尚未命中时显示黄色半透明盒体。
- 当前段命中任意目标后切换为红色半透明。
- `DebugHitbox` 使用 top-level 世界变换，不继承第三击视觉旋转。

正式版本发布前应关闭 `debug_hitbox_enabled`，或者删除 `DebugHitbox` 节点与对应调试材质代码。

## 正式动画资产接入步骤

1. 将正式角色模型、Skeleton3D、武器挂点和正式动画播放器接入角色视觉层。
2. 保留 `MeleeAttackModule.gd` 的连击状态、输入缓存、公开方法和公共信号。
3. 将 `attack_animation_names` 指向正式的三段攻击动画。
4. 在正式动画中重新放置以下方法轨道事件：
   - `_open_combo_window`
   - `_close_combo_window`
   - `_open_hit_window`
   - `_close_hit_window`
   - 可选的 `_request_lunge_for_current_attack`
   - 可选的 `_request_third_attack_spin`
5. 根据正式动画逐帧确认剑刃轨迹和有效攻击帧，替换当前临时时间窗口。
6. 保持 `MeleeAttackModule.attack_hit` 信号签名不变，避免伤害、特效和 UI 系统跟随检测实现一起重写。

## 正式命中检测重构建议

正式动画到位后，将 `MeleeHitDetector` 内部的固定盒形 `intersect_shape()` 替换为剑刃扫掠：

1. 在正式剑模型上设置 `BladeBase` 与 `BladeTip` 两个 Marker3D。
2. 每个物理帧保存两个 Marker 的上一帧和当前帧世界位置。
3. 使用 ShapeCast3D、胶囊扫掠或多段射线覆盖上一帧到当前帧之间的完整剑刃轨迹，避免高速挥剑穿透目标。
4. 从扫掠结果取得更准确的碰撞点和表面法线。
5. 继续沿用每段攻击的目标去重集合。
6. 继续通过同一个 `attack_hit(target, hit_position, hit_direction, combo_index)` 信号输出结果。

重构完成后可以删除以下临时字段：

- `hitbox_sizes`
- `forward_offsets`
- `hitbox_center_height`
- `query_shape`
- 固定盒形查询 Transform 的计算代码

## 后续伤害系统边界

当前检测器只报告命中，不处理生命值、伤害、硬直、击退、阵营关系扩展或死亡。正式实现建议由独立伤害系统监听 `attack_hit`，再调用敌人的统一受击接口，例如：

```gdscript
target.receive_hit(hit_data)
```

`hit_data` 后续可包含基础伤害、连击倍率、击退、伤害类型、攻击来源和表面法线。不要把这些逻辑写回临时动画或固定盒形检测代码中。

## 回退与拆卸

- 只需从 Hero 视觉层删除 `MeleeAttackModule` 实例，即可同时移除攻击动画、前移、第三击旋转和命中检测。
- `HeroController.gd` 不引用 `MeleeAttackModule` 或 `MeleeHitDetector`，删除模块不会破坏移动、冲刺、重力和目标锁定。
- 如果只想暂时关闭命中检测，可禁用 `MeleeHitDetector` 的物理处理或移除该子节点，并同步移除模块脚本中对检测器的连接与启停调用。
