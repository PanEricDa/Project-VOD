# Ranged Attack Movement and Combat Boundary Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make AI basic-attack movement data-driven per weapon and keep combat inside a player-centered boundary.

**Architecture:** `WeaponData` provides an attack movement multiplier. `AICombatSystem` exposes the equipped value and `AllyBehaviorStateMachine` applies it only during active basic attacks; the existing orbit logic otherwise remains unchanged. The existing forced disengagement rule becomes a two-sided distance check using one renamed parameter.

**Tech Stack:** Godot 4.7, GDScript, existing headless contract tests.

## Global Constraints

- Every exported field and public method has nearby Simplified Chinese documentation.
- Do not add a parallel movement or return system.
- Do not modify TestScene unit instances.

---

### Task 1: Weapon attack-motion data and consumer

**Files:**
- Modify: `Item/Weapon/WeaponData.gd`
- Modify: `Item/Weapon/Bow/BowData.tres`
- Modify: `UnitSystem/Components/Combat/AI/AICombatSystem.gd`
- Modify: `UnitSystem/Components/Behavior/AllyBehaviorStateMachine.gd`
- Modify: `UnitSystem/Tests/WeaponDataInheritanceTest.gd`

- [x] **Step 1: Write a failing test**

Assert WeaponData exposes `attack_movement_speed_multiplier` and Bow resolves it as `0.0`.

- [x] **Step 2: Run the test and verify it fails**

Run `WeaponDataInheritanceTest.gd`; expected failure: the field does not exist.

- [x] **Step 3: Implement the data flow**

Add the documented default field, configure Bow to zero, expose a safe getter from AICombatSystem, and use it only while `COMBAT_ATTACK` has an active attack.

- [x] **Step 4: Run the test and verify it passes**

Run `WeaponDataInheritanceTest.gd`; expected `PASS`.

### Task 2: Bidirectional combat boundary

**Files:**
- Modify: `UnitSystem/Components/Behavior/AllyBehaviorStateMachine.gd`
- Modify: `UnitSystem/Tests/AllyBehaviorStateMachineTest.gd`

- [x] **Step 1: Write a failing test**

Place an ally beyond the player combat boundary while its target remains near the player; assert `_should_force_disengage()` returns true.

- [x] **Step 2: Run the test and verify it fails**

Run `AllyBehaviorStateMachineTest.gd`; expected failure because only player-to-target distance is currently checked.

- [x] **Step 3: Implement the single shared boundary**

Rename the Inspector field and return true when either target-to-player or owner-to-player horizontal distance exceeds it.

- [x] **Step 4: Run focused and integration validation**

Run `AllyBehaviorStateMachineTest.gd`, `WeaponDataInheritanceTest.gd`, and `BasicAttackDamageIntegrationTest.gd`, then run a headless editor scan. All must pass with no new warnings.
