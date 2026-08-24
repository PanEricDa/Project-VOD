# Player Attack Buffer And Hold Combo Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add configurable input buffering and hold-to-chain behavior to the data-driven player weapon combo controller.

**Architecture:** Keep weapon animation discovery unchanged. `PlayerAttackController` owns short-lived input-buffer, chain-wait and held-combo-restart timers and reads the configured InputMap action state.

**Tech Stack:** Godot 4.7, GDScript, SceneTree headless tests.

## Global Constraints

- Do not modify `Scenes/TestScene.tscn`.
- Do not change weapon animation assets or the dynamic `basic_attack_1...N` discovery contract.
- Do not introduce player GCD, movement restrictions, Hitbox or damage behavior.
- New identifiers use English; new code comments use detailed Simplified Chinese.

---

### Task 1: Define failing behavior tests

**Files:**
- Modify: `WeaponCombatSystem/04-Tests/PlayerWeaponComboTest.gd`

**Interfaces:**
- Consumes: `request_basic_attack()`, `get_combo_index()` and the existing attack signals.
- Produces: regression coverage for `input_buffer_duration`, `hold_to_chain_enabled` and `hold_combo_restart_delay`.

- [x] Added a test showing an early buffered click expires before the current animation ends.
- [x] Added a test showing a late buffered click advances exactly one segment.
- [x] Added a test showing a held action automatically completes all available segments.
- [x] Added a test showing a held action restarts at segment one only after the configured delay.
- [x] Added a test showing release during the restart delay cancels automatic restart.
- [x] Ran the test and confirmed failure because the new exported properties did not exist.

### Task 2: Implement controller timing

**Files:**
- Modify: `WeaponCombatSystem/03-Components/PlayerAttackController.gd`

**Interfaces:**
- Produces:
  - `input_buffer_duration: float = 0.15`
  - `hold_to_chain_enabled: bool = true`
  - `hold_combo_restart_delay: float = 0.3`

- [x] Added the exported parameters and internal buffer/restart timers.
- [x] Decreased the input buffer during active attacks and discarded expired input.
- [x] Continued at animation completion for a valid buffer or a currently held attack action.
- [x] Waited `hold_combo_restart_delay` after the final segment before restarting while held.
- [x] Cleared all new state during cancel, weapon change and component reconfiguration.
- [x] Ran `PlayerWeaponComboTest.gd` and confirmed it passes.

### Task 3: Regression verification

**Files:**
- Verify: `UnitSystem/Tests/*.gd`
- Verify: `WeaponCombatSystem/04-Tests/*.gd`

- [x] Ran all UnitSystem and WeaponCombatSystem tests.
- [x] Ran a Godot 4.7 headless editor scan.
- [x] Refreshed MCP and loaded the controller with all four expected defaults.
- [x] Confirmed `Scenes/TestScene.tscn` remains unchanged.
