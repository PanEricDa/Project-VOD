# Ally Formation / Combat 单状态机设计

## 1. 目标

为新 `AllyBase2` 建立一个单节点、单移动所有权的行为状态机，统一管理当前已经成熟的
Formation 行为和第一阶段 Combat 移动行为。

本阶段只实现以下闭环：

```text
编队游荡
→ 编队追赶
→ 发现敌人
→ 接近战斗距离
→ 保持战斗距离并轻微游荡
→ 目标失效或玩家脱战
→ 返回编队
```

本阶段不接入普通攻击、技能、伤害、攻击冷却或职业战斗模块。

## 2. 职责边界

最终节点结构：

```text
AllyBase2
├── Visual
├── CollisionShape3D
├── MovementSystem
│   └── NavigationAgent3D
├── AITargetingComponent
└── BehaviorStateMachine
```

各层职责如下：

- `AIUnitBase`：唯一执行导航、水平速度、冲刺、重力、视觉转向和
  `move_and_slide()`。
- `AITargetingComponent`：扫描候选目标、应用选择策略、维护当前锁定目标。
- `AllyBehaviorStateMachine`：唯一决定 Ally 当前行为，向 `AIUnitBase` 提交本帧
  移动与朝向意图。
- `AllyBase2`：装配组件、调用状态机、转发公共信号，不保存第二套 Formation 或
  Combat 算法。

现有 `FormationComponent` 的编队中心、方向稳定、随机游荡、分侧、归位和追赶冲刺
算法完整迁入 `AllyBehaviorStateMachine`。迁移验证通过后删除
`FormationComponent.gd/.tscn/.gd.uid`，不保留并行实现。

## 3. 基础状态

状态机使用一个可读的扁平枚举：

```gdscript
enum BehaviorState {
    FORMATION_WANDER,
    FORMATION_REPOSITION,
    COMBAT_APPROACH,
    COMBAT_HOLD,
    RETURN,
    CUSTOM,
}
```

### 3.1 `FORMATION_WANDER`

- 使用现有编队中心和分侧算法。
- 在编队允许区域内按 `1.5～3.0s` 间隔选择随机游荡点。
- 正常移动时允许朝向移动方向。
- 获得有效目标后切换到 `COMBAT_APPROACH`。
- 距离编队中心过远或玩家方向发生需要追赶的变化时切换到
  `FORMATION_REPOSITION`。

### 3.2 `FORMATION_REPOSITION`

- 追赶当前编队中心。
- 保留现有玩家距离、方向变化确认和紧急冲刺判断。
- 返回稳定编队区域后切换到 `FORMATION_WANDER`。
- 追赶期间获得有效目标时，Combat 拥有更高优先级，切换到
  `COMBAT_APPROACH`。

### 3.3 `COMBAT_APPROACH`

- Formation 不再计算或提交移动目标。
- 状态机沿目标方向计算战斗距离环上的接近点。
- 使用正常 AI 导航靠近该点。
- 到达 `preferred_combat_distance ± combat_distance_tolerance` 后切换到
  `COMBAT_HOLD`。
- 移动期间仍持续面向目标，不面向移动方向。

### 3.4 `COMBAT_HOLD`

- 距离大于允许上限时切回 `COMBAT_APPROACH`。
- 距离小于允许下限时向外调整到战斗距离。
- 位于允许环带时，沿目标周围进行低速、轻微的切向随机游荡。
- 战斗游荡复用 Formation 的随机刷新计时和目标生成基础方法，不运行第二套
  Formation 状态。
- 全程持续面向当前目标。

### 3.5 `RETURN`

- 目标失效或强制脱战后进入。
- 直接返回当前编队中心，不执行战斗距离计算。
- 进入稳定编队区域后切换到 `FORMATION_WANDER`。
- 如果索敌没有处于强制暂停，返回途中重新获得有效目标时可以进入
  `COMBAT_APPROACH`。

### 3.6 `CUSTOM`

`CUSTOM` 是唯一预留的外部行为扩展入口。未来的休息、互动、庆祝、采集或剧情行为
通过一个 `custom_state_id` 和上下文字典进入，不在当前阶段创建多个空枚举、节点或
Resource。

默认状态机不支持任何自定义状态。未实现的请求返回 `false`，不会改变当前状态或
移动意图。

## 4. 固定优先级与转换规则

状态判定按以下顺序执行：

```text
有效 CUSTOM
→ 玩家强制脱战
→ 当前目标失效
→ 有效目标进入或维持 Combat
→ RETURN
→ Formation
```

