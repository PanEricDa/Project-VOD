# Flat Weapon Animation Database Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace weapon-owned proxy animations with a flat Race + WeaponType animation database for PlayerBase and IronSword.

**Architecture:** UnitProfile provides Race, WeaponDefinition provides WeaponType, and WeaponAnimationDatabase resolves the external AnimationLibrary. Equipment performs atomic validation and loading; weapon scenes contain only visual/skill structure.

**Tech Stack:** Godot 4.7, GDScript, Resource `.tres`, SceneTree headless tests.

## Global Constraints

- Do not modify or add units to `Scenes/TestScene.tscn`.
- Only configure `PLAYER_BASE + SWORD + IronSword`.
- Preserve PlayerAttackController input buffer, combo reset and hold-to-chain behavior.
- All new identifiers use English and new code comments use detailed Simplified Chinese.
- The project is not a Git repository; verification output replaces commits.

---

### Task 1: Define the flat Resource contracts

**Files:**
- Create: `UnitSystem/UnitProfiles/UnitProfile.gd`
- Create: `UnitSystem/UnitProfiles/PlayerBase/PlayerBaseProfile.tres`
- Create: `WeaponCombatSystem/02-Core/WeaponAnimationEntry.gd`
- Create: `WeaponCombatSystem/02-Core/WeaponAnimationDatabase.gd`
- Create: `WeaponCombatSystem/02-Core/WeaponAnimationDatabase.tres`
- Modify: `UnitSystem/00_UnitBase.gd`
- Modify: `WeaponCombatSystem/02-Core/WeaponDefinition.gd`
- Test: `WeaponCombatSystem/04-Tests/WeaponAnimationDatabaseTest.gd`

- [x] Wrote failing tests for typed Race, WeaponType, exact lookup, missing rows and duplicate rows.
- [x] Ran the database test and confirmed the Resource types were missing.
- [x] Implemented the minimal Resource scripts and PlayerBase profile.
- [x] Ran the database test and confirmed it passes.

### Task 2: Extract the Player sword AnimationLibrary

**Files:**
- Create: `UnitSystem/UnitProfiles/PlayerBase/Animations/PlayerSwordAnimationLibrary.tres`
- Modify: `WeaponCombatSystem/02-Core/WeaponAnimationDatabase.tres`
- Modify: `WeaponCombatSystem/00-Weapons/IronSword/IronSwordDefinition.tres`
- Modify: `UnitSystem/PlayerBase.tscn`
- Test: `WeaponCombatSystem/04-Tests/IronSwordExampleTest.gd`

- [x] Updated the test to require one `PLAYER_BASE + SWORD` row and direct BodyRoot/WeaponSocket tracks.
- [x] Ran the test and confirmed failure against the proxy animation assets.
- [x] Migrated RESET and all three attacks to the external Library.
- [x] Restored the real PlayerBase WeaponSocket default transform.
- [x] Ran the test and confirmed it passes.

### Task 3: Simplify the weapon scene

**Files:**
- Modify: `WeaponCombatSystem/02-Core/WeaponBase.gd`
- Replace: `WeaponCombatSystem/00-Weapons/IronSword/IronSword.tscn`
- Delete: `WeaponCombatSystem/01-WeaponTypes/Sword/SwordBase.tscn`
- Test: `WeaponCombatSystem/04-Tests/WeaponSceneContractsTest.gd`

- [x] Updated the contract test to require only VisualRoot and SkillSocket responsibilities.
- [x] Ran the test and confirmed failure against the animation-owning WeaponBase.
- [x] Simplified WeaponBase and rebuilt IronSword as a direct WeaponBase scene.
- [x] Removed SwordBase and its RefCharacter cycle.
- [x] Ran the contract test and confirmed it passes.

### Task 4: Rewire equipment and animation playback

**Files:**
- Modify: `WeaponCombatSystem/03-Components/CharacterAnimationController.gd`
- Modify: `WeaponCombatSystem/03-Components/WeaponEquipmentComponent.gd`
- Modify: `WeaponCombatSystem/03-Components/PlayerAttackController.gd`
- Modify: `UnitSystem/PlayerBase.tscn`
- Test: `WeaponCombatSystem/04-Tests/WeaponCombatComponentsTest.gd`
- Test: `WeaponCombatSystem/04-Tests/PlayerWeaponComboTest.gd`

- [x] Updated tests for database injection, atomic equipment and controller-owned combo discovery.
- [x] Ran both tests and confirmed failure against the old source-remapping pipeline.
- [x] Implemented direct Library validation/loading and database resolution.
- [x] Moved combo discovery to CharacterAnimationController.
- [x] Ran both tests and confirmed they pass, including input buffer and held looping.

### Task 5: Add the animation Workbench

**Files:**
- Create: `WeaponCombatSystem/05-Authoring/SwordAnimationWorkbench.tscn`
- Modify: `WeaponCombatSystem/04-Tests/WeaponAuthoringSceneTest.gd`

- [x] Updated the authoring test to require a real PlayerBase instance, IronSword preview and external Library.
- [x] Ran the test and confirmed the Workbench was missing.
- [x] Created the Workbench without references from runtime assets.
- [x] Ran the authoring test and confirmed it passes.

### Task 6: Performance and expansion verification

**Files:**
- Modify: `WeaponCombatSystem/04-Tests/WeaponAnimationDatabaseTest.gd`
- Create: `Docs/WeaponCombatExpansionEvaluation.md`

- [x] Benchmarked repeated worst-position table lookup and printed total/average microseconds.
- [x] Verified lookup is called only during equip and never from `_process` or `_physics_process`.
- [x] Documented exact files/configuration required for one new Race and one new WeaponType.
- [x] Run all UnitSystem and WeaponCombatSystem tests.
- [x] Run a Godot 4.7 headless editor scan and MCP resource load.
- [x] Confirm `Scenes/TestScene.tscn` remains unchanged.
