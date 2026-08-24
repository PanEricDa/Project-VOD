# Pack Target Handoff Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Pack members adopt other members' active targets only after normal local target resolution has no result.

**Architecture:** `AITargetingComponent` retains ownership of the sole locked target and gains a non-exported fallback `Callable`. `EncounterController` injects this callback per registered enemy, resolves valid targets from the same Pack, and triggers refreshes when a Pack first engages.

**Tech Stack:** Godot 4.7, GDScript, SceneTree headless tests.

## Global Constraints

- Do not add or modify any unit instance in `Scenes/TestScene.tscn`.
- New public interfaces and configurable fields require adjacent Simplified Chinese documentation.
- Do not create a new external Resource for this runtime-only relationship.

---

### Task 1: Define fallback targeting behavior with tests

**Files:**
- Modify: `UnitSystem/Tests/EncounterControllerTest.gd`

**Interfaces:**
- Consumes: `EnemyBase.get_targeting_component() -> AITargetingComponent`
- Produces: tests for Pack activation, Pack target handoff, local-target priority, and lifecycle cleanup.

- [ ] **Step 1: Write failing tests**

Add a test that creates two Pack enemies plus two hostile test units. Give the first enemy a target outside the second enemy's local perception, then request target refresh on the second enemy and assert it locks the first enemy's valid target. Add a nearby valid local target and assert the second enemy selects that local target instead. Exit the source enemy from combat, refresh again, and assert no Pack fallback target is supplied.

- [ ] **Step 2: Run the focused test and verify it fails**

Run:

```powershell
& 'G:\Godot\Godot_v4.7.1-stable_win64_console.exe' --headless --path 'G:\Godot\SipSip' --script res://UnitSystem/Tests/EncounterControllerTest.gd
```

Expected: FAIL because Pack fallback still uses the permanent assist override and has no local-first resolver.

### Task 2: Add local-first fallback resolution

**Files:**
- Modify: `UnitSystem/Components/Targeting/AI/AITargetingComponent.gd`
- Modify: `UnitSystem/AI/Enemy/EnemyBase.gd`
- Modify: `UnitSystem/Encounter/EncounterController.gd`

**Interfaces:**
- Produces: `AITargetingComponent.set_fallback_target_resolver(resolver: Callable)`, `clear_fallback_target_resolver()`, and `EnemyBase.refresh_targeting()`.
- Consumes: `EncounterController` Pack records and `EnemyBase` targeting/combat state.

- [ ] **Step 1: Implement component fallback after local selection fails**

Remove the permanent `_pack_assist_target` field and methods. Resolve valid local retention and policy candidates before calling the fallback `Callable`. Accept an external fallback target only when it remains valid, targetable, and hostile to the owner.

- [ ] **Step 2: Implement controller resolver and lifecycle injection**

During Pack registration, inject one callable per enemy bound to its Pack. Resolve targets from other living in-combat members, select the closest valid target to the requester, and return `null` when no qualifying provider remains. On first combat state entry, refresh each living member instead of setting a persistent target. Clear resolver callables at Pack reset and clear.

- [ ] **Step 3: Run focused test and verify it passes**

Run the Task 1 command. Expected: `EncounterControllerTest: PASS`.

### Task 3: Regression verification and documentation review

**Files:**
- Modify: `Docs/Superpowers/Specs/2026-08-04-pack-target-handoff-design.md` only if verification discovers a design mismatch.

- [ ] **Step 1: Run targeting and enemy behavior regressions**

```powershell
& 'G:\Godot\Godot_v4.7.1-stable_win64_console.exe' --headless --path 'G:\Godot\SipSip' --script res://UnitSystem/Tests/AITargetingComponentTest.gd
& 'G:\Godot\Godot_v4.7.1-stable_win64_console.exe' --headless --path 'G:\Godot\SipSip' --script res://UnitSystem/Tests/EnemyBehaviorStateMachineTest.gd
& 'G:\Godot\Godot_v4.7.1-stable_win64_console.exe' --headless --editor --quit --path 'G:\Godot\SipSip'
```

- [ ] **Step 2: Self-review**

Confirm the final code has no permanent Pack-specific target field, no cross-Pack scanning, and no new Inspector configuration. Confirm the spec and plan contain no unresolved placeholders.
