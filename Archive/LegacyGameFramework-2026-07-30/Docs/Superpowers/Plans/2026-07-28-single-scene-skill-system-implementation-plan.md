# Single-Scene SkillSystem Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the multi-asset Skill/Definition/Delivery assembly with a single-scene SkillBase framework while preserving target validation, cast timing, cooldowns, AI usage, delivery extensibility, Firebolt, and HolyLight.

**Architecture:** Build the new framework beside the current `Independent*` implementation under `SkillSystem/12-SingleScene`, using final public class names so both systems can coexist. A concrete skill scene owns all common configuration on its root and contains one embedded typed DeliveryConfig; SkillBase delegates runtime delivery to a fixed child runner and requests character animation through an interface-only SkillHost/action-driver boundary. After Firebolt and HolyLight pass isolated and UnitSystem runtime tests, archive the old implementation and promote the new folders to the final numbered layout.

**Tech Stack:** Godot 4.7, GDScript 2.0, PackedScene, typed Resource SubResources, AnimationPlayer method tracks, CharacterBody3D, headless SceneTree tests.

## Global Constraints

- All implementation must follow Godot 4.7 APIs and GDScript syntax.
- All identifiers must be English; all newly added code must contain detailed Simplified Chinese comments.
- A concrete skill has one manually maintained `.tscn`; no per-skill Definition `.tres` or Delivery `.tscn`.
- Common skill configuration is edited on the skill root; fixed internal nodes do not re-export duplicate fields or NodePaths.
- `base_cast_time` means time from action start to `release_action()`, not full animation duration.
- Skill cooldown and shared action cooldown begin only after Delivery successfully starts.
- Projectile gameplay, collision, impact range, payload, flight VFX, and impact VFX remain projectile responsibilities.
- Do not modify or add unit instances in `res://Scenes/TestScene.tscn`.
- Existing `Independent*` skills remain runnable until the new Firebolt and HolyLight both pass migration tests.
- Formal external `.tres` or `.res` files must be saved with Godot `ResourceSaver` and verified with `ResourceLoader.get_resource_uid(path) != ResourceUID.INVALID_ID`.
- Embedded DeliveryConfig SubResources must be saved through `PackedScene.pack()` and `ResourceSaver.save()`, then their owning scene UID must be verified.
- The project is not a Git repository. Replace commit steps with explicit verification checkpoints and do not initialize Git.

---

## Final File Layout

The staging layout exists only during Tasks 1–7:

```text
SkillSystem/12-SingleScene/
├─ Core/
│  ├─ SkillBase.gd
│  ├─ SkillBase.tscn
│  ├─ SkillContext.gd
│  ├─ SkillDeliveryResult.gd
│  ├─ SkillHostComponent.gd
│  └─ SkillHostComponent.tscn
├─ Delivery/
│  ├─ SkillDeliveryConfig.gd
│  ├─ TrackingProjectileDeliveryConfig.gd
│  ├─ InstantTargetDeliveryConfig.gd
│  ├─ GroundAreaDeliveryConfig.gd
│  └─ SkillDeliveryRunner.gd
├─ Extensions/
│  ├─ SkillConditionBase.gd
│  ├─ SkillCostBase.gd
│  └─ SkillEffectBase.gd
└─ Tests/
   ├─ SingleSceneDeliveryRunnerTest.gd
   ├─ SingleSceneSkillBaseTest.gd
   ├─ SingleSceneSkillHostTest.gd
   ├─ SingleSceneFireboltTest.gd
   └─ SingleSceneHolyLightTest.gd
```

Temporary concrete scenes:

```text
SkillSystem/00-Skills/Firebolt/FireboltSkillSingleScene.tscn
SkillSystem/00-Skills/HolyLight/HolyLightSkillSingleScene.tscn
```

After Task 8:

```text
SkillSystem/
├─ 00-Skills/
├─ 01-Core/
├─ 02-Delivery/
├─ 03-Extensions/
├─ 04-Docs/
└─ 05-Tests/

Archive/SkillSystemLegacy-2026-07-28/
```

The promotion step must update every `res://SkillSystem/12-SingleScene/...` reference and re-run an editor scan before the old system is considered archived successfully.

---

### Task 1: Core Runtime Data and Typed Delivery Configs

**Files:**
- Create: `SkillSystem/12-SingleScene/Core/SkillContext.gd`
- Create: `SkillSystem/12-SingleScene/Core/SkillDeliveryResult.gd`
- Create: `SkillSystem/12-SingleScene/Delivery/SkillDeliveryConfig.gd`
- Create: `SkillSystem/12-SingleScene/Delivery/TrackingProjectileDeliveryConfig.gd`
- Create: `SkillSystem/12-SingleScene/Delivery/InstantTargetDeliveryConfig.gd`
- Create: `SkillSystem/12-SingleScene/Delivery/GroundAreaDeliveryConfig.gd`
- Create: `SkillSystem/12-SingleScene/Extensions/SkillConditionBase.gd`
- Create: `SkillSystem/12-SingleScene/Extensions/SkillCostBase.gd`
- Create: `SkillSystem/12-SingleScene/Extensions/SkillEffectBase.gd`
- Create: `SkillSystem/12-SingleScene/Tests/SingleSceneCoreContractsTest.gd`

