# Independent Skill System Design

Date: 2026-07-16
Godot target: 4.7

## Objective

Build a complete, independently organized skill-system module under `res://SkillSystem/`. The module provides a reusable skill runtime, a generic host/mediator, a delivery pipeline, and one minimal implementation for every extension point. It must be usable and testable without AllyBase and without modifying any existing skill, character, or TestScene content.

The first version favors a small, coherent skeleton over a wide catalog of behaviors. New skills should normally require Inspector assembly rather than new scripts.

## Scope and Migration Boundary

The new module is developed in parallel with the current skill implementation.

This phase must not modify or reference:

- `Scripts/AI/AllyBase.gd`
- `Scripts/Combat/Skills/SkillModuleBase.gd`
- Existing Fireball or Healing skill scripts, resources, scenes, or effects
- Mage, Healer, or any other character source scene
- `Scenes/TestScene.tscn`

No legacy skill is migrated or deleted. Character integration is a separate future design and implementation phase.

The module may use the public APIs of:

- `ResourcePoolComponent`
- `HealthComponent`
- `FactionComponent`

It otherwise depends only on Godot 4.7 core APIs.

## Architectural Approach

The system uses Scene skeletons for runtime, positional, and visual objects, and Resource strategies for reusable data and behavior.

```text
Actor or future adapter
        -> SkillHostComponent
        -> SkillBase
        -> SkillDefinition and strategy Resources
        -> SkillDeliveryAgent
        -> Trajectory / Collision / ImpactSelector / Payload / Presentation
        -> HealthComponent / FactionComponent / ResourcePoolComponent
```

Reverse dependencies are prohibited. Delivery objects do not read SkillBase internals, Payloads do not control trajectories or cooldowns, and Presentation does not decide gameplay results.

## Module Layout

```text
res://SkillSystem/
├── 01-Core/
│   ├── SkillBase.gd
│   ├── SkillBase.tscn
│   ├── SkillHostComponent.gd
│   ├── SkillHostComponent.tscn
│   ├── SkillDefinition.gd
│   ├── SkillContext.gd
│   └── SkillDeliveryResult.gd
├── 02-Conditions/
│   ├── SkillConditionBase.gd
│   └── AlwaysSkillCondition.gd
├── 03-Targeting/
│   ├── SkillTargetSelectorBase.gd
│   └── ProvidedTargetSelector.gd
├── 04-Decisions/
│   ├── SkillDecisionPolicyBase.gd
│   └── BasicRandomDecisionPolicy.gd
├── 05-Costs/
│   ├── SkillCostBase.gd
│   └── NoSkillCost.gd
├── 07-Delivery/
│   ├── Agents/
│   │   ├── SkillDeliveryAgentBase.gd
│   │   ├── BasicDeliveryAgent.gd
│   │   └── BasicDeliveryAgent.tscn
│   ├── Trajectories/
│   │   ├── SkillTrajectoryBase.gd
│   │   └── DirectTrajectory.gd
│   ├── Collisions/
│   │   ├── SkillCollisionPolicyBase.gd
│   │   └── ArrivalCollisionPolicy.gd
│   └── Impacts/
│       ├── SkillImpactSelectorBase.gd
│       └── DirectImpactSelector.gd
├── 08-Payloads/
│   ├── SkillPayloadBase.gd
│   └── HealthChangePayload.gd
├── 06-Presentation/
│   ├── SkillPresentationBase.gd
│   └── SceneSkillPresentation.gd
├── 09-Presets/
│   └── DefaultSkillDefinition.tres
├── 11-Tests/
│   ├── SkillStrategyContractTest.gd
│   ├── SkillDeliveryPipelineTest.gd
│   ├── SkillBaseRuntimeTest.gd
│   ├── SkillHostComponentTest.gd
│   ├── SkillSystemAssemblyTest.gd
│   └── Fixtures/
│       └── TestCombatant.tscn
├── 10-Docs/
│   ├── 2026-07-16-independent-skill-system-design.md
│   ├── Architecture.md
│   ├── InspectorAssemblyGuide.md
│   └── ExtensionPoints.md
└── README.md
```

All new runtime code, tests, presets, and module-facing documentation live under this directory.

## Core Runtime Data

### SkillContext

`SkillContext` is a per-request `RefCounted` object. No mutable request data is stored in shared Resources.

