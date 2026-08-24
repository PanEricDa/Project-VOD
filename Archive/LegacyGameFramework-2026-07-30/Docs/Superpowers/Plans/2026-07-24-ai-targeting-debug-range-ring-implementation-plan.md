# AI Targeting Debug Range Ring Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为所有 `AllyBase2` 继承单位增加独立可调的单一索敌半径，并在通用索敌组件中显示可开关、可变色的运行时调试范围圈。

**Architecture:** `AllyBase2` 根节点只导出 `targeting_radius`，配置组件时将首次索敌半径传入；`AITargetingComponent` 内部固定计算保持半径为首次索敌半径加 `1m`。调试圆环作为组件场景的 `MeshInstance3D` 子节点，仅显示首次索敌范围，并根据锁定状态切换材质颜色。

**Tech Stack:** Godot 4.7、GDScript、`Area3D`、`SphereShape3D`、`MeshInstance3D`、`TorusMesh`、headless `SceneTree` 测试。

## Global Constraints

- 所有字段和方法使用英文标识，新增代码提供详细简体中文注释。
- 每个伙伴单位根节点只暴露一个 `targeting_radius`；保持半径不得成为第二个 Inspector 参数。
- 内部保持半径固定等于 `targeting_radius + 1.0m`。
- 调试范围圈显示首次索敌半径，并可通过 `debug_range_visible` 开关。
- 无目标时范围圈为浅灰色半透明；有目标时为橙红色半透明。
- 范围圈不得参与物理检测、碰撞或目标选择。
- 不修改 `Scenes/TestScene.tscn` 或 `Scenes/TestScene2.tscn` 中的任何单位实例。
- 项目不是 Git 仓库，不执行提交步骤，以测试输出作为交付依据。

---

## File Map

- Modify `UnitSystem/Tests/AITargetingComponentTest.gd`：验证单一半径配置、内部 `+1m`、圆环尺寸、开关和颜色状态。
- Modify `UnitSystem/Tests/AllyTargetingIntegrationTest.gd`：验证每个 `AllyBase2` 实例独立传入根节点半径。
- Modify `UnitSystem/Components/Targeting/AI/AITargetingComponent.gd`：收口半径配置并管理调试圆环。
- Modify `UnitSystem/Components/Targeting/AI/AITargetingComponent.tscn`：增加通用 `DebugRangeRing`。
- Modify `UnitSystem/AI/Ally/AllyBase2.gd`：导出唯一的单位索敌半径并传给组件。

### Task 1: 单一索敌半径契约

**Files:**
- Modify: `UnitSystem/Tests/AITargetingComponentTest.gd`
- Modify: `UnitSystem/Tests/AllyTargetingIntegrationTest.gd`
- Modify: `UnitSystem/Components/Targeting/AI/AITargetingComponent.gd`
- Modify: `UnitSystem/AI/Ally/AllyBase2.gd`

**Interfaces:**
- Produces:
  - `AITargetingComponent.configure(owner_unit: UnitBase, targeting_radius: float) -> bool`
  - `AITargetingComponent.get_targeting_radius() -> float`
  - `AITargetingComponent.get_retention_radius() -> float`
  - `AllyBase2.targeting_radius: float = 6.0`

- [ ] **Step 1: Write failing radius tests**

Update the component test to configure a non-default radius and assert the fixed internal buffer:

```gdscript
_expect(
	component.configure(owner, 8.0),
	"component accepts owner and targeting radius"
)
_expect(
	is_equal_approx(component.get_targeting_radius(), 8.0),
	"component uses the configured acquisition radius"
)
_expect(
	is_equal_approx(component.get_retention_radius(), 9.0),
	"component calculates a fixed one-metre retention buffer"
)
```

Update the Ally integration test before adding the Ally to the tree:

```gdscript
ally.targeting_radius = 8.0
_world.add_child(ally)
_expect(
	is_equal_approx(targeting.get_targeting_radius(), 8.0),
	"AllyBase2 forwards its per-unit targeting radius"
)
_expect(
	is_equal_approx(targeting.get_retention_radius(), 9.0),
	"AllyBase2 does not expose a second retention setting"
)
```

- [ ] **Step 2: Run tests and verify RED**

Run:

```powershell
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' --headless --path 'G:\Godot\SipSip' --script res://UnitSystem/Tests/AITargetingComponentTest.gd
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' --headless --path 'G:\Godot\SipSip' --script res://UnitSystem/Tests/AllyTargetingIntegrationTest.gd
```

Expected: tests fail because `configure()` lacks the radius argument, the getters do not exist, and `AllyBase2` does not expose `targeting_radius`.

- [ ] **Step 3: Implement the minimal single-radius API**

In `AITargetingComponent.gd`, replace exported acquisition/retention fields with internal values:

```gdscript
const RETENTION_DISTANCE_BUFFER: float = 1.0

var _targeting_radius: float = 6.0
var _retention_radius: float = 7.0

func configure(owner_unit: UnitBase, targeting_radius: float) -> bool:
	_targeting_radius = maxf(targeting_radius, 0.1)
	_retention_radius = _targeting_radius + RETENTION_DISTANCE_BUFFER
	# 保留现有持有者、形状复制与物理处理配置。
	return true

func get_targeting_radius() -> float:
	return _targeting_radius

func get_retention_radius() -> float:
	return _retention_radius
```

All current target selection and shape synchronization must use `_targeting_radius` and `_retention_radius`.

In `AllyBase2.gd`, add:

```gdscript
@export_category("Targeting")
@export_range(0.1, 100.0, 0.1, "or_greater")
var targeting_radius: float = 6.0
```

Configure the child with:

```gdscript
_targeting_component.configure(self, targeting_radius)
```

- [ ] **Step 4: Run focused tests and verify GREEN**

Expected: both focused tests exit `0` and print `PASS`.

### Task 2: 可开关调试圆环与锁定颜色

**Files:**
- Modify: `UnitSystem/Tests/AITargetingComponentTest.gd`
- Modify: `UnitSystem/Components/Targeting/AI/AITargetingComponent.gd`
- Modify: `UnitSystem/Components/Targeting/AI/AITargetingComponent.tscn`

**Interfaces:**
- Produces:
  - `AITargetingComponent.debug_range_visible: bool = true`
  - Child node `DebugRangeRing: MeshInstance3D`

- [ ] **Step 1: Write failing debug-ring tests**

After component configuration, assert:

```gdscript
var debug_ring := component.get_node_or_null(^"DebugRangeRing") as MeshInstance3D
_expect(debug_ring != null, "component owns a debug range ring")
_expect(debug_ring.visible, "debug range ring is visible by default")

var torus := debug_ring.mesh as TorusMesh
_expect(
	torus != null and is_equal_approx(torus.outer_radius, 8.0),
	"debug ring displays the configured targeting radius"
)

var idle_material := debug_ring.material_override as StandardMaterial3D
_expect(
	idle_material != null and idle_material.albedo_color.is_equal_approx(
		Color(0.72, 0.75, 0.80, 0.32)
	),
	"debug ring is translucent light gray without a target"
)
```

After acquiring an enemy, assert the material color becomes:

```gdscript
Color(1.0, 0.24, 0.08, 0.48)
```

After `clear_locked_target()`, assert it returns to gray. Set `component.debug_range_visible = false`, invoke configuration synchronization through `refresh_target()`, and assert the ring is hidden while targeting still operates.

- [ ] **Step 2: Run the component test and verify RED**

Expected: FAIL because `DebugRangeRing` and `debug_range_visible` do not exist.

- [ ] **Step 3: Add the visual node**

In `AITargetingComponent.tscn`, add:

```text
AITargetingComponent
├── DetectionShape
└── DebugRangeRing (MeshInstance3D / TorusMesh)
```