**Interfaces:**
- Produces: `SkillContext.duplicate_context() -> SkillContext`
- Produces: `SkillDeliveryConfig.validate_configuration() -> PackedStringArray`
- Produces: typed configs `TrackingProjectileDeliveryConfig`, `InstantTargetDeliveryConfig`, and `GroundAreaDeliveryConfig`
- Produces: optional extension contracts `SkillConditionBase.evaluate(context)`, `SkillCostBase.can_pay/commit/refund(context)`, and `SkillEffectBase.apply(context, result, target)`

- [ ] **Step 1: Write the failing core contract test**

Create a SceneTree test that loads every new script path, instantiates each class, and asserts typed defaults:

```gdscript
extends SceneTree

const ROOT := "res://SkillSystem/12-SingleScene/"
var failures: Array[String] = []

func _initialize() -> void:
	var tracking_script := load(ROOT + "Delivery/TrackingProjectileDeliveryConfig.gd") as Script
	_expect(tracking_script != null, "tracking config script loads")
	if tracking_script != null:
		var config: Resource = tracking_script.new()
		_expect(config.get("projectile_scene") == null, "projectile defaults empty")
		_expect(is_equal_approx(float(config.get("projectile_speed")), 12.0), "speed default")
		_expect((config.call("validate_configuration") as PackedStringArray).size() > 0, "missing projectile warns")
	call_deferred(&"_finish")

func _expect(value: bool, message: String) -> void:
	if not value:
		failures.append(message)

func _finish() -> void:
	if failures.is_empty():
		print("SingleSceneCoreContractsTest: PASS")
		quit(0)
	else:
		for failure: String in failures:
			push_error(failure)
		quit(1)
```

- [ ] **Step 2: Run the test and verify RED**

Run:

```powershell
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' --headless --path . -s res://SkillSystem/12-SingleScene/Tests/SingleSceneCoreContractsTest.gd
```

Expected: FAIL because the new script paths do not exist.

- [ ] **Step 3: Implement SkillContext and SkillDeliveryResult**

`SkillContext.gd` must contain only per-request runtime data:

```gdscript
class_name SkillContext
extends RefCounted

var caster: Node3D
var host: Node
var requested_target: Node3D
var resolved_target: Node3D
var candidate_targets: Array[Node3D] = []
var target_position: Vector3 = Vector3.INF
var delivery_parent: Node
var request_source: int = 0

func duplicate_context() -> SkillContext:
	var copy := SkillContext.new()
	copy.caster = caster
	copy.host = host
copy.requested_target = requested_target
copy.resolved_target = resolved_target
copy.candidate_targets.assign(candidate_targets)
copy.target_position = target_position
	copy.delivery_parent = delivery_parent
	copy.request_source = request_source
	return copy
```

`SkillDeliveryResult.gd` records success, target, origin, intended position, impact position, direction, and a stable failure reason.

- [ ] **Step 4: Implement the DeliveryConfig base and three concrete configs**

`SkillDeliveryConfig.gd`:

```gdscript
class_name SkillDeliveryConfig
extends Resource

func validate_configuration() -> PackedStringArray:
	return PackedStringArray(["SkillDeliveryConfig is abstract."])
```

`TrackingProjectileDeliveryConfig.gd` exposes exactly:

```gdscript
@export var projectile_scene: PackedScene
@export_range(0.1, 100.0, 0.1, "or_greater") var projectile_speed: float = 12.0
@export_range(0.0, 2160.0, 1.0, "or_greater") var turn_speed_degrees: float = 540.0
@export_range(0.1, 60.0, 0.1, "or_greater") var maximum_lifetime: float = 5.0
@export_range(-10.0, 10.0, 0.05) var aim_height: float = 0.25
@export_range(0.0, 30.0, 0.05, "or_greater") var impact_radius: float = 0.0
```

`InstantTargetDeliveryConfig.gd` has no dummy fields and returns no warnings.

`GroundAreaDeliveryConfig.gd` exposes:

```gdscript
@export var area_scene: PackedScene
@export var ground_offset: Vector3 = Vector3.ZERO
```

- [ ] **Step 5: Implement optional extension base contracts**

Base methods must fail closed:

```gdscript
class_name SkillConditionBase
extends Node

func evaluate(_context: SkillContext) -> bool:
	return false

func get_failure_reason(_context: SkillContext) -> StringName:
	return &"condition_not_implemented"
```

`SkillCostBase` provides `can_pay`, `commit`, and idempotent `refund`; `SkillEffectBase` provides `apply`. None of these are required in a normal skill scene.

- [ ] **Step 6: Run the core contract test and verify GREEN**

Expected: `SingleSceneCoreContractsTest: PASS`.

- [ ] **Step 7: Verification checkpoint**

Run a Godot editor scan:

```powershell
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' --headless --editor --quit --path .
```

Expected: exit code `0`, no parser errors, and no duplicate `class_name` errors.

---

### Task 2: Reusable DeliveryRunner

**Files:**
- Create: `SkillSystem/12-SingleScene/Delivery/SkillDeliveryRunner.gd`
- Create: `SkillSystem/12-SingleScene/Tests/SingleSceneDeliveryRunnerTest.gd`
- Reuse: `Item/Projectiles/FireBall.tscn`

**Interfaces:**
- Consumes: `SkillContext`, `SkillDeliveryConfig`, optional `Array[SkillEffectBase]`
- Produces:

```gdscript
signal delivery_started(context: SkillContext)
signal delivery_finished(context: SkillContext, result: SkillDeliveryResult)
signal delivery_failed(context: SkillContext, reason: StringName)

func execute(
	config: SkillDeliveryConfig,
	context: SkillContext,
	launch_transform: Transform3D,
	effects: Array[SkillEffectBase]
) -> bool

func cancel(reason: StringName = &"cancelled") -> void
func is_busy() -> bool
```

