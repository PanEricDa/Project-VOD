# Ally Formation / Combat State Machine Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the standalone FormationComponent with one open Ally behavior state machine that arbitrates Formation, Combat movement, Return, and a future Custom behavior hook.

**Architecture:** `AIUnitBase` remains the sole movement executor, `AITargetingComponent` remains the sole target owner, and the new `AllyBehaviorStateMachine` becomes the sole Ally behavior decision-maker. The existing formation algorithms move into the state machine; Combat adds approach, range holding, target-facing movement, and player-distance disengagement without adding attacks.

**Tech Stack:** Godot 4.7, typed GDScript, CharacterBody3D, NavigationAgent3D, SceneTree headless tests, Godot MCP Pro runtime inspection.

## Global Constraints

- Do not add, remove, or modify any unit instance in `res://Scenes/TestScene.tscn` or `res://Scenes/TestScene2.tscn`.
- Preserve existing Formation defaults, side locking, wander timing, chase, dash, targeting radius, targeting policy, and debug-ring behavior.
- The first Combat milestone must not request attacks, skills, damage, hitboxes, cooldowns, or animations.
- Every new field and method uses English identifiers and detailed Simplified Chinese comments.
- The project is not a Git repository; replace commit steps with explicit file and test checkpoints.

---

## File Structure

### Create

- `UnitSystem/Components/Behavior/AllyBehaviorStateMachine.gd` — owns all Ally Formation, Combat, Return, and Custom state decisions.
- `UnitSystem/Components/Behavior/AllyBehaviorStateMachine.tscn` — human-visible single behavior component scene.
- `UnitSystem/Tests/AllyBehaviorStateMachineTest.gd` — state transitions, range holding, disengagement, and Custom contract.

### Modify

- `UnitSystem/Base/AIUnitBase.gd` — adds per-movement-request facing policy.
- `UnitSystem/Components/Targeting/AI/AITargetingComponent.gd` — adds temporary detection suspension.
- `UnitSystem/AI/Ally/AllyBase2.gd` — configures and forwards the new state machine.
- `UnitSystem/AI/Ally/AllyBase2.tscn` — replaces FormationComponent with BehaviorStateMachine.
- `UnitSystem/Tests/AITargetingComponentTest.gd` — proves suspension and normal reacquisition.
- `UnitSystem/Tests/AIUnitBaseLocomotionMigrationTest.gd` — proves facing policy and final flattened structure.
- `UnitSystem/Tests/AllyInheritedRootRenameTest.gd` — updates inherited-node contract.
- `UnitSystem/Tests/AllyTargetingIntegrationTest.gd` — updates Ally assembly contract.
- `UnitSystem/Tests/UnitDirectoryLayoutTest.gd` — requires new files and rejects old Formation files.

### Delete

- `UnitSystem/Components/Movement/FormationComponent.gd`
- `UnitSystem/Components/Movement/FormationComponent.gd.uid`
- `UnitSystem/Components/Movement/FormationComponent.tscn`

---

### Task 1: Add Movement-Facing Policy to AIUnitBase

**Files:**
- Modify: `UnitSystem/Tests/AIUnitBaseLocomotionMigrationTest.gd`
- Modify: `UnitSystem/Base/AIUnitBase.gd`

**Interfaces:**
- Produces:

```gdscript
func set_movement_target(
    target_position: Vector3,
    maximum_speed: float = -1.0,
    face_movement_direction: bool = true
) -> void

func should_face_movement_direction() -> bool
```

- [ ] **Step 1: Write the failing contract test**

Add assertions that a default movement request returns `true`, a Combat-style request with the third parameter returns `false`, and `clear_movement_target()` restores `true`.

```gdscript
ai.set_movement_target(Vector3(2.0, 0.0, 0.0))
_expect(ai.should_face_movement_direction(), "movement faces travel by default")
ai.set_movement_target(Vector3(2.0, 0.0, 0.0), 2.0, false)
_expect(
    not ai.should_face_movement_direction(),
    "combat movement can preserve an explicit facing direction"
)
ai.clear_movement_target()
_expect(
    ai.should_face_movement_direction(),
    "clearing movement restores the default facing policy"
)
```

