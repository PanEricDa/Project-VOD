# Ranger Crossbow Tracking Projectile Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Equip Ranger with a reusable CrossbowAttack module that fires a fast Arrow along a dynamically tracked parabolic arc and always hits a still-valid target.

**Architecture:** `AllyBase` retains targeting, range approach, facing, HOLD movement, disengage behavior, and the shared `1.0s` basic-attack cooldown. `CrossbowAttack` subclasses `AIAttackModuleBase`, owns the existing crossbow visual and launches exactly one projectile from its animation method track. `TrackingArcProjectile` owns only per-arrow flight, target tracking, hit emission, and cleanup.

**Tech Stack:** Godot 4.7, GDScript, inherited PackedScenes, AnimationPlayer method tracks, Resource `.tres`, SceneTree headless tests.

## Global Constraints

- All new fields and methods use English identifiers; all new production-code comments are detailed Simplified Chinese.
- Preserve Ranger's current body and crossbow materials and visual proportions.
- Do not add projectile movement, spawning, or hit logic to `Scripts/AI/AllyBase.gd`.
- Keep `basic_attack_global_cooldown = 1.0s`; fast shooting means `flight_duration = 0.30s`, not a shorter attack cooldown.
- Ranger uses `attack_range = 6.5`, `attack_range_tolerance = 0.4`, and `return_to_guard_after_attack = false`.
- The Arrow follows a controlled visual arc and does not use rigid-body gravity, collision blocking, or miss chance.
- CrossbowAttack keeps the inherited melee ShapeCast disabled and disables inherited AI hit-stop feedback.
- Do not modify, add, move, or recreate any Ranger or other unit instance in `Scenes/TestScene.tscn`.
- This workspace is not a Git repository; do not create commits, branches, or worktrees. Use test results and file inspection as delivery evidence.

## File Map

- Create `Scripts/Combat/AI/TrackingArcProjectile.gd`: generic single-target tracked arc flight and hit signal.
- Modify `Scenes/Projectiles/Arrow.tscn`: attach the projectile script and give the existing visual a stable node name.
- Create `Scripts/Combat/AI/CrossbowAttack.gd`: one-shot animation delivery and projectile-to-`attack_hit` bridge.
- Create `Resources/Combat/AI/RangerCrossbowAttackProfile.tres`: Ranger range and HOLD configuration.
- Modify `Scenes/Components/AiAttackModules/CrossbowAttack.tscn`: crossbow visual, animation, spawn settings, and Arrow resource.
- Modify `Scenes/ObjectScenes/Ranger.tscn`: remove the fixed crossbow and equip CrossbowAttack under `AttackModuleSocket`.
- Create `Tests/TrackingArcProjectileTest.gd`: projectile lifecycle and trajectory contract.
- Create `Tests/RangerCrossbowAttackTest.gd`: module, animation, scene assembly, cooldown, and HOLD contract.
- Modify `Docs/CurrentImplementationSummary.md`: delivered Ranger behavior and maintenance boundary.

---

### Task 1: Tracking Arc Projectile

**Files:**
- Create: `Tests/TrackingArcProjectileTest.gd`
- Create: `Scripts/Combat/AI/TrackingArcProjectile.gd`
- Modify: `Scenes/Projectiles/Arrow.tscn`

**Interfaces:**
- Consumes: a valid in-tree `CharacterBody3D` target and world-space launch position.
- Produces: `launch(target, start_position, flight_duration, arc_height, target_height_offset, maximum_lifetime) -> bool` and `projectile_hit(target, hit_position, hit_direction)`.

- [ ] **Step 1: Write the failing projectile test**

Create a SceneTree test that loads `res://Scenes/Projectiles/Arrow.tscn`, then verifies the following real behaviors:

