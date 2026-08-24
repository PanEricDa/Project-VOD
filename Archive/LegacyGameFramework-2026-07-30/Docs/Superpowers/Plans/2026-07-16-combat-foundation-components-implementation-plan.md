# Combat Foundation Components Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add reusable resource-pool, health, and faction components and mount them on the Hero, AllyBase, and EnemyBase source scenes without changing current gameplay behavior.

**Architecture:** `ResourcePoolComponent` owns bounded numeric state and transition signals. `HealthComponent` specializes it with damage, healing, death, and revival semantics; `FactionComponent` independently models identity and team relationships. Reusable component scenes are instantiated as direct children of the three combatant roots, so inherited professions and Dummy receive them automatically.

**Tech Stack:** Godot 4.7, typed GDScript, `.tscn` packed scenes, headless `SceneTree` contract tests.

## Global Constraints

- New fields, signals, and methods use English identifiers and detailed Simplified Chinese comments.
- Component code depends only on Godot core APIs and does not reference HeroController, AllyBase, EnemyBase, skill modules, attack modules, or TestScene.
- Existing `enemy_targets` groups, collision layers, and character behavior remain unchanged.
- Do not modify `Scenes/TestScene.tscn` or add any unit instance to it.
- The project is not a Git repository, so replace commit steps with filesystem and test evidence.

---

## File Map

- Create `Scripts/Combat/Components/ResourcePoolComponent.gd`: generic bounded numeric resource and boundary signals.
- Create `Scripts/Combat/Components/HealthComponent.gd`: health-specific API and semantic signals.
- Create `Scripts/Combat/Components/FactionComponent.gd`: faction identity and team relationship API.
- Create `Scenes/Components/Combat/HealthComponent.tscn`: reusable health component instance with 100/100 defaults.
- Create `Scenes/Components/Combat/FactionComponent.tscn`: reusable neutral faction component instance.
- Create `Tests/CombatFoundationComponentsTest.gd`: component behavior and source-scene assembly contract.
- Modify `Scenes/ObjectScenes/Hero.tscn`: mount health and player/team-1 faction components.
- Modify `Scenes/ObjectScenes/AllyBase.tscn`: mount health and ally/team-1 faction components.
- Modify `Scenes/EnemyScenes/EnemyBase.tscn`: mount health and enemy/team-2 faction components.

### Task 1: Add the failing component contract test

**Files:**
- Create: `Tests/CombatFoundationComponentsTest.gd`

**Interfaces:**
- Consumes: Godot `ResourceLoader`, `PackedScene`, `Node`, and signal APIs.
- Produces: executable contract for all component paths, methods, signals, numeric behavior, relationship behavior, and scene assembly.

- [x] **Step 1: Write the path-first failing test**

Create a `SceneTree` test that first checks these exact resources without statically preloading absent scripts:

```gdscript
const RESOURCE_POOL_SCRIPT_PATH := "res://Scripts/Combat/Components/ResourcePoolComponent.gd"
const HEALTH_SCRIPT_PATH := "res://Scripts/Combat/Components/HealthComponent.gd"
const FACTION_SCRIPT_PATH := "res://Scripts/Combat/Components/FactionComponent.gd"
const HEALTH_SCENE_PATH := "res://Scenes/Components/Combat/HealthComponent.tscn"
const FACTION_SCENE_PATH := "res://Scenes/Components/Combat/FactionComponent.tscn"
```

After confirming paths, instantiate the scripts/scenes dynamically and verify:

```gdscript
pool.call("set_current_value", 25.0, source)
pool.call("modify_value", -30.0, source) # actual delta -25, then depleted once
pool.call("modify_value", -1.0, source)  # no duplicate depleted
pool.call("modify_value", 10.0, source)  # restored_from_empty once
pool.call("try_consume", 11.0, source)   # false and no partial mutation

health.call("apply_damage", 30.0, source)
health.call("apply_healing", 10.0, source)
health.call("apply_damage", 1000.0, source)
health.call("apply_healing", 10.0, source) # blocked while dead
health.call("revive", 20.0, source)

friendly_a.call("is_friendly_to", friendly_b) # true for team 1 / team 1
friendly_a.call("is_hostile_to", enemy)        # true for team 1 / team 2
friendly_a.call("is_neutral_to", neutral)      # true when either team is 0
```

Load Hero, AllyBase, EnemyBase, one inherited Ally scene, and Dummy; verify direct/inherited `HealthComponent` and `FactionComponent` paths and exact defaults.

- [x] **Step 2: Run the test and confirm RED**

Run:

```powershell
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' --headless --path 'G:\Godot\SipSip' --script res://Tests/CombatFoundationComponentsTest.gd
```

Expected: exit code `1` with missing component resource assertions and no unrelated TestScene mutation.

### Task 2: Implement ResourcePoolComponent and HealthComponent

**Files:**
- Create: `Scripts/Combat/Components/ResourcePoolComponent.gd`
- Create: `Scripts/Combat/Components/HealthComponent.gd`
- Create: `Scenes/Components/Combat/HealthComponent.tscn`
- Test: `Tests/CombatFoundationComponentsTest.gd`

**Interfaces:**
- Produces: the complete public APIs and signals specified in `Docs/Superpowers/Specs/2026-07-16-combat-foundation-components-design.md`.

