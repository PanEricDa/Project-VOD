# Character Animation and Fixed NodePath Simplification Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Merge the character animation controller and its internal AnimationPlayer into one node, then remove five Inspector NodePaths that only point at fixed framework nodes.

**Architecture:** `CharacterAnimationController` becomes an `AnimationPlayer` and directly owns runtime weapon animation libraries. `WeaponBase` and `PlayerAttackController` keep their existing public behavior while resolving contractual child or sibling nodes through internal constants.

**Tech Stack:** Godot 4.7, GDScript, `.tscn` inherited scenes, `AnimationPlayer`, headless SceneTree tests.

## Global Constraints

- Do not modify `res://Scenes/TestScene.tscn` or any unit instance inside it.
- Preserve player movement, targeting, weapon equipment, three-step combo, animation signals and runtime weapon switching.
- Keep `WeaponEquipmentComponent` and `FormationComponent` Inspector NodePaths.
- Keep all identifiers in English and all new explanatory comments in Simplified Chinese.
- The project is not a Git repository; use test results and file inspection checkpoints instead of commits.

---

### Task 1: Convert CharacterAnimationController into the AnimationPlayer

**Files:**
- Modify: `WeaponCombatSystem/04-Tests/WeaponCombatComponentsTest.gd`
- Modify: `WeaponCombatSystem/04-Tests/PlayerWeaponExampleAssemblyTest.gd`
- Modify: `WeaponCombatSystem/03-Components/CharacterAnimationController.gd`
- Modify: `UnitSystem/PlayerBase.tscn`

**Interfaces:**
- Consumes: weapon `AnimationLibrary` values from `WeaponBase`.
- Produces: the existing `load_weapon_animations()`, `clear_weapon_animations()`, `play_weapon_animation()`, `stop_action()`, `is_action_playing()` and action signals on one `AnimationPlayer` node.

- [x] **Step 1: Write failing scene-contract tests**

Add assertions that `CharacterAnimationController` is an `AnimationPlayer`, has no `CharacterAnimationPlayer` child, has no `animation_player_path` property and resolves `root_node` to `CharacterActionRig`.

- [x] **Step 2: Run tests and verify the old two-node scene fails**

Run:

```powershell
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' --headless --path 'G:\Godot\SipSip' --script 'res://WeaponCombatSystem/04-Tests/PlayerWeaponExampleAssemblyTest.gd'
```

Expected: FAIL because the controller is a `Node` with a child AnimationPlayer.

- [x] **Step 3: Implement the single-node controller**

Change the script base:

```gdscript
class_name CharacterAnimationController
extends AnimationPlayer
```

Remove `animation_player_path`, `_animation_player` and `configure(AnimationPlayer)`. Replace delegated AnimationPlayer calls with calls on `self`, connect `animation_finished` in `_ready()`, and resolve animation targets through `get_node_or_null(root_node)`.

Replace the two scene nodes with:

```text
[node name="CharacterAnimationController" type="AnimationPlayer" parent="Visual/CharacterActionRig"]
root_node = NodePath("..")
script = ExtResource("5_animation_controller")
```

- [x] **Step 4: Update test construction and verify green**

Tests must instantiate `CharacterAnimationController` directly, set `root_node = ^".."`, and stop calling the removed `configure(AnimationPlayer)`.

Run the component, assembly and combo tests. Expected: PASS.

### Task 2: Remove fixed WeaponBase and PlayerAttackController NodePaths

**Files:**
- Modify: `WeaponCombatSystem/04-Tests/WeaponSceneContractsTest.gd`
- Modify: `WeaponCombatSystem/04-Tests/WeaponCombatComponentsTest.gd`
- Modify: `WeaponCombatSystem/02-Core/WeaponBase.gd`
- Modify: `WeaponCombatSystem/03-Components/PlayerAttackController.gd`
- Modify: `UnitSystem/PlayerBase.tscn`

**Interfaces:**
- Consumes: fixed weapon child names `VisualSlot`, `SkillSocket`, `Animations`; fixed PlayerCombatSystem sibling and character rig paths.
- Produces: unchanged WeaponBase getters and unchanged `PlayerAttackController.configure()` runtime injection interface.

- [x] **Step 1: Write failing property-contract tests**

Assert the absence of:

```text
WeaponBase.runtime_visual_root_path
WeaponBase.skill_socket_path
WeaponBase.animations_player_path
PlayerAttackController.equipment_component_path
PlayerAttackController.animation_controller_path
```

- [x] **Step 2: Run tests and verify the exported properties fail**

Run `WeaponSceneContractsTest.gd` and `WeaponCombatComponentsTest.gd`.
Expected: FAIL because the five exported properties still exist.

- [x] **Step 3: Replace WeaponBase exports with constants**

Use:

```gdscript
const VISUAL_SLOT_PATH: NodePath = ^"VisualSlot"
const SKILL_SOCKET_PATH: NodePath = ^"SkillSocket"
const ANIMATIONS_PATH: NodePath = ^"Animations"
```

Keep the existing getter method names and return types.

- [x] **Step 4: Replace PlayerAttackController exports with constants**

Use:

```gdscript
const EQUIPMENT_COMPONENT_PATH: NodePath = ^"../WeaponEquipmentComponent"
const ANIMATION_CONTROLLER_PATH: NodePath = \
	^"../../Visual/CharacterActionRig/CharacterAnimationController"
```

Make `_ready()` call the existing `configure()` with these resolved nodes. Remove the two serialized properties from `PlayerBase.tscn`.

- [x] **Step 5: Run targeted tests and verify green**

Run `WeaponSceneContractsTest.gd`, `WeaponCombatComponentsTest.gd`,
`PlayerWeaponExampleAssemblyTest.gd` and `PlayerWeaponComboTest.gd`.
Expected: all PASS.

### Task 3: Full verification and editor refresh

**Files:**
- Verify: `WeaponCombatSystem/03-Components/CharacterAnimationController.gd`
- Verify: `WeaponCombatSystem/02-Core/WeaponBase.gd`
- Verify: `WeaponCombatSystem/03-Components/PlayerAttackController.gd`
- Verify: `UnitSystem/PlayerBase.tscn`
- Do not modify: `Scenes/TestScene.tscn`

**Interfaces:**
- Consumes: completed single-node controller and fixed internal paths.
- Produces: verified Godot 4.7 project state with no new Output warning.

- [x] **Step 1: Run all UnitSystem and WeaponCombatSystem headless tests**

Execute every `.gd` SceneTree test in `UnitSystem/Tests` and
`WeaponCombatSystem/04-Tests`. Expected: all tests exit `0`.

- [x] **Step 2: Run a Godot editor filesystem scan**

Run Godot 4.7 with `--headless --editor --quit-after 3`. Expected: project scan completes without script parse errors.

- [x] **Step 3: Refresh the connected editor and inspect Output**

Use Godot MCP Pro to rescan the filesystem, reload `PlayerBase.tscn`, and ensure no new project error or warning is added. Clear Output after verification.

- [x] **Step 4: Verify TestScene remains untouched**

Compare the `Scenes/TestScene.tscn` last-write time recorded before and after implementation. Expected: unchanged.
