# Nearest Valid Skill Target Selector Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a typed, reusable nearest-valid-target selector and configure HolyLight to find the nearest other friendly target in cast range.

**Architecture:** Snapshot Definition targeting rules into `IndependentSkillContext`, centralize candidate validation in `IndependentSkillTargetSelectorBase`, and let both autonomous selection and `SkillBase` final validation use that contract. Keep discovery local to the selector and defer auto-request scheduling and combatant registration.

**Tech Stack:** Godot 4.7, GDScript, typed Resource exports, headless SceneTree tests.

## Global Constraints

- Do not modify `res://Scenes/TestScene.tscn`.
- All identifiers are English and new implementation comments are detailed Simplified Chinese.
- Resource strategy slots exposed by `SkillDefinition` must use their corresponding base Resource types.
- HolyLight continues to use `target_relation = FRIENDLY` and excludes its caster through selector policy.

---

### Task 1: Typed strategy slots and targeting context

**Files:**
- Modify: `SkillSystem/Core/SkillDefinition.gd`
- Modify: `SkillSystem/Core/SkillContext.gd`
- Test: `SkillSystem/Tests/SkillStrategyContractTest.gd`

**Interfaces:**
- Produces: typed Definition strategy properties and copied targeting snapshot fields on `IndependentSkillContext`.

- [ ] Add a failing contract test that checks the target selector property hint references `IndependentSkillTargetSelectorBase` and that duplicated contexts preserve targeting fields.
- [ ] Run `SkillStrategyContractTest.gd` and confirm the new assertions fail for missing type/snapshot behavior.
- [ ] Type all Definition strategy exports with their matching abstract Resource classes and add targeting snapshot fields to `SkillContext`.
- [ ] Run the contract test and confirm this task passes.

### Task 2: Central validation and nearest selection

**Files:**
- Create: `SkillSystem/Targeting/NearestValidTargetSelector.gd`
- Modify: `SkillSystem/Targeting/SkillTargetSelectorBase.gd`
- Modify: `SkillSystem/Core/SkillBase.gd`
- Test: `SkillSystem/Tests/NearestValidTargetSelectorTest.gd`

**Interfaces:**
- Produces: `is_candidate_valid(context, candidate, include_range)` and nearest-target `resolve_target(context)` behavior.
- Consumes: targeting snapshots created in Task 1.

- [ ] Add a failing SceneTree test for nearest friendly selection, caster exclusion, hostile filtering, targetable filtering, horizontal range, and no-candidate failure.
- [ ] Run the new test and confirm it fails because `NearestValidTargetSelector.gd` does not exist.
- [ ] Implement centralized validation and the minimal recursive scene discovery needed by the selector.
- [ ] Make `SkillBase` populate targeting snapshots and use the selector base validation for final request/cast checks.
- [ ] Run the selector, strategy, and runtime tests and confirm they pass.

### Task 3: HolyLight assembly and full verification

**Files:**
- Modify: `SkillSystem/00-Skills/HolyLight/HolyLightSkillDefinition.tres`
- Modify: `SkillSystem/Tests/SkillSystemAssemblyTest.gd`

**Interfaces:**
- Consumes: `NearestValidTargetSelector` with `exclude_caster = true`.

- [ ] Add a failing assembly assertion that HolyLight uses the nearest-valid selector and excludes its caster.
- [ ] Run the assembly test and confirm it fails against the current ProvidedTargetSelector configuration.
- [ ] Replace the HolyLight selector subresource and preserve FRIENDLY relation configuration.
- [ ] Run every `SkillSystem/Tests/*.gd` headless test and a project smoke scan; require exit code zero and no new parser errors or warnings.

