# Enemy AI Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让 `EnemyBase` 使用现有索敌、移动和战斗系统，完成自主索敌、追击、攻击、脱战归位的第一版 AI。

**Architecture:** `AIUnitBase` 继续是唯一的移动与物理执行者，`AITargetingComponent` 继续是唯一的锁定目标所有者。新增的 `EnemyBehaviorStateMachine` 只读取锁定目标并提交移动或攻击请求；它不保存第二份目标，也不实现武器、投射物、命中或伤害算法。

**Tech Stack:** Godot 4.7、GDScript、现有 `UnitBase` / `AIUnitBase` / `AITargetingComponent` / `TargetSelectionPolicy` / `AICombatSystem`、Godot headless 测试。

## Global Constraints

- 不自动修改 `res://Scenes/TestScene.tscn` 中的任何单位实例。
- 不创建本计划不需要的正式 `.tres` 或 `.res` 资源；继续使用已登记 UID 的 `DefaultNearestEnemy.tres`。
- 所有新增代码字段、方法与信号使用英文标识，提供详细简体中文注释。
- 旧系统归档内容不改动；只重命名当前新系统遗留的 `*2` 名称并更新其引用。
- 项目不是 Git 仓库；不创建提交。

---

### Task 1: 还原当前新单位基类名称

**Files:**
- Rename: `UnitSystem/AI/Ally/AllyBase2.gd` → `UnitSystem/AI/Ally/AllyBase.gd`
- Rename: `UnitSystem/AI/Ally/AllyBase2.tscn` → `UnitSystem/AI/Ally/AllyBase.tscn`
- Rename: `UnitSystem/AI/Enemy/EnemyBase2.gd` → `UnitSystem/AI/Enemy/EnemyBase.gd`
- Rename: `UnitSystem/AI/Enemy/EnemyBase2.tscn` → `UnitSystem/AI/Enemy/EnemyBase.tscn`
- Modify: current new-system inheriting unit scenes and all `UnitSystem/Tests/*.gd` references

**Consumes:** 当前 `AllyBase2`、`EnemyBase2` 的节点结构、脚本接口与 UID。

**Produces:** `class_name AllyBase`、`class_name EnemyBase`，且所有当前新系统继承场景和测试只使用还原后的路径与类名。

- [ ] **Step 1: 添加命名契约测试**

在 `UnitSystem/Tests/UnitDirectoryLayoutTest.gd` 增加断言：

```gdscript
_expect(
    ResourceLoader.exists("res://UnitSystem/AI/Ally/AllyBase.tscn"),
    "new ally base scene uses the canonical name"
)
_expect(
    ResourceLoader.exists("res://UnitSystem/AI/Enemy/EnemyBase.tscn"),
    "new enemy base scene uses the canonical name"
)
```

并断言现行 `AllyBase2`、`EnemyBase2` 路径不存在。

- [ ] **Step 2: 运行测试并确认失败**

Run:

```powershell
& $GodotConsole --headless --path 'G:\Godot\SipSip' --script 'res://UnitSystem/Tests/UnitDirectoryLayoutTest.gd'
```

Expected: FAIL，提示 canonical path 尚不存在。

- [ ] **Step 3: 执行完整重命名与引用迁移**

使用 Godot 安全的文件重命名流程更新脚本、场景、继承场景、测试和文档中的新系统路径；将 `class_name AllyBase2` / `EnemyBase2` 改为 `AllyBase` / `EnemyBase`。确认归档路径不修改。

- [ ] **Step 4: 运行命名、继承和编辑器验证**

Run:

```powershell
& $GodotConsole --headless --path 'G:\Godot\SipSip' --script 'res://UnitSystem/Tests/UnitDirectoryLayoutTest.gd'
& $GodotConsole --headless --path 'G:\Godot\SipSip' --script 'res://UnitSystem/Tests/AllyInheritedRootRenameTest.gd'
& $GodotConsole --headless --editor --path 'G:\Godot\SipSip' --quit
```

Expected: 全部 PASS，编辑器扫描无脚本或场景引用错误。

### Task 2: 建立敌人状态机的测试契约

**Files:**
- Create: `UnitSystem/Tests/EnemyBehaviorStateMachineTest.gd`
- Modify: `UnitSystem/Tests/UnitDirectoryLayoutTest.gd`

**Consumes:** `AIUnitBase.set_movement_target()`、`clear_movement_target()`、`get_combat_system()`，以及 `AITargetingComponent.get_locked_target()` / `suspend_detection()`。

**Produces:** 对 `EnemyBehaviorStateMachine` 的状态、出生点、归位、目标唯一性与战斗请求的可执行契约。

