# UnitBase Movement Hierarchy Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在不修改旧单位和 TestScene 的前提下，创建 PlayerBase、AIUnitBase、AllyBase2、EnemyBase2 及可拆分的 AI 移动组件。

**Architecture:** UnitBase 继续维护生命和阵营；PlayerBase 独立读取 InputMap 执行玩家移动；AIUnitBase 通过 MovementSystem 统一调度自动移动；AllyBase2 额外挂载 FormationComponent；EnemyBase2 暂时只使用通用重力和停驻能力。

**Tech Stack:** Godot 4.7、GDScript、CharacterBody3D、NavigationAgent3D、SceneTree headless tests。

## Global Constraints

- 所有字段、方法和信号使用英文标识；新增脚本提供详细简体中文注释。
- 不修改 `Scenes/TestScene.tscn`，不向其添加任何单位实例。
- 不修改旧 `Scenes/ObjectScenes/Hero.tscn`、`Scenes/ObjectScenes/AllyBase.tscn`、`Scenes/EnemyScenes/EnemyBase.tscn` 及其脚本。
- 本阶段不迁移目标锁定、敌人感知、攻击、技能、战斗站位或职业单位。
- `MovementSystem` 必须保持零位移、零旋转和单位缩放。
- 项目不是 Git 仓库，因此所有“提交”检查点改为文件清单和测试结果记录。

---

### Task 1: 新继承链场景契约测试

**Files:**
- Create: `UnitSystem/Tests/UnitHierarchyTest.gd`
- Create later: `UnitSystem/PlayerBase.tscn`
- Create later: `UnitSystem/AIUnitBase.tscn`
- Modify later: `UnitSystem/AllyBase2.tscn`
- Create later: `UnitSystem/EnemyBase2.tscn`

**Interfaces:**
- Consumes: `UnitBase` 的生命、阵营和 `CharacterBody3D` 根节点契约。
- Produces: 四个新场景必须满足的节点、脚本、阵营、碰撞层及旧系统隔离契约。

- [ ] **Step 1: 写失败测试**

测试加载四个场景并断言：

```gdscript
const PLAYER_SCENE := "res://UnitSystem/PlayerBase.tscn"
const AI_SCENE := "res://UnitSystem/AIUnitBase.tscn"
const ALLY_SCENE := "res://UnitSystem/AllyBase2.tscn"
const ENEMY_SCENE := "res://UnitSystem/EnemyBase2.tscn"

func _verify_player(player: UnitBase) -> void:
    assert(player.faction_id == "Player")
    assert(player.team_id == 1)
    assert(player.has_method("is_player_dashing"))

func _verify_ai(ai: UnitBase) -> void:
    assert(ai.has_node("MovementSystem/NavigationAgent3D"))
    assert(ai.has_node("MovementSystem/LocomotionComponent"))
    assert(not ai.has_node("MovementSystem/FormationComponent"))

func _verify_ally(ally: UnitBase) -> void:
    assert(ally.has_node("MovementSystem/FormationComponent"))
    assert(ally.faction_id == "Ally")
    assert(ally.team_id == 1)

func _verify_enemy(enemy: UnitBase) -> void:
    assert(not enemy.has_node("MovementSystem/FormationComponent"))
    assert(enemy.faction_id == "Enemy")
    assert(enemy.team_id == 2)
    assert(enemy.is_in_group("enemy_targets"))
```

测试同时读取新场景依赖，确认不引用旧 `HeroController.gd` 或旧 `AllyBase.gd`。

- [ ] **Step 2: 运行测试并确认失败**

Run:

```powershell
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' --headless --path 'G:\Godot\SipSip' --script 'res://UnitSystem/Tests/UnitHierarchyTest.gd'
```

Expected: FAIL，原因是 PlayerBase、AIUnitBase 和 EnemyBase2 尚不存在，AllyBase2 也没有 MovementSystem。

---

### Task 2: AI LocomotionComponent

**Files:**
- Create: `UnitSystem/Components/Movement/LocomotionComponent.gd`
- Create: `UnitSystem/Components/Movement/LocomotionComponent.tscn`
- Create: `UnitSystem/Tests/LocomotionComponentTest.gd`

