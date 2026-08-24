# Warrior 剑士友方设计

## 目标

新增一个继承 `AllyBase.tscn` 的近战输出职业 `Warrior`。Warrior 沿用 Guardian 已验证的目标感知、接近、公共冷却、近战保持与归队逻辑，但装备独立的 AI 剑攻击模块，攻击距离略大于 Guardian，并从三种剑招中通过随机袋选择本次攻击动画。

本功能不复用玩家 `MeleeAttackModule.gd`，避免把 InputMap、玩家三连击、攻击前移、第三击旋转和玩家专用检测器带入 AI 系统。

## 场景结构

### Warrior

创建 `res://Scenes/ObjectScenes/Warrior.tscn`，继承 `res://Scenes/ObjectScenes/AllyBase.tscn`：

```text
Warrior (AllyBase)
└── VisualRoot
    ├── BodyMesh
    └── AttackModuleSocket
        └── SwordAttack
```

默认配置：

```text
BodyMesh.size = Vector3(0.5, 0.5, 0.5)
BodyMesh.position.y = 0.25
BodyMesh.material = MatGridRed.tres
combat_guard_distance = 1.5
attack_module_path = VisualRoot/AttackModuleSocket/SwordAttack
```

Warrior 与 Guardian 共用 `AllyBase` 的基础战斗调度，不新增职业 AI 决策脚本。

#### 场景装配约束

- `SwordAttack` 是节点自身的名称，不能把 `VisualRoot/AttackModuleSocket` 等层级文字写入节点名。
- `SwordAttack` 必须是 `VisualRoot/AttackModuleSocket` 的直接子节点，不能创建在 Warrior 根节点下。
- 完整解析路径固定为 `VisualRoot/AttackModuleSocket/SwordAttack`，并与 `attack_module_path` 保持一致。
- `VisualRoot_AttackModuleSocket#SwordAttack` 属于错误的场景节点名称/层级序列化结果，不是任何 GDScript 中声明的路径。出现该结构时，`AllyBase.get_node_or_null(attack_module_path)` 会返回 `null`，Warrior 因未装配攻击模块而不会攻击。
- 已确认本次故障源于创建节点时名称和层级关系放错；将节点改名为 `SwordAttack` 并放回 `AttackModuleSocket` 后恢复正常。

### SwordAttack

创建 `res://Scenes/Components/AiAttackModules/SwordAttack.tscn`，继承 `AttackModuleBase.tscn`：

```text
SwordAttack
├── WeaponPivot
│   ├── WeaponVisualRoot
│   │   ├── Blade
│   │   └── Handle
│   └── AttackOrigin
├── AttackAnimationPlayer
├── DeliveryRoot
│   └── HitboxDetector
└── HitFeedbackBridge
```

剑使用玩家当前临时剑的简化方块造型重新建立，但只属于 AI 模块。它自动继承父模块的 Hitbox 与命中停顿 Effect。

## 攻击 Profile

创建 `res://Resources/Combat/AI/WarriorSwordAttackProfile.tres`：

```text
display_name = "Warrior Sword Attack"
attack_range = 1.0
attack_range_tolerance = 0.1
approach_speed_multiplier = 1.2
return_to_guard_after_attack = false
```

Guardian 的盾击距离为 `0.8m`；Warrior 使用 `1.0m`，体现剑的触及范围稍长。普通攻击公共冷却继续使用 `AllyBase.basic_attack_global_cooldown`，默认 `1.0s`。

攻击结束后不回撤至警戒距离，而是在武器攻击范围附近轻微游荡并等待公共冷却结束。

## 随机剑招模块

创建 `res://Scripts/Combat/AI/SwordAttack.gd`，继承 `AIAttackModuleBase`。

导出接口：

```gdscript
@export var attack_animation_names: Array[StringName] = [
    &"attack_1",
    &"attack_2",
    &"attack_3"
]
```

行为规则：