Configure the ring as cast-shadow disabled, non-physical, horizontally centered at local `y = 0.03`, with a transparent unshaded `StandardMaterial3D`. The mesh and material are duplicated per component instance during `configure()` so resizing or recoloring Amy cannot alter another unit.

- [ ] **Step 4: Implement visual synchronization**

Add:

```gdscript
const DEBUG_IDLE_COLOR := Color(0.72, 0.75, 0.80, 0.32)
const DEBUG_LOCKED_COLOR := Color(1.0, 0.24, 0.08, 0.48)
const DEBUG_RING_WIDTH: float = 0.06

@export var debug_range_visible: bool = true
@onready var _debug_range_ring: MeshInstance3D = $DebugRangeRing
```

During `configure()`, duplicate the `TorusMesh` and `StandardMaterial3D`. Add `_sync_debug_range_ring()` which:

```gdscript
_debug_range_ring.visible = debug_range_visible
torus.outer_radius = _targeting_radius
torus.inner_radius = maxf(_targeting_radius - DEBUG_RING_WIDTH, 0.01)
material.albedo_color = (
	DEBUG_LOCKED_COLOR if has_locked_target() else DEBUG_IDLE_COLOR
)
```

Call it after radius synchronization, on every actual `_set_locked_target()` transition, and when regular detection configuration is synchronized. Missing visual resources must hide the debug node without disabling targeting.

- [ ] **Step 5: Run the component test and verify GREEN**

Expected: `AITargetingComponentTest: PASS`.

### Task 3: Full Godot Verification

**Files:**
- Modify: `Docs/Superpowers/Specs/2026-07-24-ai-targeting-debug-range-ring-design.md` only if implementation details differ from the approved design.

- [ ] **Step 1: Run every UnitSystem test**

Run each `UnitSystem/Tests/*.gd` script separately with Godot 4.7. Expected: every test exits `0` and prints `PASS`.

- [ ] **Step 2: Run project scans**

Run:

```powershell
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' --headless --editor --path 'G:\Godot\SipSip' --quit
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' --headless --path 'G:\Godot\SipSip' --quit-after 120
```

Expected: both exit `0` without script parse errors.

- [ ] **Step 3: Verify runtime behavior through MCP**

Run the main scene and inspect `/root/TestScene2/Amy/AITargetingComponent/DebugRangeRing`.

Expected:

- Amy inherits the ring without editing its source scene.
- The ring is gray before acquisition and orange-red after locking `EnemyBase2`.
- Toggling `debug_range_visible` hides only the ring.
- Target acquisition continues while the ring is hidden.

- [ ] **Step 4: Inspect editor output and protected scenes**

Confirm Godot’s Output and Debugger contain no new project errors or warnings. Confirm neither `Scenes/TestScene.tscn` nor `Scenes/TestScene2.tscn` was modified.

## Implementation Result

Implemented on 2026-07-24.

- `AllyBase2` now exposes one per-unit `targeting_radius`, defaulting to `6m`.
- `AITargetingComponent` calculates its internal retention radius as `targeting_radius + 1m`.
- The shared component scene now includes `DebugRangeRing`, with an Inspector-visible `debug_range_visible` switch.
- The ring uses the acquisition radius, stays independent from physics, and changes from translucent gray to orange-red when a target is locked.
- Each component duplicates its TorusMesh, material, and detection shape so runtime changes do not leak between units.
- Updated the stale `UnitDirectoryLayoutTest` contract from the former `AllyBase2` TestScene2 instance to the user-created `Amy` instance; TestScene2 itself was not edited.
- All seven `UnitSystem/Tests/*.gd` scripts pass under Godot 4.7.
- Headless editor scan and main-scene startup both exit with code `0`.
- MCP runtime inspection confirmed Amy inherits `DebugRangeRing`; the captured runtime frame shows its locked-target orange-red ring.
