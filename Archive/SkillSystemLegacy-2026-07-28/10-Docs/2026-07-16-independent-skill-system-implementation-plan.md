# Independent Skill System Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Build the approved independent, Inspector-composable skill runtime under `res://SkillSystem/` with a generic host, a unified delivery pipeline, and one basic implementation per extension point.

**Architecture:** Runtime and positional behavior use Scene/Node skeletons; reusable policies use stateless Resource strategies. SkillBase owns request, cast, and skill cooldown; SkillHostComponent owns registration, one active slot, and global cooldown; world-parented DeliveryAgents own trajectory, arrival/collision, impact selection, Payload execution, and delivery Presentation.

**Tech Stack:** Godot 4.7, typed GDScript, Resource composition, PackedScene runtime instances, SceneTree headless tests.

## Global Constraints

- Create runtime, presets, tests, and module documentation only under `res://SkillSystem/`.
- Do not modify or reference AllyBase, legacy SkillModuleBase, legacy Fireball, legacy HealingSkill, character scenes, or TestScene.
- The only project-specific runtime dependencies permitted are public methods on `ResourcePoolComponent`, `HealthComponent`, and `FactionComponent`.
- All identifiers are English; new code has detailed Simplified Chinese comments for fields, parameters, states, methods, and extension boundaries.
- First version supplies one Base and one basic implementation per strategy family; no additional variants are added.
- Skill cooldown starts after an accepted Delivery launch, except the explicit `cooldown_on_failed_delivery` failure-penalty option.
- Delivery launch rejection refunds a committed Cost exactly once; accepted launch permanently commits the Cost.
- Project is not a Git repository, so each task records test evidence instead of creating commits.

---

## File Map

The authoritative file map is the tree in `SkillSystem/10-Docs/2026-07-16-independent-skill-system-design.md`. No runtime file may be created outside that map.

### Task 0: Baseline and protected-file snapshot

**Files:**
- Read only: existing project tests and protected legacy files.

- [x] **Step 1: Capture protected-file integrity before runtime implementation**

Record length, UTC write time, and SHA-256 in a temporary verification record for:

```text
Scripts/AI/AllyBase.gd
Scripts/Combat/Skills/SkillModuleBase.gd
Scripts/Combat/Skills/FireballSkill.gd
Scenes/Components/SkillModules/SkillModuleBase.tscn
Scenes/Components/SkillModules/FireballSkill.tscn
Scenes/Components/SkillModules/HealingSkill.tscn
Scenes/ObjectScenes/Mage.tscn
Scenes/ObjectScenes/Healer.tscn
Scenes/TestScene.tscn
```

- [x] **Step 2: Run the existing 21-test baseline**

Run every top-level `Tests/*.gd` and require exit code 0 for all tests. Record the existing Warrior warning output separately so it is not attributed to SkillSystem.

### Task 1: Core data objects and strategy contracts

**Files:**
- Create: `SkillSystem/11-Tests/SkillStrategyContractTest.gd`
- Create: `SkillSystem/11-Tests/Fixtures/TestCombatant.tscn`
- Create: `SkillSystem/01-Core/SkillContext.gd`
- Create: `SkillSystem/01-Core/SkillDeliveryResult.gd`
- Create: `SkillSystem/02-Conditions/SkillConditionBase.gd`
- Create: `SkillSystem/02-Conditions/AlwaysSkillCondition.gd`
- Create: `SkillSystem/03-Targeting/SkillTargetSelectorBase.gd`
- Create: `SkillSystem/03-Targeting/ProvidedTargetSelector.gd`
- Create: `SkillSystem/04-Decisions/SkillDecisionPolicyBase.gd`
- Create: `SkillSystem/04-Decisions/BasicRandomDecisionPolicy.gd`
- Create: `SkillSystem/05-Costs/SkillCostBase.gd`
- Create: `SkillSystem/05-Costs/NoSkillCost.gd`
- Create: `SkillSystem/06-Presentation/SkillPresentationBase.gd`
- Create: `SkillSystem/06-Presentation/SceneSkillPresentation.gd`