详细转换：

| 当前状态 | 条件 | 下一状态 |
|---|---|---|
| `FORMATION_WANDER` | 编队距离或方向需要追赶 | `FORMATION_REPOSITION` |
| `FORMATION_REPOSITION` | 回到稳定编队区域 | `FORMATION_WANDER` |
| 任意 Formation 状态 | 获得有效敌方目标 | `COMBAT_APPROACH` |
| `COMBAT_APPROACH` | 进入战斗距离环带 | `COMBAT_HOLD` |
| `COMBAT_HOLD` | 距离超过环带上限 | `COMBAT_APPROACH` |
| 任意 Combat 状态 | 目标失效 | `RETURN` |
| 任意 Combat 状态 | 玩家距目标超过 `12m` | `RETURN` |
| `RETURN` | 回到稳定编队区域 | `FORMATION_WANDER` |
| `RETURN` | 正常索敌获得有效目标 | `COMBAT_APPROACH` |
| 任意基础状态 | 有效自定义请求 | `CUSTOM` |
| `CUSTOM` | 主动退出或实现方结束 | `RETURN` |

所有状态变化统一通过 `_transition_to()`，进入、更新、退出逻辑不允许直接散落修改
当前状态。每个物理帧只调用当前状态的一个更新函数，确保没有多个行为同时提交移动
目标。

## 5. 战斗距离与游荡

`BehaviorStateMachine` 提供以下可由每个 Ally 继承场景单独覆盖的参数：

```gdscript
@export_range(0.1, 30.0, 0.1, "or_greater")
var preferred_combat_distance: float = 2.0

@export_range(0.0, 5.0, 0.05)
var combat_distance_tolerance: float = 0.25

@export_range(0.0, 5.0, 0.05)
var combat_wander_radius: float = 0.45

@export_range(0.0, 1.0, 0.05)
var combat_wander_speed_multiplier: float = 0.35

@export_range(1.0, 50.0, 0.5, "or_greater")
var maximum_player_target_distance: float = 12.0

@export_range(0.0, 10.0, 0.1)
var disengage_targeting_cooldown: float = 1.5
```

战斗距离使用水平距离计算，忽略双方高度差。目标环带为：

```text
[preferred_combat_distance - combat_distance_tolerance,
 preferred_combat_distance + combat_distance_tolerance]
```

下限最小按 `0m` 处理，所有速度倍率在运行时进行安全钳制。战斗游荡点始终限制在
目标周围的小范围环带内，不加入防重叠、单位避让或位置预约系统。

## 6. 脱战与索敌暂停

当玩家与当前目标的水平距离超过 `12m`：

1. 清除当前锁定目标。
2. 让 `AITargetingComponent` 暂停扫描 `1.5s`。
3. 状态机进入 `RETURN`。
4. 暂停期间范围圈继续显示，但使用未锁定颜色。
5. 暂停结束后直接恢复原有正常索敌策略。

暂停结束后不增加“敌人必须位于玩家 10m 内”等额外筛选条件。

普通目标失效或离开锁定保持范围时也进入 `RETURN`，但不会自动触发这段强制脱战
暂停。现有索敌双半径规则继续负责减少目标边缘反复丢失。

`AITargetingComponent` 新增：

```gdscript
func suspend_detection(
    duration: float,
    clear_target: bool = true
) -> void

func get_detection_suspend_remaining() -> float
```

该接口只暂停运行时扫描，不修改 Inspector 中持久化的 `detection_enabled`。

## 7. AIUnitBase 朝向接口扩展

为支持“横向移动但持续面向敌人”，公共运动接口扩展为：

```gdscript
func set_movement_target(
    target_position: Vector3,
    maximum_speed: float = -1.0,
    face_movement_direction: bool = true
) -> void
```

- Formation 与 Return 使用默认值 `true`。
- Combat 使用 `false`，并调用 `set_desired_facing()` 提交目标方向。
- 清除移动目标和运动状态复位时恢复默认朝向策略，避免战斗设置泄漏到 Formation。
- 现有两参数调用保持兼容。

## 8. 公共接口与信号

`AllyBehaviorStateMachine`：

```gdscript
signal state_changed(
    previous_state: BehaviorState,
    current_state: BehaviorState
)

signal formation_side_changed(new_side: int)

func configure(
    owner_body: AIUnitBase,
    targeting_component: AITargetingComponent
) -> bool

func physics_tick(delta: float) -> void
func get_current_state() -> BehaviorState
func get_current_state_name() -> StringName
func is_in_combat() -> bool

func request_formation_side(
    side: int,
    refresh_target: bool = true
) -> void

func request_custom_state(
    custom_state_id: StringName,
    context: Dictionary = {}
) -> bool

func exit_custom_state() -> void
```

