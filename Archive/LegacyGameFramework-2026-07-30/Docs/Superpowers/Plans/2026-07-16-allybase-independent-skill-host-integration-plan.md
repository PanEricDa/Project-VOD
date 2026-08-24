# AllyBase Independent SkillHost Safe Integration Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Mount and safely initialize the independent SkillHost on AllyBase, expose manual forwarding APIs, and synchronize action blocking/shared cooldowns without changing automatic AI behavior.

**Architecture:** AllyBase owns a local `SkillHostComponent/SkillSocket` node pair and treats the Host through its public API. Existing AllyBase AI remains authoritative; the adapter only injects owner/runtime parent, forwards explicit requests, synchronizes cooldown start/extension events, and prevents new/old actions from starting during the other system's active cast.

**Tech Stack:** Godot 4.7, typed GDScript, inherited `.tscn` scenes, SceneTree headless tests.

## Global Constraints

- Do not modify TestScene or add any unit instance to it.
- Do not automatically request a new-system skill or select a target.
- Do not connect new Host approach, facing, or movement-lock signals to AllyBase movement.
- Preserve the legacy SkillModuleSocket and all legacy behavior.
- All new identifiers are English and new code has detailed Simplified Chinese comments.
- Project is not a Git repository; record test/hash evidence instead of commits.

---

### Task 0: Baseline and protected snapshots

**Files:** Read only.

- [x] **Step 1: Record hashes**

Capture length, UTC timestamp, and SHA-256 for `Scenes/TestScene.tscn`, all Ally profession source scenes, and legacy skill files.

- [x] **Step 2: Run baseline tests**

Run the five independent SkillSystem tests and all 21 top-level project tests. Require zero failures and record the two known Warrior warning emissions.

### Task 1: Scene mount, owner injection, and public forwarding

**Files:**
- Create: `Tests/AllyIndependentSkillHostAssemblyTest.gd`
- Modify: `Scenes/ObjectScenes/AllyBase.tscn`
- Modify: `Scripts/AI/AllyBase.gd`

**Interfaces:**
- Consumes `SkillSystem/Core/SkillHostComponent.gd` public API.
- Produces `get_independent_skill_host()`, `request_independent_skill()`, and `request_best_independent_skill()`.

- [x] **Step 1: Write the failing integration test**

Verify exact nodes, Host script/default fields, inherited ally availability, owner/runtime-parent injection, empty registry, no automatic health change, missing-skill false result, and manual request success after inserting a test SkillBase beneath the socket.

- [x] **Step 2: Run RED**

```powershell
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' --headless --path 'G:\Godot\SipSip' --script res://Tests/AllyIndependentSkillHostAssemblyTest.gd
```

Expected: failure because AllyBase lacks `SkillHostComponent/SkillSocket` and forwarding methods.

- [x] **Step 3: Mount local Host nodes**

Add the Host script as an external resource, then create local `SkillHostComponent` and `SkillHostComponent/SkillSocket` nodes with the same defaults as the independent Host scene.

- [x] **Step 4: Resolve/configure Host and implement forwarding**

Preload the Host type, export `independent_skill_host_path`, resolve it during `_ready()`, connect approved signals once, and call `configure_owner(self, get_tree().current_scene)`. Forwarding returns false on an invalid Host and does not retry or mutate movement.

- [x] **Step 5: Run GREEN for assembly behavior**

Expected: node/owner/manual request portions pass; synchronization assertions added in Task 2 may remain RED until that task.

### Task 2: Cooldown synchronization and action exclusion

**Files:**
- Modify: `Tests/AllyIndependentSkillHostAssemblyTest.gd`
- Modify: `Scripts/AI/AllyBase.gd`

**Interfaces:**
- Consumes Host `global_cooldown_started`, `start_global_cooldown`, `set_cast_blocked`, `get_active_skill`.
- Produces no new automatic behavior.

- [x] **Step 1: Add failing synchronization assertions**

Verify Host cooldown start extends legacy remaining time; normal attack success and legacy skill cast-start extend Host cooldown; attack/legacy casting update Host blocked state; a new-system SkillBase in CASTING blocks old begin paths without cancellation.

- [x] **Step 2: Run RED**

Expected: cooldown/action synchronization assertions fail while scene/owner assertions remain green.

- [x] **Step 3: Implement event-based cooldown synchronization**

Connect Host cooldown-start signal to a callback that applies `max(existing, duration)`. At successful old attack start and legacy skill cast start, call Host `start_global_cooldown(basic_attack_global_cooldown)`.

- [x] **Step 4: Implement reciprocal cast blocking**

Each AllyBase frame sets Host cast-blocked from normal attack or legacy active-cast state. Add `_is_independent_skill_casting()` and check it in old normal-attack and legacy-skill begin paths. Do not cancel any action or queued request.

- [x] **Step 5: Run full integration test GREEN**

Expected: `AllyIndependentSkillHostAssemblyTest: PASS`, exit 0.

### Task 3: Documentation and regression verification

**Files:**
- Modify: `SkillSystem/README.md`
- Modify: `SkillSystem/Docs/Architecture.md`
- Modify: this plan result section only.

- [x] **Step 1: Document optional AllyBase adapter**

State the node path, manual-only request APIs, synchronized cooldown behavior, and deferred target/movement integration.

- [x] **Step 2: Run focused and module tests**

Run the Ally integration test and all five SkillSystem tests. Expected: 6 pass, 0 fail, 0 new issues.

- [x] **Step 3: Run all existing project tests**

Run all top-level tests, now 22 including the new integration test. Expected: 22 pass, with only the two known Warrior warnings.

- [x] **Step 4: Run Godot smoke and integrity checks**

Require smoke exit 0 with zero warnings/errors. Confirm TestScene and unrelated protected legacy/profession files retain their baseline hashes; only AllyBase source/script and approved docs/test files change.

- [x] **Step 5: Record results**

Mark verified steps complete and append RED/GREEN counts, test totals, smoke status, and unchanged TestScene SHA-256.

## Implementation Results

- Task 1 RED: AllyBase and inherited Guardian lacked `SkillHostComponent/SkillSocket` and adapter methods. GREEN: scene inheritance, owner/world injection, inert empty Host, and explicit manual delivery passed.
- Task 2 RED: five synchronization contracts failed: Host-to-legacy cooldown, legacy-skill-to-Host cooldown, legacy-attack-to-Host cooldown, action-block updater, and independent CASTING query. GREEN: all five contracts and reciprocal old/new begin blocking passed.
- Focused Ally integration test: 1 passed, 0 failed.
- Independent SkillSystem suite: 5 passed, 0 failed, 0 issues.
- Top-level project suite: 22 passed, 0 failed, 0 error lines. Two pre-existing Warrior warning emissions remain unchanged.
- Godot 4.7 headless smoke: exit code 0, 0 warning/error lines.
- Protected unrelated files changed: 0 of 10.
- TestScene SHA-256 remained `D1E28252C9C7E0D52DFEC06A302193B9531B75D8EF17AC91C617C7B668BA6509`.
