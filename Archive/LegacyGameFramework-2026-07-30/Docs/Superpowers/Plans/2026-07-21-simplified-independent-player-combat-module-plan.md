# Simplified Independent Player Combat Module Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Replace PlayerBase's current multi-component weapon combat assembly with one independent PlayerCombatModule and one flat WeaponData Resource, while leaving the legacy Hero combat system untouched.

**Architecture:** PlayerBase becomes combat-free. A composed PlayerCombatTestCharacter inherits PlayerBase and attaches one PlayerCombatModule that owns equipment, input, combo playback, ShapeCast hit detection, lunge and local hit stop. Each concrete weapon uses one flat WeaponData that directly references its scene and external AnimationLibrary.

**Tech Stack:** Godot 4.7, GDScript, AnimationLibrary, ShapeCast3D, SceneTree headless tests, Godot MCP Pro.

## Global Constraints

- Do not modify, reference or delete the legacy Hero, MeleeAttackModule, MeleeHitDetector or Effects/Combat files.
- Do not add, remove or replace any unit instance in `res://Scenes/TestScene.tscn`.
- Preserve PlayerBase movement, dash, gravity, facing and targeting behavior.
- Use InputMap action `player_attack`; do not hardcode input events.
- Use English identifiers and detailed Simplified Chinese comments in new GDScript.
- Use one flat WeaponData per weapon; do not add Race, WeaponType, databases, entry Resources or nested custom Resources.
- The project is not a Git repository; verification evidence replaces commits.

---

### Task 1: Freeze Legacy Boundaries and Specify Flat Weapon Data

**Files:**
- Create: `WeaponCombatSystem/Tests/LegacyHeroIsolationTest.gd`
- Create: `WeaponCombatSystem/Tests/WeaponDataTest.gd`
- Create: `WeaponCombatSystem/WeaponData.gd`
- Create: `WeaponCombatSystem/Weapons/IronSword/IronSwordData.tres`
- Create: `WeaponCombatSystem/Weapons/IronSword/IronSword.tscn`
- Create: `WeaponCombatSystem/Weapons/IronSword/IronSwordVisual.tscn`
- Create: `WeaponCombatSystem/Weapons/IronSword/IronSwordAnimations.tres`

**Interfaces:**
- Produces:

```gdscript
class_name WeaponData
extends Resource

@export var display_name: String
@export var weapon_scene: PackedScene
@export var attack_animation_library: AnimationLibrary
@export var hitbox_size: Vector3
@export var hitbox_offset: Vector3
```

- [x] **Step 1: Write failing isolation and flat-data tests**

`LegacyHeroIsolationTest` records the approved SHA-256 values for all frozen legacy
files and TestScene, then rejects any new-system path inside those files.

`WeaponDataTest` requires the five flat fields, a scriptless IronSword scene, the
existing materials, `RESET`, three numbered attacks and animation method tracks
for hitbox/lunge.

- [x] **Step 2: Run tests and verify RED**

Run both tests from `res://WeaponCombatSystem/Tests/`.
Expected: missing new files and class.

- [x] **Step 3: Implement minimal flat weapon assets**

Create the five-field Resource, copy the IronSword visual without changing its
materials, and author the external library against the composed PlayerBase paths.

- [x] **Step 4: Run tests and verify GREEN**

Expected: `LegacyHeroIsolationTest: PASS` and `WeaponDataTest: PASS`.

### Task 2: Build One Self-Contained Combat Module

**Files:**
- Create: `WeaponCombatSystem/Tests/PlayerCombatModuleTest.gd`
- Create: `WeaponCombatSystem/Tests/PlayerCombatComboTest.gd`
- Create: `WeaponCombatSystem/Tests/PlayerCombatHitboxTest.gd`
- Create: `WeaponCombatSystem/PlayerCombatModule.gd`
- Create: `WeaponCombatSystem/PlayerCombatModule.tscn`

**Interfaces:**
- Produces:

```gdscript
func configure(
    owner_body: CharacterBody3D,
    body_root: Node3D,
    weapon_socket: Node3D
) -> bool
func equip_weapon(weapon_data: WeaponData) -> bool
func unequip_weapon() -> void
func request_attack() -> void
func cancel_attack() -> void
func is_attacking() -> bool
func get_equipped_weapon_data() -> WeaponData
func animation_open_hitbox() -> void
func animation_close_hitbox() -> void
func animation_request_lunge(distance: float, duration: float) -> void
```

- [x] **Step 1: Write failing module tests**

Require one scripted root, one AnimationPlayer, one ShapeCast3D and one debug
MeshInstance3D. Verify atomic equipment, runtime unequip/re-equip and missing-data
handling.