- [ ] **Step 2: Run the focused test and verify RED**

Run:

```powershell
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' --headless --path 'G:\Godot\SipSip' --script res://UnitSystem/Tests/AIUnitBaseLocomotionMigrationTest.gd
```

Expected: parse/runtime failure because `should_face_movement_direction()` and the third parameter do not exist.

- [ ] **Step 3: Implement minimal facing ownership**

Add `_face_movement_direction: bool = true`. Save the third parameter in `set_movement_target()`, only overwrite `_desired_facing_direction` inside `_process_regular_motion()` when the flag is true, and restore the flag in `clear_movement_target()` and `_reset_motion_runtime_state()`.

- [ ] **Step 4: Run the focused test and verify GREEN**

Expected: `AIUnitBaseLocomotionMigrationTest: PASS`.

---

### Task 2: Add Temporary Targeting Suspension

**Files:**
- Modify: `UnitSystem/Tests/AITargetingComponentTest.gd`
- Modify: `UnitSystem/Components/Targeting/AI/AITargetingComponent.gd`

**Interfaces:**
- Produces:

```gdscript
func suspend_detection(
    duration: float,
    clear_target: bool = true
) -> void

func get_detection_suspend_remaining() -> float
func is_detection_suspended() -> bool
```

- [ ] **Step 1: Add failing suspension tests**

With an enemy already inside the acquisition radius:

```gdscript
component.suspend_detection(0.05)
_expect(component.get_locked_target() == null, "suspension clears the lock")
component.refresh_target()
_expect(
    component.get_locked_target() == null,
    "manual refresh cannot bypass active suspension"
)
_expect(component.is_detection_suspended(), "suspension reports active")
await create_timer(0.08).timeout
component.refresh_target()
_expect(
    component.get_locked_target() == nearer_enemy,
    "normal targeting resumes without extra filters"
)
```

Also assert that `detection_enabled` remains true and the ring uses its idle color during suspension.

- [ ] **Step 2: Run the targeting test and verify RED**

Run the existing `AITargetingComponentTest.gd`; expect missing-method failure.

- [ ] **Step 3: Implement suspension**

Add a non-negative `_detection_suspend_remaining` timer. Decrement it in `_physics_process()`, make `refresh_target()` return after clearing any target while suspended, and do not modify `detection_enabled`. `suspend_detection()` keeps the maximum of the current and requested remaining duration so repeated requests cannot shorten an active pause.

- [ ] **Step 4: Run the targeting test and verify GREEN**

Expected: `AITargetingComponentTest: PASS`.

---

### Task 3: Build the Unified Ally Behavior State Machine

**Files:**
- Create: `UnitSystem/Tests/AllyBehaviorStateMachineTest.gd`
- Create: `UnitSystem/Components/Behavior/AllyBehaviorStateMachine.gd`
- Create: `UnitSystem/Components/Behavior/AllyBehaviorStateMachine.tscn`

**Interfaces:**
- Consumes:
  - `AIUnitBase.set_movement_target(target, speed, face_movement_direction)`
  - `AIUnitBase.set_desired_facing(direction)`
  - `AITargetingComponent.get_locked_target()`
  - `AITargetingComponent.suspend_detection(duration)`
- Produces:

```gdscript
enum BehaviorState {
    FORMATION_WANDER,
    FORMATION_REPOSITION,
    COMBAT_APPROACH,
    COMBAT_HOLD,
    RETURN,
    CUSTOM,
}

signal state_changed(
    previous_state: BehaviorState,
    current_state: BehaviorState
)
signal formation_side_changed(new_side: int)

func configure(
    owner_body: AIUnitBase,
    targeting_component: AITargetingComponent
) -> bool
func set_player(player: CharacterBody3D) -> void
func physics_tick(delta: float) -> void
func get_current_state() -> BehaviorState
func get_current_state_name() -> StringName
func is_in_combat() -> bool
func get_locked_side() -> int
func request_formation_side(side: int, refresh_target: bool = true) -> void
func request_custom_state(
    custom_state_id: StringName,
    context: Dictionary = {}
) -> bool
func exit_custom_state() -> void
```

