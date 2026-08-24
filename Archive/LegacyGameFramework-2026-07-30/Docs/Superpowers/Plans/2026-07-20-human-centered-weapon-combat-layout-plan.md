# Human-Centered Weapon Combat Layout Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reorganize WeaponCombatSystem into a numbered, designer-readable workflow with one typed Setup entry while preserving IronSword combat behavior.

**Architecture:** Keep the existing `Race + WeaponType → AnimationLibrary` runtime data flow. Move authoring assets, runtime scripts and tests into numbered ownership folders, then add an authoring-only `WeaponCombatSetup` Resource and canonical README.

**Tech Stack:** Godot 4.7, GDScript, `.tres` Resources, `.tscn` scenes, headless SceneTree tests, Godot MCP Pro.

## Global Constraints

- Do not modify or add unit instances in `res://Scenes/TestScene.tscn`.
- Preserve the IronSword material, visual scene and three-hit attack timing.
- Preserve input buffer, combo reset, hold chaining and held-combo restart behavior.
- New Race and WeaponType values remain developer-owned enums.
- Designer-facing fields use typed Resource references.
- The project is not a Git repository; do not create commits.

---

### Task 1: Add the Human-Readable Layout Contract

**Files:**
- Create: `WeaponCombatSystem/07-Tests/WeaponCombatAuthoringLayoutTest.gd`

**Interfaces:**
- Consumes: the approved numbered path contract.
- Produces: a failing test that requires every new path, the Setup entry and the guide.

- [x] **Step 1: Write the failing layout test**

The test must assert:

```gdscript
const SETUP_PATH := "res://WeaponCombatSystem/00-StartHere/WeaponCombatSetup.tres"
const GUIDE_PATH := "res://WeaponCombatSystem/00-StartHere/README.md"
const DATABASE_PATH := "res://WeaponCombatSystem/05-Registry/WeaponAnimationDatabase.tres"

assert(ResourceLoader.exists(SETUP_PATH))
assert(ResourceLoader.exists(DATABASE_PATH))
assert(FileAccess.file_exists(GUIDE_PATH))
```

It must also require the numbered IronSword definition, scene, animation library,
workbench, runtime scripts and all seven migrated legacy tests.

- [x] **Step 2: Run the test and verify RED**

Run:

```powershell
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' `
  --headless --path 'G:\Godot\SipSip' `
  --script res://WeaponCombatSystem/07-Tests/WeaponCombatAuthoringLayoutTest.gd
```

Expected: FAIL because the new numbered paths and Setup resource do not exist.

### Task 2: Migrate the Existing Subsystem Atomically

**Files:**
- Move: `WeaponCombatSystem/00-Weapons/IronSword/IronSwordDefinition.tres` → `WeaponCombatSystem/01-WeaponDefinitions/IronSwordDefinition.tres`
- Move: `WeaponCombatSystem/00-Weapons/IronSword/*Scene*` → `WeaponCombatSystem/02-WeaponScenes/IronSword/`
- Move: `UnitSystem/UnitProfiles/PlayerBase/Animations/PlayerSwordAnimationLibrary.tres` → `WeaponCombatSystem/03-AnimationLibraries/PlayerBase/PlayerBaseSwordAnimationLibrary.tres`
- Move: `WeaponCombatSystem/05-Authoring/SwordAnimationWorkbench.tscn` → `WeaponCombatSystem/04-AnimationWorkbenches/PlayerBase/PlayerBaseSwordWorkbench.tscn`
- Move: `WeaponCombatSystem/02-Core/WeaponAnimationDatabase.tres` → `WeaponCombatSystem/05-Registry/WeaponAnimationDatabase.tres`
- Move: `WeaponCombatSystem/02-Core/*.gd` → `WeaponCombatSystem/06-Runtime/Core/`
- Move: `WeaponCombatSystem/03-Components/*.gd` → `WeaponCombatSystem/06-Runtime/Components/`
- Move: `WeaponCombatSystem/04-Tests/*` → `WeaponCombatSystem/07-Tests/`
- Modify: `UnitSystem/PlayerBase.tscn`
- Modify: all moved `.tscn`, `.tres` and `.gd` references.

**Interfaces:**
- Consumes: existing class names and UIDs.
- Produces: identical runtime classes and resources at numbered paths.

- [x] **Step 1: Move scripts with their `.uid` files**

Preserve class names and script UIDs while changing only filesystem ownership.

- [x] **Step 2: Move assets and update all internal paths**

Update every `ext_resource`, `preload`, constant and test path to the new location.
No compatibility duplicates remain under old paths.

- [x] **Step 3: Run the seven migrated combat tests**

Expected: all seven existing tests print `PASS` from their new `07-Tests` paths.

### Task 3: Add the Typed Setup Entry and Canonical Guide

**Files:**
- Create: `WeaponCombatSystem/06-Runtime/Authoring/WeaponCombatSetup.gd`
- Create: `WeaponCombatSystem/00-StartHere/WeaponCombatSetup.tres`
- Create: `WeaponCombatSystem/00-StartHere/README.md`
- Modify: `WeaponCombatSystem/07-Tests/WeaponCombatAuthoringLayoutTest.gd`

**Interfaces:**
- Produces:

```gdscript
class_name WeaponCombatSetup
extends Resource

@export var animation_database: WeaponAnimationDatabase
@export var default_unit_profile: UnitProfile
@export var example_weapon_definition: WeaponDefinition
@export var animation_workbench_scene: PackedScene
```

- [x] **Step 1: Keep the layout test RED for missing typed content**

The test loads Setup and asserts all four typed references are non-null and point
to the intended PlayerBase/IronSword example resources.

- [x] **Step 2: Implement the minimal Setup Resource**

Create the script and `.tres` with references to the migrated database,
`PlayerBaseProfile.tres`, `IronSwordDefinition.tres` and
`PlayerBaseSwordWorkbench.tscn`.

- [x] **Step 3: Write the system guide**

Document the numbered folders, designer workflow, developer enum boundary, naming
rules, Setup navigation, runtime data flow and diagnostic order.

- [x] **Step 4: Run the layout test and verify GREEN**

Expected: `WeaponCombatAuthoringLayoutTest: PASS`.

### Task 4: Verify Behavior, Performance and Migration Safety

**Files:**
- Update: `Docs/WeaponCombatExpansionEvaluation.md`
- Update: `Docs/Superpowers/Plans/2026-07-20-human-centered-weapon-combat-layout-plan.md`

- [x] **Step 1: Run all UnitSystem and numbered WeaponCombatSystem tests**

Expected: 8 UnitSystem tests and 8 WeaponCombatSystem tests pass.

- [x] **Step 2: Run a complete Godot 4.7 editor import**

Run:

```powershell
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' `
  --headless --path 'G:\Godot\SipSip' --editor --import --quit
```

Expected: exit code `0`, no `ERROR`, `SCRIPT ERROR` or `WARNING`.

- [x] **Step 3: Verify migration boundaries**

Assert old WeaponCombatSystem directories no longer contain project files,
the database benchmark remains equip-time only, and `Scenes/TestScene.tscn`
retains its baseline SHA-256:

```text
ED61E6208F63EAB5FF28EEA2D6142BD321A13B5A077D87E28DBC4DBFA0C723A1
```

- [x] **Step 4: Reload with Godot MCP Pro**

Open `PlayerBaseSwordWorkbench.tscn`, inspect its scene tree and verify the current
Output panel receives no new errors.