- [x] **Step 2: Run module test and verify RED**

Expected: missing scene and class.

- [x] **Step 3: Implement equipment and animation loading**

Validate WeaponData before replacing the current weapon. Load the library as
`weapon`, discover continuous `basic_attack_N` names and preserve the current
weapon on failure.

- [x] **Step 4: Run module test and verify GREEN**

Expected: `PlayerCombatModuleTest: PASS`.

- [x] **Step 5: Write and run combo test RED**

Verify one press, buffer expiration, three-hit limit, combo reset, hold continuation
and held full-combo restart.

- [x] **Step 6: Implement minimal combo state machine and verify GREEN**

Expected: `PlayerCombatComboTest: PASS`.

- [x] **Step 7: Write and run hitbox test RED**

Verify closed-window silence, enemy filtering, per-window deduplication, multiple
targets, lunge state and local hit stop.

- [x] **Step 8: Implement ShapeCast detection, lunge and hit stop**

Use only the module root script; ShapeCast3D and DebugHitbox have no scripts.

- [x] **Step 9: Run all three module tests GREEN**

Expected: all module tests print `PASS`.

### Task 3: Purify PlayerBase and Create Composition Scenes

**Files:**
- Create: `WeaponCombatSystem/Tests/PlayerBasePurityTest.gd`
- Create: `WeaponCombatSystem/Tests/PlayerCombatTestCharacterTest.gd`
- Modify: `UnitSystem/PlayerBase.tscn`
- Create: `WeaponCombatSystem/Authoring/PlayerCombatTestCharacter.tscn`
- Create: `WeaponCombatSystem/Authoring/IronSwordWorkbench.tscn`

**Interfaces:**
- Consumes: `PlayerCombatModule.tscn`, `IronSwordData.tres`, PlayerBase's
  `BodyRoot` and `WeaponSocket`.
- Produces: a combat-free PlayerBase and one no-binder-script composed character.

- [x] **Step 1: Write purity and composition tests RED**

Require PlayerBase to contain no WeaponCombatSystem reference or combat node.
Require the composed scene to inherit PlayerBase, attach exactly one module and
assign all typed node references plus starting weapon.

- [x] **Step 2: Remove combat assembly from PlayerBase**

Remove current attack controller, equipment component, animation controller,
database and weapon definition references. Preserve visual transforms and every
unit parameter.

- [x] **Step 3: Create test character and Workbench**

The test character adds one PlayerCombatModule. The Workbench instances it and
adds ground, light and camera only.

- [x] **Step 4: Run purity, composition and all UnitSystem tests**

Expected: every test prints `PASS`.

### Task 4: Remove Superseded Numbered Combat Implementation

**Files:**
- Delete: superseded numbered `WeaponCombatSystem/00-*` through `07-*`.
- Rewrite: `WeaponCombatSystem/README.md`
- Update: `Docs/WeaponCombatExpansionEvaluation.md`
- Update: `Docs/Superpowers/Plans/2026-07-21-simplified-independent-player-combat-module-plan.md`

- [x] **Step 1: Confirm the replacement test suite is GREEN**

No deletion occurs before Tasks 1-3 pass.

- [x] **Step 2: Delete only superseded current-system files**

Do not touch any legacy Hero or Effects/Combat file.

- [x] **Step 3: Write the concise final guide**

Document PlayerBase purity, module attachment, WeaponData creation, runtime
equipment, animation authoring, method-track hooks and manual TestScene addition.

- [x] **Step 4: Run path and isolation scans**

Require no database, WeaponType, Race mapping, numbered directory or old current
component reference in UnitSystem or the new WeaponCombatSystem.

### Task 5: Full Verification and MCP Inspection

- [x] **Step 1: Run all UnitSystem and new WeaponCombatSystem tests**

Expected: zero failures and no error output.

- [x] **Step 2: Run Godot 4.7 full editor import**

Expected: exit code `0`, no `ERROR`, `SCRIPT ERROR` or `WARNING`.

- [x] **Step 3: Verify frozen hashes**

Legacy Hero files and TestScene must match the hashes captured before Task 1.

- [x] **Step 4: Inspect with Godot MCP Pro**

Open `IronSwordWorkbench.tscn`, verify PlayerBase + PlayerCombatModule + IronSword,
then clear and read Output to confirm no new errors.

- [x] **Step 5: Provide manual TestScene instructions**

Tell the user to add `PlayerCombatTestCharacter.tscn` manually, identify the target
parent and suggest an initial position. Do not modify TestScene.