```gdscript
extends SceneTree

const ARROW_SCENE_PATH := "res://Scenes/Projectiles/Arrow.tscn"

var failures: Array[String] = []


func _initialize() -> void:
    call_deferred("_run")


func _run() -> void:
    var arrow_scene: PackedScene = load(ARROW_SCENE_PATH) as PackedScene
    _assert_true(arrow_scene != null, "Arrow scene must load", failures)
    if arrow_scene == null:
        _finish()
        return

    var target := CharacterBody3D.new()
    root.add_child(target)
    target.global_position = Vector3(4.0, 0.0, 0.0)

    var arrow := arrow_scene.instantiate() as Node3D
    root.add_child(arrow)
    _assert_true(arrow.has_method("launch"), "Arrow must expose launch()", failures)
    _assert_true(arrow.has_signal("projectile_hit"), "Arrow must expose projectile_hit", failures)

    var hit_count := 0
    var hit_target: CharacterBody3D
    var hit_position := Vector3.ZERO
    arrow.connect(
        &"projectile_hit",
        func(body: CharacterBody3D, position: Vector3, _direction: Vector3) -> void:
            hit_count += 1
            hit_target = body
            hit_position = position
    )

    _assert_true(
        arrow.call("launch", target, Vector3.ZERO, 0.30, 0.80, 0.25, 2.0) == true,
        "valid launch must start",
        failures
    )
    arrow.call("_physics_process", 0.15)
    _assert_near(arrow.global_position.x, 2.0, 0.01, "midpoint horizontal progress", failures)
    _assert_near(arrow.global_position.y, 0.925, 0.02, "midpoint tracked arc height", failures)

    target.global_position = Vector3(6.0, 0.0, 0.0)
    arrow.call("_physics_process", 0.15)
    _assert_true(hit_count == 1, "Arrow must emit exactly one hit", failures)
    _assert_true(hit_target == target, "Arrow must hit tracked target", failures)
    _assert_near(hit_position.x, 6.0, 0.01, "Arrow must hit latest target position", failures)
    _assert_near(hit_position.y, 0.25, 0.01, "Arrow must use target height offset", failures)

    var invalid_arrow := arrow_scene.instantiate() as Node3D
    root.add_child(invalid_arrow)
    _assert_true(
        invalid_arrow.call("launch", null, Vector3.ZERO, 0.30, 0.80, 0.25, 2.0) != true,
        "missing target must reject launch",
        failures
    )
    invalid_arrow.queue_free()

    var removed_target := CharacterBody3D.new()
    root.add_child(removed_target)
    var orphan_arrow := arrow_scene.instantiate() as Node3D
    root.add_child(orphan_arrow)
    var orphan_hits := 0
    orphan_arrow.connect(
        &"projectile_hit",
        func(_body: CharacterBody3D, _position: Vector3, _direction: Vector3) -> void:
            orphan_hits += 1
    )
    _assert_true(
        orphan_arrow.call("launch", removed_target, Vector3.ZERO, 0.30, 0.80, 0.25, 2.0) == true,
        "in-tree target must launch",
        failures
    )
    removed_target.queue_free()
    await process_frame
    orphan_arrow.call("_physics_process", 0.05)
    _assert_true(orphan_hits == 0, "invalidated target must not emit hit", failures)

    target.queue_free()
    await process_frame
    _finish()


func _assert_true(value: bool, message: String, output: Array[String]) -> void:
    if not value:
        output.append(message)


func _assert_near(value: float, expected: float, tolerance: float, message: String, output: Array[String]) -> void:
    if absf(value - expected) > tolerance:
        output.append(message + ": expected " + str(expected) + ", got " + str(value))


func _finish() -> void:
    if failures.is_empty():
        print("TrackingArcProjectileTest: PASS")
        quit(0)
        return
    for failure: String in failures:
        push_error(failure)
    quit(1)
```

- [ ] **Step 2: Run the test and verify RED**

```powershell
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' --headless --path 'G:\Godot\SipSip' --script res://Tests/TrackingArcProjectileTest.gd
```

Expected: exit code `1`, reporting that Arrow lacks `launch()` and `projectile_hit`.

- [ ] **Step 3: Implement the projectile script**

Create `TrackingArcProjectile.gd` with this lifecycle:

