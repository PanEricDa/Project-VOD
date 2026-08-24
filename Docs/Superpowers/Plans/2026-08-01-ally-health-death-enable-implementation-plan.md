# Ally Health and Death Enablement Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the inherited health bar, life state, and revive-oriented death policy explicit and regression-tested for every `AllyBase` descendant.

**Architecture:** `UnitBase` remains the single owner of health, `WorldHealthBar`, and `UnitState`; `AIUnitBase` remains responsible for cancelling AI actions on death. `AllyBase` only records its default starting health and non-removal death policy, so no duplicate components or parallel lifecycle logic are introduced.

**Tech Stack:** Godot 4.7, GDScript, headless SceneTree tests.

## Global Constraints

- Do not modify user unit instances in `TestScene.tscn` or `TestCombatRoom.tscn`.
- All visible Inspector configuration must include nearby Simplified Chinese descriptions in its owning script.
- Ally death keeps the unit for future `revive()`; it never uses the enemy removal/dissolve policy by default.

---

### Task 1: Prove the Ally source-scene contract

**Files:**
- Create: `UnitSystem/Tests/AllyStatusConfigurationTest.gd`

**Interfaces:**
- Consumes: `AllyBase.tscn`, `UnitBase.health_changed`, `WorldHealthBar`, `UnitStateComponent`.
- Produces: a regression test for default full health, health-bar damage display, and revive-oriented death mode.

- [x] **Step 1: Write the failing test**

Load `AllyBase.tscn` and inspect its packed-scene overrides. Assert that the root explicitly sets `maximum_health = 100.0` and `starting_health_percentage = 100.0`, and its inherited `UnitState` explicitly sets `death_mode = KEEP_FOR_REVIVE`.

- [x] **Step 2: Run the test to verify it fails**

Run:

```powershell
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' --headless --path 'G:\Godot\SipSip' --script 'res://UnitSystem/Tests/AllyStatusConfigurationTest.gd'
```

Expected: failure because the Ally source scene does not yet explicitly declare those inherited defaults.

### Task 2: Make Ally defaults explicit without duplicating components

**Files:**
- Modify: `UnitSystem/AI/Ally/AllyBase.tscn`
- Modify: `UnitSystem/Tests/AllyStatusConfigurationTest.gd`

**Interfaces:**
- Consumes: inherited `UnitBase` child paths `UnitState` and `WorldUIRoot/WorldHealthBar`.
- Produces: every Ally descendant starts at full health, owns the inherited UI, and remains after death for explicit revival.

- [x] **Step 1: Add only inherited-scene overrides**

Set the Ally root's inherited health defaults and the inherited `UnitState.death_mode` to `KEEP_FOR_REVIVE`. Do not add a second health bar, health script, or death component.

- [x] **Step 2: Extend the runtime assertion**

Instantiate `AllyBase`; apply real damage and verify its inherited `WorldHealthBar` becomes visible. Apply lethal damage, verify the Ally remains valid and dead, then call `revive()` and verify it is targetable again.

- [x] **Step 3: Run the test to verify it passes**

Run the Task 1 command. Expected: `AllyStatusConfigurationTest: PASS` with no script errors.

### Task 3: Regression verification and documentation record

**Files:**
- Modify: `Docs\Superpowers\Plans\2026-08-01-ally-health-death-enable-implementation-plan.md`

- [x] **Step 1: Run focused and lifecycle tests**

Run `AllyStatusConfigurationTest.gd`, `WorldHealthBarTest.gd`, `UnitDeathLifecycleTest.gd`, and a Godot 4.7 headless editor scan.

- [x] **Step 2: Record results**

Mark this plan complete only after all commands return exit code 0. Expected test-only warnings, if any, must be identified separately from errors.

**Result (2026-08-01):** `AllyStatusConfigurationTest` passed after the source-scene overrides were added. The focused health-bar and death-lifecycle suites, plus the editor scan, were run successfully; any warnings shown by tests are intentional coverage of guarded branches and contain no script errors.
