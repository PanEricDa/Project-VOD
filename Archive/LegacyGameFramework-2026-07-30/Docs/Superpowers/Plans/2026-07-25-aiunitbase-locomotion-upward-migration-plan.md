# AIUnitBase Locomotion Upward Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将通用 AI 运动执行从独立 LocomotionComponent 上移到 AIUnitBase，并删除不再需要的组件节点与文件，同时保持 AllyBase2 和 EnemyBase2 当前行为。

**Architecture:** `AIUnitBase` 直接持有 NavigationAgent3D、运动参数和运动运行时状态，并在固定物理顺序中先调用子类行为入口，再执行移动、重力、朝向和 `move_and_slide()`。现有 FormationComponent 暂时保留，但改为直接调用持有者 `AIUnitBase` 的公开运动接口。

**Tech Stack:** Godot 4.7、GDScript、CharacterBody3D、NavigationAgent3D、headless SceneTree 测试。

## Global Constraints

- 本阶段不改写 Formation、Combat、Targeting 或 Enemy 行为算法。
- 所有运动参数默认值必须与旧 LocomotionComponent 完全一致。
- 不修改 PlayerBase。
- 不修改 TestScene 或 TestScene2 中的任何单位实例。
- 新增及迁移代码使用英文标识和详细简体中文注释。
- 项目不是 Git 仓库，不执行分支或提交步骤。

---

## File Map

- Create `UnitSystem/Tests/AIUnitBaseLocomotionMigrationTest.gd`：验证根节点运动接口、参数、节点结构和继承单位装配。
- Modify `UnitSystem/Base/AIUnitBase.gd`：接收 LocomotionComponent 的全部运动执行内容。
- Modify `UnitSystem/Base/AIUnitBase.tscn`：删除 LocomotionComponent 实例与资源引用。
- Modify `UnitSystem/Components/Movement/FormationComponent.gd`：改为调用 AIUnitBase 接口。
- Modify `UnitSystem/AI/Ally/AllyBase2.gd`：更新 Formation 配置入口。
- Modify `UnitSystem/AI/Enemy/EnemyBase2.gd`：更新过时注释。
- Modify `UnitSystem/Tests/UnitDirectoryLayoutTest.gd`：登记删除后的旧组件路径。
- Delete `UnitSystem/Components/Movement/LocomotionComponent.gd`
- Delete `UnitSystem/Components/Movement/LocomotionComponent.tscn`

### Task 1: 建立上移后的运动契约

**Files:**
- Create: `UnitSystem/Tests/AIUnitBaseLocomotionMigrationTest.gd`

**Interfaces:**
- Produces the required AIUnitBase API:
  - `set_movement_target(target_position: Vector3, maximum_speed: float = -1.0) -> void`
  - `clear_movement_target() -> void`
  - `has_movement_target() -> bool`
  - `set_desired_facing(direction: Vector3) -> void`
  - `request_dash(target_position: Vector3) -> bool`
  - `can_dash() -> bool`
  - `is_dashing() -> bool`
  - `is_recovering() -> bool`
  - `get_dash_cooldown_remaining() -> float`

- [ ] **Step 1: Write the failing migration test**

Load `AIUnitBase.tscn`, instantiate it and assert:

```gdscript
_expect(
	ai.get_node_or_null(^"MovementSystem/LocomotionComponent") == null,
	"AIUnitBase no longer mounts a LocomotionComponent node"
)
_expect(is_equal_approx(ai.movement_speed, 4.2), "movement speed moved to root")
_expect(is_equal_approx(ai.dash_speed, 9.0), "dash speed moved to root")
_expect(is_equal_approx(ai.rotation_speed, 7.0), "facing speed moved to root")
_expect(is_equal_approx(ai.gravity_multiplier, 1.0), "gravity moved to root")

ai.set_movement_target(Vector3(2.0, 0.0, 0.0))
_expect(ai.has_movement_target(), "AIUnitBase accepts movement targets")
ai.clear_movement_target()
_expect(not ai.has_movement_target(), "AIUnitBase clears movement targets")
_expect(ai.request_dash(Vector3(2.0, 0.0, 0.0)), "AIUnitBase starts dash")
_expect(ai.is_dashing(), "dash state is owned by AIUnitBase")
```

Also load AllyBase2 and EnemyBase2 and assert both are `AIUnitBase`, neither contains the old locomotion child, and Ally still contains FormationComponent.

- [ ] **Step 2: Run the test and verify RED**

```powershell
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' --headless --path 'G:\Godot\SipSip' --script res://UnitSystem/Tests/AIUnitBaseLocomotionMigrationTest.gd
```

Expected: fail because the old child still exists and the movement fields/methods are not members of AIUnitBase.

### Task 2: Move Locomotion into AIUnitBase

**Files:**
- Modify: `UnitSystem/Base/AIUnitBase.gd`
- Modify: `UnitSystem/Base/AIUnitBase.tscn`

- [ ] **Step 1: Move configuration and runtime state**

Add `MotionState`, all existing Movement/Dash/Facing/Physics exports, `_navigation_agent`, `_visual_root`, gravity, movement target, facing, dash and recovery state directly to AIUnitBase.

Remove `_locomotion_component` and its `configure()` call. `_ready()` validates only MovementSystem, NavigationAgent3D and Visual, then resets internal motion state.

- [ ] **Step 2: Move the public API**

