# Decoupled Skill Module Base Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a complete dependency-free skill lifecycle component, expose a one-way AllyBase host adapter, and mount exactly one placeholder skill instance in the Mage source scene for validation.

**Architecture:** `SkillModuleBase` owns request delay, queue, cast, validation, placeholder delivery, and skill cooldown without knowing AllyBase. AllyBase depends only on its public API to mount modules and start the existing shared combat cooldown on `cast_started`. Mage is the only class source scene that receives a module instance in this phase.

**Tech Stack:** Godot 4.7, GDScript, `.tscn`, `.tres`, SceneTree headless contract tests, Godot MCP verification.

## Global Constraints

- All code identifiers are English and all newly added code contains detailed Simplified Chinese comments.
- `SkillModuleBase` must not reference `AllyBase`, basic-attack types, class-specific scripts, or TestScene paths.
- Do not add skill instances to Guardian, Warrior, Ranger, Healer, or `Scenes/TestScene.tscn`.
- Add one placeholder `SkillModuleBase` instance only to `Scenes/ObjectScenes/Mage.tscn` under `VisualRoot/SkillModuleSocket`.
- Public cooldown starts at successful cast start; skill cooldown starts only after successful delivery.
- Project is not a Git repository; do not create commits, branches, or worktrees.

---

### Task 1: Skill Profile and Base Lifecycle

**Files:**
- Create: `Scripts/Combat/Skills/SkillProfile.gd`
- Create: `Scripts/Combat/Skills/SkillModuleBase.gd`
- Create: `Scenes/Components/SkillModules/SkillModuleBase.tscn`
- Create: `Resources/Combat/Skills/DefaultSkillProfile.tres`
- Test: `Tests/SkillModuleBaseTest.gd`

**Interfaces:**
- Produces `SkillProfile`, `SkillModuleBase`, `request_skill()`, `begin_cast()`, cancellation/reset/query methods, and lifecycle signals.
- Consumes only generic `Node3D` owner/target and standard Godot timing, animation, and random APIs.

- [x] **Step 1: Write the failing base contract test**

Create a failure-accumulating SceneTree test that loads the planned scene, checks `CastOrigin`, `DeliveryRoot`, `SkillAnimationPlayer`, all public methods/signals, Profile defaults, and drives deterministic timing by setting all decision delays and cast time to zero. Verify a request becomes queued, `begin_cast()` emits `cast_started`, placeholder delivery emits `skill_delivered`, and cooldown begins.

Key lifecycle assertions:

```gdscript
module.configure_skill_owner(owner)
assert(module.request_skill(target))
await process_frame
assert(module.is_queued())
assert(module.begin_cast())
await process_frame
assert(delivered_count == 1)
assert(module.get_skill_cooldown_remaining() > 0.0)
```

- [x] **Step 2: Run RED**

```powershell
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' --headless --path 'G:\Godot\SipSip' --script res://Tests/SkillModuleBaseTest.gd
```

Expected: non-zero exit because the base files do not exist.

- [x] **Step 3: Implement the reusable Profile**

Define `SkillTargetFaction`, `SkillDeliveryType`, and all approved cast/cooldown/decision exports. Normalize min/max pairs at read time and keep optional group validation empty by default.

- [x] **Step 4: Implement SkillModuleBase**

Use the approved state enum:

```gdscript
enum SkillState { READY, DECISION_WAIT, QUEUED, CASTING, COOLDOWN }
```

Implement generic owner injection, target request, one-time hesitation roll, queue completion, out-of-range notification, externally gated `begin_cast()`, final range validation, overridable placeholder delivery, successful-delivery cooldown, failure retry, cancellation, reset, state queries, and structured optional debug logs. Process skill-local timers in `_physics_process()` so no host update call is required.

- [x] **Step 5: Build the base scene and default resource**

Create:

```text
SkillModuleBase
├── CastOrigin
├── DeliveryRoot
└── SkillAnimationPlayer
```

Attach the script, assign `DefaultSkillProfile.tres`, and include an empty `RESET` animation so future inherited modules have a stable animation library.

- [x] **Step 6: Expand lifecycle tests**

Verify:

- Out-of-range requests queue and emit `cast_range_required` without moving nodes.
- Invalid owner/target and optional wrong group reject or fail with stable reasons.
- Final range failure does not start skill cooldown and returns to decision wait.
- Cancellation preserves an existing cooldown; reset clears it.
- Cooldown emits start/finish exactly once.
- Extra hesitation is rolled once and appended to normal delay.

- [x] **Step 7: Run GREEN**

Run the Task 1 command. Expected: `SkillModuleBaseTest: PASS`, exit code `0`.

---

### Task 2: One-Way AllyBase Host Adapter

**Files:**
- Modify: `Scripts/AI/AllyBase.gd`
- Modify: `Scenes/ObjectScenes/AllyBase.tscn`
- Test: `Tests/AllySkillModuleHostTest.gd`

**Interfaces:**
- Consumes `SkillModuleBase.configure_skill_owner()`, request/begin/cancel methods, and `cast_started`.
- Produces `set_skill_module()`, `get_skill_module()`, `request_equipped_skill()`, `begin_equipped_skill_cast()`, and `cancel_equipped_skill()`.