**Interfaces:**
- Consumes: `CharacterBody3D`、`NavigationAgent3D`、`Node3D` Visual。
- Produces:

```gdscript
class_name LocomotionComponent
extends Node

func configure(
    owner_body: CharacterBody3D,
    navigation_agent: NavigationAgent3D,
    visual_root: Node3D
) -> bool
func set_movement_target(target_position: Vector3, maximum_speed: float = -1.0) -> void
func clear_movement_target() -> void
func has_movement_target() -> bool
func set_desired_facing(direction: Vector3) -> void
func request_dash(target_position: Vector3) -> bool
func physics_tick(delta: float) -> void
func can_dash() -> bool
func is_dashing() -> bool
func is_recovering() -> bool
func get_dash_cooldown_remaining() -> float
```

- [ ] **Step 1: 写失败测试**

测试覆盖：

```gdscript
_assert_true(component.configure(body, agent, visual), "valid dependencies configure")
component.set_movement_target(Vector3(2.0, 0.0, 0.0))
component.physics_tick(0.1)
_assert_true(body.velocity.x > 0.0, "movement target accelerates body")

_assert_true(component.request_dash(Vector3(5.0, 0.0, 0.0)), "dash starts")
_assert_true(component.is_dashing(), "dash state exposed")

component.clear_movement_target()
component.physics_tick(0.1)
_assert_true(not is_nan(body.velocity.y), "gravity remains valid")
```

另验证无 NavigationAgent 时 `configure()` 返回 false，组件不产生运行时崩溃。

- [ ] **Step 2: 运行测试并确认失败**

Expected: FAIL，原因是组件场景和脚本尚不存在。

- [ ] **Step 3: 实现最小 LocomotionComponent**

导出旧 Ally 默认运动参数：

```gdscript
@export var movement_speed: float = 4.2
@export var movement_acceleration: float = 20.0
@export var slowing_distance: float = 0.2
@export var arrival_distance: float = 0.15
@export var dash_speed: float = 9.0
@export var dash_max_distance: float = 3.0
@export var dash_arrival_distance: float = 0.35
@export var dash_cooldown: float = 1.5
@export var dash_recovery_duration: float = 0.2
@export var dash_acceleration: float = 40.0
@export var rotation_speed: float = 7.0
@export var gravity_multiplier: float = 1.0
```

内部状态使用 `IDLE / MOVING / DASHING / RECOVERING`。`physics_tick()` 必须按以下顺序执行：

```gdscript
_update_dash_cooldown(delta)
_update_horizontal_velocity(delta)
_apply_gravity(delta)
_update_visual_facing(delta)
var previous_position := owner_body.global_position
owner_body.move_and_slide()
_update_dash_distance_after_slide(previous_position)
```

NavigationAgent 尚未同步、路径结束或没有导航地图时，直接使用目标位置作为下一路径点。

- [ ] **Step 4: 运行测试并确认通过**

Expected: `LocomotionComponentTest: PASS`。

---

### Task 3: AIUnitBase 与 EnemyBase2

**Files:**
- Create: `UnitSystem/AIUnitBase.gd`
- Create: `UnitSystem/AIUnitBase.tscn`
- Create: `UnitSystem/EnemyBase2.gd`
- Create: `UnitSystem/EnemyBase2.tscn`
- Create: `UnitSystem/Tests/AIUnitBaseTest.gd`

**Interfaces:**
- Consumes: `UnitBase`、`LocomotionComponent`。
- Produces:

```gdscript
class_name AIUnitBase
extends UnitBase

func get_locomotion_component() -> LocomotionComponent
func _update_ai_movement(_delta: float) -> void
```

- [ ] **Step 1: 写失败测试**

测试实例化 AIUnitBase 并断言：

```gdscript
_assert_true(ai.get_node("MovementSystem") is Node3D, "movement root")
_assert_equal(ai.get_node("MovementSystem").transform, Transform3D.IDENTITY, "zero transform")
_assert_true(ai.get_locomotion_component() != null, "locomotion exposed")
```

实例化 EnemyBase2，运行若干物理帧并断言其水平速度保持零、垂直速度有效、阵营与分组正确。