```gdscript
enum RequestMode {
    MANUAL,
    AI,
    FORCED
}

var request_mode: RequestMode
var caster: Node3D
var host: Node
var requested_target: Node3D
var resolved_target: Node3D
var target_position: Vector3
var cast_origin: Vector3
var delivery_parent: Node
var metadata: Dictionary
```

Request semantics:

- `MANUAL` bypasses AI decision delay.
- `AI` uses the configured decision policy.
- `FORCED` bypasses decision delay and receives selection priority, but cannot bypass conditions, target validation, range, action blocking, global cooldown, or skill cooldown.

### SkillDeliveryResult

`SkillDeliveryResult` is the common result of arrival or collision.

```gdscript
var succeeded: bool
var failure_reason: StringName
var original_target: Node3D
var collision_target: Node3D
var affected_targets: Array[Node3D]
var origin_position: Vector3
var intended_position: Vector3
var impact_position: Vector3
var impact_direction: Vector3
```

The basic direct delivery sets the collision target to the resolved target, the impact position to the snapshotted target position, and the affected target array to the direct target.

## SkillDefinition

`SkillDefinition` is the master per-skill Resource. Its policy Resources are embedded by default so a normal skill maintains one external definition file.

```gdscript
enum TargetRelation {
    ANY,
    SELF,
    FRIENDLY,
    HOSTILE,
    NEUTRAL
}
```

Default fields:

```text
Identity
  skill_id = default_skill
  display_name = Default Skill
  ai_priority = 0

Targeting
  target_relation = ANY
  require_targetable = true

Cast
  cast_range = 5.0
  cast_range_tolerance = 0.25
  cast_time = 0.5
  can_move_while_casting = false

Cooldown
  skill_cooldown = 6.0
  cooldown_on_failed_delivery = false

Policies
  condition
  target_selector
  decision_policy
  cost
  cast_presentation
```

`SELF` compares actor identity. Other relations use the caster and target `FactionComponent` public relationship methods. When `require_targetable` is true, the target FactionComponent must permit targeting. A missing FactionComponent makes any relationship other than `ANY` or direct `SELF` invalid.

## SkillBase

### Scene

```text
SkillBase
├── CastOrigin
├── PresentationRoot
├── DeliverySocket
├── SkillAnimationPlayer
└── SkillAudioPlayer
```

Root Inspector slots:

```gdscript
@export var skill_definition: SkillDefinition
@export var delivery_agent_scene: PackedScene
```

`delivery_agent_scene` is a PackedScene rather than a persistent projectile child. This permits multiple independent delivery instances to coexist after their skills have released the host slot.

Cast range uses horizontal X/Z distance between caster and resolved target, matching the project's top-down movement plane. Height differences do not independently make a target out of range. The Delivery pipeline still uses full 3D transforms and positions.

### State

```gdscript
enum SkillState {
    READY,
    DECISION_WAIT,
    QUEUED,
    CASTING,
    COOLDOWN
}
```

Flow:

```text
READY
  -> resolve target
  -> validate structure, relation, condition, and cost availability
  -> DECISION_WAIT for AI requests only
  -> QUEUED
  -> host waits for range, global cooldown, and action availability
  -> CASTING
  -> final target, condition, cost, and range validation
  -> commit cost
  -> create and launch DeliveryAgent
  -> COOLDOWN after launch is accepted
  -> optionally COOLDOWN after a rejected launch when cooldown_on_failed_delivery is true
  -> READY
```

Delivery impact is independent after launch. A later miss or Payload failure does not undo an accepted cast or cooldown. By default, a missing scene, wrong agent type, invalid delivery parent, or rejected launch prevents skill cooldown. When `cooldown_on_failed_delivery` is explicitly enabled, those terminal launch failures start the configured skill cooldown as a failure penalty. Request rejection and pre-launch target, condition, cost, or range failures never start cooldown.

If a Cost was committed immediately before a DeliveryAgent launch and that launch is rejected, SkillBase calls `refund()` exactly once. The optional failure cooldown does not change this refund rule. Once launch is accepted, the Cost is committed permanently even if the delivery later misses.

### API

```gdscript
func configure_owner(caster: Node3D, host: Node = null) -> void
func request_skill(context: SkillContext) -> bool
func begin_cast() -> bool
func cancel_skill(reason: StringName = &"cancelled") -> void
func reset_skill() -> void
func can_request(context: SkillContext) -> bool
func can_begin_cast() -> bool
func is_target_in_cast_range() -> bool
func is_ready() -> bool
func is_casting() -> bool
func get_state() -> SkillState
func get_current_context() -> SkillContext
func get_cooldown_remaining() -> float
```

