# Ally AI Autonomous Targeting Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为 `AllyBase2` 增加持续球形感知、双半径稳定锁定和单脚本 Policy Resource 驱动的自主索敌能力。

**Architecture:** `AITargetingComponent` 使用一个 `Area3D` 每隔 `0.2s` 读取重叠物体，当前目标在 `7m` 保持半径内持续锁定，无目标时将 `6m` 获取范围内的 `UnitBase` 候选交给 `TargetSelectionPolicy`。`AllyBase2` 只负责配置组件、转发信号和开放读取接口，不改变编队移动。

**Tech Stack:** Godot 4.7、GDScript、`Area3D`、`SphereShape3D`、`Resource`、headless `SceneTree` 测试。

## Global Constraints

- 所有新增字段和方法使用英文标识，新增代码提供详细简体中文注释。
- 不修改 `res://Scenes/TestScene.tscn` 或其中的任何单位实例。
- 不实现追击、面向、攻击、技能、玩家策略或视野可视化。
- 所有 Policy `.tres` 只引用同一个 `TargetSelectionPolicy.gd`。
- 当前项目不是 Git 仓库，不执行提交步骤，以测试输出作为交付依据。

---

## File Map

- Create `UnitSystem/Components/Targeting/AI/Policies/TargetSelectionPolicy.gd`：保存统一筛选配置并选择最近有效目标。
- Create `UnitSystem/Components/Targeting/AI/Policies/DefaultNearestEnemy.tres`：第一版默认敌方最近目标配置。
- Create `UnitSystem/Components/Targeting/AI/AITargetingComponent.gd`：管理感知、刷新、锁定生命周期和 Policy 装卸。
- Create `UnitSystem/Components/Targeting/AI/AITargetingComponent.tscn`：可拖放的 `Area3D` 组件场景。
- Create `UnitSystem/Tests/TargetSelectionPolicyTest.gd`：验证 Policy 筛选和优先级。
- Create `UnitSystem/Tests/AITargetingComponentTest.gd`：验证持续扫描、双半径和稳定锁定。
- Modify `UnitSystem/AI/Ally/AllyBase2.gd`：配置组件、转发信号和公开读取接口。
- Modify `UnitSystem/AI/Ally/AllyBase2.tscn`：实例化索敌组件。
- Create `UnitSystem/Tests/AllyTargetingIntegrationTest.gd`：验证 Ally 装配与现有编队结构。
- Modify `UnitSystem/Tests/UnitDirectoryLayoutTest.gd`：将新文件加入目录契约。

### Task 1: TargetSelectionPolicy Resource

**Files:**
- Create: `UnitSystem/Tests/TargetSelectionPolicyTest.gd`
- Create: `UnitSystem/Components/Targeting/AI/Policies/TargetSelectionPolicy.gd`
- Create: `UnitSystem/Components/Targeting/AI/Policies/DefaultNearestEnemy.tres`

**Interfaces:**
- Consumes: `UnitBase.is_hostile_to()`, `is_friendly_to()`, `is_targetable()`, `is_dead()`.
- Produces:
  - `is_candidate_valid(owner_unit: UnitBase, candidate: UnitBase, maximum_distance: float) -> bool`
  - `calculate_priority(owner_unit: UnitBase, candidate: UnitBase) -> float`
  - `select_target(owner_unit: UnitBase, candidates: Array[UnitBase], maximum_distance: float) -> UnitBase`

- [ ] **Step 1: Write a failing policy test**

Create a headless `SceneTree` test that instantiates lightweight `UnitBase` nodes with team IDs and positions, then verifies:

```gdscript
var selected: UnitBase = policy.select_target(
    owner,
    [far_enemy, ally, dead_enemy, near_enemy],
    6.0
)
_expect(selected == near_enemy, "nearest valid hostile target is selected")
```

It must also verify self, friendly, neutral, dead, untargetable and out-of-range candidates are rejected.

- [ ] **Step 2: Run the test and verify RED**

Run:

```powershell
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' --headless --path 'G:\Godot\SipSip' --script res://UnitSystem/Tests/TargetSelectionPolicyTest.gd
```

Expected: non-zero exit because `TargetSelectionPolicy` and its resource do not yet exist.