```gdscript
class_name AITrackingArcProjectile
extends Node3D

## 单支追踪抛物线投射物抵达有效目标时发送一次命中事件。
signal projectile_hit(
    target: CharacterBody3D,
    hit_position: Vector3,
    hit_direction: Vector3
)

var tracked_target: CharacterBody3D
var launch_position: Vector3 = Vector3.ZERO
var flight_duration: float = 0.30
var arc_height: float = 0.80
var target_height_offset: float = 0.25
var maximum_lifetime: float = 2.0
var elapsed_time: float = 0.0
var flight_is_active: bool = false
var hit_was_emitted: bool = false


func _ready() -> void:
    set_physics_process(false)


## 注入目标与本次飞行参数；无效目标或非正时长会拒绝启动。
func launch(
    target: CharacterBody3D,
    start_position: Vector3,
    duration: float,
    height: float,
    hit_height_offset: float,
    lifetime_limit: float
) -> bool:
    if not is_instance_valid(target) or not target.is_inside_tree():
        return false
    if duration <= 0.0 or lifetime_limit <= 0.0:
        return false

    tracked_target = target
    launch_position = start_position
    flight_duration = duration
    arc_height = max(height, 0.0)
    target_height_offset = hit_height_offset
    maximum_lifetime = lifetime_limit
    elapsed_time = 0.0
    hit_was_emitted = false
    flight_is_active = true
    global_position = launch_position
    set_physics_process(true)
    return true


func _physics_process(delta: float) -> void:
    if not flight_is_active:
        return
    if not is_instance_valid(tracked_target) or not tracked_target.is_inside_tree():
        _finish_without_hit()
        return

    elapsed_time += max(delta, 0.0)
    if elapsed_time >= maximum_lifetime:
        _finish_without_hit()
        return

    var progress: float = clamp(elapsed_time / flight_duration, 0.0, 1.0)
    var tracked_end: Vector3 = (
        tracked_target.global_position + Vector3.UP * target_height_offset
    )
    var base_position: Vector3 = launch_position.lerp(tracked_end, progress)
    var next_position: Vector3 = (
        base_position + Vector3.UP * sin(progress * PI) * arc_height
    )
    var flight_direction: Vector3 = next_position - global_position
    global_position = next_position
    if flight_direction.length_squared() > 0.000001:
        look_at(global_position + flight_direction.normalized(), Vector3.UP)

    if progress >= 1.0:
        _finish_with_hit(tracked_end, flight_direction)


func _finish_with_hit(hit_position: Vector3, flight_direction: Vector3) -> void:
    if hit_was_emitted:
        return
    hit_was_emitted = true
    flight_is_active = false
    set_physics_process(false)
    var safe_direction: Vector3 = flight_direction.normalized()
    if safe_direction.length_squared() <= 0.000001:
        safe_direction = Vector3.FORWARD
    projectile_hit.emit(tracked_target, hit_position, safe_direction)
    queue_free()


func _finish_without_hit() -> void:
    flight_is_active = false
    set_physics_process(false)
    queue_free()
```

Attach the script to Arrow and rename the existing `CSGBox3D` node to `ArrowVisual`. Keep its size and material unchanged.

- [ ] **Step 4: Run the focused test and verify GREEN**

Run the command from Step 2.

Expected: `TrackingArcProjectileTest: PASS`, exit code `0`, with no parse errors.

---

### Task 2: Crossbow Attack Module and Profile

**Files:**
- Create: `Tests/RangerCrossbowAttackTest.gd`
- Create: `Scripts/Combat/AI/CrossbowAttack.gd`
- Create: `Resources/Combat/AI/RangerCrossbowAttackProfile.tres`
- Modify: `Scenes/Components/AiAttackModules/CrossbowAttack.tscn`

**Interfaces:**
- Consumes: `AIAttackModuleBase.request_attack(target)`, `AttackOrigin`, Arrow's `launch(...)`, and Arrow's `projectile_hit`.
- Produces: one projectile per valid attack, inherited `attack_hit`, and Inspector projectile parameters.

- [ ] **Step 1: Write the failing module contract**

Create `RangerCrossbowAttackTest.gd` and first assert:

```gdscript
const CROSSBOW_SCENE_PATH := "res://Scenes/Components/AiAttackModules/CrossbowAttack.tscn"
const PROFILE_PATH := "res://Resources/Combat/AI/RangerCrossbowAttackProfile.tres"
const ARROW_SCENE_PATH := "res://Scenes/Projectiles/Arrow.tscn"

var crossbow_scene: PackedScene = load(CROSSBOW_SCENE_PATH) as PackedScene
var crossbow: Node = crossbow_scene.instantiate()
root.add_child(crossbow)

_assert_true(crossbow.get_script() != null, "CrossbowAttack needs its own script", failures)
_assert_true(crossbow.get("projectile_scene") != null, "missing Arrow projectile scene", failures)
_assert_near(crossbow.get("projectile_flight_duration"), 0.30, 0.001, "flight duration", failures)
_assert_near(crossbow.get("projectile_arc_height"), 0.80, 0.001, "arc height", failures)
_assert_near(crossbow.get("projectile_target_height_offset"), 0.25, 0.001, "target height", failures)
_assert_near(crossbow.get("projectile_maximum_lifetime"), 2.0, 0.001, "maximum lifetime", failures)
_assert_true(crossbow.get("hitbox_enabled") == false, "ranged ShapeCast must stay disabled", failures)
_assert_true(crossbow.get("hit_feedback_enabled") == false, "ranged hit-stop must stay disabled", failures)
_assert_near(crossbow.call("get_attack_range"), 6.5, 0.001, "Ranger attack range", failures)
_assert_near(crossbow.call("get_attack_range_tolerance"), 0.4, 0.001, "range tolerance", failures)
_assert_true(not crossbow.call("should_return_to_guard_after_attack"), "Ranger must HOLD", failures)
_assert_true(crossbow.has_node("WeaponPivot/WeaponVisualRoot/CrossbowRoot/LoadedBolt"), "missing loaded bolt", failures)
```

Inspect the `attack` animation and assert length `0.35`, exactly one `_release_projectile` method key near `0.12`, and no `_open_hit_window`/`_close_hit_window` methods.

For runtime delivery, use the real Arrow scene, record `root.get_child_count()`, call `request_attack(target)`, then call `_release_projectile()` twice. Assert the root child count increases by exactly one. Locate the new child whose script is `AITrackingArcProjectile`, advance it once with `projectile.call("_physics_process", 0.30)`, and assert CrossbowAttack forwards exactly one `attack_hit` signal.

- [ ] **Step 2: Run the test and verify RED**

```powershell
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' --headless --path 'G:\Godot\SipSip' --script res://Tests/RangerCrossbowAttackTest.gd
```

Expected: exit code `1` because the current CrossbowAttack is only an empty inherited base scene and the Ranger profile does not exist.

- [ ] **Step 3: Create the Ranger Profile**

```ini
[gd_resource type="Resource" script_class="AIAttackProfile" load_steps=2 format=3]

[ext_resource type="Script" path="res://Scripts/Combat/AI/AttackProfile.gd" id="1_profile"]

[resource]
script = ExtResource("1_profile")
display_name = "Ranger Crossbow Shot"
attack_range = 6.5
attack_range_tolerance = 0.4
approach_speed_multiplier = 1.0
return_to_guard_after_attack = false
```

- [ ] **Step 4: Implement CrossbowAttack.gd**

