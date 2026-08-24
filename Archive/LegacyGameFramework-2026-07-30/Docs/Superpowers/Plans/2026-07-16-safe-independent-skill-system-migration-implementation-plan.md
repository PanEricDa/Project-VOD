# Safe Independent Skill System Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the independent `SkillSystem` the only runtime skill path through a reversible, test-gated migration of HolyLight and Mage Fireball.

**Architecture:** Preserve AllyBase combat perception and movement ownership, add a thin `AllySkillRequestBridge` that submits AI requests to `SkillHostComponent`, and let typed Skill resources own target selection and execution. Build the new path beside the legacy path, enforce mutual exclusion, cut over one source scene at a time, and retain all legacy files as deprecated rollback assets.

**Tech Stack:** Godot 4.7, GDScript, PackedScene/Resource composition, headless SceneTree tests, PowerShell backup and verification.

## Global Constraints

- Never modify or add unit instances in `res://Scenes/TestScene.tscn`.
- Do not delete, move, or rename legacy skill scripts, scenes, Profiles, projectiles, effects, or tests.
- New runtime code uses English identifiers and detailed Simplified Chinese comments.
- New and legacy automatic skill schedulers must never run simultaneously on one unit.
- The workspace is not a Git repository; create an external pre-cutover archive and SHA-256 manifest before source changes.
- Stop after Task 3 for user runtime approval; stop again after Task 5 before removing the legacy Mage instance reference.

---

### Task 0: Baseline and rollback snapshot

**Files:**
- Read: `Scenes/TestScene.tscn`
- Archive externally: `G:/Godot/SipSip_MigrationBackups/2026-07-16-pre-independent-skill-migration.zip`
- Create externally: `G:/Godot/SipSip_MigrationBackups/2026-07-16-pre-independent-skill-migration.sha256.txt`

**Interfaces:**
- Produces: immutable rollback archive, TestScene baseline hash, and green pre-migration test evidence.

- [ ] Run all `SkillSystem/Tests/*.gd` and `Tests/*.gd` with Godot 4.7 headless; stop if any baseline test fails.
- [ ] Record SHA-256 for `Scenes/TestScene.tscn`, `Scenes/ObjectScenes/AllyBase.tscn`, `Scenes/ObjectScenes/Healer.tscn`, `Scenes/ObjectScenes/Mage.tscn`, and `Scripts/AI/AllyBase.gd`.
- [ ] Create the external archive without changing project source files.
- [ ] Run a headless project smoke scan and require no new parser errors.

### Task 1: Generic Ally skill request bridge

**Files:**
- Create: `Scripts/AI/Components/AllySkillRequestBridge.gd`
- Create: `Scenes/Components/AI/AllySkillRequestBridge.tscn`
- Create: `Tests/AllySkillRequestBridgeTest.gd`

**Interfaces:**
- Consumes: `IndependentSkillHostComponent.request_best_skill()`, `cancel_active_skill()`, and Host intent signals.
- Produces:
  - `set_combat_context(active: bool, preferred_target: Node3D) -> void`
  - `clear_combat_context() -> void`
  - `is_requesting_enabled() -> bool`
  - `has_approach_request() -> bool`
  - `get_approach_target() -> Node3D`
  - `get_approach_range() -> float`
  - `get_approach_tolerance() -> float`
  - `get_facing_target() -> Node3D`
  - `is_movement_locked() -> bool`

- [ ] Write a failing test covering default disabled state, request interval, combat-only/out-of-combat modes, preferred target forwarding, no-valid-skill safety, Host intent caching, active-skill release, combat-exit cancellation, and node-exit cleanup.
- [ ] Run `Tests/AllySkillRequestBridgeTest.gd`; verify RED because the component does not exist.
- [ ] Implement the minimal bridge. It may call Host APIs but must not access AllyBase fields or write CharacterBody3D velocity.
- [ ] Run the bridge test and all `SkillSystem/Tests`; require PASS and no ERROR/WARNING.

### Task 2: Safe AllyBase integration and movement arbitration

**Files:**
- Modify: `Scenes/ObjectScenes/AllyBase.tscn`
- Modify: `Scripts/AI/AllyBase.gd`
- Modify: `Tests/AllyIndependentSkillHostAssemblyTest.gd`
- Create: `Tests/AllyIndependentSkillMovementTest.gd`

**Interfaces:**
- Consumes: Task 1 bridge intent getters.
- Produces: AllyBase initialization, context feed, approach movement, facing, movement lock, and explicit legacy/new scheduler mutual exclusion.

- [ ] Add failing assembly assertions for an inherited, disabled-by-default bridge and a valid Host path.
- [ ] Add a failing movement test showing an out-of-range independent skill owns horizontal movement until it enters cast range, casting lock stops horizontal motion without disabling gravity, and combat exit releases intent.
- [ ] Run both tests and verify RED for missing bridge assembly/consumption.
- [ ] Instance the bridge as a direct AllyBase child and export `skill_request_bridge_path` plus `legacy_skill_scheduler_enabled`.
- [ ] Resolve the bridge during `_ready()`, feed combat state and `current_visible_enemy`, and synchronize `basic_attack_global_cooldown` into Host configuration.
- [ ] Process Host intent before formation/combat horizontal movement. Keep gravity, visual facing, and `move_and_slide()` on the existing common path.
- [ ] Run Ally movement, attack, scheduler, formation, and Host integration tests; require unchanged legacy behavior while the bridge is disabled.

### Task 3: HolyLight automatic request cut-in