**Interfaces:**
- Produces the exact Context, Result, Condition, Target, Decision, Cost, and Presentation signatures in the approved design.
- `TestCombatant.tscn` is a Node3D with existing `HealthComponent.tscn` and `FactionComponent.tscn` children; faction defaults to `test`, team 1, targetable true.

- [x] **Step 1: Write the path-first strategy contract test**

The test must dynamically check all Task 1 paths before loading them, then verify:

```gdscript
var context_a: RefCounted = context_script.new()
var context_b: RefCounted = context_script.new()
context_a.set("metadata", {"request": "a"})
assert(context_b.get("metadata").is_empty())

assert(always_condition.call("evaluate", context_a))
assert(not base_condition.call("evaluate", context_a))

context_a.set("requested_target", target)
assert(provided_selector.call("resolve_target", context_a))
assert(context_a.get("resolved_target") == target)

context_a.set("request_mode", 1) # AI
var delay: float = random_policy.call("get_decision_delay", context_a, seeded_rng)
assert(delay >= 0.3 and delay <= 8.0)

assert(no_cost.call("can_pay", context_a))
assert(no_cost.call("commit", context_a))
```

Force deterministic random samples to verify normal bounds, forced extra-hesitation bounds, and zero delay for MANUAL/FORCED. Verify `SceneSkillPresentation` safely returns null when no effect scene is configured.

- [x] **Step 2: Run RED**

```powershell
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' --headless --path 'G:\Godot\SipSip' --script res://SkillSystem/11-Tests/SkillStrategyContractTest.gd
```

Expected: exit 1 with missing Task 1 resources, not a parser error in the test.

- [x] **Step 3: Implement the per-request data objects**

`SkillContext.gd` is a RefCounted with the approved RequestMode enum and independent default metadata dictionary. Add `duplicate_context()` that creates a new context, copies scalar/node references, and duplicates metadata so tests and selectors never share a mutable dictionary.

`SkillDeliveryResult.gd` is a RefCounted with the approved fields and empty affected-target array per instance.

- [x] **Step 4: Implement Base Resources with safe defaults**

Base behavior is explicit and non-successful unless absence is inherently safe:

```gdscript
# SkillConditionBase
func evaluate(_context: SkillContextType) -> bool: return false
func get_failure_reason(_context: SkillContextType) -> StringName: return &"condition_not_implemented"

# SkillTargetSelectorBase
func resolve_target(_context: SkillContextType) -> bool: return false
func get_failure_reason(_context: SkillContextType) -> StringName: return &"target_selector_not_implemented"

# SkillDecisionPolicyBase
func get_decision_delay(_context: SkillContextType, _rng: RandomNumberGenerator) -> float: return 0.0

# SkillCostBase
func can_pay(_context: SkillContextType) -> bool: return false
func commit(_context: SkillContextType) -> bool: return false
func refund(_context: SkillContextType) -> void: pass
func get_failure_reason(_context: SkillContextType) -> StringName: return &"cost_not_implemented"

# SkillPresentationBase
func play(_parent: Node, _transform: Transform3D, _context: SkillContextType, _result: SkillDeliveryResultType = null) -> Node: return null
```

Use path preloads for cross-module parameter types so headless loading does not depend on editor class-cache timing.

- [x] **Step 5: Implement the basic strategies**

- `AlwaysSkillCondition`: true and empty failure reason.
- `ProvidedTargetSelector`: validates an inside-tree requested Node3D, writes resolved target and global position, otherwise `target_resolution_failed`.
- `BasicRandomDecisionPolicy`: exports approved bounds/chance, uses the supplied RNG, and returns zero for MANUAL/FORCED.
- `NoSkillCost`: can-pay and commit true, refund no-op, empty reason.
- `SceneSkillPresentation`: validates parent and PackedScene, instantiates it, applies world transform when Node3D, adds it to parent, and conditionally calls configured `play_method_name`.