- [ ] **Step 1: Write a failing scene/interface test**

Instantiate the new scene and verify it loads, exposes six states, accepts an `AIUnitBase` plus `AITargetingComponent`, starts in `FORMATION_WANDER`, reports non-combat, and rejects an unsupported Custom state without changing state.

- [ ] **Step 2: Run the new test and verify RED**

Expected: resource load failure because the scene does not exist.

- [ ] **Step 3: Create the component scene and state-machine shell**

Create a Node scene named `BehaviorStateMachine` with the typed script. Implement `_transition_to()` as the only state mutation path and emit `state_changed` exactly once per real transition.

- [ ] **Step 4: Port Formation behavior without changing defaults**

Move all Formation exports and algorithms from `FormationComponent.gd` into the new script. Map:

```text
WANDER     -> FORMATION_WANDER
REPOSITION -> FORMATION_REPOSITION
```

Preserve player-path resolution, direction confirmation, smoothed formation center, side locking, wander target selection, idle facing, chase and dash decisions.

- [ ] **Step 5: Add failing Combat transition assertions**

Use an explicit test player and target:

```text
target acquired outside preferred distance -> COMBAT_APPROACH
target enters distance band              -> COMBAT_HOLD
target moves beyond upper band           -> COMBAT_APPROACH
target becomes invalid                   -> RETURN
owner reaches formation center           -> FORMATION_WANDER
```

Assert `is_in_combat()` only for Approach and Hold.

- [ ] **Step 6: Implement Combat Approach and Hold**

Calculate horizontal target distance. Approach the target-distance ring with facing policy false. Hold behavior:

```text
too far  -> transition to COMBAT_APPROACH
too near -> submit an outward correction point
in band  -> submit a low-speed tangential wander point
```

Every Combat tick calls `set_desired_facing(horizontal_target_direction)` after submitting movement.

- [ ] **Step 7: Add and implement forced disengagement**

Test a player-target separation above `12m`; expect target clearing, `RETURN`, and a positive targeting suspension. Implement this check before ordinary Combat state updates. Normal target invalidation enters Return without starting suspension.

- [ ] **Step 8: Test and implement Custom extension hooks**

Create a test subclass that supports `&"rest"`, records enter/update/exit calls, and verifies:

```text
request rest -> CUSTOM
physics tick -> update hook
exit         -> RETURN
unknown id   -> false and no transition
```

- [ ] **Step 9: Run the complete state-machine test and verify GREEN**

Expected: `AllyBehaviorStateMachineTest: PASS`.

---

### Task 4: Assemble AllyBase2 and Remove the Legacy Formation Component

**Files:**
- Modify: `UnitSystem/AI/Ally/AllyBase2.gd`
- Modify: `UnitSystem/AI/Ally/AllyBase2.tscn`
- Modify: `UnitSystem/Tests/AllyInheritedRootRenameTest.gd`
- Modify: `UnitSystem/Tests/AllyTargetingIntegrationTest.gd`
- Modify: `UnitSystem/Tests/AIUnitBaseLocomotionMigrationTest.gd`
- Modify: `UnitSystem/Tests/UnitDirectoryLayoutTest.gd`
- Delete: `UnitSystem/Components/Movement/FormationComponent.gd`
- Delete: `UnitSystem/Components/Movement/FormationComponent.gd.uid`
- Delete: `UnitSystem/Components/Movement/FormationComponent.tscn`

**Interfaces:**
- Produces:

```gdscript
signal behavior_state_changed(
    previous_state: AllyBehaviorStateMachine.BehaviorState,
    current_state: AllyBehaviorStateMachine.BehaviorState
)

func get_behavior_state_machine() -> AllyBehaviorStateMachine
```

- [ ] **Step 1: Update integration tests first**

Require `BehaviorStateMachine` at the Ally root, reject
`MovementSystem/FormationComponent`, replace `get_formation_component()` checks with
`get_behavior_state_machine()`, and verify state-signal forwarding.

