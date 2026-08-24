# Death Camera Focus Fallback Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Keep the camera on the most relevant living unit when the player dies: nearest ally first, then nearest enemy, then no target.

**Architecture:** Extend the existing `CameraFollowController`; it remains the sole owner of camera focus selection and existing smoothing. A stored player death position provides a stable distance origin. The controller keeps a fallback focus until that focus dies or a higher-priority living class becomes available.

**Tech Stack:** Godot 4.7, GDScript, SceneTree headless tests.

## Global Constraints

- Do not edit unit instances in `TestScene.tscn` or `TestCombatRoom.tscn`.
- Keep the camera's fixed angle, offset, smoothing, and height-lock behavior unchanged.
- Do not add manual NodePath configuration; selection uses `UnitBase.faction_id` and living state only.

---

### Task 1: Prove fallback priority with real UnitBase instances

**Files:**
- Modify: `UnitSystem/Tests/CameraFollowControllerTest.gd`

**Interfaces:**
- Consumes: `CameraFollowController._resolve_follow_target()`, `UnitBase.apply_damage()`, `UnitBase.revive()`.
- Produces: regression coverage for player → closest ally → closest enemy → none → revived player.

- [x] **Step 1: Add a fallback fixture**

Create a living Player at `(0, 0, 0)`, Allies at `(2, 0, 0)` and `(6, 0, 0)`, and Enemies at `(1, 0, 0)` and `(4, 0, 0)`.

- [x] **Step 2: Assert expected transitions and run RED**

Kill the Player, expect the nearby Ally; kill both Allies, expect the nearby Enemy; kill both Enemies, expect no focus; revive the Player, expect it again. Run `CameraFollowControllerTest.gd`; it must fail because the old controller only accepts Player faction candidates and allows dead players.

### Task 2: Add priority focus selection

**Files:**
- Modify: `UnitSystem/Components/Camera/CameraFollowController.gd`

**Interfaces:**
- Produces: `FocusMode` internal state and read-only `debug_focus_mode`; living candidates selected in priority order `PLAYER`, `ALLY_FALLBACK`, `ENEMY_FALLBACK`, `NONE`.

- [x] **Step 1: Track a stable fallback origin**

When a living Player becomes dead, record its world position once. Use it to rank fallback candidates so a falling corpse or a later respawn does not shift the nearest calculation.

- [x] **Step 2: Replace Player-only resolution with living priority resolution**

Choose a living Player when exactly one exists; otherwise choose the nearest living Ally, then nearest living Enemy, using the stored death origin. No living candidate clears focus without moving the CameraRig.

- [x] **Step 3: Preserve stable fallback and recovery**

When an Ally/Enemy fallback remains valid, retain it rather than switching among same-priority candidates. Recheck higher priority candidates at the existing retry interval, so player revival restores player focus without manual setup.

- [x] **Step 4: Run focused test and observe GREEN**

Run `CameraFollowControllerTest.gd`; expected `PASS`.

### Task 3: Regression verification

**Files:**
- Modify: `Docs/Superpowers/Plans/2026-08-01-death-camera-focus-fallback-implementation-plan.md`

- [x] **Step 1: Run camera, health/death, and editor checks**

Run `CameraFollowControllerTest.gd`, `UnitDeathLifecycleTest.gd`, `WorldHealthBarTest.gd`, and a Godot 4.7 headless editor scan.

- [x] **Step 2: Record result**

Mark complete only after every command exits `0` and document any expected warning separately from errors.

**Result (2026-08-01):** The RED test confirmed the former Player-only resolver retained a dead Player target. The replacement now selects Player → nearest Ally → nearest Enemy, records the player's death position once, and returns to Player on revival. `CameraFollowControllerTest`, `UnitDeathLifecycleTest`, `WorldHealthBarTest`, and the Godot editor scan all passed. The Camera test's multiple-Player warning is intentional coverage of the ambiguity guard and is not a script error.
