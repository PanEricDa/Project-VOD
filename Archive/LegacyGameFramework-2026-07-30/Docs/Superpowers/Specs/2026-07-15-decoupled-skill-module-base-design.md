# Decoupled Skill Module Base Design

Date: 2026-07-15

## Objective

Create a complete, independently testable `SkillModuleBase` component and expand `AllyBase` only as a one-way host adapter. The first phase does not create a real class skill, projectile, AOE, healing result, or damage result. Instead, the base module performs its complete request, decision, queue, cast, delivery, and cooldown lifecycle; the default delivery implementation prints structured debug output and emits the same signals that future child modules will use.

## Dependency Boundary

The dependency direction is strictly:

```text
AllyBase -> SkillModuleBase public API
SkillModuleBase -X-> AllyBase
```

`SkillModuleBase` accepts a generic `Node3D` owner and target. It must not read `AllyBase` fields, call Ally movement methods, inspect its combat states, or know about basic attacks. This allows the same component to be hosted later by allies, enemies, players, summons, or test doubles.

`AllyBase` may reference the generic skill type because it is the host. It only handles mounting, unmounting, signal forwarding, public request methods, and shared combat cooldown activation.

## Phase-One Scope

Included:

- Reusable skill Profile resource.
- Independent `SkillModuleBase.tscn` and script.
- Complete skill-local lifecycle and timing.
- Generic owner and target injection.
- Target position and range validation.
- Normal and rare extended decision delay.
- Cast cancellation, failure, reset, and skill cooldown.
- Placeholder delivery that logs success and emits production-facing signals.
- `AllyBase` skill socket, exported module path, mounting API, signal connections, signal forwarding, and shared cooldown integration.
- Automated tests for the module and Ally host adapter.

Excluded:

- Automatic AI timing and target selection.
- Character movement into cast range.
- Concrete Warrior, Guardian, Ranger, Mage, or Healer skills.
- Projectile, ground AOE, healing, damage, hit detection, status effects, and visual effects.
- Changes to unit instances in `TestScene.tscn`.

## Resources and Scene Structure

Planned files:

```text
Scripts/Combat/Skills/SkillProfile.gd
Scripts/Combat/Skills/SkillModuleBase.gd
Scenes/Components/SkillModules/SkillModuleBase.tscn
Resources/Combat/Skills/DefaultSkillProfile.tres
Tests/SkillModuleBaseTest.gd
Tests/AllySkillModuleHostTest.gd
```

Base scene:

```text
SkillModuleBase
├── CastOrigin
├── DeliveryRoot
└── SkillAnimationPlayer
```

`AllyBase.tscn` gains a generic socket without a skill instance:

```text
AllyBase
└── VisualRoot
    ├── AttackModuleSocket
    └── SkillModuleSocket
```

No skill is automatically added to Guardian, Warrior, Ranger, Mage, Healer, or TestScene in this phase.

## Profile Data

`SkillProfile` stores static skill-level configuration:

```gdscript
@export var display_name: String = "Skill"
@export var target_faction: SkillTargetFaction = SkillTargetFaction.ENEMY
@export var delivery_type: SkillDeliveryType = SkillDeliveryType.PROJECTILE
@export var required_target_group: StringName = &""

@export_range(0.0, 50.0, 0.1) var cast_range: float = 5.0
@export_range(0.0, 5.0, 0.05) var cast_range_tolerance: float = 0.25
@export_range(0.0, 10.0, 0.05) var cast_time: float = 0.5
@export_range(0.0, 120.0, 0.1) var skill_cooldown: float = 6.0

@export_range(0.0, 10.0, 0.1) var decision_delay_min: float = 0.3
@export_range(0.0, 10.0, 0.1) var decision_delay_max: float = 3.0
@export_range(0.0, 1.0, 0.01) var extra_hesitation_chance: float = 0.10
@export_range(0.0, 10.0, 0.1) var extra_hesitation_min: float = 3.0
@export_range(0.0, 10.0, 0.1) var extra_hesitation_max: float = 5.0
```

The faction and delivery enums are metadata and validation aids. The base does not branch into concrete projectile, AOE, or healing behavior. `required_target_group` is optional: an empty value performs only structural target validation; a non-empty value requires group membership. This avoids hard-coding an ally group that the current project does not yet define.

## Skill State Machine

```gdscript
enum SkillState {
    READY,
    DECISION_WAIT,
    QUEUED,
    CASTING,
    COOLDOWN
}
```

State flow:

```text
READY
  -> request_skill(valid target)
DECISION_WAIT
  -> normal 0.3-3.0s delay
  -> 10% chance appends 3.0-5.0s hesitation
QUEUED
  -> external host calls begin_cast() when movement/action/GCD conditions allow
CASTING
  -> cast_time completes and delivery succeeds
COOLDOWN
  -> skill_cooldown reaches zero
READY
```

The normal delay is selected first. The 10% extra hesitation is decided once per request and appended to the normal delay; it is not rolled repeatedly.

If the owner or target becomes invalid during decision wait, queue, or cast, the module emits failure/cancellation as appropriate and returns to `READY` without starting skill cooldown.

## Range and Cast Rules

- `request_skill()` accepts a target outside cast range because movement belongs to the host.
- When decision delay completes, the module emits `skill_queued`.
- If the target is outside range, it also emits `cast_range_required` but does not move the owner.
- `begin_cast()` succeeds only while `QUEUED`, with a valid owner and target inside `cast_range + cast_range_tolerance`.
- A successful `begin_cast()` immediately emits `cast_started`. Future Ally integration uses this signal to start the shared combat global cooldown at cast start.
- During `CASTING`, the module does not move either node.
- At the end of `cast_time`, owner, target, optional target group, and range are checked once again.
- A failed final check emits `cast_failed`, does not start skill cooldown, and starts a new decision delay for the same still-valid request only when the target remains structurally valid. An invalid target returns to `READY` and clears the request.
- A successful delivery starts skill cooldown immediately.

