# UnitStateComponent Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans or superpowers:subagent-driven-development to implement this plan task-by-task.

**Goal:** Add one reusable unit state/lifecycle component that centralizes death, revive, and future status entry points without coupling `UnitBase` to presentation or deleting current health logic.

**Architecture:** `UnitStateComponent` is mounted once under `UnitBase`. It listens to the existing `died` and `revived` signals, owns death cleanup policy and pending-destroy timing, and optionally instantiates a death effect. `UnitBase` remains the source of truth for health and keeps all existing public signals. UI, skills, combat, and visual nodes remain independent.

**Tech Stack:** Godot 4.7, GDScript, PackedScene, SceneTreeTimer.

## Global Constraints

- Do not add or modify unit instances in `Scenes/TestScene.tscn`.
- New formal scenes must be saved by Godot/ResourceSaver and have a valid UID.
- All new fields and methods use English identifiers with Simplified Chinese comments.
- Death effects must not be required for the state component to function.
- Enemy cleanup is configurable; player and ally units default to keeping their root for revive.

---

### Task 1: Define the component contract with a failing test

**Files:**
- Create: `UnitSystem/Components/State/UnitStateComponentTest.gd`
- Modify: `UnitSystem/Tests/UnitDeathLifecycleTest.gd`

**Interfaces:**
- Consumes: `UnitBase.died(source)` and `UnitBase.revived(current_health, source)`.
- Produces: `UnitStateComponent.is_dead_state()`, `is_pending_destroy()`, `cancel_pending_destroy()`, and cleanup mode enum.

- [x] Add tests for the default keep-root mode: lethal damage enters dead state, revive clears it, and no queue-free is scheduled.
- [x] Add tests for destroy-after-effect mode using a short delay: lethal damage enters pending destroy, `cancel_pending_destroy()` cancels it, and the unit remains valid.
- [x] Add tests that a component without a death effect still handles death and revive without errors.
- [x] Run the focused test and confirm it fails before implementation, then passes after implementation.

### Task 2: Implement the reusable state/lifecycle component

**Files:**
- Create: `UnitSystem/Components/State/UnitStateComponent.gd`
- Create: `UnitSystem/Components/State/UnitStateComponent.tscn`

**Interfaces:**
- Public enum `DeathMode { KEEP_FOR_REVIVE, REMOVE_AFTER_DELAY, REMOVE_IMMEDIATELY }`.
- Exported properties: `death_mode`, `death_effect_scene`, `remove_after_seconds`.
- Public methods: `configure_owner(owner: UnitBase)`, `cancel_pending_destroy()`, `is_pending_destroy()`, `is_dead_state()`, `restore_after_revive()`.

- [x] Implement owner discovery/configuration without hard-coding a concrete player or ally class.
- [x] Connect and disconnect owner death/revive signals safely.
- [x] On death, record lifecycle state, optionally hide the configured visual, optionally spawn the effect, and schedule destruction only for the selected policy.
- [x] Reparent a spawned effect to the owner’s parent before owner deletion so the effect can finish independently.
- [x] On revive, cancel pending deletion, restore visual visibility, and return to alive state.
- [x] Make repeated death/revive calls idempotent and avoid orphan timers/effects.
- [x] Add Chinese comments describing the lifecycle and extension points.

### Task 3: Mount the component on UnitBase without moving health logic

**Files:**
- Modify: `UnitSystem/Base/00_UnitBase.tscn`
- Modify: `UnitSystem/Base/00_UnitBase.gd` only if owner wiring requires a minimal hook.

**Interfaces:**
- `UnitBase` exposes `UnitStateComponent` at child path `UnitState`.

- [x] Add the `UnitStateComponent` instance under `UnitBase`.
- [x] Configure the component from the owning `UnitBase` at runtime, preserving scene inheritance and renamed derived roots.
- [x] Keep `UnitBase` health fields, signals, and `apply_damage()/revive()` behavior unchanged.
- [x] Ensure missing optional component does not make UnitBase fail, for compatibility with archived/custom scenes.

### Task 4: Configure policy defaults and verify current unit behavior

**Files:**
- Modify: `UnitSystem/Player/PlayerBase.tscn` only if an explicit keep-root override is needed.
- Modify: `UnitSystem/Base/AIUnitBase.tscn` only if an explicit keep-root override is needed.
- Modify: relevant unit source scenes only when their death policy is intentionally different from the base default.

**Interfaces:**
- Player/ally default: `KEEP_FOR_REVIVE`.
- Enemy default: `REMOVE_AFTER_DELAY` only where explicitly configured; no TestScene instance edits.

- [x] Verify player and ally death still cancel actions through their existing signal listeners.
- [x] Verify player/ally revive restores the visual and leaves the root alive.
- [x] Verify enemy policy can be changed on its source scene without changing UnitBase code.
- [x] Do not add, remove, or reposition units in TestScene.

### Task 5: Documentation and verification

**Files:**
- Create: `Docs/Superpowers/Specs/2026-07-31-unit-state-component-design.md`
- Modify: the current progress/usage guide if present.

- [x] Document what belongs in `UnitStateComponent` and what remains outside it.
- [x] Document future status extension boundaries: numeric values, modifiers, control restrictions, and lifecycle.
- [x] Run focused UnitSystem headless tests and editor scan.
- [x] Verify the new scene has a valid Godot resource UID and the component script type loads in Inspector Quick Load.
- [x] Record that no TestScene unit instances were modified.