Signals:

```gdscript
signal request_accepted(context: SkillContext)
signal decision_wait_started(context: SkillContext, duration: float)
signal skill_queued(context: SkillContext)
signal cast_range_required(context: SkillContext, range: float, tolerance: float)
signal cast_started(context: SkillContext)
signal delivery_launched(context: SkillContext, agent: SkillDeliveryAgentBase)
signal cast_failed(context: SkillContext, reason: StringName)
signal cast_cancelled(context: SkillContext, reason: StringName)
signal cooldown_started(duration: float)
signal cooldown_finished()
```

## SkillHostComponent

### Scene

```text
SkillHostComponent
└── SkillSocket
```

Only direct children of `SkillSocket` are discovered. Internal nodes of a skill cannot be accidentally registered as additional skills.

### Responsibilities

- Register, unregister, and discover multiple skills.
- Inject the caster and delivery parent.
- Maintain one active cast slot.
- Maintain the shared global cooldown.
- Select the highest-priority available skill, with random selection among equal priorities.
- Expose explicit skill and best-skill request entry points.
- Forward approach, facing, and movement-lock requests without moving the actor.
- Release the active slot after successful delivery launch or terminal failure/cancellation.

The host does not know combat state and does not autonomously search the world. An external caller decides when to request AI selection and supplies the suggested target or position.

### API

```gdscript
func configure_owner(caster: Node3D, delivery_parent: Node = null) -> void
func register_skill(skill: SkillBase) -> bool
func unregister_skill(skill: SkillBase) -> bool
func discover_skills() -> void
func request_skill(
    skill_id: StringName,
    target: Node3D = null,
    target_position: Vector3 = Vector3.INF,
    request_mode: SkillContext.RequestMode = SkillContext.RequestMode.MANUAL
) -> bool
func request_best_skill(
    target: Node3D = null,
    target_position: Vector3 = Vector3.INF,
    request_mode: SkillContext.RequestMode = SkillContext.RequestMode.AI
) -> bool
func cancel_active_skill(reason: StringName = &"cancelled") -> void
func set_cast_blocked(blocked: bool) -> void
func start_global_cooldown(duration_override: float = -1.0) -> void
func get_global_cooldown_remaining() -> float
func is_global_cooldown_ready() -> bool
func get_registered_skills() -> Array[SkillBase]
func get_active_skill() -> SkillBase
```

Signals for future adapters:

```gdscript
signal approach_requested(context: SkillContext, cast_range: float, tolerance: float)
signal facing_requested(context: SkillContext)
signal movement_lock_requested(locked: bool)
```

The default global cooldown is `1.0s`. It starts on `cast_started`. External attack systems may call `start_global_cooldown()` and `set_cast_blocked()` without the host referencing an attack-module type.

## Delivery Runtime

### Runtime Parent

`configure_owner()` accepts an optional world parent. If omitted, the host uses `caster.get_tree().current_scene`. Launch fails with `invalid_delivery_parent` when neither is valid.

The DeliveryAgent is added to the world parent before receiving `DeliverySocket.global_transform`. It is not parented to the caster or skill and therefore does not inherit later caster motion.

### Delivery State

```gdscript
enum DeliveryState {
    IDLE,
    TRAVELLING,
    IMPACTED,
    CANCELLED
}
```

API:

```gdscript
func launch(context: SkillContext, origin_transform: Transform3D) -> bool
func cancel_delivery(reason: StringName = &"cancelled") -> void
func get_delivery_state() -> DeliveryState
func get_context() -> SkillContext
```

The BasicDeliveryAgent owns only per-instance timing and transforms. Shared strategy Resources remain stateless.

Inspector slots:

```text
trajectory
collision_policy
impact_selector
payloads[]
launch_presentation
travel_presentation
impact_presentation
```

Flow:

```text
launch
  -> resolve origin and snapshotted destination
  -> start launch/travel Presentation
  -> sample Trajectory each physics frame
  -> ask CollisionPolicy for arrival/collision result
  -> ask ImpactSelector for affected targets
  -> execute Payloads in array order
  -> play impact Presentation
  -> emit result and free the runtime instance
```