`SELF` skills ignore target distance and use the configured owner as the target. Ground-position delivery can retain a target node for validation while also storing the requested world position.

## Default Delivery and Future Overrides

The base implementation provides an overridable method:

```gdscript
func deliver_skill(
    owner: Node3D,
    target: Node3D,
    target_position: Vector3
) -> bool
```

In phase one it prints structured debug information when `debug_logging_enabled` is true, emits the delivery lifecycle signals, and returns `true`. This is a deliberate test delivery, not a real gameplay effect.

Future child modules override the method:

- Projectile child: spawn a projectile and return whether creation succeeded.
- Ground AOE child: spawn an area-delivery scene at `target_position` and return whether creation succeeded.
- Instant-target child: attach or spawn an effect at the current target and return whether delivery succeeded.

Once delivery returns `true`, later projectile hits or misses do not alter skill cooldown.

## Public API

```gdscript
func configure_skill_owner(owner: Node3D) -> void
func request_skill(target: Node3D, target_position: Vector3 = Vector3.INF) -> bool
func begin_cast() -> bool
func cancel_skill() -> void
func reset_module() -> void

func can_request_skill() -> bool
func can_begin_cast() -> bool
func is_casting() -> bool
func is_queued() -> bool
func get_skill_state() -> SkillState
func get_skill_cooldown_remaining() -> float
func get_current_target() -> Node3D
func get_cast_range() -> float
func get_cast_range_tolerance() -> float
```

Request rejection does not modify the active lifecycle. `reset_module()` clears all timers, targets, and state. `cancel_skill()` clears the current request but preserves an already-running skill cooldown.

## Signals

```gdscript
signal skill_requested(target: Node3D)
signal decision_wait_started(target: Node3D, duration: float, used_extra_hesitation: bool)
signal skill_queued(target: Node3D)
signal cast_range_required(target: Node3D, cast_range: float, tolerance: float)
signal cast_started(target: Node3D)
signal delivery_requested(target: Node3D, target_position: Vector3)
signal skill_delivered(target: Node3D, target_position: Vector3)
signal cast_failed(target: Node3D, reason: StringName)
signal cast_cancelled(target: Node3D)
signal cooldown_started(duration: float)
signal cooldown_finished()
signal module_reset()
```

Failure reasons use stable `StringName` values such as `invalid_owner`, `invalid_target`, `wrong_target_group`, `out_of_range`, and `delivery_failed`.

## AllyBase Host Adapter

`AllyBase` gains:

```gdscript
@export_node_path("Node3D") var skill_module_path: NodePath

func set_skill_module(module: SkillModuleBase) -> void
func get_skill_module() -> SkillModuleBase
func request_equipped_skill(target: Node3D, target_position: Vector3 = Vector3.INF) -> bool
func begin_equipped_skill_cast() -> bool
func cancel_equipped_skill() -> void
```

Mounting behavior:

- Disconnect and cancel the previous module.
- Configure the old module with a null owner.
- Store the new module and inject `self` as owner.
- Connect only public module signals.
- Unmounted or invalid modules fail safely without disrupting formation, combat movement, gravity, or basic attacks.

The existing `basic_attack_global_cooldown` remains the per-unit shared combat cooldown value in phase one. Its remaining timer becomes the gate for both basic attacks and skill cast start. A successful `cast_started` signal immediately sets the same remaining timer, matching the existing basic-attack start-time semantics. Skill cooldown remains entirely inside the module and begins only after successful delivery.

First-phase Ally behavior is intentionally manual/API-driven:

- AllyBase does not automatically select skill targets.
- AllyBase does not automatically call `request_equipped_skill()`.
- AllyBase does not move toward `cast_range_required` yet.
- Tests drive the public API and confirm the complete lifecycle and shared cooldown connection.

This preserves a stable component boundary before automatic AI scheduling is added.

## Debug Logging

`debug_logging_enabled` defaults to `true` for the prototype base and can be disabled per module. Logs include module name, profile display name, owner, target, state transition, selected decision duration, extra hesitation result, cast start, delivery result, cooldown start, failure reason, cancellation, and reset.

Logs are diagnostic only; tests primarily verify signals and state so production behavior does not depend on console text.

## Validation

`SkillModuleBaseTest.gd` verifies:

- Scene structure, Profile defaults, enums, API, and signals.
- Owner and target configuration.
- Normal delay boundaries and deterministic random injection for tests.
- Exactly one 10% hesitation roll per request and correct appended duration.
- Queue and out-of-range signals without movement.
- Cast start and completion range checks.
- Successful placeholder delivery and cooldown start.
- Failure without skill cooldown.
- Cancel/reset behavior and invalid owner/target handling.

`AllySkillModuleHostTest.gd` verifies:

- Generic socket and exported path.
- Mount, replace, and unmount lifecycle.
- One-way owner injection.
- Public request/begin/cancel forwarding.
- Shared combat cooldown starts immediately on `cast_started`.
- Skill cooldown starts only after successful delivery.
- No module is safe and does not affect existing behavior.

All existing combat tests and Godot 4.7 headless smoke validation must remain green. `Scenes/TestScene.tscn` must remain unchanged.
