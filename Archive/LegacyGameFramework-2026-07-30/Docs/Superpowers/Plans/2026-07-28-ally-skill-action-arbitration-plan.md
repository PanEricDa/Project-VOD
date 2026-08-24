# Ally Skill Action Arbitration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Allow an Ally AI unit to automatically cast equipped skills, gate casting through a public permission interface, and select skills or basic attacks through one shared action cooldown.

**Architecture:** `AllyBehaviorStateMachine` remains the only action arbiter. It receives optional `SkillHost`, owns the AI action GCD, and chooses between its existing `AICombatSystem` basic attack executor and the independent `SkillHost` executor. SkillHost remains reusable and does not depend on Ally classes; Caster chooses its behavior by root-scene policy fields.

**Tech Stack:** Godot 4.7, GDScript, PackedScene inheritance, Godot headless SceneTree tests.

## Global Constraints

- Do not modify `res://Scenes/TestScene.tscn`.
- `SkillHost/SkillSocket` direct children are the only equipped skills.
- Existing basic-only Ally units must preserve their behavior by default.
- Skills and basic attacks share one AI action GCD; per-skill cooldown remains independent.
- Do not add damage, health, target-selection, or new skill visual behavior.

---

### Task 1: SkillHost Casting Permission and External GCD Gate

**Files:**
- Modify: `SkillSystem/11-Tests/SkillHostComponentTest.gd`
- Modify: `SkillSystem/01-Core/SkillHostComponent.gd`

**Interfaces:**
- `set_skill_casting_enabled(enabled: bool) -> void`
- `is_skill_casting_enabled() -> bool`
- `set_external_global_cooldown_blocked(blocked: bool) -> void`
- `set_use_external_global_cooldown(active: bool) -> void`
- `get_preferred_cast_range() -> float`

- [ ] Write tests that disabling casting cancels an active request and rejects new requests, while an external GCD block holds a queued skill without cancelling it.
- [ ] Run `SkillHostComponentTest.gd` and observe the missing-interface failure.
- [ ] Implement the permission/gate fields; reject requests while casting is disabled; include the external gate when deciding whether a queued skill may begin; avoid internal Host GCD when externally controlled.
- [ ] Verify the SkillHost regression test passes.

### Task 2: Combat Executor External-GCD Mode

**Files:**
- Modify: `UnitSystem/Tests/AICombatSystemTest.gd`
- Modify: `UnitSystem/Components/Combat/AI/AICombatSystem.gd`

**Interfaces:**
- `set_use_external_global_cooldown(active: bool) -> void`
- External mode removes only the executor's local cooldown start/check; callers remain responsible for action permission.

- [ ] Add a failing test that an externally controlled combat system does not start its own GCD after accepting a basic attack.
- [ ] Implement the explicit mode with default `false`, preserving existing standalone combat behavior.
- [ ] Run the AI combat test and verify existing internal-GCD behavior remains valid outside external mode.

### Task 3: Ally Action Policy and Shared GCD

**Files:**
- Modify: `UnitSystem/Tests/AllyBehaviorStateMachineTest.gd`
- Modify: `UnitSystem/Components/Behavior/AllyBehaviorStateMachine.gd`
- Modify: `UnitSystem/AI/Ally/AllyBase2.gd`

**Interfaces:**
- Policies: `BASIC_ONLY`, `SKILL_PRIORITY_THEN_BASIC`, `SKILL_ONLY_WITH_BASIC_WHEN_DISABLED`.
- Root fields: `combat_action_policy`, `automatic_skill_cast_enabled`, `shared_action_cooldown_duration`.
- Runtime methods: `set_automatic_skill_cast_enabled(enabled: bool)` and `is_automatic_skill_cast_enabled() -> bool`.

- [ ] Add failing behavior tests for skill-only Caster behavior, disabled-skill basic fallback, and a skill-started shared GCD blocking a basic attack.
- [ ] Extend StateMachine `configure()` with an optional SkillHost, connect skill approach/facing/movement-lock/cast-start signals, and manage one shared cooldown timer.
- [ ] Make basic attack selection conditional on the policy and skill permission; when a skill is active, use its cast range for approach and suppress basic attacks.
- [ ] In AllyBase2, inject inherited `SkillHost` into the state machine and forward the three root configuration fields.
- [ ] Verify the behavior tests pass.

### Task 4: Caster Assembly

**Files:**
- Modify: `UnitSystem/AI/Ally/Units/Caster.tscn`
- Modify: `UnitSystem/Tests/UnitBaseSkillHostAssemblyTest.gd`

- [ ] Add a failing assembly check that Caster's `FireboltSkill` is a direct `SkillHost/SkillSocket` child and Caster uses skill-only fallback policy.
- [ ] Move the inherited-scene child from `SkillHost` to `SkillHost/SkillSocket`; configure Caster for `SKILL_ONLY_WITH_BASIC_WHEN_DISABLED`, automatic casting enabled, and a 1.0-second shared GCD.
- [ ] Run the assembly test, behavior/host/combat tests, and a Godot editor scan.
