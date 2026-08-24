# UnitBase 移动继承链重建设计

## 1. 目标与迁移方式

在 `UnitSystem` 下并行建立新的单位继承链，将玩家控制移动和 AI 自动移动从旧综合脚本中安全拆出。旧 Hero、AllyBase、EnemyBase、职业场景和 TestScene 均保持不变，待新基类验证稳定后再逐个迁移。

```text
UnitBase
├── PlayerBase
└── AIUnitBase
    ├── AllyBase2
    └── EnemyBase2
```

`UnitBase` 继续只表示单位身份，维护生命、阵营关系和目标有效性，不增加任何移动算法。

## 2. 文件结构

```text
UnitSystem/
├── 00_UnitBase.gd
├── 00_UnitBase.tscn
├── PlayerBase.gd
├── PlayerBase.tscn
├── AIUnitBase.gd
├── AIUnitBase.tscn
├── AllyBase2.gd
├── AllyBase2.tscn
├── EnemyBase2.gd
├── EnemyBase2.tscn
├── Components/
│   └── Movement/
│       ├── LocomotionComponent.gd
│       ├── LocomotionComponent.tscn
│       ├── FormationComponent.gd
│       └── FormationComponent.tscn
└── Tests/
```

## 3. PlayerBase

`PlayerBase` 直接继承 `UnitBase`，不继承任何 AI 节点。根脚本读取现有 InputMap：

- `player_move_left`
- `player_move_right`
- `player_move_forward`
- `player_move_backward`
- `player_dash`

迁移旧 HeroController 中以下行为及默认值：

- 平面移动：速度 `4.0`，加速度 `24.0`。
- 视觉朝向：转速 `12.0`。
- 玩家冲刺：距离 `2.5m`、速度 `10.0m/s`、连续次数 `2`、冷却 `2.0s`。
- 项目默认重力与稳定贴地。
- `last_movement_direction` 继续公开，供友方编队在玩家视觉节点不可用时兜底读取。

本阶段不迁移鼠标目标锁定、最近目标锁定、锁定范围指示圈、玩家近战模块、命中反馈或摄像机逻辑。未来目标锁定可以通过独立组件向 PlayerBase 提供朝向覆盖，而不重新混入移动实现。

默认阵营配置：

```text
faction_id = Player
team_id = 1
collision_layer = 2
collision_mask = 1
```

## 4. AIUnitBase 与 MovementSystem

`AIUnitBase` 继承 `UnitBase`，并建立所有自动移动单位共享的节点：

```text
AIUnitBase
└── MovementSystem (Node3D，保持零变换)
    ├── NavigationAgent3D
    └── LocomotionComponent
```

`AIUnitBase` 是移动调度器：

1. 先调用子类行为入口更新本帧移动意图。
2. 再调用 `LocomotionComponent` 执行速度、重力、朝向和 `move_and_slide()`。

子类只提交移动意图，不直接写入 `CharacterBody3D.velocity`，保证同一物理帧只有一个运动执行者。

### LocomotionComponent 职责

- NavigationAgent3D 路径点读取和无导航地图时的直线回退。
- 平滑加速、到达减速和停止。
- 重力与稳定贴地。
- 平滑旋转 `Visual`。
- 通用单次 AI 追赶冲刺、冲刺距离、冷却和恢复。
- 公开移动目标、停止、朝向、冲刺及状态查询接口。

它不读取玩家、不计算编队、不搜索敌人，也不决定何时攻击。

## 5. AllyBase2 与 FormationComponent

`AllyBase2` 继承 `AIUnitBase`，在继承的 `MovementSystem` 下增加：

```text
MovementSystem
└── FormationComponent
```

`FormationComponent` 从旧 AllyBase 迁移以下已验证行为：

- 读取玩家 `Visual` 的实际正面作为编队参照。
- 视觉节点不可用时，依次回退到玩家速度和 `last_movement_direction`。
- 前后编队距离和编队中心平滑。
- 椭圆区域随机游荡，默认换点间隔 `1.5～3.0s`。
- 自由跨侧、随机锁侧、固定左侧和固定右侧。
- 进入区域后才允许离区重选，避免后排角色反复横跳。
- 玩家明显转向时请求冲刺。
- 玩家持续移动且伙伴掉队时，在冷却结束后允许再次冲刺。
- 距离过远时紧急返回编队。
- 待机时面向玩家正面，移动时面向移动方向。

组件只计算编队目标并调用 `LocomotionComponent` 的公共接口，不应用重力、不调用 `move_and_slide()`。

为未来 Mage/Ranger 协调保留公开接口：

```gdscript
signal formation_side_changed(new_side: int)

func get_locked_side() -> int
func request_locked_side(side: int, refresh_target: bool = true) -> void
```

本阶段不迁移敌人感知、警戒距离、战斗游荡、攻击接近、普通攻击、技能施法接近或战斗脱离。

默认阵营配置：

```text
faction_id = Ally
team_id = 1
collision_layer = 2
collision_mask = 1
```

## 6. EnemyBase2

`EnemyBase2` 继承 `AIUnitBase`，当前不安装具体行为组件。因此它只通过 `LocomotionComponent` 应用重力并稳定停留，作为未来巡逻、追击和返回出生点行为的宿主。

默认配置：

```text
faction_id = Enemy
team_id = 2
collision_layer = 4
collision_mask = 1
group = enemy_targets
```

## 7. 生命周期与错误处理

- 所有子类 `_ready()` 必须调用 `super._ready()`，确保 UnitBase 初始化生命值。
- AIUnitBase 启动时验证 `MovementSystem`、`NavigationAgent3D`、`LocomotionComponent` 和 `Visual`。
- 必需节点缺失时输出明确配置错误并停止该单位的物理处理，不影响其他单位。
- AllyBase2 找不到玩家时停止编队决策，但仍让 LocomotionComponent 处理重力。
- MovementSystem 必须保持零位移、零旋转和单位缩放，确保导航代理与单位根节点同步。

## 8. 验证边界

- UnitBase 原有健康与阵营测试保持通过。
- PlayerBase 使用 InputMap 完成移动、冲刺计数和冷却。
- AIUnitBase 的运动执行顺序为“行为决策 → Locomotion 执行”。
- AllyBase2 能跟随玩家正面、游荡、锁侧、掉队追赶并重复冲刺。
- EnemyBase2 在无行为组件时不会产生水平移动，但仍受重力。
- 新场景不依赖旧 `HeroController.gd` 或旧 `AllyBase.gd`。
- 所有旧场景文件和 `Scenes/TestScene.tscn` 保持不变。
- Godot 4.7 脚本编译、headless 测试和项目扫描通过。