- [ ] **Step 2: 运行测试并确认失败**

Expected: FAIL，原因是两个场景及脚本尚不存在。

- [ ] **Step 3: 创建 AIUnitBase**

节点：

```text
AIUnitBase (继承 UnitBase)
└── MovementSystem (Node3D)
    ├── NavigationAgent3D
    └── LocomotionComponent (实例)
```

`AIUnitBase._ready()` 调用 `super._ready()` 后配置组件。`_physics_process()`：

```gdscript
func _physics_process(delta: float) -> void:
    _update_ai_movement(delta)
    locomotion_component.physics_tick(delta)
```

`_update_ai_movement()` 是供子类覆写的空行为入口；默认先清空移动目标，因此无行为 AI 只受重力。

- [ ] **Step 4: 创建 EnemyBase2**

`EnemyBase2.gd` 只继承 `AIUnitBase`，不覆写移动决策。场景设置 Enemy 阵营、队伍 2、层 4、掩码 1 和 `enemy_targets` 分组。

- [ ] **Step 5: 运行测试并确认通过**

Expected: `AIUnitBaseTest: PASS`。

---

### Task 4: FormationComponent 与 AllyBase2

**Files:**
- Create: `UnitSystem/Components/Movement/FormationComponent.gd`
- Create: `UnitSystem/Components/Movement/FormationComponent.tscn`
- Create: `UnitSystem/AllyBase2.gd`
- Modify: `UnitSystem/AllyBase2.tscn`
- Create: `UnitSystem/Tests/FormationComponentTest.gd`
- Create: `UnitSystem/Tests/AllyBase2MovementTest.gd`

**Interfaces:**
- Consumes: `AIUnitBase.get_locomotion_component()`。
- Produces:

```gdscript
class_name FormationComponent
extends Node

signal formation_side_changed(new_side: int)

func configure(owner_body: CharacterBody3D, locomotion: LocomotionComponent) -> bool
func physics_tick(delta: float) -> void
func get_locked_side() -> int
func request_locked_side(side: int, refresh_target: bool = true) -> void
```

`AllyBase2` 转发：

```gdscript
signal formation_side_changed(new_side: int)
func get_formation_component() -> FormationComponent
func get_locked_formation_side() -> int
func request_formation_side(side: int, refresh_target: bool = true) -> void
```

- [ ] **Step 1: 写失败测试**

测试使用一个 PlayerBase 或轻量 UnitBase 玩家夹具：

```gdscript
formation.set("player_path", formation.get_path_to(player))
_assert_true(formation.configure(ally, locomotion), "formation configures")
formation.physics_tick(0.1)
_assert_true(locomotion.has_movement_target(), "formation submits movement")
```

继续验证：

- 玩家 Visual 正面优先于移动输入。
- `LOCKED_RANDOM_SIDE` 只生成当前侧目标。
- `request_locked_side(-1)` 更新侧向并发送一次信号。
- 距离玩家过远且冲刺可用时提出冲刺。
- 冲刺冷却结束且玩家持续移动、伙伴仍掉队时可再次提出冲刺。

- [ ] **Step 2: 运行测试并确认失败**

Expected: FAIL，原因是 FormationComponent 和 AllyBase2 脚本尚不存在。

- [ ] **Step 3: 实现 FormationComponent**

迁移旧 AllyBase 的 `BehaviorState` 与 `FormationSideMode`，但移除所有战斗状态。导出参数保持旧默认值：

```gdscript
front_distance = 2.5
formation_smoothness = 6.0
maximum_player_distance = 4.5
emergency_dash_distance = 5.5
wander_lateral_radius = 1.1
wander_lateral_minimum = 0.0
wander_forward_radius = 0.65
wander_interval_min = 1.5
wander_interval_max = 3.0
minimum_target_change_distance = 0.35
dash_turn_angle_threshold = 55.0
dash_trigger_distance = 1.5
dash_retry_distance = 2.5
dash_retry_player_speed_threshold = 0.5
direction_confirmation_time = 0.1
```

`physics_tick()` 只计算并提交意图：

