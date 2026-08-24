# Caster Firebolt Runtime Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Verify and complete the existing Caster AI path so a locked hostile target results in a real Firebolt cast and delivery launch.

**Architecture:** Keep `IndependentSkillHostComponent` and `FireboltDelivery` unchanged. `AllyBehaviorStateMachine` remains the sole AI action arbiter and consumes existing SkillHost requests only where the generic combat distance/facing behavior does not already satisfy them.

**Tech Stack:** Godot 4.7, GDScript, SceneTree headless tests.

## Global Constraints

- Do not modify `res://Scenes/TestScene.tscn`.
- Do not create a parallel skill, AI, projectile, or targeting flow.
- Preserve the existing SkillHost public interface and Caster scene assembly.

---

### Task 1: Caster runtime delivery test

**Files:**
- Create: `UnitSystem/Tests/CasterFireboltRuntimeTest.gd`

- [x] Create an isolated scene tree with Caster, a Player-faction `UnitBase`, and `EnemyBase2`.
- [x] Inject a locked hostile result after target-system coverage, then wait for Firebolt's existing `delivery_launched` signal.
- [x] Assert that Caster launches a Firebolt delivery agent through its real SkillHost and state-machine path.
- [x] Run the test and identify the UnitBase/FactionComponent compatibility gap in skill target validation.

### Task 2: Minimal state-machine handoff

**Files:**
- Modify: `UnitSystem/Components/Behavior/AllyBehaviorStateMachine.gd`

- [x] Keep the existing state-machine approach/facing behavior because the runtime test proves it already satisfies Firebolt's range and facing needs.
- [x] Extend `SkillTargetSelectorBase` to use UnitBase's public faction relation methods, while retaining the old `FactionComponent` fallback.
- [x] Re-run the runtime test and the existing SkillHost / Caster assembly tests.