```gdscript
class_name AICrossbowAttack
extends AIAttackModuleBase

@export_category("Projectile")
## 发射时实例化的投射物场景；默认使用 Arrow.tscn。
@export var projectile_scene: PackedScene
@export_range(0.01, 5.0, 0.01) var projectile_flight_duration: float = 0.30
@export_range(0.0, 10.0, 0.05) var projectile_arc_height: float = 0.80
@export_range(-5.0, 5.0, 0.05) var projectile_target_height_offset: float = 0.25
@export_range(0.01, 30.0, 0.05) var projectile_maximum_lifetime: float = 2.0
@export_node_path("Node3D") var attack_origin_path: NodePath = ^"WeaponPivot/AttackOrigin"
@export_node_path("Node3D") var loaded_projectile_visual_path: NodePath = ^"WeaponPivot/WeaponVisualRoot/CrossbowRoot/LoadedBolt"

var projectile_was_released: bool = false


func request_attack(target: CharacterBody3D) -> bool:
    projectile_was_released = false
    _set_loaded_projectile_visible(true)
    return super.request_attack(target)


func reset_module() -> void:
    super.reset_module()
    projectile_was_released = false
    _set_loaded_projectile_visible(true)


## AnimationPlayer 方法轨道只调用一次；标志位阻止错误轨道生成重复箭矢。
func _release_projectile() -> void:
    if attack_state != AttackState.ATTACKING or projectile_was_released:
        return
    projectile_was_released = true
    _set_loaded_projectile_visible(false)
    if projectile_scene == null:
        push_warning("AICrossbowAttack: projectile_scene is missing.")
        return
    if not is_instance_valid(current_target) or not current_target.is_inside_tree():
        return

    var origin: Node3D = get_node_or_null(attack_origin_path) as Node3D
    if origin == null:
        push_warning("AICrossbowAttack: attack_origin_path is invalid.")
        return
    var projectile: Node3D = projectile_scene.instantiate() as Node3D
    if projectile == null or not projectile.has_method("launch"):
        if projectile != null:
            projectile.queue_free()
        push_warning("AICrossbowAttack: projectile must be a Node3D with launch().")
        return

    var projectile_parent: Node = get_tree().current_scene
    if projectile_parent == null:
        projectile_parent = get_tree().root
    projectile_parent.add_child(projectile)
    if projectile.has_signal("projectile_hit"):
        projectile.connect(&"projectile_hit", _on_projectile_hit)
    var launched: bool = projectile.call(
        "launch",
        current_target,
        origin.global_position,
        projectile_flight_duration,
        projectile_arc_height,
        projectile_target_height_offset,
        projectile_maximum_lifetime
    ) == true
    if not launched:
        projectile.queue_free()


func _on_projectile_hit(
    target: CharacterBody3D,
    hit_position: Vector3,
    hit_direction: Vector3
) -> void:
    attack_hit.emit(target, hit_position, hit_direction)


func _on_animation_finished(animation_name: StringName) -> void:
    var finished_current_attack: bool = (
        attack_state == AttackState.ATTACKING
        and animation_name == attack_animation_name
    )
    super._on_animation_finished(animation_name)
    if finished_current_attack:
        projectile_was_released = false
        _set_loaded_projectile_visible(true)


func _set_loaded_projectile_visible(visible_value: bool) -> void:
    var loaded_visual: Node3D = get_node_or_null(loaded_projectile_visual_path) as Node3D
    if loaded_visual != null:
        loaded_visual.visible = visible_value
```

- [ ] **Step 5: Build CrossbowAttack.tscn**

Keep it inherited from `AttackModuleBase.tscn`, attach `CrossbowAttack.gd`, assign the Ranger Profile and Arrow scene, and set:

```text
root name = CrossbowAttack
attack_animation_name = attack
hitbox_enabled = false
hit_feedback_enabled = false
projectile_flight_duration = 0.30
projectile_arc_height = 0.80
projectile_target_height_offset = 0.25
projectile_maximum_lifetime = 2.0
AttackOrigin.position = Vector3(0.32, 0.385, -0.70)
```

Move the existing Ranger crossbow visual into `WeaponPivot/WeaponVisualRoot/CrossbowRoot`, preserving its current transforms, sizes, and `MatGridYellow.tres`. Rename the old visual `Bolt` to `LoadedBolt`.

Create `RESET` and `attack` animations. `attack` length is `0.35s`; animate only `WeaponPivot` local position/rotation and add one method key `_release_projectile()` at `0.12s`. Do not call hit-window methods.

- [ ] **Step 6: Run the focused module test and verify GREEN for module assertions**

Run the command from Step 2.

Expected: projectile module, Profile, visual, animation, one-shot delivery, and hit forwarding assertions pass. Ranger assembly assertions added in Task 3 may remain RED until that task is complete.

---

### Task 3: Equip Ranger and Verify Shared Cooldown/HOLD

**Files:**
- Modify: `Scenes/ObjectScenes/Ranger.tscn`
- Modify: `Tests/RangerCrossbowAttackTest.gd`