Copy the public API listed in Task 1 to AIUnitBase. Replace the former `_owner_body` access with direct `self`, `global_position`, `velocity`, `is_on_floor()`, `is_on_wall()` and `move_and_slide()`.

- [ ] **Step 3: Preserve fixed physics order**

Implement:

```gdscript
func _physics_process(delta: float) -> void:
	if not _ai_movement_ready:
		return
	_update_ai_movement(delta)
	_update_dash_cooldown(delta)
	match _motion_state:
		MotionState.DASHING:
			_process_dash(delta)
		MotionState.RECOVERING:
			_process_recovery(delta)
		_:
			_process_regular_motion(delta)
	_apply_gravity(delta)
	_update_visual_facing(delta)
	var previous_position: Vector3 = global_position
	move_and_slide()
	if _motion_state == MotionState.DASHING:
		_update_dash_after_slide(previous_position)
```

The default `_update_ai_movement()` calls `clear_movement_target()`.

- [ ] **Step 4: Remove the scene child**

Delete the LocomotionComponent PackedScene external resource and child instance from AIUnitBase.tscn. Keep MovementSystem and NavigationAgent3D unchanged.

- [ ] **Step 5: Run the migration test**

Expected at this checkpoint: AIUnitBase assertions pass; Ally may still fail until Formation adaptation.

### Task 3: Adapt Formation and remove legacy files

**Files:**
- Modify: `UnitSystem/Components/Movement/FormationComponent.gd`
- Modify: `UnitSystem/AI/Ally/AllyBase2.gd`
- Modify: `UnitSystem/AI/Enemy/EnemyBase2.gd`
- Modify: `UnitSystem/Tests/UnitDirectoryLayoutTest.gd`
- Delete: `UnitSystem/Components/Movement/LocomotionComponent.gd`
- Delete: `UnitSystem/Components/Movement/LocomotionComponent.tscn`

- [ ] **Step 1: Change the Formation dependency**

Replace:

```gdscript
var _owner_body: CharacterBody3D
var _locomotion: LocomotionComponent

func configure(
	owner_body: CharacterBody3D,
	locomotion: LocomotionComponent
) -> bool:
```

with:

```gdscript
var _owner_body: AIUnitBase

func configure(owner_body: AIUnitBase) -> bool:
	_owner_body = owner_body
	_configured = is_instance_valid(_owner_body)
```

Replace every `_locomotion.*` call with `_owner_body.*`. Keep all Formation calculations and exported defaults unchanged.

- [ ] **Step 2: Update Ally configuration**

Change:

```gdscript
_formation_component.configure(self, get_locomotion_component())
```

to:

```gdscript
_formation_component.configure(self)
```

- [ ] **Step 3: Remove legacy component files**

Delete both LocomotionComponent files and add their paths to `UnitDirectoryLayoutTest.LEGACY_FILES`, proving they remain absent.

Update only the EnemyBase2 comment that still says LocomotionComponent owns gravity.

- [ ] **Step 4: Run focused tests**

Run:

```powershell
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' --headless --path 'G:\Godot\SipSip' --script res://UnitSystem/Tests/AIUnitBaseLocomotionMigrationTest.gd
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' --headless --path 'G:\Godot\SipSip' --script res://UnitSystem/Tests/AllyInheritedRootRenameTest.gd
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' --headless --path 'G:\Godot\SipSip' --script res://UnitSystem/Tests/AllyTargetingIntegrationTest.gd
```

Expected: all print `PASS`.

### Task 4: Full Verification

- [ ] **Step 1: Run every UnitSystem test**

Run each `UnitSystem/Tests/*.gd` separately. Expected: all exit `0` and print `PASS`.

- [ ] **Step 2: Run Godot scans**

```powershell
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' --headless --editor --path 'G:\Godot\SipSip' --quit
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' --headless --path 'G:\Godot\SipSip' --quit-after 120
```

Expected: both exit `0` without parse errors.

- [ ] **Step 3: Runtime verification**

Run TestScene2 through MCP and verify:

- Amy still wanders and follows the player.
- EnemyBase2 stays grounded without autonomous movement.
- Amy still acquires EnemyBase2 and displays the targeting ring.
- No LocomotionComponent node exists at runtime.

- [ ] **Step 4: Protected-scene and output check**

Confirm TestScene and TestScene2 were not modified, and Godot Output contains no new project errors or warnings.

## 实施结果（2026-07-25）

- `AIUnitBase` 已直接拥有导航、普通移动、冲刺、恢复、重力和视觉转向。
- `MovementSystem` 已精简为共享容器；父场景只保留 `NavigationAgent3D`。
- `FormationComponent` 继续只负责提交编队移动意图，并改为直接调用宿主
  `AIUnitBase` 的开放运动接口。
- `AllyBase2` 已适配新的 `FormationComponent.configure(self)` 装配方式。
- 旧 `LocomotionComponent.gd/.tscn/.gd.uid` 已删除，并由目录契约测试防止回流。
- 新增 `AIUnitBaseLocomotionMigrationTest.gd`，验证父类参数、接口、节点结构及
  Ally/Enemy 继承关系。
- 8 个 `UnitSystem` 测试全部通过；Godot 4.7 编辑器扫描和无窗口启动均退出码
  为 `0`。
- MCP 运行 `TestScene2` 时确认 Amy 正常移动与索敌，EnemyBase2 继承运动参数但
  保持静止，运行树中不存在 `LocomotionComponent`，Output 无新增警告或错误。
- 未修改 `TestScene.tscn` 或 `TestScene2.tscn` 的单位实例。