- [x] **Step 1: Implement the generic bounded resource**

Use `class_name ResourcePoolComponent extends Node`, initialize a private `current_value` from the clamped authoring values in `_ready()`, and route all mutation through one internal boundary-aware setter. The setter returns the actual signed delta and emits `value_changed`, `depleted`, and `restored_from_empty` only for real changes and boundary crossings.

`try_consume()` must be atomic:

```gdscript
func try_consume(amount: float, source: Node = null) -> bool:
    if amount < 0.0 or amount > current_value:
        return false
    if is_zero_approx(amount):
        return true
    modify_value(-amount, source)
    return true
```

- [x] **Step 2: Implement health semantics**

Use `class_name HealthComponent extends ResourcePoolComponent`. Damage returns `absf(min(applied_delta, 0.0))`; healing returns `maxf(applied_delta, 0.0)`. Connect to or override the generic transition hook so `died` occurs exactly on a positive-to-zero transition. Block normal healing while dead and require `revive()` to cross the empty boundary.

- [x] **Step 3: Create the reusable health scene**

Create a single `Node` root named `HealthComponent` with the health script and exact 100/100 defaults.

- [x] **Step 4: Run the focused test**

Run the Task 1 command. Expected: resource/health behavior passes; remaining failures are limited to missing faction component and source-scene mounts.

### Task 3: Implement FactionComponent and mount all components

**Files:**
- Create: `Scripts/Combat/Components/FactionComponent.gd`
- Create: `Scenes/Components/Combat/FactionComponent.tscn`
- Modify: `Scenes/ObjectScenes/Hero.tscn`
- Modify: `Scenes/ObjectScenes/AllyBase.tscn`
- Modify: `Scenes/EnemyScenes/EnemyBase.tscn`
- Test: `Tests/CombatFoundationComponentsTest.gd`

**Interfaces:**
- Consumes: `HealthComponent.tscn` and `FactionComponent.tscn` packed scenes.
- Produces: `is_friendly_to()`, `is_hostile_to()`, and `is_neutral_to()` plus exact root child paths on all combatant scenes.

- [x] **Step 1: Implement team relationships**

Use `class_name FactionComponent extends Node`. Treat null/invalid components and any zero team as neutral. Friendly means equal nonzero team IDs; hostile means different nonzero team IDs.

- [x] **Step 2: Create the reusable neutral faction scene**

Create a root named `FactionComponent` configured as `faction_id = &"neutral"`, `team_id = 0`, and `targetable = true`.

- [x] **Step 3: Mount the packed component scenes**

Add both packed-scene resources and direct child instances to each source scene. Override only faction fields:

```text
Hero:      faction_id = player, team_id = 1
AllyBase:  faction_id = ally,   team_id = 1
EnemyBase: faction_id = enemy,  team_id = 2
```

Leave Health at 100/100 and preserve every existing node, group, collision setting, script, and resource.

- [x] **Step 4: Run the focused test and confirm GREEN**

Run the Task 1 command. Expected: `CombatFoundationComponentsTest: PASS`, exit code `0`.

### Task 4: Regression and scene-integrity verification

**Files:**
- Verify only; do not modify `Scenes/TestScene.tscn`.

**Interfaces:**
- Consumes: completed components and mounts.
- Produces: compile, regression, and TestScene-integrity evidence.

- [x] **Step 1: Record TestScene integrity before final validation**

Capture path, length, last-write time, and SHA-256. Compare against the working copy after all tests; any difference is a failure.

- [x] **Step 2: Run every headless test**

```powershell
$godot = 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe'
Get-ChildItem 'G:\Godot\SipSip\Tests' -Filter '*.gd' | Sort-Object Name | ForEach-Object {
    & $godot --headless --path 'G:\Godot\SipSip' --script ('res://Tests/' + $_.Name)
    if ($LASTEXITCODE -ne 0) { throw "Test failed: $($_.Name)" }
}
```

Expected: every test prints its `PASS` marker and exits `0`.

- [x] **Step 3: Run the project smoke check**

```powershell
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' --headless --path 'G:\Godot\SipSip' --quit-after 10
```

Expected: no parser errors, script errors, invalid resource paths, or new warnings from the components.

- [x] **Step 4: Recheck TestScene integrity**

Expected: length, timestamp, and SHA-256 exactly match the pre-validation snapshot.

- [x] **Step 5: Update plan checkboxes and report evidence**

## Implementation Results

- Focused TDD cycle: the new test first failed on the five absent component resources, then passed after implementation.
- Final focused result: `CombatFoundationComponentsTest: PASS`.
- Full headless suite: 21 passed, 0 failed.
- The full suite retained two pre-existing `AISwordAttack` warning emissions intentionally exercised by `WarriorSwordAttackTest`; no component-related warning or error was emitted.
- Project smoke run: exit code 0 with 0 warning/error lines.
- `Scenes/TestScene.tscn` remained byte-for-byte unchanged: SHA-256 `D1E28252C9C7E0D52DFEC06A302193B9531B75D8EF17AC91C617C7B668BA6509`.

Mark completed steps only after observing their command output. Report component paths, mounted source scenes, focused-test result, full-suite count, smoke result, and unchanged TestScene hash.