A single Payload failure emits diagnostics but does not roll back other Payloads or the skill cooldown.

## Strategy Contracts and Basic Implementations

### Conditions

`SkillConditionBase`:

```gdscript
func evaluate(context: SkillContext) -> bool
func get_failure_reason(context: SkillContext) -> StringName
```

`AlwaysSkillCondition` always succeeds.

### Targeting

`SkillTargetSelectorBase`:

```gdscript
func resolve_target(context: SkillContext) -> bool
func get_failure_reason(context: SkillContext) -> StringName
```

`ProvidedTargetSelector` copies a valid `requested_target` to `resolved_target` and records its current position. It performs no world search.

### Decision

`SkillDecisionPolicyBase`:

```gdscript
func get_decision_delay(
    context: SkillContext,
    random_generator: RandomNumberGenerator
) -> float
```

`BasicRandomDecisionPolicy` defaults to:

```text
normal_delay_min = 0.3
normal_delay_max = 3.0
extra_hesitation_chance = 0.10
extra_hesitation_min = 3.0
extra_hesitation_max = 5.0
```

Only AI requests use this delay. Manual and forced requests use zero.

### Costs

`SkillCostBase`:

```gdscript
func can_pay(context: SkillContext) -> bool
func commit(context: SkillContext) -> bool
func refund(context: SkillContext) -> void
func get_failure_reason(context: SkillContext) -> StringName
```

`NoSkillCost` always permits and commits successfully; refund is a no-op. No mana implementation is included.

### Trajectories

`SkillTrajectoryBase`:

```gdscript
func get_travel_duration(context: SkillContext, origin: Vector3, destination: Vector3) -> float
func sample_transform(
    context: SkillContext,
    origin: Transform3D,
    destination: Vector3,
    progress: float
) -> Transform3D
```

`DirectTrajectory` linearly interpolates to the snapshotted destination. It exports `travel_duration` and `face_travel_direction`. A duration of zero completes immediately and represents instant delivery.

### Collision

`SkillCollisionPolicyBase`:

```gdscript
func evaluate(
    context: SkillContext,
    previous_transform: Transform3D,
    current_transform: Transform3D,
    progress: float
) -> SkillDeliveryResult
```

`ArrivalCollisionPolicy` returns no result before progress reaches one. At arrival it produces a direct successful result, or a failed result if `require_valid_target_on_arrival` is true and the target is invalid. It does not perform a physics query.

### Impact Selection

`SkillImpactSelectorBase`:

```gdscript
func select_targets(context: SkillContext, result: SkillDeliveryResult) -> Array[Node3D]
```

`DirectImpactSelector` selects the valid collision target, falling back to the valid resolved target.

### Payloads

`SkillPayloadBase`:

```gdscript
func apply(context: SkillContext, result: SkillDeliveryResult, target: Node3D) -> bool
```

`HealthChangePayload` exports:

```text
operation = DAMAGE or HEAL
amount = 10.0
health_component_path = HealthComponent
```

Damage calls `apply_damage()` and healing calls `apply_healing()`. Zero actual change from a valid call is not a system failure. A missing component or incompatible interface is a Payload failure. Relationship validation remains the SkillDefinition's responsibility.

### Presentation

`SkillPresentationBase`:

```gdscript
func play(
    parent: Node,
    world_transform: Transform3D,
    context: SkillContext,
    result: SkillDeliveryResult = null
) -> Node
```

`SceneSkillPresentation` exports a PackedScene, `call_play_method`, and `play_method_name`. It instantiates the scene at the requested parent and transform and invokes the configured play method only when available. Effects may contain particles, animation, lighting, and audio. Missing optional Presentation never blocks gameplay.

## Default Runnable Assembly

`DefaultSkillDefinition.tres` embeds:

```text
AlwaysSkillCondition
ProvidedTargetSelector
BasicRandomDecisionPolicy
NoSkillCost
```

`BasicDeliveryAgent.tscn` embeds:

```text
DirectTrajectory
ArrivalCollisionPolicy
DirectImpactSelector
HealthChangePayload(DAMAGE, 10.0)
```

`SkillBase.tscn` references both defaults. A manually supplied valid target with HealthComponent can therefore complete request, cast, instant direct delivery, ten points of damage, and skill cooldown without AllyBase or a custom script.

## Inspector Assembly Rules

