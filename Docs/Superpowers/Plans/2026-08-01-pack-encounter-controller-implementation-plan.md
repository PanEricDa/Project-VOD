# Pack 遭遇控制器实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为 TestCombatRoom 已摆放的敌群实现自动 Pack 遭遇登记、开战、脱战重置、清除与房间清除信号。

**Architecture:** `EnemyBehaviorStateMachine` 将自身状态同步到 `UnitBase` 的通用战斗状态；独立 `EncounterController` 仅订阅 `UnitBase` 信号，并按同级 `EnemyContainer` 的直接子节点建立 Pack 记录。控制器不接管敌人 AI、生成、移动、血量、奖励或胜负。

**Tech Stack:** Godot 4.7、GDScript、Godot headless 测试、Godot MCP Pro。

## 全局约束

- 每个新增 `@export` 参数、公开方法和信号必须紧邻提供详细简体中文说明。
- 控制器不得依赖手写敌人 NodePath、节点名称或特定敌人类型以外的行为状态机实现。
- 不改动 `res://Scenes/TestScene.tscn` 内的单位实例；本任务仅在用户已放置单位的 `TestCombatRoom.tscn` 根节点装配控制器。
- 不创建 `.tres/.res` 外部资源，也不增加波次、敌人生成、奖励、门、玩家失败、回血或复活逻辑。
- 项目没有 Git 工作区，不创建提交、分支或工作树。

---

### Task 1：把敌人行为状态同步到 UnitBase 战斗状态

**Files:**
- Modify: `UnitSystem/Components/Behavior/EnemyBehaviorStateMachine.gd`
- Modify: `UnitSystem/Tests/EnemyBehaviorStateMachineTest.gd`

**Interfaces:**
- Consumes: `UnitBase.enter_combat()`, `UnitBase.exit_combat()`。
- Produces: 对每个有效 EnemyBase，CHASE / ATTACK 对应 `is_in_combat() == true`，RETURN_HOME / IDLE 对应 `false`。

- [x] **Step 1: 写出失败的状态同步测试**

在既有测试中，在远距离目标进入 `CHASE` 后增加：

```gdscript
_expect(owner.is_in_combat(), "chase synchronizes owner into UnitBase combat state")
```

然后让目标失效、推进状态机到 `RETURN_HOME` 和抵达 home，断言：

```gdscript
_expect(not owner.is_in_combat(), "return home synchronizes owner out of UnitBase combat state")
```

- [x] **Step 2: 运行测试，确认同步断言失败**

运行：

```powershell
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' --headless --path 'G:\Godot\SipSip' --script 'res://UnitSystem/Tests/EnemyBehaviorStateMachineTest.gd'
```

预期：新断言失败，因为当前敌人状态机尚未调用 `enter_combat()` / `exit_combat()`。

- [x] **Step 3: 在唯一状态转换入口同步公共状态**

在 `_transition_to(next_state)` 中状态变更后、发出 `state_changed` 前加入：

```gdscript
if next_state == State.CHASE or next_state == State.ATTACK:
	_owner_body.enter_combat()
else:
	_owner_body.exit_combat()
```

再在 `configure()` 初始状态设为 `IDLE` 时调用一次 `_owner_body.exit_combat()`，保证复用、复活或重新装配后的初值一致。只在状态机转换入口处理，不能在每帧 `physics_tick()` 重复调用。

- [x] **Step 4: 运行敌人行为测试，确认通过**

运行 Task 1 命令。

预期：`EnemyBehaviorStateMachineTest: PASS`。

### Task 2：实现独立 Pack EncounterController 与其失败测试

**Files:**
- Create: `UnitSystem/Encounter/EncounterController.gd`
- Create: `UnitSystem/Encounter/EncounterController.tscn`
- Create: `UnitSystem/Tests/EncounterControllerTest.gd`

**Interfaces:**
- Consumes: 同级 `EnemyContainer`，其直接 `Node3D` 子节点作为 Pack；Pack 子树中的 `EnemyBase`；`UnitBase.combat_state_changed` 和 `UnitBase.died`。
- Produces: `pack_started`、`pack_reset`、`pack_cleared`、`room_cleared`、`pack_tracking_invalid` 信号，以及 Pack 调试查询方法。

- [x] **Step 1: 写出失败的控制器契约测试**

测试动态建立根节点、`EnemyContainer`、两个非空 Pack、一个空 Pack 和敌人，实例化控制器后等待一帧。期望接口：

```gdscript
controller.reset_delay = 0.1
controller.configure_from_parent()
_expect(controller.get_registered_enemy_count(pack_a) == 2, "Pack A registers nested enemies")
_expect(controller.get_pack_state(pack_a) == EncounterController.PackState.DORMANT, "Pack starts dormant")
```

