# Player Dash Combo Cancel Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Allow player Dash to cancel an active attack while preserving the next valid combo segment for a short, bounded continuation window.

**Architecture:** `PlayerAttackController` owns attack interruption and preserves only the current combo index. `PlayerBase` remains responsible for Dash and passes the predicted Dash duration through one public controller interface. The continuation allowance is calculated once when Dash begins as half of that duration; since the original window continues counting down during Dash, consecutive Dashes cannot extend it indefinitely.

**Tech Stack:** Godot 4.7, GDScript, Godot headless SceneTree regression tests.

## Global Constraints

- Do not modify `res://Scenes/TestScene.tscn`.
- Dash cancels animation, hit window, attack motion and hit stop, but must not emit a completed combo or reset its index.
- Continuation compensation equals `expected_dash_duration * 0.5` seconds.
- Only an actively playing attack is cancellable; an existing `CHAIN_WAIT` receives no additional time.

---

### Task 1: Define Dash-Cancel Continuation Contract

**Files:**
- Modify: `UnitSystem/Tests/PlayerDashComboContinuityTest.gd`
- Modify: `UnitSystem/Components/Combat/PlayerAttackController.gd`

**Interfaces:**
- Produces `interrupt_attack_for_dash(expected_dash_duration: float) -> bool`.
- `true` means an active attack was cancelled and a continuation window was opened.

- [ ] **Step 1: Write failing tests**

```gdscript
var cancelled := controller.interrupt_attack_for_dash(0.25)
_expect(cancelled, "active attack can be dash-cancelled")
_expect(controller.get_combo_index() == 1, "dash cancellation preserves combo index")
_expect(controller.get("_state") == PlayerAttackController.AttackState.CHAIN_WAIT, "dash cancellation opens chain wait")
_expect(is_equal_approx(float(controller.get("_combo_reset_remaining")), 0.425), "dash cancellation restores half of the expected Dash duration")
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```powershell
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' --headless --path 'G:\Godot\SipSip' --script res://UnitSystem/Tests/PlayerDashComboContinuityTest.gd
```

Expected: failure because `interrupt_attack_for_dash` does not exist.

- [ ] **Step 3: Implement the controller method**

```gdscript
func interrupt_attack_for_dash(expected_dash_duration: float) -> bool:
	if _state != AttackState.ATTACKING:
		return false
	set_hit_stop_active(false)
	_close_attack_hit_window()
	_cancel_owner_attack_motion()
	_current_attack_animation = &""
	_state = AttackState.CHAIN_WAIT
	_combo_reset_remaining = combo_reset_duration + maxf(expected_dash_duration, 0.0) * 0.5
	_play_reset_animation()
	return true
```

- [ ] **Step 4: Run test to verify it passes**

Run the Task 1 command. Expected: `PlayerDashComboContinuityTest: PASS`.

### Task 2: Wire PlayerBase Dash to the Controller Interface

**Files:**
- Modify: `UnitSystem/Player/PlayerBase.gd`
- Modify: `UnitSystem/Tests/PlayerDashComboContinuityTest.gd`

**Interfaces:**
- `PlayerBase._start_dash()` calls `AttackController.interrupt_attack_for_dash(dash_distance / dash_speed)` once before Dash state begins.

- [ ] **Step 1: Extend the failing test**

```gdscript
player.dash_distance = 2.5
player.dash_speed = 10.0
player._start_dash(Vector3.FORWARD)
_expect(controller.get_combo_index() == 1, "PlayerBase Dash preserves the pending next combo segment")
```

- [ ] **Step 2: Run test to verify it fails**

Run the Task 1 command. Expected: Dash does not invoke the new interruption interface.

- [ ] **Step 3: Implement the minimal PlayerBase bridge**

```gdscript
var attack_controller := get_node_or_null(^"AttackController")
if attack_controller != null and attack_controller.has_method(&"interrupt_attack_for_dash"):
	attack_controller.call(
		"interrupt_attack_for_dash",
		dash_distance / maxf(dash_speed, 0.000001)
	)
```

Place it in `_start_dash()` immediately before the existing attack-motion cancellation.

- [ ] **Step 4: Run test and editor scan**

Run:

```powershell
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' --headless --path 'G:\Godot\SipSip' --script res://UnitSystem/Tests/PlayerDashComboContinuityTest.gd
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' --headless --path 'G:\Godot\SipSip' --editor --quit
```

Expected: test passes and the editor scan reports no parse errors.
