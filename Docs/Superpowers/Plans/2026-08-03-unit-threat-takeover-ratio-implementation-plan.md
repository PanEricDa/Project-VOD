# Unit Threat Takeover Ratio Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a unit define how far above the current target's local threat it must rise before an enemy switches to it.

**Architecture:** The source `UnitBase` provides a documented ratio; `EnemyThreatComponent` reads only the selected challenger’s ratio during its existing single target-resolution comparison. Guardian overrides the inherited default in its source scene.

**Tech Stack:** Godot 4.7, GDScript, existing headless contract tests.

## Global Constraints

- Every exported property has nearby Simplified Chinese documentation.
- EnemyThreatComponent remains the only threat-table and target-resolution authority.
- Do not modify TestScene unit instances.

---

### Task 1: Add and consume per-challenger takeover ratios

**Files:**
- Modify: `UnitSystem/Base/00_UnitBase.gd`
- Modify: `UnitSystem/Components/Threat/EnemyThreatComponent.gd`
- Modify: `UnitSystem/AI/Ally/Units/Guardian.tscn`
- Modify: `UnitSystem/Tests/EnemyThreatComponentTest.gd`

**Interfaces:**
- Produces: `UnitBase.threat_takeover_ratio: float`, default `1.25`.
- Consumes: the current highest valid threat candidate inside `EnemyThreatComponent.resolve_target()`.

- [x] **Step 1: Write a failing test**

Create a challenger at 106 threat against a current target at 100. Assert default `1.25` retains the current target; set the challenger ratio to `1.05` and assert it becomes the target.

- [x] **Step 2: Run the test and verify the tank assertion fails**

Run: `Godot_v4.7.1-stable_win64_console.exe --headless --path G:\Godot\SipSip -s res://UnitSystem/Tests/EnemyThreatComponentTest.gd`

Expected: the current fixed 125% comparison retains the target despite the challenger test value.

- [x] **Step 3: Implement the minimal source-owned ratio**

Add the documented UnitBase export. In the existing comparison, multiply the current threat by the highest challenger’s clamped ratio. Set Guardian to `1.05`.

- [x] **Step 4: Verify target-resolution tests pass**

Run the same headless command. Expected: `EnemyThreatComponentTest: PASS`.

- [x] **Step 5: Verify scene and editor loading**

Run the UnitRootConfiguration contract and a headless editor scan. Expected: both exit with code `0` and report no new errors.
