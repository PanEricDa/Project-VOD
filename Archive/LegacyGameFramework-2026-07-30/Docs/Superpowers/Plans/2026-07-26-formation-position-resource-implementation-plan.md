# Formation Position Resource Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 Amy 当前阵型站位数字迁移为一份可选择的 `FormationPositionData` 资源，并在既有 Formation 游荡目标生成阶段加入不产生持续推力的同队落脚点防重叠检查。

**Architecture:** `FormationPositionData` 只保存编队中心偏移、游荡区域和分侧模式；`AllyBehaviorStateMachine` 继续独占 Formation 算法，并通过强类型资源读取位置。防重叠只在原 `_select_new_formation_wander_target()` 刷新时扫描同队 AI 的当前位置与 Formation 预定目标，候选拥挤则重选，Combat 完全不参与。

**Tech Stack:** Godot 4.7、GDScript、Resource/`.tres`、PackedScene、现有 SceneTree headless 测试。

**Implementation Status (2026-07-26): Completed.** 四个任务均已实现。最终串行运行
17 项 `UnitSystem/Tests/*.gd` 全部通过，Godot
`4.7.stable.official.5b4e0cb0f` headless 编辑器扫描退出码为 0。
`Scenes/TestScene2.tscn` 未被改写，旧 AI 攻击模块与归档场景均保留。

> 后续命名更新：首轮 `AmyFormationPosition.tres` 已重命名为通用
> `Forward.tres`，并补齐另外五份标准位置资源。本计划下方保留首轮实施记录，
> 当前有效路径以设计规格和 `Docs/CurrentImplementationSummary.md` 为准。

## Global Constraints

- 不修改 `res://Scenes/TestScene2.tscn`、归档 TestScene 或其中任何单位实例。
- 第一阶段只创建 `AmyFormationPosition.tres`，不预制其他阵型位置。
- 不增加阵型协调器、子槽位、独立换位计时器、持续分离力或单位物理碰撞。
- Combat 状态不读取阵型资源、不运行目标占用检查。
- Return 与 Formation 使用阵型位置；强制脱战继续复用现有 `FORMATION_REPOSITION` 跟随和 Dash。
- 所有字段与方法使用英文标识，新增代码使用详细简体中文注释。
- 项目不是 Git 仓库，不创建提交，以 RED/GREEN 测试和 Godot 4.7 扫描作为检查点。

---

## File Map

### Create

- `UnitSystem/AI/Ally/Formation/FormationPositionData.gd`：阵型位置静态数据类型。
- `UnitSystem/AI/Ally/Formation/Positions/AmyFormationPosition.tres`：Amy 当前阵型位置数据。
- `UnitSystem/Tests/FormationPositionDataTest.gd`：资源类型、默认值和 Amy 数据契约。
- `UnitSystem/Tests/FormationTargetReservationTest.gd`：候选重选、最宽松降级和同队过滤测试。

### Modify

- `UnitSystem/Components/Behavior/AllyBehaviorStateMachine.gd`：读取资源、运行时切换、Formation 候选占用检查。
- `UnitSystem/AI/Ally/Units/Amy.tscn`：只覆盖 `formation_position` 资源。
- `UnitSystem/Tests/AllyBehaviorStateMachineTest.gd`：资源切换、Return/Combat 边界与旧行为回归。
- `UnitSystem/Tests/UnitDirectoryLayoutTest.gd`：登记新增资源、脚本和测试文件。
- `Docs/CurrentImplementationSummary.md`：记录最终资源装配和防重叠规则。
- `Docs/Superpowers/Specs/2026-07-25-formation-position-resource-design.md`：回填实际文件路径和验证结果。

---

### Task 1: FormationPositionData 与 Amy 资源契约

**Files:**

- Create: `UnitSystem/AI/Ally/Formation/FormationPositionData.gd`
- Create: `UnitSystem/AI/Ally/Formation/Positions/AmyFormationPosition.tres`
- Create: `UnitSystem/Tests/FormationPositionDataTest.gd`
- Modify: `UnitSystem/Tests/UnitDirectoryLayoutTest.gd`