- [ ] **Step 1: 写失败测试**

测试创建具有 `AIMeleeCombatSystem`、`AITargetingComponent` 与敌对测试单位的 `EnemyBase`，并断言：

```gdscript
_expect(machine.get_current_state() == EnemyBehaviorStateMachine.State.IDLE, "starts idle")
_expect(machine.get_home_position().is_equal_approx(enemy.global_position), "captures runtime home")

targeting.refresh_target()
machine.physics_tick(0.1)
_expect(machine.get_current_state() == EnemyBehaviorStateMachine.State.CHASE, "target starts chase")

enemy.global_position = target.global_position + Vector3(0.0, 0.0, 0.6)
machine.physics_tick(0.1)
_expect(machine.get_current_state() == EnemyBehaviorStateMachine.State.ATTACK, "weapon range starts attack")

enemy.global_position = machine.get_home_position() + Vector3(20.0, 0.0, 0.0)
machine.physics_tick(0.1)
_expect(machine.get_current_state() == EnemyBehaviorStateMachine.State.RETURN_HOME, "leash forces return")
_expect(targeting.is_detection_suspended(), "return suspends reacquisition")
```

另加测试：状态机不导出目标节点字段，且始终通过 `AITargetingComponent` 读取当前目标。

- [ ] **Step 2: 运行并确认失败**

Run:

```powershell
& $GodotConsole --headless --path 'G:\Godot\SipSip' --script 'res://UnitSystem/Tests/EnemyBehaviorStateMachineTest.gd'
```

Expected: FAIL，因为组件和 `State` 尚不存在。

### Task 3: 实现可复用的敌人行为状态机

**Files:**
- Create: `UnitSystem/Components/Behavior/EnemyBehaviorStateMachine.gd`
- Create: `UnitSystem/Components/Behavior/EnemyBehaviorStateMachine.tscn`
- Modify: `UnitSystem/Tests/EnemyBehaviorStateMachineTest.gd`

**Consumes:** `AIUnitBase`、`AITargetingComponent`、`AICombatSystem`。

**Produces:**

```gdscript
enum State { IDLE, CHASE, ATTACK, RETURN_HOME }
signal state_changed(previous_state: State, current_state: State)

func configure(owner_body: AIUnitBase, targeting: AITargetingComponent, combat: AICombatSystem) -> bool
func physics_tick(delta: float) -> void
func get_current_state() -> State
func get_home_position() -> Vector3
```

- [ ] **Step 1: 实现最小状态与配置校验**

组件配置成功时记录 `owner_body.global_position` 为 `_home_position`；持有 `AIUnitBase`、`AITargetingComponent`、`AICombatSystem` 的私有引用。任一引用无效时返回 `false` 并输出一次明确错误。

暴露下列 Inspector 参数：

```gdscript
@export_range(0.5, 100.0, 0.1, "or_greater") var leash_distance: float = 12.0
@export_range(0.05, 5.0, 0.05, "or_greater") var home_arrival_distance: float = 0.25
```

- [ ] **Step 2: 实现 IDLE、CHASE 与 ATTACK**

每个 `physics_tick()` 读取一次 `targeting.get_locked_target()`。`IDLE` 有有效目标时切到 `CHASE`；`CHASE` 使用 `owner.set_movement_target(target.global_position, -1.0, true)`；到达 `combat.get_attack_range() + combat.get_attack_range_tolerance()` 后进入 `ATTACK`。

`ATTACK` 每帧 `owner.set_desired_facing(target.global_position - owner.global_position)`，仅在 `combat.is_global_cooldown_ready()` 和 `not combat.is_attacking()` 时调用：

```gdscript
combat.request_basic_attack(target)
```

目标离开攻击距离后回到 `CHASE`；攻击距离以现有 `AICombatSystem` 的武器数据为唯一来源。

- [ ] **Step 3: 实现脱战归位与安全清理**

当目标失效或敌人与 `_home_position` 的水平距离大于 `leash_distance`：

```gdscript
combat.cancel_current_action()
targeting.suspend_detection(RETURN_DETECTION_SUSPEND_SECONDS, true)
owner.set_movement_target(_home_position)
_transition_to(State.RETURN_HOME)
```

`RETURN_HOME` 到达 `home_arrival_distance` 后清除移动目标并切到 `IDLE`。暂停时长必须覆盖返程；返程完成后显式恢复扫描。死亡时取消当前行为；复活后重新记录当前位置为出生点并回到 `IDLE`。

- [ ] **Step 4: 运行状态机测试**

