# Combat Room Flow Controller Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Resolve player-death room flow without making surviving allies seek unengaged distant enemy packs.

**Architecture:** `CombatRoomController` is a room-level orchestrator under `GameFlow/Rooms`. It subscribes to existing unit life signals and `EncounterController` Pack signals. It emits flow results only; reset, checkpoint, reward, and scene transition remain future `GameRunController` work.

**Tech Stack:** Godot 4.7, GDScript, headless SceneTree tests.

## Global Constraints

- Do not modify any user unit instances in `TestScene.tscn`.
- Do not modify Ally/Enemy AI, targeting ranges, combat components, or `EncounterController` state ownership.
- In a player-death last stand, only already engaged packs prolong play; dormant distant packs never auto-activate.

---

### Task 1: Create a failing room-flow lifecycle test

**Files:**
- Create: `GameFlow/Rooms/Tests/CombatRoomControllerTest.gd`

- [x] Assert the path and class load, then create a room with one Player, one Ally, one EnemyContainer/Pack, and an EncounterController.
- [x] Assert Player death with a living Ally enters LAST_STAND; Pack clear ends in FAILED after the configured delay; Player revival returns to NORMAL; no Ally triggers FAILED.
- [x] Run test and observe RED because the controller does not exist.

### Task 2: Implement the room-level controller

**Files:**
- Create: `GameFlow/Rooms/CombatRoomController.gd`
- Create: `GameFlow/Rooms/CombatRoomController.tscn`
- Modify: `Scenes/TestCombatRoom.tscn`

- [x] Add `NORMAL`, `LAST_STAND`, `FAILED`, `COMPLETED` runtime states and documented signals.
- [x] Resolve a unique Player and all Ally units by `faction_id`; listen to `died` and `revived` without NodePath configuration.
- [x] Subscribe to the sibling EncounterController; track only Pack `started` events as active and remove Pack entries on reset/clear.
- [x] Player death with survivors enters LAST_STAND; if no active Pack, or the final active Pack clears/resets, schedule failure; Player revive returns NORMAL; room clear while player lives enters COMPLETED.
- [x] Add only `CombatRoomController` to TestCombatRoom root; do not alter user units.

### Task 3: Verify and record

- [x] Run `CombatRoomControllerTest.gd`, `EncounterControllerTest.gd`, `CameraFollowControllerTest.gd`, and a headless editor scan.
- [x] Mark complete only with zero command failures and record expected warnings separately.

**Result (2026-08-01):** The initial RED test failed because `CombatRoomController` was absent. The completed controller passed its dedicated room-flow test, EncounterController regression, Camera fallback regression, and Godot editor scan. The Empty Pack and multiple Player warnings shown by regression tests are intentional coverage of guarded invalid/ambiguous configurations; no script errors occurred.