**Interfaces:**
- Consumes: `AllyBase.attack_module_path`, `set_attack_module()`, `_try_start_basic_attack()`, and CrossbowAttack Profile getters.
- Produces: a source Ranger scene with a stable attack-module path and no duplicate fixed weapon.

- [ ] **Step 1: Add failing Ranger assembly and behavior assertions**

Extend the focused test:

```gdscript
const RANGER_SCENE_PATH := "res://Scenes/ObjectScenes/Ranger.tscn"

var ranger_scene: PackedScene = load(RANGER_SCENE_PATH) as PackedScene
var ranger: CharacterBody3D = ranger_scene.instantiate() as CharacterBody3D
root.add_child(ranger)
await process_frame

_assert_true(
    ranger.get("attack_module_path") == NodePath("VisualRoot/AttackModuleSocket/CrossbowAttack"),
    "Ranger attack_module_path must match scene tree",
    failures
)
_assert_true(
    ranger.has_node("VisualRoot/AttackModuleSocket/CrossbowAttack"),
    "Ranger must equip CrossbowAttack under AttackModuleSocket",
    failures
)
_assert_true(
    not ranger.has_node("VisualRoot/CrossbowRoot"),
    "Ranger must not keep duplicate fixed crossbow",
    failures
)
_assert_near(ranger.get("basic_attack_global_cooldown"), 1.0, 0.001, "shared cooldown", failures)
```

Create a real in-tree target, set it as `current_visible_enemy`, clear cooldown, and call the existing attack start path. Assert the request succeeds, cooldown becomes `1.0`, and after module animation completion the state becomes `BasicAttackState.HOLD`, not `RETURN_TO_GUARD`.

- [ ] **Step 2: Run and verify RED**

Expected: Ranger lacks the module path and still owns `VisualRoot/CrossbowRoot`.

- [ ] **Step 3: Reassemble Ranger.tscn**

- Add `CrossbowAttack.tscn` as a node named exactly `CrossbowAttack` under `VisualRoot/AttackModuleSocket`.
- Set `attack_module_path = NodePath("VisualRoot/AttackModuleSocket/CrossbowAttack")` on the Ranger root.
- Remove the old `VisualRoot/CrossbowRoot` subtree only after its visual data has been preserved in CrossbowAttack.
- Preserve the Ranger source values observed immediately before assembly: body material, body dimensions, formation parameters, user-adjusted `enemy_vision_range = 6.5`, user-adjusted `combat_guard_distance = 5.0`, and every unrelated Inspector value.
- Save and reopen the source scene once, then confirm the child remains under `AttackModuleSocket`; reject any encoded root name such as `VisualRoot_AttackModuleSocket#CrossbowAttack`.

- [ ] **Step 4: Run the focused test and verify GREEN**

Expected: `RangerCrossbowAttackTest: PASS`, exit code `0`.

---

### Task 4: Regression and Runtime Verification

**Files:**
- Verify: all combat scripts and scenes
- Verify only: `Scenes/TestScene.tscn`

**Interfaces:**
- Produces: evidence that Ranger did not regress Guardian, Warrior, AllyBase, or TestScene ownership rules.

- [ ] **Step 1: Run the projectile and all combat test scripts**

```powershell
$godot = 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe'
$tests = @(
  'TrackingArcProjectileTest.gd',
  'RangerCrossbowAttackTest.gd',
  'AIAttackHitboxTest.gd',
  'AIAttackModuleBaseTest.gd',
  'AIHitFeedbackTest.gd',
  'AllyAttackDistanceTest.gd',
  'AllyBasicAttackTest.gd',
  'GuardianShieldAttackTest.gd',
  'WarriorSwordAttackTest.gd'
)
foreach ($test in $tests) {
  & $godot --headless --path 'G:\Godot\SipSip' --script ("res://Tests/" + $test)
  if ($LASTEXITCODE -ne 0) { exit 1 }
}
```

Expected: all nine scripts print `PASS` and exit `0`.

- [ ] **Step 2: Smoke-test project startup**

```powershell
& $godot --headless --path 'G:\Godot\SipSip' --quit-after 10
```

Expected: exit code `0` with no parse or runtime errors.