Run:

```powershell
& $GodotConsole --headless --path 'G:\Godot\SipSip' --script 'res://UnitSystem/Tests/EnemyBehaviorStateMachineTest.gd'
```

Expected: PASS，覆盖待机、追击、攻击、脱战、归位、死亡清理与重新索敌。

### Task 4: 将敌人基类装配至既有公共组件

**Files:**
- Modify: `UnitSystem/AI/Enemy/EnemyBase.gd`
- Modify: `UnitSystem/AI/Enemy/EnemyBase.tscn`
- Modify: `UnitSystem/Tests/EnemyBehaviorStateMachineTest.gd`

**Consumes:** Task 3 的 `EnemyBehaviorStateMachine.configure()` 与当前 `AITargetingComponent.tscn`、`DefaultNearestEnemy.tres`。

**Produces:** 可继承的 `EnemyBase`，具体敌人无需编写脚本即可配置目标半径、脱战半径和武器。

- [ ] **Step 1: 扩展 EnemyBase 的根节点配置**

增加单一的敌人索敌半径：

```gdscript
@export_category("Targeting")
@export_range(0.1, 100.0, 0.1, "or_greater")
var targeting_radius: float = 6.0
```

在 `_ready()` 中先配置 `AITargetingComponent.configure(self, targeting_radius)`，再配置 `EnemyBehaviorStateMachine.configure(self, targeting, get_combat_system())`。将目标变化和行为状态变化作为只读转发信号公开给未来 UI/调试层。

- [ ] **Step 2: 更新 EnemyBase 场景结构**

在 `EnemyBase.tscn` 实例化：

```text
EnemyBase
├── CombatSystem
├── AITargetingComponent
└── BehaviorStateMachine
```

`AITargetingComponent` 引用当前 `DefaultNearestEnemy.tres`，不复制 `.tres`。保持已有 Visual、武器预览、CombatSystem 与死亡配置不变。

- [ ] **Step 3: 委托物理行为给状态机**

在 `EnemyBase._update_ai_movement(delta)` 中仅调用：

```gdscript
_behavior_state_machine.physics_tick(delta)
```

若组件不可用，调用父类空行为，确保配置失败时不会出现无效移动或报错循环。

- [ ] **Step 4: 运行集成测试和编辑器扫描**

Run:

```powershell
& $GodotConsole --headless --path 'G:\Godot\SipSip' --script 'res://UnitSystem/Tests/EnemyBehaviorStateMachineTest.gd'
& $GodotConsole --headless --path 'G:\Godot\SipSip' --script 'res://UnitSystem/Tests/AITargetingComponentTest.gd'
& $GodotConsole --headless --path 'G:\Godot\SipSip' --script 'res://UnitSystem/Tests/AICombatSystemTest.gd'
& $GodotConsole --headless --editor --path 'G:\Godot\SipSip' --quit
```

Expected: 全部 PASS；编辑器扫描无错误。

### Task 5: 回归验证和设计文档收尾

**Files:**
- Modify: `Docs/Superpowers/Specs/2026-08-01-enemy-ai-foundation-design.md`
- Modify: `Docs/Superpowers/Plans/2026-08-01-enemy-ai-foundation-implementation-plan.md`

**Consumes:** Tasks 1–4 的运行结果。

**Produces:** 已记录最终节点路径、默认值和验证结果的设计/计划文档。

- [ ] **Step 1: 运行完整相关回归集**

Run:

```powershell
& $GodotConsole --headless --path 'G:\Godot\SipSip' --script 'res://UnitSystem/Tests/AIUnitBaseLocomotionMigrationTest.gd'
& $GodotConsole --headless --path 'G:\Godot\SipSip' --script 'res://UnitSystem/Tests/AITargetingComponentTest.gd'
& $GodotConsole --headless --path 'G:\Godot\SipSip' --script 'res://UnitSystem/Tests/AICombatSystemTest.gd'
& $GodotConsole --headless --path 'G:\Godot\SipSip' --script 'res://UnitSystem/Tests/EnemyBehaviorStateMachineTest.gd'
& $GodotConsole --headless --editor --path 'G:\Godot\SipSip' --quit
```

Expected: 所有测试 PASS，编辑器扫描无错误。

- [ ] **Step 2: 通过 MCP 检查编辑器输出**

刷新项目后读取 Godot 输出和错误面板，确认无新的错误或警告；若有，先定位来源并修复，再更新文档。

- [ ] **Step 3: 记录结果**

在设计文档的验收条件下记录已通过的测试与最终默认参数。将本计划所有完成的复选框改为 `[x]`。
