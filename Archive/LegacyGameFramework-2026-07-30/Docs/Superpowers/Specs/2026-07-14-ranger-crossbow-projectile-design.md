# Ranger 十字弓追踪抛物线射击设计

## 目标

为继承 `AllyBase.tscn` 的 Ranger 装配可拆装的 `CrossbowAttack` 普通攻击模块。Ranger 继续复用现有敌人感知、目标选择、攻击接近、朝向、普通攻击公共冷却、脱战和归队逻辑；武器模块负责射击动画与生成 Arrow，Arrow 独立负责快速抛物线追踪和抵达命中。

当前阶段保证箭矢命中仍然有效的移动目标，但只发送命中信号，不实现伤害、生命值、击退、受击动画或屏幕震动。

## 复用边界

### AllyBase

不加入任何箭矢或弹道代码，继续负责：

- 在感知范围内维护当前敌方目标。
- 根据武器 Profile 的 `attack_range` 接近目标。
- 成功开始攻击后启动 `basic_attack_global_cooldown`，默认 `1.0s`。
- 攻击期间保持面向目标并停止主动水平接近。
- 攻击结束后依据 Profile 决定近战保持或返回警戒距离。
- 目标失效、玩家脱战和模块卸下时取消当前攻击并恢复既有状态。

### CrossbowAttack

`res://Scenes/Components/AiAttackModules/CrossbowAttack.tscn` 继续继承 `AttackModuleBase.tscn`，使用独立脚本扩展远程发射，不复制 AllyBase 的战斗调度。

模块负责：

- 保存 Ranger 的临时十字弓模型。
- 播放一次普通射击动画。
- 在动画方法轨道指定的发射帧，从 `AttackOrigin` 生成一支 Arrow。
- 把 Arrow 的命中事件转换为父模块统一的 `attack_hit(target, hit_position, hit_direction)` 信号。
- 攻击取消、目标失效或发射配置错误时安全结束，不启动额外攻击任务。

`hitbox_enabled` 保持 `false`，远程攻击不使用父场景的近战 ShapeCast。

### Arrow

`res://Scenes/Projectiles/Arrow.tscn` 使用独立投射物脚本，只管理单支箭的视觉飞行和生命周期，不搜索目标、不选择阵营，也不计算攻击冷却。

## 场景结构

### Ranger

```text
Ranger (AllyBase)
└── VisualRoot
    ├── BodyMesh
    └── AttackModuleSocket
        └── CrossbowAttack
```

- 删除 Ranger 当前固定在 `VisualRoot` 下的 `CrossbowRoot` 及其武器子节点。
- 在 `VisualRoot/AttackModuleSocket` 下实例化节点名为 `CrossbowAttack` 的模块。
- `attack_module_path` 设置为 `VisualRoot/AttackModuleSocket/CrossbowAttack`。
- 节点名称只填写 `CrossbowAttack`，不得把父级路径编码进节点名称。

### CrossbowAttack

```text
CrossbowAttack (AttackModuleBase)
├── WeaponPivot
│   ├── WeaponVisualRoot
│   │   └── CrossbowRoot
│   │       ├── Stock
│   │       ├── BowLimbs
│   │       ├── Grip
│   │       └── LoadedBolt
│   └── AttackOrigin
├── AttackAnimationPlayer
├── DeliveryRoot
│   └── HitboxDetector (继承但禁用)
└── HitFeedbackBridge (继承但本模块关闭命中停顿)
```

`LoadedBolt` 只承担装填中的视觉占位。动画发射帧隐藏它，攻击复位时重新显示；实际飞行物始终由 Arrow 场景创建。

### Arrow

```text
Arrow (Node3D)
└── ArrowVisual
```

Arrow 添加到当前运行场景的独立节点层级，不作为 Ranger 或 CrossbowAttack 的子节点继续飞行，因此不会继承射手后续的移动或旋转。

## 攻击 Profile

新增 Ranger 专用 `AIAttackProfile` 资源，默认值：

```text
display_name = "Ranger Crossbow Shot"
attack_range = 6.5
attack_range_tolerance = 0.4
approach_speed_multiplier = 1.0
return_to_guard_after_attack = false
```

实施期间用户将 Ranger 源场景的 `combat_guard_distance` 调整为 `5.0m`、`enemy_vision_range` 调整为 `6.5m`；攻击模块装配保留这些 Inspector 值。首次进入 `6.5m` 攻击距离并射击后，Ranger 不返回警戒距离，而是在 `6.5m ± 0.4m` 附近复用 AllyBase 现有战斗游荡和距离保持逻辑。

公共冷却继续由 Ranger 持有的 `AllyBase.basic_attack_global_cooldown` 控制，默认 `1.0s`。箭矢飞行速度不改变普通攻击频率。

## 射击时序

射击动画建议总长约 `0.35s`：

```text
0.00–0.08s：轻微抬弩并准备发射
约 0.12s：调用 _release_projectile()，生成一支 Arrow
0.12–0.22s：轻微后坐
0.22–0.35s：恢复 RESET 姿态并显示 LoadedBolt
```

一次成功的 `request_attack(target)` 最多生成一支箭。是否生成箭由攻击模块内部的单次发射标记保护，动画方法轨道重复调用也不得生成第二支。

攻击动画结束后模块立即恢复 `IDLE`，能否再次射击仍由 AllyBase 的公共冷却决定。

## Arrow 追踪抛物线