**Files:**
- Modify: `Scenes/ObjectScenes/Healer.tscn`
- Modify: `SkillSystem/00-Skills/HolyLight/HolyLightSkillDefinition.tres` only if explicit defaults are needed
- Create: `Tests/HealerHolyLightAutoSkillTest.gd`
- Modify: `SkillSystem/Docs/InspectorAssemblyGuide.md`

**Interfaces:**
- Consumes: nearest-valid FRIENDLY selector, bridge out-of-combat request mode, and inherited Host.
- Produces: Healer automatically requests HolyLight when another friendly target is inside cast range.

- [ ] Write a failing integration test proving Healer can cast outside combat when another friendly is within range, excludes itself, safely does nothing without a valid friend, respects Host/global and skill cooldowns, and does not activate the legacy scheduler.
- [ ] Run the test and verify RED because the Healer bridge override is not enabled.
- [ ] In `Healer.tscn`, enable the inherited bridge, set `request_while_out_of_combat = true`, and leave `legacy_skill_scheduler_enabled = true` because Healer has no registered legacy skill; mutual exclusion is still enforced by the empty legacy registry.
- [ ] Document the Inspector assembly and distinction between AI trigger, TargetSelector, Host, and Skill execution.
- [ ] Run every SkillSystem and project test, run smoke scan, and compare the current TestScene SHA-256 to Task 0.
- [ ] **USER GATE:** Stop and ask the user to run the existing TestScene and approve HolyLight target choice, cadence, movement interaction, and visual result.

### Task 4: New-system Fireball parity implementation

**Files:**
- Create: `SkillSystem/00-Skills/Fireball/FireballSkill.tscn`
- Create: `SkillSystem/00-Skills/Fireball/FireballSkillDefinition.tres`
- Create: `SkillSystem/00-Skills/Fireball/FireballDelivery.tscn`
- Create: `SkillSystem/00-Skills/Fireball/FireballDeliveryAgent.gd`
- Create: `Tests/IndependentFireballSkillTest.gd`

**Interfaces:**
- Consumes: existing Fireball projectile `launch()` contract and visual scenes; `ProvidedTargetSelector`; Host delivery parent.
- Produces: independent hostile Fireball with the existing gameplay parameters and visuals.

- [ ] Characterize the old Fireball parameters and launch contract in a failing new-system parity test.
- [ ] Verify RED for missing independent Fireball resources.
- [ ] Assemble a typed hostile Skill Definition with 6m range, 0.25m tolerance, 0.75s cast, 5s skill cooldown, 0.3–3s decision delay, 10% extra hesitation, and 3–5s extra delay.
- [ ] Implement a delivery adapter that reuses the existing projectile and effects without moving or modifying those assets.
- [ ] Verify origin, target forwarding, launch, delivery failure semantics, successful cooldown, projectile tracking, impact, and explosion signals.
- [ ] Run old and new Fireball tests together; require both paths to pass.

### Task 5: Mage dual-mounted exclusive cutover

**Files:**
- Modify: `Scenes/ObjectScenes/Mage.tscn`
- Modify: `Tests/MageSkillAssemblyTest.gd`
- Create: `Tests/MageIndependentSkillCutoverTest.gd`

**Interfaces:**
- Consumes: Task 4 Fireball and inherited bridge.
- Produces: new Fireball runtime path with legacy Fireball retained but disabled for rollback.

- [ ] Add failing scene assertions for the new Fireball under `SkillHostComponent/SkillSocket`, bridge enabled, and legacy scheduler disabled.
- [ ] Preserve the old Fireball node and `skill_module_path`, but set `legacy_skill_scheduler_enabled = false`; enable the bridge so only the new path can request.
- [ ] Verify enemy reuse, random delay, range approach, facing, cast lock, projectile delivery, shared cooldown, disengage, re-entry, and zero duplicate projectile launches.
- [ ] Run all tests and smoke scan; compare TestScene SHA-256 to Task 0.
- [ ] **USER GATE:** Stop and ask the user to approve Mage Fireball in the existing TestScene before removing any legacy scene reference.

### Task 6: Runtime zero-reference deprecation state

**Files:**
- Modify: `Scenes/ObjectScenes/Mage.tscn`
- Modify: legacy documentation headers only where safe
- Create: `Docs/Migrations/2026-07-16-legacy-skill-system-deprecation.md`
- Modify: relevant assembly tests

**Interfaces:**
- Produces: no runtime scene reference to legacy SkillModule scenes while all legacy files remain available.

- [ ] After Task 5 user approval, remove only the old Fireball instance and path override from the Mage source scene.
- [ ] Scan runtime scenes and non-deprecated runtime scripts for legacy references; tests and deprecated files are allowed to retain references.
- [ ] Record rollback assets, old-to-new mappings, observation checklist, and explicit prohibition on physical deletion.
- [ ] Run the full test suite and smoke scan; compare TestScene SHA-256 to Task 0.

### Task 7: Observation and separate cleanup decision

**Files:**
- Update: `Docs/Migrations/2026-07-16-legacy-skill-system-deprecation.md`

**Interfaces:**
- Produces: evidence for a future, separately approved physical-cleanup plan.

- [ ] Observe HolyLight and Fireball for repeated requests, stuck active slots, cooldown drift, stale movement ownership, disengage/re-engage, scene reload, and unit removal.
- [ ] Record user acceptance or defects without deleting any legacy assets.
- [ ] If accepted, create a separate cleanup proposal; do not remove legacy files under this plan.