- [x] **Step 6: Create the test fixture and run GREEN**

Create the fixture using the existing project component PackedScenes without modifying those sources. Run the Task 1 command and expect `SkillStrategyContractTest: PASS`, exit 0.

### Task 2: Unified Delivery pipeline

**Files:**
- Create: `SkillSystem/11-Tests/SkillDeliveryPipelineTest.gd`
- Create: `SkillSystem/07-Delivery/01-Trajectories/SkillTrajectoryBase.gd`
- Create: `SkillSystem/07-Delivery/01-Trajectories/DirectTrajectory.gd`
- Create: `SkillSystem/07-Delivery/02-Collisions/SkillCollisionPolicyBase.gd`
- Create: `SkillSystem/07-Delivery/02-Collisions/ArrivalCollisionPolicy.gd`
- Create: `SkillSystem/07-Delivery/03-Impacts/SkillImpactSelectorBase.gd`
- Create: `SkillSystem/07-Delivery/03-Impacts/DirectImpactSelector.gd`
- Create: `SkillSystem/08-Payloads/SkillPayloadBase.gd`
- Create: `SkillSystem/08-Payloads/HealthChangePayload.gd`
- Create: `SkillSystem/07-Delivery/00-Agents/SkillDeliveryAgentBase.gd`
- Create: `SkillSystem/07-Delivery/00-Agents/BasicDeliveryAgent.gd`
- Create: `SkillSystem/07-Delivery/00-Agents/BasicDeliveryAgent.tscn`

**Interfaces:**
- Consumes Task 1 Context, Result, and Presentation.
- Produces `launch(context, origin_transform) -> bool`, delivery states/signals, and the default instant/direct ten-damage agent scene.

- [x] **Step 1: Write the failing Delivery pipeline test**

Test both an in-memory strategy assembly and `BasicDeliveryAgent.tscn`:

```gdscript
trajectory.set("travel_duration", 0.0)
assert(agent.call("launch", context, origin))
await process_frame
assert(target_health.call("get_current_value") == 90.0)

trajectory.set("travel_duration", 0.1)
assert(agent.call("launch", context, origin))
assert(agent.call("get_delivery_state") == TRAVELLING)
await create_timer(0.15).timeout
assert(agent.global_position.is_equal_approx(snapshot_destination))
```

Also verify base strategies fail safely, invalid/missing target handling, direct target selection, HEAL restoring health, missing HealthComponent emitting Payload failure without crash, payload array order, and moving the caster after launch not moving the world-parented agent.

- [x] **Step 2: Run RED**

Run the Delivery test explicitly. Expected: exit 1 due to missing Delivery resources.

- [x] **Step 3: Implement trajectory, collision, impact, and payload contracts**

Use the exact signatures from the design. Base trajectory returns zero duration and the origin transform; base collision returns null; base impact returns an empty typed Node3D array; base Payload returns false.

`DirectTrajectory` clamps duration to nonnegative, linearly interpolates origin to destination, and optionally faces horizontal or full 3D travel direction without producing invalid basis for a zero vector.

`ArrivalCollisionPolicy` returns null before progress 1. At arrival it returns a populated Result. With `require_valid_target_on_arrival`, an invalid resolved target produces `succeeded = false` and `failure_reason = invalid_target_on_arrival`.

`DirectImpactSelector` returns one valid collision target or fallback resolved target.

`HealthChangePayload` finds the configured child path, checks the expected method, calls damage or healing with `context.caster` as source, and treats a valid zero-effect call as successful.

- [x] **Step 4: Implement DeliveryAgentBase**

The Base owns state, context, and public signals but refuses launch with `delivery_agent_not_implemented`. It exposes:

```gdscript
signal delivery_started(context)
signal delivery_impacted(context, result)
signal payload_applied(context, result, target, payload)
signal payload_failed(context, result, target, payload)
signal delivery_failed(context, reason)
signal delivery_finished(context, result)
```

Cancellation sets CANCELLED, emits failure/finished once, and queues the runtime instance for deletion.

- [x] **Step 5: Implement BasicDeliveryAgent and default scene**

Validate mandatory strategy slots in `launch()`. Snapshot the resolved target position, start optional launch/travel Presentation, and process zero duration synchronously without dividing by zero. Positive duration advances in `_physics_process`, samples DirectTrajectory, and asks CollisionPolicy for a result each frame.

On a successful result, select targets, execute all Payloads in array order, record affected targets, play Impact Presentation, emit result signals, and queue-free. A failed collision result emits delivery failure and finishes safely. Missing optional Presentation is ignored.

`BasicDeliveryAgent.tscn` embeds DirectTrajectory with duration 0, ArrivalCollisionPolicy, DirectImpactSelector, and HealthChangePayload DAMAGE 10.

- [x] **Step 6: Run GREEN**

Expected: `SkillDeliveryPipelineTest: PASS`, exit 0, no warning/error output.

### Task 3: SkillDefinition and SkillBase runtime

**Files:**
- Create: `SkillSystem/11-Tests/SkillBaseRuntimeTest.gd`
- Create: `SkillSystem/01-Core/SkillDefinition.gd`
- Create: `SkillSystem/01-Core/SkillBase.gd`
- Create: `SkillSystem/01-Core/SkillBase.tscn`
- Create: `SkillSystem/09-Presets/DefaultSkillDefinition.tres`

**Interfaces:**
- Consumes Task 1 strategies and Task 2 DeliveryAgent scene.
- Produces the approved skill state machine, public API, signals, target relation validation, range validation, cost refund, and skill-local cooldown.

- [x] **Step 1: Write the failing SkillBase runtime test**

Cover:

- Exact scene nodes and public methods/signals.
- Default preset fields and embedded strategy types.
- Context isolation across sequential requests.
- MANUAL immediate queue; AI decision wait; FORCED immediate queue.
- Horizontal X/Z range ignoring height.
- SELF, FRIENDLY, HOSTILE, NEUTRAL, ANY, and targetable validation using fixture FactionComponents.
- Final validation after target movement.
- Delivery scene missing/wrong type/rejected launch.
- Accepted launch starts skill cooldown.
- Default failed launch does not start cooldown.
- `cooldown_on_failed_delivery = true` starts failure cooldown.
- Cost commit occurs once, rejected launch refunds once, accepted launch does not refund.
- Cancel/reset cleanup and optional cast Presentation.

- [x] **Step 2: Run RED**

Expected: exit 1 due to missing Definition/Base resources.

- [x] **Step 3: Implement SkillDefinition and default preset**

Use the exact exported categories and defaults from the design. Strategy fields are typed Resource references using path preloads. Add a TargetRelation enum with exact order `ANY, SELF, FRIENDLY, HOSTILE, NEUTRAL`.

The preset embeds AlwaysCondition, ProvidedTargetSelector, BasicRandomDecisionPolicy, and NoSkillCost.

- [x] **Step 4: Implement SkillBase validation and lifecycle**

Use a private RNG per SkillBase. `request_skill()` duplicates the incoming Context, injects configured caster/host, resolves target, then validates relation, condition, and `can_pay`. AI starts decision wait; other modes queue immediately.

`begin_cast()` requires QUEUED and performs range/structural checks. During CASTING update the timer; at completion revalidate target, relation, condition, cost, and horizontal range, commit cost, instantiate the configured PackedScene under `context.delivery_parent`, verify it derives from DeliveryAgentBase, and launch it with `DeliverySocket.global_transform`.

If launch fails, call `refund()` exactly once and apply the optional failure cooldown. If accepted, emit `delivery_launched`, clear request data, and start skill cooldown. Do not wait for impact.