- [ ] **Step 3: Implement the single policy type**

Create `TargetSelectionPolicy.gd` with:

```gdscript
class_name TargetSelectionPolicy
extends Resource

enum TargetRelation { HOSTILE, FRIENDLY, ANY }
enum PriorityMode { NEAREST }

@export var target_relation: TargetRelation = TargetRelation.HOSTILE
@export var require_targetable: bool = true
@export var require_alive: bool = true
@export var priority_mode: PriorityMode = PriorityMode.NEAREST
```

`is_candidate_valid()` rejects nulls, self, nodes outside the tree, invalid relation, invalid state and horizontal distances beyond `maximum_distance`. `calculate_priority()` returns horizontal distance squared. `select_target()` returns the valid candidate with the smallest score and never mutates the input array.

Create `DefaultNearestEnemy.tres` referencing only this script and using the default exported values.

- [ ] **Step 4: Run the policy test and verify GREEN**

Expected: `TargetSelectionPolicyTest: PASS`.

### Task 2: AITargetingComponent

**Files:**
- Create: `UnitSystem/Tests/AITargetingComponentTest.gd`
- Create: `UnitSystem/Components/Targeting/AI/AITargetingComponent.gd`
- Create: `UnitSystem/Components/Targeting/AI/AITargetingComponent.tscn`

**Interfaces:**
- Consumes: `TargetSelectionPolicy.select_target()` and `is_candidate_valid()`.
- Produces:
  - `signal locked_target_changed(previous_target: UnitBase, current_target: UnitBase)`
  - `configure(owner_unit: UnitBase) -> bool`
  - `get_locked_target() -> UnitBase`
  - `has_locked_target() -> bool`
  - `refresh_target() -> void`
  - `clear_locked_target() -> void`
  - `set_selection_policy(policy: TargetSelectionPolicy, refresh_immediately: bool = true) -> void`

- [ ] **Step 1: Write a failing component test**

Create a physics-aware headless test that places an owner and targets under a `Node3D`, waits for physics frames, and verifies:

```gdscript
component.refresh_target()
_expect(component.get_locked_target() == near_enemy, "acquires nearest enemy")

near_enemy.global_position = Vector3(0.0, 0.0, -6.5)
component.refresh_target()
_expect(component.get_locked_target() == near_enemy, "retains target inside 7m")
```

The test also verifies a target at `6.5m` cannot be acquired initially, a nearer newcomer does not replace a valid target, a freed/dead target causes reacquisition, disabling clears the lock, and repeated refreshes can discover an enemy that remains overlapping.

- [ ] **Step 2: Run the test and verify RED**

Run the new test with the Godot console command. Expected: non-zero exit because the component scene and class do not exist.

- [ ] **Step 3: Implement the component script**

Create an `Area3D` script with exported typed configuration:

```gdscript
@export var detection_enabled: bool = true
@export_range(0.1, 100.0, 0.1, "or_greater")
var acquisition_radius: float = 6.0
@export_range(0.1, 100.0, 0.1, "or_greater")
var retention_radius: float = 7.0
@export_range(0.05, 5.0, 0.05, "or_greater")
var refresh_interval: float = 0.2
@export var selection_policy: TargetSelectionPolicy
```

`configure()` validates owner and `DetectionShape`, duplicates the `SphereShape3D`, synchronizes its radius and enables monitoring. `_physics_process()` accumulates time and invokes `refresh_target()` repeatedly. `refresh_target()` first validates the current lock with the retention radius; only if invalid does it collect current overlaps and invoke Policy with the acquisition radius.

Use `_set_locked_target()` as the only mutation point so the change signal is emitted exactly once per actual transition.

- [ ] **Step 4: Create the component scene**

Create:

```text
AITargetingComponent (Area3D)
└── DetectionShape (CollisionShape3D / SphereShape3D radius 7.0)
```

Set collision layer `0`, collision mask `4`, monitoring enabled, monitorable disabled, and assign `DefaultNearestEnemy.tres`.

- [ ] **Step 5: Run the component test and verify GREEN**

Expected: `AITargetingComponentTest: PASS`.

### Task 3: AllyBase2 Integration