**Interfaces:**

- Produces `FormationPositionData.SideMode`：`FREE_CROSSING / LOCKED_RANDOM_SIDE / FIXED_LEFT / FIXED_RIGHT`。
- Produces strongly typed fields: `display_name`, `center_offset`, `lateral_radius`, `lateral_minimum`, `forward_radius`, `side_mode`。
- Later tasks consume `res://UnitSystem/AI/Ally/Formation/Positions/AmyFormationPosition.tres`。

- [ ] **Step 1: Write the failing resource test**

Create `FormationPositionDataTest.gd` as a real SceneTree resource test:

```gdscript
extends SceneTree

const RESOURCE_PATH: String = (
	"res://UnitSystem/AI/Ally/Formation/Positions/"
	+ "AmyFormationPosition.tres"
)

var _failures: Array[String] = []


func _initialize() -> void:
	var data := load(RESOURCE_PATH) as FormationPositionData
	_expect(data != null, "Amy formation position loads as typed resource")
	if data != null:
		_expect(data.display_name == "Amy Formation Position", "display name")
		_expect(
			data.center_offset.is_equal_approx(Vector2(0.0, 2.5)),
			"Amy keeps the current center offset"
		)
		_expect(is_equal_approx(data.lateral_radius, 1.1), "lateral radius")
		_expect(is_equal_approx(data.lateral_minimum, 0.0), "lateral minimum")
		_expect(is_equal_approx(data.forward_radius, 0.65), "forward radius")
		_expect(
			data.side_mode == FormationPositionData.SideMode.FREE_CROSSING,
			"Amy keeps free crossing"
		)
	_finish()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	for failure: String in _failures:
		push_error(failure)
	print(
		"FormationPositionDataTest: PASS"
		if _failures.is_empty()
		else "FormationPositionDataTest: FAIL (%d)" % _failures.size()
	)
	quit(0 if _failures.is_empty() else 1)
```

- [ ] **Step 2: Run the test and verify RED**

Run:

```powershell
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' --headless --path 'G:\Godot\SipSip' --script 'res://UnitSystem/Tests/FormationPositionDataTest.gd'
```

Expected: non-zero exit because `FormationPositionData` and Amy resource do not exist.

- [ ] **Step 3: Implement the typed Resource**

Create `FormationPositionData.gd`:

```gdscript
class_name FormationPositionData
extends Resource

## 设计师可选的友方阵型位置静态数据。
## 本资源不保存任何单位实例、随机目标、计时器或移动状态。

enum SideMode {
	FREE_CROSSING,
	LOCKED_RANDOM_SIDE,
	FIXED_LEFT,
	FIXED_RIGHT,
}

@export var display_name: String = "Formation Position"

@export_category("Center")
## x 为相对跟随目标的右侧偏移，y 为相对跟随目标的前方偏移。
@export var center_offset: Vector2 = Vector2(0.0, 2.5)

@export_category("Wander Area")
@export_range(0.0, 5.0, 0.05)
var lateral_radius: float = 1.1
@export_range(0.0, 5.0, 0.05)
var lateral_minimum: float = 0.0
@export_range(0.0, 5.0, 0.05)
var forward_radius: float = 0.65
@export var side_mode: SideMode = SideMode.FREE_CROSSING
```

Create `AmyFormationPosition.tres` with this exact content. Do not create any other position resource:

```text
[gd_resource type="Resource" script_class="FormationPositionData" load_steps=2 format=3]

[ext_resource type="Script" path="res://UnitSystem/AI/Ally/Formation/FormationPositionData.gd" id="1_position"]

[resource]
script = ExtResource("1_position")
display_name = "Amy Formation Position"
center_offset = Vector2(0, 2.5)
lateral_radius = 1.1
lateral_minimum = 0.0
forward_radius = 0.65
side_mode = 0
```

- [ ] **Step 4: Register the new paths in the directory contract**

Add the Resource script and Amy `.tres` to `UnitDirectoryLayoutTest.REQUIRED_FILES`. Load the `.tres` in `_verify_resources_load()` and assert it is `FormationPositionData` with the expected resource path.