All exit paths restore RESET animation when available. Missing optional cast animation or Presentation remains safe.

- [x] **Step 5: Create SkillBase.tscn**

Create exact nodes `CastOrigin`, `PresentationRoot`, `DeliverySocket`, `SkillAnimationPlayer`, and `SkillAudioPlayer`. Assign DefaultSkillDefinition and BasicDeliveryAgent PackedScene. Include empty `RESET` and `cast` animations.

- [x] **Step 6: Run GREEN**

Expected: `SkillBaseRuntimeTest: PASS`, exit 0.

### Task 4: Generic SkillHostComponent mediator

**Files:**
- Create: `SkillSystem/11-Tests/SkillHostComponentTest.gd`
- Create: `SkillSystem/01-Core/SkillHostComponent.gd`
- Create: `SkillSystem/01-Core/SkillHostComponent.tscn`

**Interfaces:**
- Consumes Task 3 SkillBase API/signals.
- Produces skill discovery/registration, explicit and best-skill requests, active-slot ownership, global cooldown, cast blocking, and adapter request signals.

- [x] **Step 1: Write the failing Host test**

Verify:

```gdscript
host.call("configure_owner", caster, root)
assert(host.call("register_skill", skill_a))
assert(not host.call("register_skill", skill_a))
assert(host.call("request_skill", &"skill_a", target))
assert(host.call("get_active_skill") == skill_a)
```

Also cover direct-child socket discovery, unregister cleanup, highest-priority choice, deterministic random tie selection, FORCED selection priority, one active slot, out-of-range `approach_requested`, `facing_requested`, movement lock/unlock, global cooldown start on cast start, external `start_global_cooldown`, `set_cast_blocked` preserving QUEUED state, release on delivery launch/failure/cancel, and delivery-parent injection.

- [x] **Step 2: Run RED**

Expected: exit 1 due to missing Host resources.

- [x] **Step 3: Implement registration and context creation**

The scene root is Node with a direct `SkillSocket` child. Discovery scans direct children only. Register connects only approved SkillBase signals and injects caster/host. Unregister cancels, disconnects, resets, clears owner, and releases active slot without changing global cooldown.

Request APIs create a fresh SkillContext, set mode/target/position/host/caster/delivery parent, and delegate to a selected skill. `request_best_skill()` filters requestable skills and selects highest `ai_priority`; equal priorities use the host RNG. FORCED requests consider only otherwise valid skills and bypass delay, not validation/cooldown.

- [x] **Step 4: Implement scheduling and adapter signals**

In `_physics_process`, decrement global cooldown. For an active QUEUED skill:

- Emit facing request when target valid.
- If out of range, emit approach request and leave queued.
- If in range but blocked/global cooldown active, leave queued.
- Otherwise call `begin_cast()`.

For CASTING, emit facing each frame and movement lock true when movement is disallowed. On `cast_started`, start global cooldown. On delivery launch, release the active slot and unlock movement. Terminal failure/cancel also releases/unlocks. Never move or rotate the caster directly.

- [x] **Step 5: Create Host scene and run GREEN**

Expected: `SkillHostComponentTest: PASS`, exit 0.

### Task 5: Default end-to-end assembly and module documentation

**Files:**
- Create: `SkillSystem/11-Tests/SkillSystemAssemblyTest.gd`
- Create: `SkillSystem/README.md`
- Create: `SkillSystem/10-Docs/Architecture.md`
- Create: `SkillSystem/10-Docs/InspectorAssemblyGuide.md`
- Create: `SkillSystem/10-Docs/ExtensionPoints.md`

**Interfaces:**
- Consumes all earlier tasks.
- Produces a self-explanatory, default runnable module and documentation matching the approved folder-to-Inspector mapping.

- [x] **Step 1: Write the failing end-to-end assembly test**

Instantiate TestCombatant caster/target, Host, and default SkillBase without custom scripts. Register skill, manually request target, await cast and instant delivery, and assert target health changes from 100 to 90 and skill cooldown begins.