```gdscript
_update_player_direction(delta)
_update_formation_center(delta)
_update_formation_side_lock(delta)
_update_behavior_state()
_update_idle_facing(delta)
_submit_current_movement()
```

不写 `velocity`，不调用 `move_and_slide()`，不读取敌人或技能。

- [ ] **Step 4: 重建 AllyBase2**

AllyBase2 继承 AIUnitBase，并在 `MovementSystem` 下实例化 FormationComponent。`_update_ai_movement()` 调用 FormationComponent 的 `physics_tick()`。设置 Ally 阵营、队伍 1、层 2 和掩码 1。

- [ ] **Step 5: 运行测试并确认通过**

Expected: `FormationComponentTest: PASS` 与 `AllyBase2MovementTest: PASS`。

---

### Task 5: PlayerBase

**Files:**
- Create: `UnitSystem/PlayerBase.gd`
- Create: `UnitSystem/PlayerBase.tscn`
- Create: `UnitSystem/Tests/PlayerBaseMovementTest.gd`

**Interfaces:**
- Consumes: 现有五个 InputMap action、UnitBase 的 `Visual`。
- Produces:

```gdscript
class_name PlayerBase
extends UnitBase

func is_player_dashing() -> bool
func get_available_dash_count() -> int
func get_dash_cooldown_remaining() -> float
```

- [ ] **Step 1: 写失败测试**

测试验证默认参数、InputMap 动作存在、玩家阵营和连续冲刺状态接口。通过 `Input.action_press()`/`Input.action_release()` 驱动物理帧，断言水平速度方向与斜向归一化。

- [ ] **Step 2: 运行测试并确认失败**

Expected: FAIL，原因是 PlayerBase 场景和脚本尚不存在。

- [ ] **Step 3: 迁移玩家移动**

从旧 HeroController 迁移：

```gdscript
var input_vector := Input.get_vector(
    &"player_move_left",
    &"player_move_right",
    &"player_move_forward",
    &"player_move_backward"
)
var movement_direction := Vector3(input_vector.x, 0.0, input_vector.y)
```

保留平滑加速、真实冲刺位移扣除、撞墙结束冲刺、连续次数耗尽后开始冷却、冷却后补满、重力和 Visual 平滑朝向。删除目标锁定相关调用，移动朝向优先级为“冲刺方向 → 当前输入方向 → 保持原朝向”。

PlayerBase 场景继承 UnitBase，设置 Player 阵营、队伍 1、层 2 和掩码 1。

- [ ] **Step 4: 运行测试并确认通过**

Expected: `PlayerBaseMovementTest: PASS`。

---

### Task 6: 集成验证与文档记录

**Files:**
- Modify: `Docs/CurrentImplementationSummary.md`
- Verify only: `Scenes/TestScene.tscn`
- Verify only: old Hero/Ally/Enemy scenes and scripts

**Interfaces:**
- Consumes: Tasks 1–5 的全部场景和测试。
- Produces: 可供后续职业逐个迁移的稳定新基类链。

- [ ] **Step 1: 运行 UnitSystem 全部测试**

逐个运行 `UnitSystem/Tests/*.gd`，Expected: 全部 PASS。

- [ ] **Step 2: 运行既有 SkillSystem 回归测试**

逐个运行 `SkillSystem/11-Tests/*.gd`，Expected: 全部 PASS。

- [ ] **Step 3: 执行 Godot 4.7 项目扫描**

```powershell
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' --headless --editor --path 'G:\Godot\SipSip' --quit
```

Expected: exit code 0，无新增脚本解析错误。

- [ ] **Step 4: 使用 MCP 验证**

重新扫描项目，分别验证 PlayerBase、AIUnitBase、LocomotionComponent、FormationComponent、AllyBase2 和 EnemyBase2 脚本可编译。

- [ ] **Step 5: 核对安全边界**

对实施前后记录的 SHA256 进行比较，确认 TestScene 和旧 Hero/Ally/Enemy 文件未改变。若用户在实施期间主动保存这些文件，只报告差异，不覆盖用户修改。

- [ ] **Step 6: 更新实施摘要**

记录新继承链、组件职责、当前未迁移范围和下一阶段职业迁移顺序。