- [ ] **Step 1: Write failing tests for instant and projectile delivery**

The test must prove:

- Instant delivery calls every effect once on `resolved_target`.
- Missing target rejects Instant delivery.
- Tracking delivery spawns exactly one projectile under `delivery_parent`.
- The projectile receives the supplied world launch origin, not the runner position.
- Invalid configs fail without leaving runtime children.
- Runner can be reused only after its current delivery finishes or is cancelled.

Use a local fake projectile with the same eight-argument `launch()` contract as the existing FireBall.

- [ ] **Step 2: Run the test and verify RED**

Expected: FAIL because `SkillDeliveryRunner.gd` does not exist.

- [ ] **Step 3: Implement type dispatch without per-skill Agent scenes**

The runner must dispatch only by typed config:

```gdscript
func execute(
	config: SkillDeliveryConfig,
	context: SkillContext,
	launch_transform: Transform3D,
	effects: Array[SkillEffectBase]
) -> bool:
	if _busy or config == null or context == null or not launch_transform.is_finite():
		return false
	if not config.validate_configuration().is_empty():
		return false
	if config is TrackingProjectileDeliveryConfig:
		return _execute_tracking(config, context, launch_transform)
	if config is InstantTargetDeliveryConfig:
		return _execute_instant(context, launch_transform, effects)
	if config is GroundAreaDeliveryConfig:
		return _execute_ground_area(config, context, launch_transform)
	return false
```

The runner contains all runtime state. Delivery Resources remain immutable during execution.

- [ ] **Step 4: Port the existing tracking projectile contract**

Call the projectile with:

```gdscript
projectile.callv(&"launch", [
	context.caster,
	context.resolved_target,
	launch_transform.origin,
	initial_direction,
	config.projectile_speed,
	config.turn_speed_degrees,
	config.maximum_lifetime,
	config.impact_radius,
])
```

Do not copy damage, collision, radius target selection, or VFX logic out of the projectile.

- [ ] **Step 5: Implement Instant and GroundArea minimum behavior**

Instant delivery creates a successful result immediately and applies the supplied effect components.

GroundArea instantiates `area_scene` under `delivery_parent`, positions it at `target_position + ground_offset`, and requires a minimal `launch(context) -> bool` contract.

- [ ] **Step 6: Run the delivery test and verify GREEN**

Expected: `SingleSceneDeliveryRunnerTest: PASS`.

- [ ] **Step 7: Run the existing projectile test as a regression check**

Run:

```powershell
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' --headless --path . -s res://SkillSystem/11-Tests/TrackingProjectileDeliveryAgentTest.gd
```

Expected: PASS. The old system must still work.

---

### Task 3: Single-Scene SkillBase

**Files:**
- Create: `SkillSystem/12-SingleScene/Core/SkillBase.gd`
- Create: `SkillSystem/12-SingleScene/Core/SkillBase.tscn`
- Create: `SkillSystem/12-SingleScene/Tests/SingleSceneSkillBaseTest.gd`

**Interfaces:**
- Produces:

```gdscript
signal action_requested(
	skill: SkillBase,
	animation_name: StringName,
	target: Node3D,
	effective_cast_time: float
)
signal cast_range_required(context: SkillContext, cast_range: float)
signal cast_started(context: SkillContext)
signal release_started(context: SkillContext)
signal delivery_started(context: SkillContext)
signal delivery_finished(context: SkillContext, result: SkillDeliveryResult)
signal skill_failed(context: SkillContext, reason: StringName)
signal skill_cancelled(context: SkillContext, reason: StringName)
signal cooldown_started(duration: float)
signal cooldown_finished()

func configure_owner(caster: Node3D, host: Node, delivery_parent: Node) -> void
func request_skill(context: SkillContext) -> bool
func try_request_action() -> bool
func confirm_action_started(cast_transform: Transform3D) -> bool
func release_action(launch_transform: Transform3D) -> bool
func finish_action() -> void
func cancel_skill(reason: StringName = &"cancelled") -> void
func reset_skill() -> void
func can_request(context: SkillContext) -> bool
func is_ready() -> bool
func is_casting() -> bool
func get_effective_cast_time() -> float
```

- [ ] **Step 1: Write the failing SkillBase contract test**

Test:

- Root is `Node`, not `Node3D`.
- Scene has fixed `DeliveryRunner` and `RuntimeEffects` children.
- Root exposes every approved Inspector group property.
- No `skill_definition`, `delivery_agent_scene`, or exported NodePath remains.
- Provided hostile target requests an action.
- `SELF` resolves the caster; `PROVIDED` resolves `requested_target`; `AUTO_NEAREST` chooses the nearest valid entry from `candidate_targets`.
- A valid target outside `cast_range` is accepted into `QUEUED`, emits `cast_range_required`, and does not request animation yet.
- `try_request_action()` emits `action_requested` only after the queued target enters range.
- `release_action()` performs final validation.
- `confirm_action_started()` spawns Cast VFX at the supplied world transform; Release VFX uses the separately supplied current world transform.
- Cost commits only at release and refunds once when Delivery fails.
- Skill cooldown begins only after Delivery starts.
- Cast-speed fallback is `1.0` when the owner lacks `get_cast_speed_multiplier()`.
- Invalid cast-speed values reject the request.

- [ ] **Step 2: Run the test and verify RED**

Expected: FAIL because the new SkillBase scene does not exist.