- [ ] **Step 3: Verify through Godot MCP**

- Refresh/reload the project if the editor has stale scripts.
- Open `Ranger.tscn` and inspect `VisualRoot/AttackModuleSocket/CrossbowAttack`.
- Check editor errors and output; expected new error count is `0`.
- Run the existing TestScene read-only. Observe a user-placed Ranger only if one already exists; do not add, move, remove, or recreate a unit.
- Confirm visible arrows leave the crossbow, arc quickly, track moving Dummy targets, and disappear on arrival.

- [ ] **Step 4: Recheck TestScene preservation**

Compare `Scenes/TestScene.tscn` timestamp/content recorded before implementation with the final file. If it changed during verification, stop and report the difference; do not overwrite, restore, or otherwise modify user-owned unit configuration.

---

### Task 5: Documentation Handoff

**Files:**
- Modify: `Docs/CurrentImplementationSummary.md`
- Modify: `Docs/Superpowers/Plans/2026-07-14-ranger-crossbow-projectile-implementation-plan.md`

**Interfaces:**
- Produces: a concise maintenance record and final verification evidence.

- [ ] **Step 1: Update the implementation summary**

Add a Ranger section recording:

```text
Ranger source: res://Scenes/ObjectScenes/Ranger.tscn
Weapon module: res://Scenes/Components/AiAttackModules/CrossbowAttack.tscn
Projectile: res://Scenes/Projectiles/Arrow.tscn
Attack range: 6.5m ± 0.4m
Shared cooldown: 1.0s
Projectile flight: 0.30s tracked arc, 0.80m arc height
Post-attack state: HOLD at attack range; no return to current 5.0m guard distance
Current hit result: attack_hit signal only; no damage or collision blocking
```

Also record that CrossbowAttack must be named exactly and parented directly under `VisualRoot/AttackModuleSocket`.

- [ ] **Step 2: Append final verification results to this plan**

Record the exact PASS count, smoke-test exit code, MCP editor error count, and confirmation that TestScene unit instances were not modified by Codex. Do not claim success if any verification step remains failing.

- [ ] **Step 3: Give manual TestScene guidance only if needed**

If the user needs a Ranger instance, instruct them to drag `res://Scenes/ObjectScenes/Ranger.tscn` into the same unit parent used by their other units and choose a non-overlapping ground position. Do not perform this placement automatically.

## Implementation Result

- Added `TrackingArcProjectile.gd` and attached it to the existing Arrow scene without changing the Arrow visual size or material.
- Added `CrossbowAttack.gd`, `RangerCrossbowAttackProfile.tres`, the migrated crossbow visual, a `0.35s` shooting animation, and a single `_release_projectile()` key at `0.12s`.
- Ranger now resolves `VisualRoot/AttackModuleSocket/CrossbowAttack`; the user-created module placement and user-adjusted `enemy_vision_range=6.5` / `combat_guard_distance=5.0` were preserved.
- The Arrow uses a `0.30s` dynamically tracked arc with `0.80m` height and emits one unified hit for a still-valid target. CrossbowAttack keeps melee ShapeCast and AI hit-stop disabled.
- TDD evidence: TrackingArcProjectile failed first for missing `launch()`/`projectile_hit`; CrossbowAttack failed first for missing script/Profile/exports/animation; Ranger assembly failed first only for missing `attack_module_path`. Each focused test passed after its minimal implementation.
- Fresh verification: 9 test scripts passed, project Headless smoke exited `0`, and TestScene SHA-256 remained `91C88AE6EAFC5A22CD49DBC898438E65228C5428F515C34B12AFDBA23CF5E96E`.
- MCP `CACHE_MODE_REPLACE` inspection confirmed the Ranger path, `CrossbowAttack.gd`, Ranger Profile, LoadedBolt visual, and disabled hit-stop. `get_editor_errors` still retains 7 historical/tool-generated entries: four progress-dialog errors, two `validate_script` temporary-copy `class_name` false positives, and one placeholder-instance method-call error from read-only inspection. Headless compilation and runtime tests report no project parse/runtime failure.
- `Scenes/TestScene.tscn` and all unit instances inside it were preserved unchanged.