### 初始化接口

Arrow 提供显式初始化接口：

```gdscript
func launch(
    target: CharacterBody3D,
    start_position: Vector3,
    flight_duration: float,
    arc_height: float,
    target_height_offset: float,
    maximum_lifetime: float
) -> bool
```

返回 `true` 表示目标和参数有效并开始飞行；返回 `false` 时调用者立即销毁该实例且不发送命中。

公开信号：

```gdscript
signal projectile_hit(
    target: CharacterBody3D,
    hit_position: Vector3,
    hit_direction: Vector3
)
```

### 默认参数

```text
flight_duration = 0.30s
arc_height = 0.80m
target_height_offset = 0.25m
maximum_lifetime = 2.0s
```

这些参数由 CrossbowAttack 导出到 Inspector，并在生成 Arrow 时注入，使后续其他弓、弩或法术模块可以复用 Arrow 而使用不同速度与弧高。

### 轨迹算法

Arrow 在发射时保存世界起点，并以固定 `flight_duration` 推进归一化进度：

```text
progress = clamp(elapsed_time / flight_duration, 0, 1)
tracked_end = target.global_position + Vector3.UP * target_height_offset
base_position = lerp(start_position, tracked_end, progress)
arc_offset = Vector3.UP * sin(progress * PI) * arc_height
arrow_position = base_position + arc_offset
```

- 每帧重新读取 `tracked_end`，因此目标移动时箭矢会平滑修正剩余路径并保证抵达目标。
- 飞行进度不会因目标移动而重置，默认约 `0.30s` 后必定结束。
- 箭矢视觉朝向使用本帧位置相对上一帧位置的方向，使模型沿实际飞行切线转向。
- 抛物线只是一种受控视觉轨迹，不使用 RigidBody3D 重力或真实弹道解算。

## 命中与异常规则

- 当 `progress` 到达 `1.0` 且目标仍有效、仍在场景树中时，Arrow 将自身放到最新目标点，发送一次 `projectile_hit`，随后销毁。
- CrossbowAttack 接收该事件并转发父模块的统一 `attack_hit` 信号。
- 目标在飞行期间被删除、退出场景树或不再有效时，Arrow 立即销毁，不发送命中。
- `maximum_lifetime` 是异常保险；超过该时间仍未结束时直接销毁。
- Arrow 不依赖碰撞层和 Area3D，当前阶段不会被墙体或其他单位阻挡，也不会误中路径上的单位。
- 同一支箭只能发送一次命中；CrossbowAttack 的攻击动画结束不销毁已经发射的箭。
- 本阶段 CrossbowAttack 设置 `hit_feedback_enabled = false`，箭矢命中不触发 AI 局部卡刀；统一 `attack_hit` 接口仍保留给未来伤害和远程反馈系统。

## Ranger 战斗行为

1. Ranger 感知并选择目标。
2. 公共冷却可用时，从警戒状态接近至 `6.5m ± 0.4m`。
3. CrossbowAttack 成功开始，AllyBase 启动默认 `1.0s` 公共冷却。
4. Ranger 在攻击动画期间停止主动水平移动并保持面向目标。
5. 箭矢在发射帧生成，以约 `0.30s` 的追踪抛物线抵达目标。
6. 攻击结束后进入现有 `HOLD`，不返回当前 `5.0m` 警戒距离。
7. 冷却期间在攻击距离附近轻微游荡；目标过远则重新接近，目标过近则通过距离保持向外调整。
8. 冷却结束且目标有效时直接开始下一次普通射击。
9. 目标失效或现有强制脱战规则生效时退出攻击循环并返回玩家编队。

## 测试与验收

- Ranger 正确继承 AllyBase，CrossbowAttack 位于 `VisualRoot/AttackModuleSocket` 下，路径完全一致。
- 十字弓模型已从 Ranger 固定视觉迁移到 CrossbowAttack，材质和现有外观保持不变。
- CrossbowAttack 使用 Ranger Profile，射程为 `6.5m`，攻击后不返回警戒距离。
- 成功攻击才启动 `1.0s` 公共冷却；一次攻击只发射一支箭。
- Arrow 默认约 `0.30s` 抵达目标，中点具有接近 `0.80m` 的额外弧高。
- 目标移动时 Arrow 继续追踪并最终命中最新位置。
- 目标失效时 Arrow 安全销毁且不发送命中。
- Arrow 命中通过 CrossbowAttack 转发为一次统一 `attack_hit`。
- 远程模块不启用近战 ShapeCast，也不触发当前 AI 命中停顿。
- 攻击结束后 Ranger 在攻击距离进入 HOLD，并复用既有战斗游荡。
- 未装备或配置无效时 Ranger 保持现有警戒游荡，不报运行时错误。
- Godot 4.7 脚本编译、Headless 测试和编辑器错误检查通过。
- 不由 Codex 修改或重新添加 `TestScene.tscn` 中的 Ranger 实例；如需新增单位，由用户在 Godot 编辑器中手动完成。

## 暂缓范围

- 实际伤害、生命值、击退、受击状态和死亡。
- 障碍物遮挡、弹体碰撞、友军阻挡和落空概率。
- 真实重力弹道、弹速单位换算和提前量预测。
- 弹药数量、装填时间、多重射击和暴击。
- 箭矢命中特效、音效、粒子、插入目标或对象池。
- 正式骨骼动画、弩弦动画和正式武器挂点。