- [ ] **Step 3: Create the fixed scene structure**

`SkillBase.tscn`:

```text
SkillBase (Node, SkillBase.gd)
├─ DeliveryRunner (Node, SkillDeliveryRunner.gd)
└─ RuntimeEffects (Node)
```

The scene must not contain `CastOrigin`, `DeliverySocket`, or `SkillAnimationPlayer`.

- [ ] **Step 4: Implement root Inspector fields**

Use enums on `SkillBase.gd`:

```gdscript
enum TargetSource { PROVIDED, SELF, AUTO_NEAREST }
enum TargetRelation { ANY, SELF, FRIENDLY, HOSTILE, NEUTRAL }
enum SkillState { READY, QUEUED, ACTION_REQUESTED, CASTING, RELEASED, COOLDOWN }
```

Add approved groups:

```gdscript
@export_category("Identity")
@export var skill_id: StringName = &"default_skill"
@export var display_name: String = "Default Skill"
@export var icon: Texture2D
@export var ai_priority: int = 0

@export_category("Targeting")
@export var target_source: TargetSource = TargetSource.PROVIDED
@export var target_relation: TargetRelation = TargetRelation.ANY
@export_range(0.0, 100.0, 0.1, "or_greater") var cast_range: float = 5.0
@export var require_targetable: bool = true
@export var validate_target_on_release: bool = true

@export_category("Casting")
@export var action_animation_name: StringName = &"cast"
@export_range(0.0, 30.0, 0.05, "or_greater") var base_cast_time: float = 0.5
@export var can_move_while_casting: bool = false
@export var can_turn_while_casting: bool = true
@export var cancel_when_target_invalid: bool = true

@export_category("Cooldown")
@export_range(0.0, 600.0, 0.1, "or_greater") var skill_cooldown: float = 6.0
@export var cooldown_on_failed_release: bool = false

@export_category("AI Usage")
@export var automatic_cast_enabled: bool = true
@export_range(0.0, 10.0, 0.1) var decision_delay_min: float = 0.3
@export_range(0.0, 10.0, 0.1) var decision_delay_max: float = 3.0
@export_range(0.0, 1.0, 0.01) var extra_hesitation_chance: float = 0.1
@export_range(0.0, 10.0, 0.1) var extra_hesitation_min: float = 3.0
@export_range(0.0, 10.0, 0.1) var extra_hesitation_max: float = 5.0

@export_category("Presentation")
@export var cast_effect_scene: PackedScene
@export var release_effect_scene: PackedScene
@export var cancel_effect_scene: PackedScene

@export_category("Delivery")
@export var delivery: SkillDeliveryConfig
```

- [ ] **Step 5: Implement validation, optional component discovery, and cooldown**

Discover only direct children implementing `SkillConditionBase`, `SkillCostBase`, or `SkillEffectBase`. Fixed internal children must be skipped.

General target validation remains inside SkillBase. Special components add rules; they do not replace relation/range checks.

`request_skill()` validates identity, relation, targetable state, Condition, and Cost availability without rejecting a valid out-of-range target. It enters `QUEUED` and calls `try_request_action()`. When range is not yet satisfied, `try_request_action()` emits `cast_range_required`; when range becomes valid, it transitions to `ACTION_REQUESTED` and emits `action_requested`.

Target resolution is explicit:

```gdscript
match target_source:
	TargetSource.SELF:
		context.resolved_target = _skill_owner
	TargetSource.PROVIDED:
		context.resolved_target = context.requested_target
	TargetSource.AUTO_NEAREST:
		context.resolved_target = _find_nearest_valid_candidate(context)
```

Relation checks use public unit methods such as `is_friendly_to()`, `is_hostile_to()`, and `is_targetable()` through interface checks; SkillSystem must not preload UnitSystem classes.

`get_effective_cast_time()`:

```gdscript
func get_effective_cast_time() -> float:
	var multiplier: float = 1.0
	if is_instance_valid(_skill_owner) and _skill_owner.has_method(&"get_cast_speed_multiplier"):
		multiplier = float(_skill_owner.call(&"get_cast_speed_multiplier"))
	if not is_finite(multiplier) or multiplier <= 0.0:
		return -1.0
	return maxf(base_cast_time, 0.0) / multiplier
```

- [ ] **Step 6: Implement world-space presentation spawning**

Effects must be added under `context.delivery_parent`, assigned the supplied world transform, and tracked by `RuntimeEffects`. Never derive launch coordinates from the Skill scene transform.

Store the last valid action transform only for cancel presentation. Do not reuse the cast-start transform for Delivery; `release_action()` always receives a fresh launch transform from the character action driver.

- [ ] **Step 7: Save the scene through Godot and verify UID**

Use a temporary SceneTree setup script with `PackedScene.pack()` and `ResourceSaver.save()`, then assert:

```gdscript
ResourceLoader.get_resource_uid(
	"res://SkillSystem/12-SingleScene/Core/SkillBase.tscn"
) != ResourceUID.INVALID_ID
```

- [ ] **Step 8: Run the SkillBase test and verify GREEN**

Expected: `SingleSceneSkillBaseTest: PASS`.

---

### Task 4: Single-Scene SkillHost and Action Boundary

**Files:**
- Create: `SkillSystem/12-SingleScene/Core/SkillHostComponent.gd`
- Create: `SkillSystem/12-SingleScene/Core/SkillHostComponent.tscn`
- Create: `SkillSystem/12-SingleScene/Tests/SingleSceneSkillHostTest.gd`