- [ ] **Step 5: Verify GREEN**

Run `FormationPositionDataTest.gd` and `UnitDirectoryLayoutTest.gd`. Expected: both exit 0 and no warning is printed.

---

### Task 2: Resource-driven Formation state machine and Amy assembly

**Files:**

- Modify: `UnitSystem/Components/Behavior/AllyBehaviorStateMachine.gd`
- Modify: `UnitSystem/AI/Ally/Units/Amy.tscn`
- Modify: `UnitSystem/Tests/AllyBehaviorStateMachineTest.gd`

**Interfaces:**

- Consumes `FormationPositionData` from Task 1.
- Produces `@export var formation_position: FormationPositionData`.
- Produces:

```gdscript
func set_formation_position(data: FormationPositionData) -> bool
func get_formation_position() -> FormationPositionData
```

- Existing callers continue consuming `get_current_movement_target()`, `physics_tick()` and Formation state names without signature changes.

- [ ] **Step 1: Add failing state-machine assertions**

Extend `AllyBehaviorStateMachineTest.gd` with a runtime resource switch:

```gdscript
var runtime_position := FormationPositionData.new()
runtime_position.display_name = "Runtime Test Position"
runtime_position.center_offset = Vector2(2.0, 4.0)
runtime_position.lateral_radius = 0.0
runtime_position.lateral_minimum = 0.0
runtime_position.forward_radius = 0.0
runtime_position.side_mode = FormationPositionData.SideMode.FREE_CROSSING

_expect(
	state_machine.set_formation_position(runtime_position),
	"formation position can be replaced through the public interface"
)
_expect(
	state_machine.get_formation_position() == runtime_position,
	"state machine exposes the selected shared resource"
)
var invalid_position := FormationPositionData.new()
invalid_position.lateral_radius = -1.0
_expect(
	not state_machine.set_formation_position(invalid_position),
	"invalid runtime position data is rejected without replacing the selection"
)
state_machine.physics_tick(0.016)
_expect(
	state_machine.get_current_movement_target().is_equal_approx(
		Vector3(2.0, player.global_position.y, -4.0)
	),
	"center offset is converted through player right and forward"
)
```

Also instantiate Amy and assert:

```gdscript
var amy := (load(AMY_SCENE_PATH) as PackedScene).instantiate() as AllyBase2
var amy_behavior := amy.get_node(^"BehaviorStateMachine") as AllyBehaviorStateMachine
_expect(
	amy_behavior.formation_position.resource_path
		== "res://UnitSystem/AI/Ally/Formation/Positions/AmyFormationPosition.tres",
	"Amy explicitly selects the migrated position resource"
)
```

Set a second resource while the state machine is in `COMBAT_APPROACH`; assert the state remains Combat and the current combat movement target is not replaced by the resource center.

- [ ] **Step 2: Run the behavior test and verify RED**

Run `AllyBehaviorStateMachineTest.gd`. Expected: parse/method failure because the typed export and public resource methods are absent.

- [ ] **Step 3: Add safe resource storage and fallback constants**

Remove the duplicated public position exports from the state machine:

```gdscript
front_distance
wander_lateral_radius
wander_lateral_minimum
wander_forward_radius
formation_side_mode
```

Replace them with:

```gdscript
const DEFAULT_FORMATION_CENTER_OFFSET := Vector2(0.0, 2.5)
const DEFAULT_LATERAL_RADIUS: float = 1.1
const DEFAULT_LATERAL_MINIMUM: float = 0.0
const DEFAULT_FORWARD_RADIUS: float = 0.65
const DEFAULT_SIDE_MODE := FormationPositionData.SideMode.FREE_CROSSING

@export_category("Formation Position")
@export var formation_position: FormationPositionData
```

Implement typed getters for each effective value so missing resources use these exact fallback constants. Add `_get_configuration_warnings()` describing a missing resource without blocking runtime.

- [ ] **Step 4: Implement runtime replacement**

Implement:

```gdscript
func set_formation_position(data: FormationPositionData) -> bool:
	if not _is_valid_formation_position_data(data):
		return false
	formation_position = data
	_initialize_formation_side()
	_combat_wander_target_valid = false
	if (
		_configured
		and is_instance_valid(_player)
		and _is_formation_or_return_state()
	):
		_raw_formation_center = _calculate_raw_formation_center(
			_stable_player_direction
		)
		_smoothed_formation_center = _raw_formation_center
		if _current_state == BehaviorState.RETURN:
			_movement_target = _constrain_target(_smoothed_formation_center)
		else:
			_select_new_formation_wander_target()
	return true


func get_formation_position() -> FormationPositionData:
	return formation_position
```

Implement the validation used above:

```gdscript
func _is_valid_formation_position_data(
	data: FormationPositionData
) -> bool:
	return (
		data != null
		and data.center_offset.is_finite()
		and data.lateral_radius >= 0.0
		and data.lateral_minimum >= 0.0
		and data.forward_radius >= 0.0
		and int(data.side_mode) >= int(FormationPositionData.SideMode.FREE_CROSSING)
		and int(data.side_mode) <= int(FormationPositionData.SideMode.FIXED_RIGHT)
	)
```

The effective-value getters must also use `maxf(..., 0.0)` so a malformed resource loaded directly from disk cannot produce a negative random range before the setter is called.

`_is_formation_or_return_state()` must return true only for `FORMATION_WANDER`, `FORMATION_REPOSITION` and `RETURN`. Combat and Custom only store the new resource and apply it when returning to Formation/Return.

- [ ] **Step 5: Migrate the existing calculations**

Update `_calculate_raw_formation_center()`:

```gdscript
func _calculate_raw_formation_center(direction: Vector3) -> Vector3:
	var player_right := Vector3(-direction.z, 0.0, direction.x)
	var center_offset: Vector2 = _get_formation_center_offset()
	return (
		_player.global_position
		+ player_right * center_offset.x
		+ direction * center_offset.y
	)
```

Define and use these exact private getters:

```gdscript
func _get_formation_center_offset() -> Vector2
func _get_formation_lateral_radius() -> float
func _get_formation_lateral_minimum() -> float
func _get_formation_forward_radius() -> float
func _get_formation_side_mode() -> FormationPositionData.SideMode
```

Update side initialization, random target generation and side-lock boundary checks to read these effective values. Calculate side-lock relative position from `_raw_formation_center` rather than `_player.global_position`; this is behavior-preserving for Amy `(0.0, 2.5)` and allows future lateral center offsets.

In `physics_tick()`, do not call `_update_formation_center()` while the current state is `COMBAT_APPROACH`, `COMBAT_HOLD`, `COMBAT_ATTACK` or `CUSTOM`. Formation and Return continue updating it. This prevents a resource assigned during Combat from being read until the unit returns to Formation/Return.

Do not read `formation_position` inside `_update_combat_approach()`, `_update_combat_hold()` or `_update_combat_attack()`.

- [ ] **Step 6: Assemble Amy without touching TestScene2**

Add the Amy resource as an ext-resource in `Amy.tscn`, then override only the inherited node:

```text
[node name="BehaviorStateMachine" parent="." index="4"]
formation_position = ExtResource("amy_formation")
preferred_combat_distance = 1.5
```

Do not open, save or rewrite `Scenes/TestScene2.tscn`; its inherited Amy instance will receive source-scene behavior automatically.

- [ ] **Step 7: Verify GREEN and existing formation behavior**

Run:

- `FormationPositionDataTest.gd`
- `AllyBehaviorStateMachineTest.gd`
- `AllyInheritedRootRenameTest.gd`
- `AllyTargetingIntegrationTest.gd`
- `AllyMeleeCombatIntegrationTest.gd`

Expected: all exit 0. Existing Amy Formation values remain numerically identical before overlap protection is added.

---

### Task 3: Formation target reservation without continuous separation

**Files:**