覆盖下列实际行为：首次进入战斗只发一次 `pack_started`；全部存活敌人脱战后先为 `RESETTING`，延迟结束才发一次 `pack_reset`；延迟中重入战斗取消 reset；最后死亡优先于同帧脱战并只发一次 `pack_cleared`；所有非空 Pack 清除后只发一次 `room_cleared`；空 Pack 不计入完成；未死亡而离树时只发 `pack_tracking_invalid`，不发 clear。

- [x] **Step 2: 运行测试，确认接口缺失导致失败**

运行：

```powershell
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' --headless --path 'G:\Godot\SipSip' --script 'res://UnitSystem/Tests/EncounterControllerTest.gd'
```

预期：控制器场景或 `configure_from_parent()`、`PackState`、信号查询接口不存在。

- [x] **Step 3: 用单一 PackRecord 数据模型实现登记与结算**

在 `EncounterController.gd` 内定义：

```gdscript
enum PackState { DORMANT, ENGAGED, RESETTING, CLEARED, TRACKING_INVALID }

class PackRecord extends RefCounted:
	var pack: Node3D
	var enemies: Array[EnemyBase] = []
	var defeated_enemy_ids: Dictionary = {}
	var state: PackState = PackState.DORMANT
	var reset_remaining: float = 0.0
	var has_emitted_started: bool = false
	var has_emitted_cleared: bool = false
	var tracking_invalid: bool = false
```

仅导出：

```gdscript
## Pack 内所有存活敌人离战后，确认重置前持续保持非战斗的时间，单位为秒。
## 默认 1.0 秒；期间任一敌人重新进入战斗会取消本次重置，仅影响 EncounterController 的状态与 pack_reset 信号。
@export_range(0.0, 10.0, 0.05) var reset_delay: float = 1.0
```

`configure_from_parent()` 使用 `get_parent().get_node_or_null(^"EnemyContainer")` 扫描直接 Pack 和递归敌人，连接每只敌人的 `combat_state_changed`、`died` 和 `tree_exiting`。每个事件仅设置“待结算”标记，并通过 `call_deferred("_evaluate_packs")` 在帧末统一处理，确保死亡优先。

结算优先级固定为：追踪无效 → 全部死亡 `CLEARED` → 任一存活敌人战斗中 `ENGAGED` → 全部存活敌人离战 `RESETTING/DORMANT`。只在状态边沿发送信号；`CLEARED` 终态不回退。

- [x] **Step 4: 创建最小 PackedScene 并运行控制器测试**

`EncounterController.tscn` 只包含根 `Node` 和脚本。`_ready()` 通过 `call_deferred` 调用 `configure_from_parent()`，并在缺少 `EnemyContainer` 时输出一次明确配置错误。

再次运行 Task 2 命令。

预期：`EncounterControllerTest: PASS`。

### Task 3：装配 TestCombatRoom、回归验证与文档记录

**Files:**
- Modify: `Scenes/TestCombatRoom.tscn`
- Modify: `Docs/Superpowers/Specs/2026-08-01-pack-encounter-controller-design.md`
- Modify: `Docs/Superpowers/Plans/2026-08-01-pack-encounter-controller-implementation-plan.md`

**Interfaces:**
- Consumes: `EncounterController.tscn`。
- Produces: TestCombatRoom 根节点的一个 EncounterController 实例；不改动玩家、伙伴、敌人或 Pack 内容。

- [x] **Step 1: 扩展控制器测试，确认真实房间装配**

加载 `res://Scenes/TestCombatRoom.tscn`，断言：

```gdscript
var controller := room.get_node_or_null(^"EncounterController") as EncounterController
_expect(controller != null, "TestCombatRoom equips EncounterController")
_expect(room.get_node_or_null(^"EnemyContainer/Pack_A") != null, "existing user Pack A remains present")
```

并在等待两帧后确认控制器为三个非空 Pack 登记敌人。

- [x] **Step 2: 运行测试，确认房间尚未装配控制器而失败**

运行 Task 2 的 headless 命令。

预期：`TestCombatRoom equips EncounterController` 失败。

- [x] **Step 3: 仅实例化控制器到房间根节点**

在 `TestCombatRoom.tscn` 添加 `EncounterController.tscn` 外部场景实例。不得移动、修改、删除或新增用户已经放置的 Hero、伙伴、敌人和 Pack；不得新增其他房间逻辑。

- [x] **Step 4: 执行完整验证并记录实际结果**

运行：

```powershell
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' --headless --path 'G:\Godot\SipSip' --script 'res://UnitSystem/Tests/EncounterControllerTest.gd'
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' --headless --path 'G:\Godot\SipSip' --script 'res://UnitSystem/Tests/EnemyBehaviorStateMachineTest.gd'
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' --headless --editor --path 'G:\Godot\SipSip' --quit
```

随后通过 MCP 刷新项目并检查编辑器错误面板。把实际命令结果、MCP 错误数、控制器只装配根节点且未修改用户单位实例的结论追加到设计文档；将本计划复选框标记完成。