**Interfaces:**
- Produces:

```gdscript
signal action_requested(
	skill: SkillBase,
	animation_name: StringName,
	target: Node3D,
	effective_cast_time: float
)
signal movement_lock_requested(locked: bool)
signal facing_requested(context: SkillContext)
signal approach_requested(context: SkillContext, cast_range: float)
signal skill_released(context: SkillContext)

func configure_owner(caster: Node3D, delivery_parent: Node = null) -> void
func register_skill(skill: SkillBase) -> bool
func unregister_skill(skill: SkillBase) -> bool
func request_skill(
	skill_id: StringName,
	target: Node3D,
	candidate_targets: Array[Node3D] = [],
	target_position := Vector3.INF,
	source := 0
) -> bool
func request_best_skill(target: Node3D) -> bool
func confirm_active_action_started(cast_transform: Transform3D) -> bool
func release_active_action(launch_transform: Transform3D) -> bool
func finish_active_action() -> void
func cancel_active_skill(reason: StringName = &"cancelled") -> void
func get_registered_skills() -> Array[SkillBase]
func get_active_skill() -> SkillBase
func get_preferred_cast_range() -> float
func set_skill_casting_enabled(enabled: bool) -> void
func is_skill_casting_enabled() -> bool
```

- [ ] **Step 1: Write the failing host test**

Test:

- Fixed `SkillSocket` exists.
- Host automatically uses its direct `Node3D` parent as owner.
- It registers only direct SkillBase children.
- Duplicate `skill_id` is rejected with a configuration warning.
- Disabled casting rejects requests.
- `request_best_skill()` filters by `automatic_cast_enabled`, readiness, target validity, and AI priority.
- Random decision delay remains skill-root data but the host owns the timer.
- A queued out-of-range skill remains active and the host keeps forwarding `approach_requested` until it enters range.
- `get_preferred_cast_range()` returns the active skill range, or the highest-priority ready automatic skill range when no skill is active.
- The host does not play AnimationPlayer directly.
- Successful Delivery release, not cast start, starts external shared cooldown notification.
- Cancelling active skill unlocks movement and frees the action slot.

- [ ] **Step 2: Run the test and verify RED**

Expected: FAIL because the new host does not exist.

- [ ] **Step 3: Implement the host scene**

```text
SkillHostComponent (Node)
└─ SkillSocket (Node)
```

Only `SkillSocket` is an assembly slot. The Host must not export its fixed path.

- [ ] **Step 4: Implement registration and owner configuration**

Each registered skill receives:

```gdscript
skill.configure_owner(_caster, self, _delivery_parent)
```

Connect and forward `action_requested`. Do not import UnitSystem scripts or concrete AI classes.

- [ ] **Step 5: Implement automatic selection and hesitation**

Use a host-owned `RandomNumberGenerator`. For equal priority, preserve stable SkillSocket child order.

Decision delay:

```text
normal random delay
+ optional 10% extra hesitation
```

The host must not mutate skill-root delay parameters.

- [ ] **Step 6: Implement active action routing**

The UnitSystem will call:

```gdscript
confirm_active_action_started(cast_transform)
release_active_action(launch_transform)
finish_active_action()
```

The host forwards these calls only to its active skill.

During `_physics_process`, the host calls `try_request_action()` for the active queued skill. It must not create a second request or reroll hesitation while approaching.

- [ ] **Step 7: Run the host test and verify GREEN**

Expected: `SingleSceneSkillHostTest: PASS`.

- [ ] **Step 8: Verify the old host still passes**

Run `res://SkillSystem/11-Tests/SkillHostComponentTest.gd`.

Expected: PASS.

---

### Task 5: Character Action Events and Cast-Time Animation Scaling

**Files:**
- Modify: `UnitSystem/Components/Animation/CharacterAnimationEventPlayer.gd`
- Modify: `UnitSystem/Components/Combat/AI/AIAttackController.gd`
- Modify: `UnitSystem/Components/Combat/AI/AICombatSystem.gd`
- Create: `UnitSystem/Tests/AISkillActionAnimationTest.gd`

**Interfaces:**
- `CharacterAnimationEventPlayer` adds:

```gdscript
signal action_release_requested()
signal action_finish_requested()

func release_action() -> void
func finish_action() -> void
```

- `AIAttackController` adds:

```gdscript
signal external_action_released()
signal external_action_finished()
signal external_action_cancelled()

func request_external_action(
	animation_name: StringName,
	effective_cast_time: float
) -> bool

func cancel_external_action() -> void
func get_action_launch_transform() -> Transform3D
```

- [ ] **Step 1: Write the failing animation integration test**

Construct a CharacterAnimationEventPlayer with an animation whose method track calls:

```text
0.60s → release_action()
1.00s → finish_action()
```

Assert:

- `effective_cast_time = 1.20` plays at speed `0.5`.
- Release occurs at approximately `1.20s`.
- `effective_cast_time = 0.30` plays at speed `2.0`.
- `effective_cast_time = 0` requires the release marker at time `0`.
- Missing release marker rejects the action.
- Multiple release markers reject the first-version contract.
- Cancelling returns the AnimationPlayer to RESET.
- While an external skill action is active, `can_attack()` and a second external action request both return false.
- Existing melee and ranged attack tests still pass.

- [ ] **Step 2: Run the test and verify RED**

Expected: FAIL because the generic action events and external action API do not exist.

- [ ] **Step 3: Add generic AnimationPlayer method-track events**

Keep legacy methods:

```gdscript
release_projectile()
open_attack_hit_window()
close_attack_hit_window()
```

Do not make them emit the new generic release signal automatically; this prevents double delivery in existing animations.

- [ ] **Step 4: Implement release-marker inspection in AIAttackController**

Inspect the selected animation's method tracks and accept exactly one `release_action` key. Compute:

```gdscript
playback_speed = (
	1.0
	if effective_cast_time <= 0.0
	else release_marker_time / effective_cast_time
)
```

Reject non-finite or non-positive speed.

- [ ] **Step 5: Reuse the existing visual endpoint resolution**

Use the already resolved `CharacterAnimationEventPlayer` and weapon/projectile origin. `get_action_launch_transform()` must return the current character visual `ProjectileOrigin` world transform and must not reference Player, Hero, SkillBase, or a Skill-local marker.

- [ ] **Step 6: Add AICombatSystem pass-through methods**

AICombatSystem exposes the external action request/cancel and generic action signals without knowing SkillBase types. This keeps UnitSystem-to-SkillSystem adaptation at the behavior/assembly boundary.

- [ ] **Step 7: Run new and regression tests**

Run:

```text
UnitSystem/Tests/AISkillActionAnimationTest.gd
UnitSystem/Tests/AICombatSystemTest.gd
UnitSystem/Tests/AllyMeleeCombatIntegrationTest.gd
UnitSystem/Tests/RangedAttackPipelineTest.gd
```

Expected: all PASS.

---

### Task 6: Firebolt as One Skill Scene

**Files:**
- Create: `SkillSystem/00-Skills/Firebolt/FireboltSkillSingleScene.tscn`
- Create: `SkillSystem/12-SingleScene/Tests/SingleSceneFireboltTest.gd`
- Reuse: `Item/Projectiles/FireBall.tscn`
- Reuse: `Effects/Skills/Fireball/FireballCastChargeEffect.tscn`
- Reuse: `Effects/Skills/Fireball/FireballFlightEffect.tscn`
- Reuse: `Effects/Skills/Fireball/FireballExplosionEffect.tscn`

**Interfaces:**
- Produces one Firebolt scene with root-owned data and an embedded `TrackingProjectileDeliveryConfig`
- Does not create `FireboltSkillDefinition.tres` or `FireboltDelivery.tscn`

- [ ] **Step 1: Write the failing Firebolt assembly test**

Assert:

- Scene inherits the new SkillBase.
- Scene UID is valid.
- Root contains `skill_id = &"firebolt"`, hostile provided-target rules, cast range `6.0`, base cast time `0.75`, cooldown `3.0`.
- Root requests the stable character action name `character/firebolt_cast`.
- Root references the cast charge effect.
- Root Delivery is a local `TrackingProjectileDeliveryConfig`.
- Config references `FireBall.tscn` and preserves speed `9.0`, turn speed `180.0`, lifetime `3.0`, radius `1.2`, and aim height `0.25`.
- No external Definition or Firebolt Delivery scene is referenced.

- [ ] **Step 2: Run the test and verify RED**

Expected: FAIL because the new scene does not exist.

- [ ] **Step 3: Create Firebolt with ResourceSaver**

Instantiate the new SkillBase scene, assign all root properties, create the config with:

```gdscript
var delivery := TrackingProjectileDeliveryConfig.new()
delivery.resource_local_to_scene = true
delivery.projectile_scene = load("res://Item/Projectiles/FireBall.tscn")
delivery.projectile_speed = 9.0
delivery.turn_speed_degrees = 180.0
delivery.maximum_lifetime = 3.0
delivery.impact_radius = 1.2
delivery.aim_height = 0.25
skill.delivery = delivery
```

Pack and save the scene through Godot.

- [ ] **Step 4: Add a runtime launch test at a nonzero world position**

Place a caster at `(10, 0, 4)`, target at `(14, 0, 1)`, and provide a launch transform from a Marker3D under the caster visual.

Assert the FireBall begins at the Marker3D world position, faces the target, and does not appear at `(0, 0, 0)`.

- [ ] **Step 5: Run Firebolt tests and verify GREEN**

Expected:

```text
SingleSceneFireboltTest: PASS
```

The old `FireboltSkillAssemblyTest.gd` must still PASS at this stage.

---

### Task 7: HolyLight as One Skill Scene and Optional Effect Component

**Files:**
- Create: `SkillSystem/12-SingleScene/Extensions/HealthChangeSkillEffect.gd`
- Create: `SkillSystem/00-Skills/HolyLight/HolyLightSkillSingleScene.tscn`
- Create: `SkillSystem/12-SingleScene/Tests/SingleSceneHolyLightTest.gd`
- Reuse: `Effects/Skills/HolyLight/HolyLightHealEffect.tscn`

**Interfaces:**
- Produces `HealthChangeSkillEffect.operation`, `amount`, and `apply(...)`
- Produces HolyLight with embedded `InstantTargetDeliveryConfig` and one direct HealEffect component

- [ ] **Step 1: Write the failing HolyLight test**

Assert:

- One skill scene is the only manually maintained skill asset.
- Root targets Friendly units.
- Delivery is an embedded InstantTarget config.
- One `HealthChangeSkillEffect` direct child heals `25.0`.
- Release effect uses `HolyLightHealEffect.tscn`.
- Instant delivery changes target health exactly once.
- Missing HealthComponent fails delivery without starting cooldown.

- [ ] **Step 2: Run the test and verify RED**

Expected: FAIL because the effect script and new scene do not exist.