- Create: `UnitSystem/Tests/FormationTargetReservationTest.gd`
- Modify: `UnitSystem/Components/Behavior/AllyBehaviorStateMachine.gd`
- Modify: `UnitSystem/Tests/UnitDirectoryLayoutTest.gd`

**Interfaces:**

- Consumes the existing `_select_new_formation_wander_target()` refresh event; no new timer.
- Produces state-machine configuration:

```gdscript
@export_range(0.0, 5.0, 0.05)
var minimum_reserved_spacing: float = 0.65

@export_range(1, 32, 1)
var maximum_candidate_attempts: int = 8
```

- Does not change `AIUnitBase.set_movement_target()`, velocity, Dash or collision.

- [ ] **Step 1: Write a deterministic failing reservation test**

Create a test-only subclass that overrides only candidate generation, while exercising the real state machine occupancy and selection code:

```gdscript
class PredictableFormationStateMachine extends AllyBehaviorStateMachine:
	var candidates: Array[Vector2] = []

	func _generate_formation_local_candidate() -> Vector2:
		if candidates.is_empty():
			return Vector2.ZERO
		return candidates.pop_front()
```

Build a real world with PlayerBase and two same-team AIUnitBase owners. Place the first owner at the shared formation center. Configure the second state machine with:

```gdscript
state_machine.minimum_target_change_distance = 0.0
state_machine.minimum_reserved_spacing = 0.65
state_machine.maximum_candidate_attempts = 2
state_machine.candidates = [Vector2.ZERO, Vector2(1.0, 0.0)]
```

After configure, assert the chosen world target uses the second candidate and is `1.0m` laterally away from the occupied center.

Add a fallback case where both candidates are invalid:

```gdscript
state_machine.candidates = [Vector2(0.1, 0.0), Vector2(0.4, 0.0)]
```

Assert `0.4m` is selected because it has the greatest nearest-occupancy distance. Add a different-team AI at `0.4m` and confirm it is ignored by same-team reservation filtering.

- [ ] **Step 2: Run the reservation test and verify RED**

Run `FormationTargetReservationTest.gd`. Expected: missing exported properties/method failure or the first occupied candidate is incorrectly accepted.

- [ ] **Step 3: Separate candidate generation from candidate selection**

Extract the current lateral/longitudinal random code into:

```gdscript
func _generate_formation_local_candidate() -> Vector2:
	var lateral_radius: float = _get_formation_lateral_radius()
	var lateral_minimum: float = minf(
		_get_formation_lateral_minimum(),
		lateral_radius
	)
	var forward_radius: float = _get_formation_forward_radius()
	if (
		_get_formation_side_mode()
		== FormationPositionData.SideMode.FREE_CROSSING
	):
		var angle: float = _random_generator.randf_range(0.0, TAU)
		var radius: float = sqrt(_random_generator.randf())
		var lateral: float = cos(angle) * radius * lateral_radius
		var longitudinal: float = sin(angle) * radius * forward_radius
		if lateral_minimum > 0.0 and absf(lateral) < lateral_minimum:
			lateral = (-1.0 if lateral < 0.0 else 1.0) * lateral_minimum
		return Vector2(lateral, longitudinal)

	if _locked_side == 0:
		_locked_side = _choose_random_side()
	return Vector2(
		_random_generator.randf_range(lateral_minimum, lateral_radius)
			* float(_locked_side),
		_random_generator.randf_range(-forward_radius, forward_radius)
	)
```

Keep the same ellipse distribution for `FREE_CROSSING` and the same locked-side distribution for the other modes. This method must not inspect other units or mutate the movement target.

- [ ] **Step 4: Collect actual and reserved occupancy**

Implement an infrequent scene-tree scan called only during target refresh:

```gdscript
func _collect_formation_occupied_positions() -> Array[Vector3]:
	var occupied: Array[Vector3] = []
	var scene_root: Node = get_tree().current_scene
	if not is_instance_valid(scene_root):
		scene_root = get_tree().root
	_append_same_team_ai_occupancy(scene_root, occupied)
	return occupied
```

