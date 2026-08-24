# Threat Debug Percentage Display Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show read-only relative threat percentages in the existing debug label.

**Architecture:** `ThreatDebugDisplay` uses the existing locked target's cached local threat as the display-only 100% reference, falling back to the sorted cache's highest entry only if the locked value is unavailable. A single Inspector switch controls whether that derived text is appended; core threat and target systems remain untouched.

**Tech Stack:** Godot 4.7, GDScript, existing headless scene-contract tests.

## Global Constraints

- Every exported property and public API needs nearby Simplified Chinese documentation.
- This is debug-only and must not write to threat, targeting, health, or gameplay state.
- Do not alter TestScene unit instances.

---

### Task 1: Add the read-only display option and formatting

**Files:**
- Modify: `UnitSystem/Debug/Threat/ThreatDebugDisplay.gd`
- Modify: `UnitSystem/Tests/ThreatDebugDisplayTest.gd`

**Interfaces:**
- Produces: `show_threat_percentage: bool`, defaulting to `true`.
- Consumes: the existing sorted threat cache returned by `_get_sorted_valid_entries()`.

- [x] **Step 1: Write the failing test**

Assert that threats `17.0` and `13.0` render as `100%` and `76%`, then disable `show_threat_percentage` and assert percentage text disappears.

- [x] **Step 2: Run the test to verify it fails**

Run: `Godot_v4.7.1-stable_win64_console.exe --headless --path G:\Godot\SipSip -s res://UnitSystem/Tests/ThreatDebugDisplayTest.gd`

Expected: failure because the present label only contains raw values and has no `show_threat_percentage` property.

- [x] **Step 3: Implement the minimal display formatting**

Add a documented export switch. Derive the reference from the locked target's positive cached value, with the first sorted entry as a safety fallback, and append ` (N%)` only when enabled. Use the same helper for the summary and list rows.

- [x] **Step 4: Run the test to verify it passes**

Run the same headless command. Expected: `ThreatDebugDisplayTest: PASS`.

- [x] **Step 5: Run editor validation**

Run: `Godot_v4.7.1-stable_win64_console.exe --editor --path G:\Godot\SipSip --quit`

Expected: exit code `0` with no new parse or scene warnings.