- [ ] **Step 3: Implement HealthChangeSkillEffect**

Use the UnitBase/HealthComponent public API. Do not hardcode AllyBase, EnemyBase, or a concrete character scene.

```gdscript
enum Operation { DAMAGE, HEAL }

@export var operation: Operation = Operation.HEAL
@export_range(0.0, 999999.0, 0.1, "or_greater") var amount: float = 10.0

func apply(context: SkillContext, _result: SkillDeliveryResult, target: Node3D) -> bool:
	var method: StringName = (
		&"apply_healing"
		if operation == Operation.HEAL
		else &"apply_damage"
	)
	if not is_instance_valid(target) or not target.has_method(method):
		return false
	target.call(method, amount, context.caster)
	return true
```

`UnitBase.apply_healing()` and `UnitBase.apply_damage()` return the actual changed amount as `float`; the Effect deliberately treats a valid method call as successful even when the target is already at its health limit. It must not read or write private health fields.

- [ ] **Step 4: Create HolyLight with ResourceSaver**

Assign root data, an embedded InstantTarget config, the release VFX, and one direct HealthChangeSkillEffect child. Save and verify scene UID.

- [ ] **Step 5: Run HolyLight tests and verify GREEN**

Expected: `SingleSceneHolyLightTest: PASS`.

---

### Task 8: UnitSystem Integration, Migration, Archive, and Documentation

**Files:**
- Modify: `UnitSystem/Base/00_UnitBase.tscn`
- Modify: `UnitSystem/Components/Behavior/AllyBehaviorStateMachine.gd`
- Modify: `UnitSystem/AI/Ally/AllyBase2.gd`
- Modify: `UnitSystem/AI/Ally/Units/Caster.tscn`
- Modify: `UnitSystem/AI/Ally/Visuals/CasterVisual.tscn`
- Create: `UnitSystem/AI/Ally/Animations/CasterAnimationLibrary.res`
- Modify: `UnitSystem/Tests/UnitBaseSkillHostAssemblyTest.gd`
- Modify: `UnitSystem/Tests/CasterSkillActionAssemblyTest.gd`
- Modify: `UnitSystem/Tests/CasterFireboltRuntimeTest.gd`
- Modify: `SkillSystem/README.md`
- Create: `SkillSystem/04-Docs/SkillSystemUserGuide.md`
- Move after verification: existing legacy SkillSystem implementation to `Archive/SkillSystemLegacy-2026-07-28/`
- Promote after verification: staging Core, Delivery, Extensions, and Tests to final numbered folders

**Interfaces:**
- UnitSystem consumes only the new SkillHost public interface and generic external-action interface.
- SkillSystem does not import UnitSystem behavior, AI, Player, or concrete unit scripts.

- [ ] **Step 1: Update tests first for the new UnitBase assembly**

Expected final UnitBase structure:

```text
UnitBase
└─ SkillHost
   └─ SkillSocket
```

The test must assert:

- New SkillHost class is mounted once.
- Root fields are not duplicated on SkillHost children.
- UnitBase automatically configures itself as skill owner.
- No old `IndependentSkillHostComponent` remains after final promotion.

- [ ] **Step 2: Update Caster tests before changing Caster**

Assert:

- Caster mounts `FireboltSkill` under `SkillHost/SkillSocket`.
- Firebolt is the new one-scene skill.
- CasterVisual owns a character AnimationLibrary containing `character/firebolt_cast`.
- Firebolt requests `character/firebolt_cast`; it does not read the MagicGlobe weapon AnimationLibrary.
- AI combat system is configured as SkillHost action driver.
- Skill priority suppresses ordinary attack while skills are enabled.
- Disabling skill casting allows the existing basic-attack fallback.
- Shared action cooldown remains `1.0s`.
- Shared cooldown starts after Firebolt Delivery starts, not when casting begins.

- [ ] **Step 3: Run the updated tests and verify RED**

Expected: FAIL because UnitBase and Caster still use the old host and Firebolt.

- [ ] **Step 4: Connect the behavior state machine to the new action boundary**

When SkillHost emits `action_requested`:

```text
Behavior StateMachine
→ AICombatSystem.request_external_action()
→ on success SkillHost.confirm_active_action_started(
    AICombatSystem.get_action_launch_transform()
  )
```

When SkillHost emits `approach_requested`, keep using the existing combat approach movement. Do not add a second locomotion algorithm. While approaching, the active Skill remains queued and basic attack remains blocked according to the existing combat action policy.

When AICombatSystem emits:

```text
external_action_released
→ SkillHost.release_active_action(AICombatSystem.get_action_launch_transform())

external_action_finished
→ SkillHost.finish_active_action()

external_action_cancelled
→ SkillHost.cancel_active_skill()
```

The behavior state machine may coordinate these calls but must not inspect DeliveryConfig, projectile scenes, or skill-specific data.

- [ ] **Step 5: Create the Caster character cast AnimationLibrary**

Create `CasterAnimationLibrary.res` through Godot `AnimationLibrary`, `Animation`, and `ResourceSaver` APIs.

It contains:

```text
firebolt_cast
├─ CharacterRoot transform animation
├─ 0.75s method key: release_action()
└─ 1.00s method key: finish_action()
```

Attach it to CasterVisual's CharacterAnimationPlayer under the library key:

```text
character
```

The fully qualified animation name is:

```text
character/firebolt_cast
```

Verify:

```gdscript
ResourceLoader.get_resource_uid(
	"res://UnitSystem/AI/Ally/Animations/CasterAnimationLibrary.res"
) != ResourceUID.INVALID_ID
```

The animation may move or rotate `CharacterRoot` and `WeaponSocket`, but it must not animate the Unit root, CharacterBody3D global transform, or projectile world position.

- [ ] **Step 6: Start shared cooldown on successful skill release**

Replace the old `cast_started` shared-cooldown hook with the new `skill_released` hook:

```gdscript
func _on_skill_released(_context: SkillContext) -> void:
	_start_shared_action_cooldown()
```

Do not change the existing basic attack cooldown start rule.

- [ ] **Step 7: Switch UnitBase and Caster**

Mount the new SkillHost in UnitBase and the single-scene Firebolt in Caster. Set Firebolt `action_animation_name = &"character/firebolt_cast"`. Do not change TestScene.

- [ ] **Step 8: Run focused integration tests**

Run:

```text
UnitSystem/Tests/UnitBaseSkillHostAssemblyTest.gd
UnitSystem/Tests/CasterSkillActionAssemblyTest.gd
UnitSystem/Tests/CasterFireboltRuntimeTest.gd
UnitSystem/Tests/AISkillActionAnimationTest.gd
```

Expected: all PASS.

- [ ] **Step 9: Run all new SkillSystem tests**

Run every script under `SkillSystem/12-SingleScene/Tests`.

Expected: all PASS.

- [ ] **Step 10: Archive the legacy system only after all focused tests pass**

Before moving, resolve and verify the exact absolute source and target paths:

```text
Source: G:\Godot\SipSip\SkillSystem legacy numbered folders
Target: G:\Godot\SipSip\Archive\SkillSystemLegacy-2026-07-28
```

Use native PowerShell `Move-Item -LiteralPath` in one shell. Do not recursively delete anything.

Archive:

- old `01-Core` through `09-Presets`
- old `10-Docs`
- old `11-Tests`
- old Firebolt/HolyLight Definition and Delivery assets

Keep reusable effects and projectile scenes in their existing non-SkillSystem folders.

- [ ] **Step 11: Promote staging files and update paths**

Move:

```text
12-SingleScene/Core       → 01-Core
12-SingleScene/Delivery   → 02-Delivery
12-SingleScene/Extensions → 03-Extensions
12-SingleScene/Tests      → 05-Tests
```

Rename:

```text
FireboltSkillSingleScene.tscn → FireboltSkill.tscn
HolyLightSkillSingleScene.tscn → HolyLightSkill.tscn
```

Update all `res://SkillSystem/12-SingleScene/...` references with `apply_patch`, preserve `.uid` sidecars, and let Godot rescan.

- [ ] **Step 12: Verify scene UIDs and typed embedded Resources**

Run a Godot verification script asserting:

```gdscript
for path: String in [
	"res://SkillSystem/01-Core/SkillBase.tscn",
	"res://SkillSystem/01-Core/SkillHostComponent.tscn",
	"res://SkillSystem/00-Skills/Firebolt/FireboltSkill.tscn",
	"res://SkillSystem/00-Skills/HolyLight/HolyLightSkill.tscn",
]:
	assert(ResourceLoader.get_resource_uid(path) != ResourceUID.INVALID_ID)
	assert(load(path) is PackedScene)
```

Instantiate Firebolt and HolyLight and assert their Delivery fields retain the correct typed Resource classes.

- [ ] **Step 13: Rewrite the human-facing guide and root README**

The guide must give this exact workflow:

```text
1. Inherit SkillBase.tscn.
2. Save one concrete SkillNameSkill.tscn.
3. Configure the root Inspector from Identity through Delivery.
4. Create the correct embedded DeliveryConfig.
5. Add Condition, Cost, or Effect child components only when genuinely needed.
6. Add the skill scene under UnitBase/SkillHost/SkillSocket.
7. Create the character cast animation and add release_action()/finish_action() method keys.
8. Run the configuration and runtime tests.
```

Include Firebolt and HolyLight as the only initial examples.

Replace the active `SkillSystem/README.md` with a short entry page that links to the new guide and states that each skill has one authoritative `.tscn`.

- [ ] **Step 14: Full verification**

Run:

```powershell
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' --headless --editor --quit --path .
```

Then run all scripts under:

```text
SkillSystem/05-Tests
UnitSystem/Tests
```

Classify unrelated pre-existing failures separately; no new parser error, invalid UID, missing resource, world-origin launch, duplicate cast, cooldown timing, or old Independent SkillSystem reference may remain.

- [ ] **Step 15: Final filesystem audit**

Use:

```powershell
rg -n "IndependentSkill|SkillDefinition|FireboltDelivery|HolyLightDelivery|12-SingleScene" SkillSystem UnitSystem
```

Expected:

- No active SkillSystem or UnitSystem runtime file references the archived implementation.
- References inside `Archive/SkillSystemLegacy-2026-07-28` are allowed.
- No `FireboltSkillDefinition.tres`, `HolyLightSkillDefinition.tres`, `FireboltDelivery.tscn`, or `HolyLightDelivery.tscn` remains in the active SkillSystem.
- `Scenes/TestScene.tscn` has not changed.

---

## Implementation Checkpoints

Because the project is not a Git repository, each task ends with:

1. A named RED test result.
2. A named GREEN test result.
3. A Godot editor scan when scripts, scenes, or Resources are added.
4. A concise record in the implementation commentary of files changed and verification commands run.

No archive or promotion operation may begin until Tasks 1–7 are GREEN.