The recursive helper accepts another node only when it is an `AIUnitBase`, is not `_owner_body`, and `team_id` equals the owner’s non-zero `team_id`. Always append its current `global_position`.

If the unit is `AllyBase2`, inspect its behavior state. Append its `get_current_movement_target()` only when the other state is `FORMATION_WANDER`, `FORMATION_REPOSITION` or `RETURN`. Never ask a Combat unit for an array slot, target point or formation calculation.

- [ ] **Step 5: Implement bounded candidate selection**

In `_select_new_formation_wander_target()`:

1. Collect occupied positions once.
2. Generate at most `maximum_candidate_attempts` candidates.
3. Convert each local candidate to a world position using `_smoothed_formation_center`, player right and stable forward.
4. Compute horizontal distance to the closest occupied position.
5. Accept the first candidate whose clearance is at least `minimum_reserved_spacing` and whose local offset satisfies `minimum_target_change_distance`.
6. Track the candidate with greatest clearance.
7. If no candidate passes, select the greatest-clearance candidate; ties keep the first generated candidate.
8. Store only the selected lateral/longitudinal values, then continue through the existing `_calculate_wander_offset_world()`, `_constrain_target()` and `_reset_wander_timer()` flow.

When no same-team occupancy exists, use `INF` clearance so the first otherwise valid candidate is accepted without extra work.

- [ ] **Step 6: Verify Combat isolation**

Extend the reservation test with a real enemy and transition the tested Ally into `COMBAT_APPROACH`. Call `physics_tick()` and assert:

- the state remains a Combat state;
- its movement target is derived from the enemy and weapon/fallback combat distance;
- adding a nearby same-team AI does not alter that combat target;
- no new Formation candidate is consumed by `PredictableFormationStateMachine`.

- [ ] **Step 7: Verify GREEN**

Run:

- `FormationTargetReservationTest.gd`
- `AllyBehaviorStateMachineTest.gd`
- `AllyTargetingIntegrationTest.gd`
- `AllyMeleeCombatIntegrationTest.gd`
- `AIUnitBaseLocomotionMigrationTest.gd`

Expected: all exit 0; no test observes velocity modification, teleportation, collision changes or a new timer.

---

### Task 4: Full regression, editor scan and documentation

**Files:**

- Modify: `Docs/CurrentImplementationSummary.md`
- Modify: `Docs/Superpowers/Specs/2026-07-25-formation-position-resource-design.md`
- Modify: this plan’s implementation status/checkpoints

**Interfaces:**

- Consumes the completed resource/state-machine contract.
- Produces human-facing configuration instructions and verification evidence.

- [ ] **Step 1: Run every UnitSystem test**

Enumerate every `UnitSystem/Tests/*.gd` file and execute each with Godot 4.7 headless. Expected: every process exits 0, including the two new tests.

- [ ] **Step 2: Run a complete Godot editor scan**

Run:

```powershell
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' --headless --editor --path 'G:\Godot\SipSip' --quit
```

Expected: file scan and global class registration complete with exit code 0 and no project script warning/error.

- [ ] **Step 3: Confirm protected scenes and existing combat modules**

Verify:

- `Scenes/TestScene2.tscn` still exists and was not rewritten by the implementation.
- archived TestScene remains untouched.
- old `Scenes/Components/AiAttackModules` still exists.
- Amy source scene contains only the intended new Formation resource override in addition to its existing settings.

- [ ] **Step 4: Update the implementation summary**

Document this designer workflow:

```text
Create/duplicate a FormationPositionData .tres
→ configure center and wander area in Inspector
→ assign it to Ally/BehaviorStateMachine/Formation Position
→ no numeric position fields need to be copied into the character scene
```

Record that first phase provides only Amy’s resource, Combat ignores Formation, and overlap prevention reserves target points rather than applying continuous force.

- [ ] **Step 5: Record final evidence**

Append the actual test count, Godot version, editor scan result and protected-scene result to the design spec and this plan. Do not claim runtime visual behavior beyond what tests and editor scan prove; final in-editor observation remains available to the user through existing TestScene2 instances without Codex modifying them.