- [ ] **Step 2: Run integration tests and verify RED**

Run `AllyInheritedRootRenameTest`, `AllyTargetingIntegrationTest`,
`AIUnitBaseLocomotionMigrationTest`, and `UnitDirectoryLayoutTest`. Expect failures on the old assembly.

- [ ] **Step 3: Replace the scene instance**

Remove the Formation ext-resource and child. Add:

```text
BehaviorStateMachine
  instance = res://UnitSystem/Components/Behavior/AllyBehaviorStateMachine.tscn
  player_path = "../Hero"
```

Keep `AITargetingComponent`, collision, targeting radius, faction and all unrelated values unchanged.

- [ ] **Step 4: Rewire AllyBase2**

Configure targeting first, then configure the state machine with `self` and targeting. `_update_ai_movement()` calls only `physics_tick(delta)`. Preserve locked-target and formation-side forwarding, add behavior-state forwarding, keep `request_formation_side()`, and remove `get_formation_component()`.

- [ ] **Step 5: Delete old Formation files and enforce layout**

Add all old Formation paths to `LEGACY_FILES`; add new behavior files to
`REQUIRED_FILES` and the behavior scene to `LOADABLE_SCENES`.

- [ ] **Step 6: Run focused integration tests and verify GREEN**

Expected: all four tests print `PASS`.

---

### Task 5: Full Verification and Documentation

**Files:**
- Modify: `Docs/Superpowers/Plans/2026-07-25-ally-formation-combat-state-machine-implementation-plan.md`

- [ ] **Step 1: Run every UnitSystem test separately**

Run every `UnitSystem/Tests/*Test.gd` with Godot 4.7 headless. Expected: exit code `0` and `PASS` for every test.

- [ ] **Step 2: Run editor and project scans**

```powershell
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' --headless --editor --path 'G:\Godot\SipSip' --quit
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' --headless --path 'G:\Godot\SipSip' --quit-after 120
```

Expected: both exit `0`, with no parse errors or project warnings.

- [ ] **Step 3: Verify TestScene2 read-only through MCP**

Run the existing scene without saving it. Confirm:

- Amy runtime tree contains `BehaviorStateMachine` and no `FormationComponent`.
- Amy acquires EnemyBase2, enters Combat, moves while facing the target, and returns when the target becomes invalid or the player-target distance exceeds `12m`.
- Output contains no new errors or warnings.

- [ ] **Step 4: Record exact implementation results**

Append a dated result section listing tests, runtime evidence, deleted legacy files, and confirmation that neither TestScene was modified.

## Implementation Results (2026-07-25)

- Added `AllyBehaviorStateMachine.gd/.tscn` with
  `FORMATION_WANDER / FORMATION_REPOSITION / COMBAT_APPROACH /
  COMBAT_HOLD / RETURN / CUSTOM`.
- Moved the complete Formation center, side lock, wander, reposition and dash
  decisions into the single state-machine component.
- Added target-distance approach, two-sided distance correction, low-speed
  Combat wander, target-facing movement, `12m` player disengagement and `1.5s`
  targeting suspension.
- Added the open Custom request and enter/update/exit hook contract.
- Extended `AIUnitBase.set_movement_target()` with an optional
  `face_movement_direction` parameter.
- Added temporary detection suspension and immediate runtime synchronization of
  the `detection_enabled` Area3D monitoring switch.
- Replaced AllyBase2's legacy Formation child with the root-level
  `BehaviorStateMachine`; deleted all FormationComponent files.
- Added `AllyBehaviorStateMachineTest.gd` and updated every affected UnitSystem
  contract test.
- Fresh verification passed all 9 UnitSystem tests, the Godot 4.7 editor scan,
  and the headless project run.
- MCP read-only runtime verification observed Amy in `COMBAT_HOLD`, confirmed
  the 1.5–3.0 second stable wander target interval, and observed return to
  Formation after the player left the engagement.
- Godot Output contained no project errors or warnings.
- No unit instance or persisted property in `TestScene.tscn` or
  `TestScene2.tscn` was modified.
