# Game Run Result UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans (or equivalent inline TDD workflow) to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a completed or failed combat room show a restartable result overlay while keeping the game world running and disabling only player input.

**Architecture:** `CombatRoomController` remains the room-level adjudicator and only emits `room_failed` / `room_completed`. An Autoload `GameRunController` automatically finds that controller in the active scene, switches a reusable CanvasLayer overlay, and applies a single PlayerBase input gate. The overlay owns presentation and the restart button; it never contains room rules.

**Tech Stack:** Godot 4.7, GDScript, CanvasLayer/Control UI, SceneTree reload.

## Global Constraints

- Do not pause the SceneTree or stop AI, camera, effects, death cleanup, or world physics.
- Disable only new PlayerBase movement, dash, targeting, and attack input while the result overlay is visible.
- Do not add, remove, or modify user-placed unit instances in `res://Scenes/TestScene.tscn`.
- Every public interface and configurable field requires adjacent Simplified Chinese documentation.
- The GameRun controller is registered through Godot project settings as an Autoload; do not hand-edit `project.godot`.

---

### Task 1: Add the result-flow contract and regression test

**Files:**
- Create: `GameFlow/Tests/GameRunResultFlowTest.gd`
- Create: `Docs/Superpowers/Plans/2026-08-01-game-run-result-ui-implementation-plan.md`

**Interfaces:**
- Produces required contract paths `res://GameFlow/GameRunController.gd` and `res://GameFlow/UI/RunResultOverlay.tscn`.
- Produces required PlayerBase public interface `set_player_input_enabled(enabled: bool)`.

- [x] Write a headless test that fails until both GameFlow assets exist and PlayerBase exposes the unified input gate.
- [x] Run the test and confirm it fails only because the result-flow assets and interface are absent.

### Task 2: Implement the reusable result overlay

**Files:**
- Create: `GameFlow/UI/RunResultOverlay.gd`
- Create: `GameFlow/UI/RunResultOverlay.tscn`

**Interfaces:**
- Produces signal `restart_requested()`.
- Produces methods `show_failure()`, `show_success()`, and `hide_result()`.

- [x] Build a CanvasLayer with a dim backdrop, centered rounded panel, title, description, and restart button.
- [x] Keep the overlay visual-only: it does not know rooms, units, factions, or SceneTree reload behavior.
- [x] Wire the button to emit `restart_requested()`.

### Task 3: Add the unified player input gate

**Files:**
- Modify: `UnitSystem/Player/PlayerBase.gd`
- Modify: `UnitSystem/Components/Combat/PlayerAttackController.gd`
- Modify: `UnitSystem/Components/Targeting/PlayerTargetingComponent.gd`

**Interfaces:**
- Produces `PlayerBase.set_player_input_enabled(enabled: bool)` and `PlayerBase.is_player_input_enabled()`.
- Produces child-controller input gate methods called only by PlayerBase.

- [x] Make disabled input suppress new move, dash, target-select, nearest-target, and attack requests.
- [x] Preserve gravity, collision, camera follow, AI, visual effects, and an already-running attack/dash action.
- [x] Do not add Inspector configuration for this runtime flow state.

### Task 4: Implement and register GameRunController

**Files:**
- Create: `GameFlow/GameRunController.gd`
- Modify through Godot project settings: Autoload `GameRunController`

**Interfaces:**
- Consumes `CombatRoomController.room_failed`, `CombatRoomController.room_completed`, `PlayerBase.set_player_input_enabled`, and `RunResultOverlay.restart_requested`.
- Produces automatic room binding with no inspector NodePath.

- [x] Search the current scene recursively for one `CombatRoomController` and reconnect safely after scene reload.
- [x] On room failure/success, show the matching overlay and disable PlayerBase input without pausing the world.
- [x] On restart, hide the overlay, restore input for the current player, and reload the current scene.
- [x] Register the script once as a Godot Autoload named `GameRunController`.

### Task 5: Verify the complete flow

**Files:**
- Test: `GameFlow/Tests/GameRunResultFlowTest.gd`
- Test: `GameFlow/Rooms/Tests/CombatRoomControllerTest.gd`

- [x] Run the new contract test and confirm it passes.
- [x] Run CombatRoomController regression coverage.
- [x] Run a Godot 4.7 headless editor scan and check the MCP editor error count after refresh.
- [x] Verify the Autoload setting is registered and no player-unit instances were changed.

## Self-review

- [x] Failure and success both show a result overlay with restart.
- [x] The world is explicitly not paused; the input boundary is limited to PlayerBase and its direct input consumers.
- [x] Room decisions remain in CombatRoomController and UI presentation remains separate.
- [x] No TestScene unit mutation is required.
