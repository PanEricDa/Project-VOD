# Enemy Idle Behavior Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为敌人待机状态提供可配置的静止或出生点附近游荡行为。

**Architecture:** 只扩展 `EnemyBehaviorStateMachine`。待机游荡拥有独立运行时目标与计时器；进入追击、攻击、归位、死亡或复活时统一清理，确保不与现有攻击距离内战斗游荡竞争移动请求。

**Tech Stack:** Godot 4.7、GDScript、现有 `AIUnitBase` 与 `EnemyBehaviorStateMachine`、Godot headless 测试。

## Global Constraints

- 不修改 `res://Scenes/TestScene.tscn` 中的任何单位实例。
- 每一个新增 `@export` 参数紧邻提供简体中文说明，包含用途、单位、默认行为和影响范围。
- 不创建新的 `.tres` 或 `.res` 资源。
- 不修改攻击距离内已有的战斗游荡与同阵营位置预留逻辑。

---

### Task 1: 待机模式与行为边界测试

**Files:**
- Modify: `UnitSystem/Tests/EnemyBehaviorStateMachineTest.gd`
- Modify: `UnitSystem/Components/Behavior/EnemyBehaviorStateMachine.gd`

**Consumes:** `EnemyBehaviorStateMachine.configure()`、`physics_tick(delta)`、`AIUnitBase.has_movement_target()`。

**Produces:** `IdleBehavior` 枚举和待机模式可回归的行为契约。

- [ ] **Step 1: 写失败测试**

在既有预测状态机测试辅助类中添加可控待机候选点，并断言：

```gdscript
state.idle_behavior = EnemyBehaviorStateMachine.IdleBehavior.STATIONARY
state.physics_tick(0.016)
_expect(not owner.has_movement_target(), "stationary idle has no movement target")

state.idle_behavior = EnemyBehaviorStateMachine.IdleBehavior.WANDER_AROUND_HOME
state.idle_candidates = [Vector3(0.4, 0.0, 0.2)]
state.physics_tick(0.016)
_expect(owner.has_movement_target(), "wander idle submits a movement target")
_expect(
    owner.get_current_movement_target().distance_to(state.get_home_position())
        <= state.idle_wander_radius,
    "idle target stays inside the home radius"
)
```

再断言锁定目标后待机移动被清除并进入 `CHASE`。

- [ ] **Step 2: 运行测试并确认失败**

Run:

```powershell
& $GodotConsole --headless --path 'G:\Godot\SipSip' --script 'res://UnitSystem/Tests/EnemyBehaviorStateMachineTest.gd'
```

Expected: FAIL，缺少 `IdleBehavior` 与待机参数。

### Task 2: 实现静止与出生点游荡

**Files:**
- Modify: `UnitSystem/Components/Behavior/EnemyBehaviorStateMachine.gd`
- Modify: `UnitSystem/Tests/EnemyBehaviorStateMachineTest.gd`

**Consumes:** Task 1 的枚举测试；`AIUnitBase.set_movement_target()`、`clear_movement_target()`。

**Produces:**

```gdscript
enum IdleBehavior { STATIONARY, WANDER_AROUND_HOME }
@export var idle_behavior: IdleBehavior = IdleBehavior.WANDER_AROUND_HOME
@export var idle_wander_radius: float = 0.8
@export var idle_wander_interval_min: float = 1.5
@export var idle_wander_interval_max: float = 3.0
@export var idle_wander_speed_multiplier: float = 0.35
```

- [ ] **Step 1: 添加 Inspector 参数和独立运行时状态**

新增 `Idle Behavior` 分类与上述字段。`idle_wander_interval_min/max` 在运行时通过 `minf/maxf` 标准化，倍率钳制到 `0.0–1.0`；新增私有待机候选点有效标记和计时器，不复用 `_combat_wander_target` 或 `_wander_timer`。

- [ ] **Step 2: 在 IDLE 实现两种模式**

没有锁定目标且当前状态为 `IDLE` 时调用 `_update_idle_behavior(delta)`：

```gdscript
match idle_behavior:
    IdleBehavior.STATIONARY:
        _clear_idle_wander()
    IdleBehavior.WANDER_AROUND_HOME:
        _submit_idle_wander_movement(delta)
```

游荡候选在 `_home_position` 周围均匀随机生成，水平距离不超过 `idle_wander_radius`；移动速度使用 `movement_speed * idle_wander_speed_multiplier`。抵达候选后等待随机间隔才生成下一点。

- [ ] **Step 3: 保证状态切换互斥**

在获得目标切入 `CHASE`、切入 `ATTACK`、`_begin_return_home()`、`_on_owner_died()` 和 `_on_owner_revived()` 时调用 `_clear_idle_wander()`。`RETURN_HOME` 抵达后转为 `IDLE`，下一物理帧按 `idle_behavior` 恢复。

- [ ] **Step 4: 运行目标测试**

Run:

```powershell
& $GodotConsole --headless --path 'G:\Godot\SipSip' --script 'res://UnitSystem/Tests/EnemyBehaviorStateMachineTest.gd'
```

Expected: PASS，既有战斗游荡断言与新增待机模式断言均通过。

### Task 3: 回归验证与文档结果

**Files:**
- Modify: `Docs/Superpowers/Specs/2026-08-01-enemy-idle-behavior-design.md`
- Modify: `Docs/Superpowers/Plans/2026-08-01-enemy-idle-behavior-implementation-plan.md`

**Consumes:** Tasks 1–2 的测试结果。

**Produces:** 标有实际验证结果的设计文档。

- [ ] **Step 1: 运行完整相关回归**

Run:

```powershell
& $GodotConsole --headless --path 'G:\Godot\SipSip' --script 'res://UnitSystem/Tests/EnemyBehaviorStateMachineTest.gd'
& $GodotConsole --headless --path 'G:\Godot\SipSip' --script 'res://UnitSystem/Tests/AITargetingComponentTest.gd'
& $GodotConsole --headless --path 'G:\Godot\SipSip' --script 'res://UnitSystem/Tests/AICombatInheritanceTest.gd'
& $GodotConsole --headless --editor --path 'G:\Godot\SipSip' --quit
```

Expected: 全部 PASS，编辑器扫描无错误。

- [ ] **Step 2: 通过 MCP 刷新并检查错误面板**

执行项目刷新，再读取错误面板；要求错误数为零。

- [ ] **Step 3: 更新设计验证记录**

在设计文档追加默认参数、测试名称和编辑器验证结果，并将已完成计划复选框标记为 `[x]`。