| Inspector property | Source folder |
|---|---|
| `SkillBase.skill_definition` | `SkillSystem/09-Presets` or skill-owned `.tres` |
| `SkillBase.delivery_agent_scene` | `SkillSystem/07-Delivery/00-Agents` |
| `SkillDefinition.condition` | `SkillSystem/02-Conditions` |
| `SkillDefinition.target_selector` | `SkillSystem/03-Targeting` |
| `SkillDefinition.decision_policy` | `SkillSystem/04-Decisions` |
| `SkillDefinition.cost` | `SkillSystem/05-Costs` |
| `SkillDefinition.cast_presentation` | `SkillSystem/06-Presentation` |
| `BasicDeliveryAgent.trajectory` | `SkillSystem/07-Delivery/01-Trajectories` |
| `BasicDeliveryAgent.collision_policy` | `SkillSystem/07-Delivery/02-Collisions` |
| `BasicDeliveryAgent.impact_selector` | `SkillSystem/07-Delivery/03-Impacts` |
| `BasicDeliveryAgent.payloads` | `SkillSystem/08-Payloads` |
| Delivery presentation slots | `SkillSystem/06-Presentation` |

A normal new skill maintains one inherited SkillBase scene, one SkillDefinition resource, one inherited BasicDeliveryAgent scene, optional Presentation scenes, and zero new scripts.

## Failure Reasons and Configuration Warnings

Stable request or launch failure reasons:

```text
missing_definition
invalid_owner
missing_target_selector
target_resolution_failed
invalid_target_relation
condition_failed
cost_unavailable
out_of_range
missing_delivery_scene
invalid_delivery_parent
invalid_delivery_agent
delivery_launch_failed
```

Delivery diagnostics:

```text
missing_trajectory
missing_collision_policy
missing_impact_selector
no_valid_impact_target
payload_failed
```

Core scenes implement `_get_configuration_warnings()` for missing definitions, agent scenes, and mandatory strategies. Optional Presentation produces no warning and no failure.

## Documentation Deliverables

- `README.md`: module entry point, directory index, dependency rules, and shortest assembly flow.
- `10-Docs/Architecture.md`: dependency direction, state machines, and runtime responsibilities.
- `10-Docs/InspectorAssemblyGuide.md`: exact drag-and-drop sources, instant/direct configuration, damage/heal configuration, and common mistakes.
- `10-Docs/ExtensionPoints.md`: Base APIs and disciplined steps for new strategy implementations.

All identifiers are English. New code contains detailed Simplified Chinese comments explaining parameters, state, methods, and extension boundaries.

## Validation

Module tests verify:

- Base scripts load and fail safely by default.
- Basic implementations match their Base signatures.
- Per-request context isolation.
- Manual, AI, and forced delay semantics.
- The approved 0.3–3.0 second normal AI delay and 10% extra 3.0–5.0 second hesitation.
- Validation order for condition, target relation, cost, range, and final cast completion.
- Failed delivery launch does not start skill cooldown under the default `cooldown_on_failed_delivery = false` configuration; enabling that property applies the documented failure penalty.
- Accepted delivery starts skill cooldown and releases the host slot immediately.
- Zero-duration instant delivery and positive-duration direct travel.
- Arrival result construction and direct impact selection.
- Damage and healing through HealthComponent.
- Safe failure when HealthComponent is absent.
- Independent global and per-skill cooldowns.
- Cast blocking preserves a queued request while preventing cast start.
- Multi-skill discovery, registration, unregistration, priority, tie selection, and one active slot.
- Optional Presentation does not affect gameplay success.
- World-parented delivery does not inherit later caster motion.
- No reference to AllyBase, legacy SkillModuleBase, legacy Fireball, or legacy HealingSkill exists in the module runtime files.

Final verification runs all module tests, all existing project tests, a Godot 4.7 headless smoke run, and an unchanged TestScene hash check.

## Deferred Scope

- Any character or AllyBase adapter.
- Migration or removal of legacy skills.
- Automatic world queries, nearest-enemy selection, or lowest-health-ally selection.
- Mana and other concrete resource costs.
- ShapeCast physics collision, environment collision, penetration, or collision masks.
- Ballistic, homing, chain, split, or returning trajectories.
- Area, chain, target-origin, ground-origin, or caster-origin impact selectors.
- Buffs, debuffs, attributes, armor, resistance, damage-type formulas, and critical hits.
- Formal production VFX, audio, models, or animations.
- TestScene unit placement or modification.