自定义状态覆写钩子：

```gdscript
func _supports_custom_state(custom_state_id: StringName) -> bool
func _enter_custom_state(
    custom_state_id: StringName,
    context: Dictionary
) -> void
func _update_custom_state(
    custom_state_id: StringName,
    delta: float
) -> void
func _exit_custom_state(custom_state_id: StringName) -> void
```

`AllyBase2` 保留现有 `formation_side_changed` 与 `locked_target_changed` 转发，并新增
`behavior_state_changed`。它提供：

```gdscript
func get_behavior_state_machine() -> AllyBehaviorStateMachine
```

旧 `get_formation_component()` 随旧组件删除。`request_formation_side()` 保留，但改为
转发到状态机，避免职业分侧调用方失去明确入口。

## 9. 配置失败与安全降级

- `AIUnitBase` 宿主无效：`configure()` 返回 `false`，状态机不启用物理更新。
- 玩家暂时无法解析：清除主动移动目标并等待后续帧重新解析，不重复刷屏报错。
- 索敌组件缺失：Formation 和 Return 仍可运行，Combat 不会进入。
- 目标在当前帧释放：先验证实例，再进入 `RETURN`，不读取失效节点属性。
- 不支持的 `CUSTOM`：返回 `false`，当前状态不变。
- 自定义状态退出：统一进入 `RETURN`，让移动控制安全回归基础状态机。
- 战斗参数出现无效组合：运行时钳制为非负距离和有效速度，不中断游戏。

## 10. 文件变更

新增：

```text
UnitSystem/Components/Behavior/AllyBehaviorStateMachine.gd
UnitSystem/Components/Behavior/AllyBehaviorStateMachine.tscn
UnitSystem/Tests/AllyBehaviorStateMachineTest.gd
```

修改：

```text
UnitSystem/Base/AIUnitBase.gd
UnitSystem/AI/Ally/AllyBase2.gd
UnitSystem/AI/Ally/AllyBase2.tscn
UnitSystem/Components/Targeting/AI/AITargetingComponent.gd
UnitSystem/Tests/AITargetingComponentTest.gd
UnitSystem/Tests/AllyInheritedRootRenameTest.gd
UnitSystem/Tests/AllyTargetingIntegrationTest.gd
UnitSystem/Tests/AIUnitBaseLocomotionMigrationTest.gd
UnitSystem/Tests/UnitDirectoryLayoutTest.gd
```

删除：

```text
UnitSystem/Components/Movement/FormationComponent.gd
UnitSystem/Components/Movement/FormationComponent.tscn
UnitSystem/Components/Movement/FormationComponent.gd.uid
```

## 11. 验证标准

- 五个基础状态按照设计条件稳定转换。
- 每帧只有当前状态提交移动与朝向意图。
- Formation 原有编队中心、分侧、游荡、追赶和冲刺行为保持。
- 获得目标后停止 Formation 计算，接近并保持战斗距离。
- `COMBAT_HOLD` 能处理过远、过近和环带内轻微游荡。
- 战斗移动期间始终面向目标。
- 玩家距目标超过 `12m` 时强制脱战并暂停索敌 `1.5s`。
- 暂停到期后恢复现有正常索敌，不增加额外筛选。
- `CUSTOM` 默认拒绝未知状态，扩展钩子可由未来子类覆写。
- Amy 继承场景改名后仍能加载和运行。
- 现有索敌范围圈与目标颜色变化保持正常。
- 所有 UnitSystem 测试、Godot 4.7 编辑器扫描和无窗口运行通过。
- MCP 运行检查中 Amy 可完成 Formation、Combat 和 Return 闭环。
- 不修改 `Scenes/TestScene.tscn` 或 `Scenes/TestScene2.tscn` 中的任何单位实例。

## 12. 暂缓范围

本阶段不实现：

- 普通攻击或技能请求。
- 攻击距离与武器距离。
- 公共冷却、施法时间或攻击动画。
- 伤害、Hitbox、受击反馈和生命值变化。
- 玩家策略指令或玩家目标覆盖。
- 仇恨、威胁评分和高级目标选择。
- 多伙伴战斗位置协调、防重叠和包围槽位。
- EnemyBase2 的战斗状态机。