Repeat with an inherited/duplicated BasicDeliveryAgent configured with HealthChangePayload HEAL and assert healing. Confirm the Delivery runtime is parented under the supplied world root. Recursively scan runtime `.gd`, `.tscn`, and `.tres` files under SkillSystem excluding Docs/Tests and reject references to legacy paths/names.

- [x] **Step 2: Run RED for missing documentation/assembly guarantees**

Expected: test fails on missing documentation resources or any incomplete default assembly contract.

- [x] **Step 3: Complete the documentation**

Write:

- README: purpose, quick start, directory table, dependencies, non-dependencies.
- Architecture: exact Host/Skill/Delivery state flow and runtime-parent rule.
- InspectorAssemblyGuide: exact folder/property table, direct instant damage example, direct timed damage example, and instant healing example.
- ExtensionPoints: every Base signature and the rule that new trajectory/collision/impact/payload behavior is added by subclassing its own Base rather than modifying SkillBase.

- [x] **Step 4: Run GREEN**

Expected: `SkillSystemAssemblyTest: PASS`, exit 0.

### Task 6: Complete regression and independence verification

**Files:**
- Modify only checkbox/result sections in this plan after evidence is observed.
- Do not modify any file outside `SkillSystem/`.

- [x] **Step 1: Run every independent module test**

```powershell
$godot = 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe'
Get-ChildItem 'G:\Godot\SipSip\SkillSystem\Tests' -Filter '*.gd' | Sort-Object Name | ForEach-Object {
    & $godot --headless --path 'G:\Godot\SipSip' --script ('res://SkillSystem/11-Tests/' + $_.Name)
    if ($LASTEXITCODE -ne 0) { throw "Module test failed: $($_.Name)" }
}
```

Expected: five module tests pass, zero fail.

- [x] **Step 2: Run every existing project test**

Run all top-level `Tests/*.gd`. Expected: all current 21 pass. Preserve the known Warrior test warning baseline; no new warning may originate from SkillSystem.

- [x] **Step 3: Run Godot smoke validation**

```powershell
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' --headless --path 'G:\Godot\SipSip' --quit-after 10
```

Expected: exit 0 with no SkillSystem parser/runtime warning or error.

- [x] **Step 4: Recheck protected files and module boundary**

Expected: all protected hashes, lengths, and timestamps match the pre-implementation snapshot. Confirm all new runtime files are under `SkillSystem/` and runtime-file scans contain no legacy dependency.

- [x] **Step 5: Update plan results**

Record RED/GREEN evidence per task, module-test count, existing-test count, smoke result, known pre-existing warnings, and protected-file hashes. Mark a checkbox complete only after its verification command succeeds.

## Implementation Results

- Task 1 RED: thirteen core/strategy resources were absent. GREEN: `SkillStrategyContractTest: PASS`.
- Task 2 RED: eleven Delivery resources were absent. GREEN: `SkillDeliveryPipelineTest: PASS`.
- Task 3 RED: SkillDefinition, SkillBase scene/script, and preset were absent. GREEN: `SkillBaseRuntimeTest: PASS`.
- Task 4 RED: SkillHostComponent scene/script were absent. GREEN: `SkillHostComponentTest: PASS`.
- Task 5 RED: four module-facing documentation files were absent. GREEN: `SkillSystemAssemblyTest: PASS`.
- Final independent module suite: 5 passed, 0 failed, 0 warning/error lines.
- Existing project suite: 21 passed, 0 failed. Two pre-existing AISwordAttack warning emissions remain in `WarriorSwordAttackTest` and match the baseline.
- Godot 4.7 headless smoke: exit code 0, 0 warning/error lines.
- Protected legacy files changed: 0 of 9.
- TestScene SHA-256 remained `D1E28252C9C7E0D52DFEC06A302193B9531B75D8EF17AC91C617C7B668BA6509`.