- [x] **Step 1: Write the failing host test**

Verify the inherited Ally scene contains `VisualRoot/SkillModuleSocket`, exposes `skill_module_path`, safely handles no module, mounts/replaces/unmounts a module, injects/clears owner, and forwards request/begin/cancel calls.

- [x] **Step 2: Run RED**

```powershell
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' --headless --path 'G:\Godot\SipSip' --script res://Tests/AllySkillModuleHostTest.gd
```

Expected: non-zero exit because the Ally host API and socket do not exist.

- [x] **Step 3: Add host fields and APIs**

Add an exported module path, runtime module reference, resolver, mount/unmount logic, and public forwarding methods. Connect only public signals. Do not put target selection, delivery, skill-local cooldown, or range movement into AllyBase.

- [x] **Step 4: Share the existing combat cooldown gate**

Keep `basic_attack_global_cooldown` as the per-unit configured duration for this phase. On `cast_started`, immediately set `basic_attack_global_cooldown_remaining` to that duration. Reject `begin_equipped_skill_cast()` while the shared timer is positive or a basic attack is currently active. The skill module remains unaware of this gate.

- [x] **Step 5: Add the generic socket**

Add `VisualRoot/SkillModuleSocket` to `AllyBase.tscn` without an instance.

- [x] **Step 6: Run GREEN and attack regression**

Run `AllySkillModuleHostTest.gd`, `AllyBasicAttackTest.gd`, and `AllyAttackDistanceTest.gd`. Expected: all pass.

---

### Task 3: Mage-Only Placeholder Assembly

**Files:**
- Modify: `Scenes/ObjectScenes/Mage.tscn`
- Test: `Tests/MageSkillAssemblyTest.gd`

**Interfaces:**
- Consumes the Ally host socket/path and base module scene.
- Produces one correctly mounted placeholder skill instance in Mage only.

- [x] **Step 1: Write the failing assembly test**

Load Mage and assert:

```text
VisualRoot/SkillModuleSocket/SkillModuleBase
```

Verify `skill_module_path` matches the exact node path, owner injection occurs after ready, and the placeholder module can complete a debug delivery when the test supplies an in-range target and clears the shared cooldown gate.

Also load Guardian, Warrior, Ranger, and Healer and assert none has a child under `VisualRoot/SkillModuleSocket`.

- [x] **Step 2: Run RED**

Expected: non-zero exit because Mage has no mounted skill.

- [x] **Step 3: Mount the base module in Mage source scene**

Add the base scene as `VisualRoot/SkillModuleSocket/SkillModuleBase` and set:

```gdscript
skill_module_path = NodePath("VisualRoot/SkillModuleSocket/SkillModuleBase")
```

Do not modify Mage materials, model nodes, formation values, or TestScene.

- [x] **Step 4: Run GREEN**

Run `MageSkillAssemblyTest.gd`. Expected: `MageSkillAssemblyTest: PASS`, exit code `0`.

---

### Task 4: Regression, MCP, and Documentation

**Files:**
- Modify: `Docs/CurrentImplementationSummary.md`
- Modify: this plan with completion results
- Verify only: `Scenes/TestScene.tscn`

**Interfaces:**
- Produces final Godot 4.7 evidence and maintenance notes.

- [x] **Step 1: Run all new and existing combat tests**

Run the three new tests plus the existing ten effect/combat tests. Expected: all pass.

- [x] **Step 2: Run Godot smoke**

```powershell
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' --headless --path 'G:\Godot\SipSip' --quit-after 10
```

Expected: exit code `0`.

- [x] **Step 3: Verify through Godot MCP**

Rescan resources, confirm zero editor errors, inspect Mage source scene assembly, and run only a non-TestScene validation scene/test. Stop all runtime sessions afterward.

- [x] **Step 4: Preserve TestScene**

Compare timestamp, size, and SHA-256 against the pre-implementation baseline. Do not save, restore, or edit TestScene.

- [x] **Step 5: Update documentation**

Record component paths, lifecycle, one-way dependency, shared versus skill cooldown behavior, Mage-only placeholder assembly, deferred automatic AI behavior, test results, MCP result, and unchanged TestScene hash.

---

## Implementation Result (2026-07-15)

- Implemented the independent Profile, module script, base scene, default resource, and complete placeholder delivery lifecycle.
- Added the one-way AllyBase host socket, mount/unmount API, signal forwarding, and shared cooldown activation at cast start.
- Mounted exactly one placeholder module in Mage source; Guardian, Warrior, Ranger, and Healer remain unmounted.
- Added three new TDD contract tests and passed all 13 effect/combat test scripts.
- Updated the stale Ranger test to validate its configurable per-unit cooldown instead of hard-coding `1.0s`; the current user-configured Ranger value remains `2.0s`.
- Godot 4.7 headless smoke exited `0`; MCP resource replacement confirmed Mage has the socket, module, and exact configured path; editor errors were `0`.
- `Scenes/TestScene.tscn` remained unchanged with SHA-256 `179A711803F0C03ECEFC8C91F3807DBC1C5AE64F6F044134E9E9C66AEB643B7E`.