1. 随机袋在第一次有效攻击请求时才复制有效动画名称并洗牌创建；一袋耗尽后的下一次有效请求再重新装满并洗牌。初始化与无效请求都不提前访问或消费随机袋，以兼容父节点尚未完成 `_ready()` 的生命周期。
2. 覆盖 `can_attack()`：只要模块处于 `IDLE`、Profile 与 AnimationPlayer 有效，并且列表中至少存在一个有效动画，就向 AllyBase 返回可攻击；不能依赖父类默认的单个 `attack_animation_name`。
3. 每次有效的 `request_attack(target)` 从袋中取出一个名称，并把父类本次使用的 `attack_animation_name` 切换为该名称；无效目标或不可攻击状态不会消耗随机袋。
4. 一袋内三招各出现一次；全部取完后重新洗牌。
5. 新一袋第一招若与上一袋最后一招相同，则与袋中另一个元素交换，避免跨轮连续重复。
6. 缺少或无效动画名称时跳过该项；没有任何有效动画时拒绝攻击并给出配置警告，不启动公共冷却。
7. 目标验证、攻击状态、命中窗口、取消、复位、命中信号和局部停顿仍由父类处理。

随机袋只决定视觉剑招，不形成玩家式连续三连击；每次攻击依然是一次独立普通攻击，并受 AllyBase 公共冷却约束。

## 三种动画

三个动画只修改 `WeaponPivot` 的局部位置与旋转：

- `attack_1`：约 `0.32s`，右向左横斩，命中窗口约 `0.10–0.22s`。
- `attack_2`：约 `0.36s`，反向斜斩，命中窗口约 `0.12–0.25s`。
- `attack_3`：约 `0.45s`，上举后向前下劈，命中窗口约 `0.18–0.34s`。

动画动作参考玩家现有三段剑招，但删除以下玩家专属方法轨道：

- 连击输入窗口。
- 攻击前移请求。
- 第三击角色旋转。

每个动画只保留 `_open_hit_window()` 和 `_close_hit_window()` 方法轨道。

## Hitbox 与反馈

SwordAttack 覆盖父模块配置：

```text
hitbox_enabled = true
HitboxDetector.position = Vector3(0, 0.35, -0.65)
BoxShape3D.size = Vector3(1.0, 0.7, 0.9)
target_collision_mask = 4
target_group = enemy_targets
debug_hitbox_enabled = true
```

检测盒固定在 Warrior 正前方，不跟随临时剑刃轨迹，以保证原型阶段判定稳定。每个攻击窗口对同一目标只命中一次，但可以命中多个敌人。

命中后自动使用父场景已经引用的 `DefaultAIHitFeedback.tres`：只暂停当前攻击动画与 Hitbox 查询，不震动摄像机，也不影响 AllyBase 移动、重力、AI 决策或公共冷却。

## 错误处理与边界

- 未装备 SwordAttack 时，Warrior 回退为 AllyBase 现有警戒游荡，不会接近至武器距离。
- Profile、动画或目标无效时，`request_attack()` 返回 `false`，AllyBase 不启动公共冷却。
- 取消、脱战、卸装和节点退出场景时，父模块负责关闭 Hitbox、解除命中停顿并恢复 RESET。
- 本阶段不加入伤害、生命值、击退、角色身体攻击动画、音效或粒子。
- 不修改或添加 `res://Scenes/TestScene.tscn` 中的任何单位实例。

## 验证标准

- Warrior 正确继承 AllyBase，身体尺寸、材质和攻击模块路径正确。
- SwordAttack 正确继承 AttackModuleBase，Profile 攻击距离为 `1.0m`。
- 三个动画存在、时长和命中窗口正确，且不包含玩家专属方法调用。
- 随机袋的一轮三次选择覆盖三种动画且不重复；跨袋边界不连续重复。
- `can_attack()` 在默认动画名为 `attack`、实际动画为 `attack_1/2/3` 时仍能让 AllyBase 正常进入接近和攻击流程。
- 无有效动画时攻击请求失败，不错误触发公共冷却契约。
- SwordAttack 的 Hitbox、命中信号与 AI 命中停顿保持可用。
- 现有 AI 战斗测试与新增 Warrior 测试全部通过。
- Godot 4.7 Headless 主场景启动无新增错误，Godot MCP 编辑器错误数为零。
- `TestScene.tscn` 保持不变；实现完成后由用户在编辑器中手动实例化 Warrior。