**Files:**
- Create: `UnitSystem/Tests/AllyTargetingIntegrationTest.gd`
- Modify: `UnitSystem/AI/Ally/AllyBase2.gd`
- Modify: `UnitSystem/AI/Ally/AllyBase2.tscn`

**Interfaces:**
- Consumes: `AITargetingComponent.configure()` and `locked_target_changed`.
- Produces:
  - `AllyBase2.locked_target_changed(previous_target: UnitBase, current_target: UnitBase)`
  - `get_targeting_component() -> AITargetingComponent`
  - `get_locked_target() -> UnitBase`

- [ ] **Step 1: Write a failing integration test**

Load and instantiate `AllyBase2.tscn`, then verify:

```gdscript
var targeting := ally.get_node_or_null(^"AITargetingComponent")
_expect(targeting is AITargetingComponent, "AllyBase2 owns targeting component")
_expect(ally.get_targeting_component() == targeting, "getter exposes component")
_expect(ally.get_formation_component() != null, "formation remains installed")
```

Add a nearby `EnemyBase2`, wait for physics, and verify `AllyBase2.get_locked_target()` and the forwarded signal. Do not load or modify `TestScene.tscn`.

- [ ] **Step 2: Run the integration test and verify RED**

Expected: non-zero exit because `AllyBase2` has not yet installed or exposed the component.

- [ ] **Step 3: Integrate the fixed child**

Add:

```gdscript
signal locked_target_changed(
    previous_target: UnitBase,
    current_target: UnitBase
)

@onready var _targeting_component: AITargetingComponent = $AITargetingComponent
```

In `_ready()`, configure the component and connect its signal without changing `_update_ai_movement()`. Add typed getters and a forwarding callback.

Instance `AITargetingComponent.tscn` directly under `AllyBase2`.

- [ ] **Step 4: Run the integration test and verify GREEN**

Expected: `AllyTargetingIntegrationTest: PASS`, and existing formation component remains configured.

### Task 4: Directory Contract and Full Verification

**Files:**
- Modify: `UnitSystem/Tests/UnitDirectoryLayoutTest.gd`
- Modify: `Docs/Superpowers/Specs/2026-07-24-ally-ai-autonomous-targeting-design.md` only if implementation paths differ from the approved design.

- [ ] **Step 1: Extend the directory contract**

Add the four production resources to `REQUIRED_FILES` and add `AITargetingComponent.tscn` to `LOADABLE_SCENES`. Do not add or change any TestScene unit expectations.

- [ ] **Step 2: Run all UnitSystem headless tests**

Run every `UnitSystem/Tests/*.gd` script separately. Expected: every command exits `0` and prints `PASS`.

- [ ] **Step 3: Run Godot project scans**

Run:

```powershell
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' --headless --editor --path 'G:\Godot\SipSip' --quit
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' --headless --path 'G:\Godot\SipSip' --quit-after 120
```

Expected: both exit `0` with no script parse errors.

- [ ] **Step 4: Refresh MCP and inspect the editor**

Rescan the filesystem through Godot MCP Pro and inspect editor errors. Expected: no new project errors or warnings attributable to the targeting implementation.

- [ ] **Step 5: Confirm protected scene integrity**

Compare `Scenes/TestScene.tscn` metadata before and after implementation and confirm it was not modified.

## Implementation Result

Implemented on 2026-07-24.

- Added the single-script `TargetSelectionPolicy` resource type and the shared `DefaultNearestEnemy.tres`.
- Added the reusable `AITargetingComponent` scene with continuous overlap refresh, `6m` acquisition and `7m` retention.
- Integrated the component directly under `AllyBase2` without changing formation movement behavior.
- Added focused Policy, component and Ally integration tests.
- Updated the directory contract to the current `Item/Weapon/Sword` and `Item/Weapon/Shield` paths.
- Updated the shield animation test to match the current controller contract: `PlayerAttackController` explicitly plays `RESET` after an attack, so each attack animation does not need to end at the reset pose.
- All scripts in `UnitSystem/Tests` pass under Godot 4.7.
- Headless editor scan and main-scene startup both exit with code `0`.
- No `TestScene.tscn` unit instance was added or modified.
