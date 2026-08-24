# AI Hit Stop Feedback Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reuse the existing combat feedback Effect to give every AI attack module a configurable local hit stop without camera shake.

**Architecture:** `HitFeedbackBridge` accepts both the player's four-argument and AI's three-argument `attack_hit` signals. `AIAttackModuleBase` implements the same local pause contract as the player attack module, while `AttackModuleBase.tscn` owns one inherited bridge configured by an AI-specific profile.

**Tech Stack:** Godot 4.7, GDScript, inherited PackedScenes, Resource `.tres`, SceneTree headless tests.

## Global Constraints

- All fields and methods use English identifiers; new code includes detailed Simplified Chinese comments.
- Hit stop freezes only the current AI attack animation and Hitbox query.
- Ally movement, facing, gravity, global cooldown, other actors, and world processing continue.
- Reuse `res://Effects/Combat/HitFeedbackBridge.tscn`; do not duplicate an AI bridge.
- Do not modify `res://Scenes/TestScene.tscn`.
- The project is not a Git repository, so verification results replace commit steps.

---

### Task 1: Specify the shared feedback contract

**Files:**
- Modify: `Tests/AIAttackModuleBaseTest.gd`
- Create: `Tests/AIHitFeedbackTest.gd`

**Interfaces:**
- Consumes: `AIAttackModuleBase.attack_hit(target, hit_position, hit_direction)`
- Produces: assertions for `set_hit_stop_active(active)`, `is_hit_stop_active()`, the inherited bridge, and the AI profile.

- [ ] Add a base-module test asserting the pause API and `HitFeedbackBridge` node exist.
- [ ] Add a feedback test that emits the AI three-argument signal and expects the attack animation to pause, the detector query to suspend, and both to resume after the configured duration.
- [ ] Add assertions that the AI profile uses `0.06s`, disables camera shake, uses a `0.03s` retrigger interval, and has multiplier `[1.0]`.
- [ ] Run both tests and confirm failure is caused by the missing API, resource, or scene instance.

Run:

```powershell
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' --headless --path 'G:\Godot\SipSip' --script res://Tests/AIAttackModuleBaseTest.gd
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' --headless --path 'G:\Godot\SipSip' --script res://Tests/AIHitFeedbackTest.gd
```

Expected: each new assertion fails for the intended missing feature.

### Task 2: Make the existing Effect signal-compatible

**Files:**
- Modify: `Effects/Combat/HitFeedbackBridge.gd`

**Interfaces:**
- Consumes: player four-argument or AI three-argument `attack_hit`.
- Produces: `play_hit_feedback(..., combo_index: int = 1)`.

- [ ] Change only the last argument to an optional `combo_index: int = 1`.
- [ ] Keep interval merging, local stop timing, player camera shake, and player combo multipliers unchanged.
- [ ] Run the new AI feedback test; expected remaining failures relate only to the missing AI module pause implementation or scene configuration.

### Task 3: Implement the AI module local pause contract

**Files:**
- Modify: `Scripts/Combat/AI/AttackModuleBase.gd`
- Modify: `Scripts/Combat/AI/AIAttackHitbox.gd`

**Interfaces:**
- Produces: `set_hit_stop_active(active: bool)`, `is_hit_stop_active()`, and detector suspension that preserves per-window deduplication.

- [ ] Add failing assertions for animation progress freezing and detector suspension.
- [ ] Add an idempotent pause flag to `AIAttackModuleBase` and pause/resume `AttackAnimationPlayer` without changing `attack_state` or `current_target`.
- [ ] Add a detector suspension API that disables active queries without calling `end_detection()` and therefore does not clear the hit set.
- [ ] On resume, reactivate detection only when the attack is still active and its hit window remains open.
- [ ] Ensure cancel, reset, animation completion, and `_exit_tree()` clear the pause state and leave the detector disabled when appropriate.
- [ ] Run `AIAttackModuleBaseTest.gd` and `AIHitFeedbackTest.gd`; expected: PASS.

### Task 4: Configure inherited AI feedback

**Files:**
- Create: `Effects/Combat/DefaultAIHitFeedback.tres`
- Modify: `Scenes/Components/AiAttackModules/AttackModuleBase.tscn`

**Interfaces:**
- Consumes: the shared `HitFeedbackBridge.tscn` and `HitFeedbackProfile`.
- Produces: inherited `HitFeedbackBridge` with `attack_source_path = NodePath("..")` and AI profile assignment.

- [ ] Create the AI profile with `0.06s` hit stop, camera shake off, `0.03s` minimum interval, and `[1.0]` multiplier.
- [ ] Instance the existing feedback bridge in the parent attack scene and point it at its parent module.
- [ ] Wire `hit_feedback_enabled` so a child module can disable feedback without removing the inherited node.
- [ ] Run the two focused tests; expected: PASS.

### Task 5: Regression and runtime verification

**Files:**
- Verify only; no `TestScene.tscn` edits.

- [ ] Run all five existing AI attack tests plus `AIHitFeedbackTest.gd`.
- [ ] Launch the main scene headlessly and confirm it starts without parse or runtime errors.
- [ ] Confirm `Scenes/TestScene.tscn` was not modified by this feature.
- [ ] Refresh/inspect the Godot MCP editor error output when available.

Expected: six test scripts exit `0`, main scene smoke test reports no new errors, and the editor error count is zero.

## 实施结果

- `AIAttackModuleBase` 已实现局部暂停、状态查询和模块级反馈开关接口。
- `AIAttackHitbox` 已实现保留窗口去重记录的查询暂停/恢复接口。
- 现有 `HitFeedbackBridge` 已兼容三参数 AI 命中信号与四参数玩家命中信号。
- 父攻击场景已实例化现有 Effect，并引用 `DefaultAIHitFeedback.tres`。
- 六个 AI 战斗测试全部通过；主场景 10 帧 Headless 启动退出码为 `0`。
- Godot MCP `get_editor_errors` 返回 `count: 0`。
- `Scenes/TestScene.tscn` 未被修改。
