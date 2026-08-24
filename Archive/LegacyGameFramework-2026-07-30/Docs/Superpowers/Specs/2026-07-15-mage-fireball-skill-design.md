# Mage Fireball Skill Design

Date: 2026-07-15

## Objective

Create the Mage's first functional projectile skill on top of the existing decoupled skill module architecture. The Mage automatically requests, approaches, casts, and delivers Fireball through generic Ally skill scheduling. Fireball uses limited homing, swept collision, and a small explosion query; it emits hit events but does not apply damage, knockback, status effects, or hit feedback.

The design must remain compatible with multiple skills per unit even though Mage equips only Fireball in this phase.

## Dependency Direction

```text
AllyBase -> SkillModuleBase public API
FireballSkill -> SkillModuleBase
FireballSkill -> FireballProjectile public launch API
FireballProjectile -X-> AllyBase
SkillModuleBase -X-> AllyBase
```

AllyBase owns generic AI-host responsibilities: skill registration, one active skill, target provision, movement ownership, facing, action exclusion, and shared combat cooldown. SkillModuleBase continues to own request delay, queue, cast timing, final validation, delivery result, and skill-local cooldown. FireballSkill only creates and launches a projectile. FireballProjectile only steers, detects collision, produces explosion results, and renders its visuals.

No fireball-specific condition, node path, projectile parameter, or hit rule may be added to AllyBase.

## Multi-Skill-Compatible Registration

AllyBase maintains:

```gdscript
var registered_skill_modules: Array[SkillModuleBase]
var active_skill_module: SkillModuleBase
```

On ready, it scans direct children of `VisualRoot/SkillModuleSocket` and registers every `SkillModuleBase`. The existing `skill_module_path`, `set_skill_module()`, and `get_skill_module()` remain compatible as the primary-skill shortcut. Runtime mounting and unmounting update the registry without requiring a scene reload.

Only one module may be active at a time. Other registered modules continue their local cooldown timers but may not request movement or cast concurrently.

SkillProfile gains:

```gdscript
@export var ai_priority: int = 0
@export var can_move_while_casting: bool = false
```

The default selector chooses the highest-priority module that can accept a request and has a valid target. Equal-priority candidates are selected randomly. With one equipped skill this reduces to Fireball without special cases.

## Open Selection Interfaces

AllyBase exposes overridable methods:

```gdscript
func select_skill_module(
    available_modules: Array[SkillModuleBase]
) -> SkillModuleBase

func select_target_for_skill(module: SkillModuleBase) -> Node3D
```

Default target rules:

- `ENEMY`: return `current_visible_enemy` when valid.
- `SELF`: return the current Ally instance.
- `ALLY`: return null. A future Healer specialization overrides this without changing SkillModuleBase.

Target acquisition belongs to the host because SkillModuleBase must remain reusable by non-Ally actors. Concrete skill modules may add stricter target validation through Profile group configuration or overridden module methods, but they do not search the world.

## Generic Ally Skill Scheduling

The scheduler is active only while AllyBase is in combat and has registered skills.

```text
No active skill
  -> collect requestable modules with valid targets
  -> select one module
  -> request_skill(target)
Active DECISION_WAIT
  -> continue normal guard-distance wandering
Active QUEUED and out of range
  -> skill approach owns horizontal movement
Active QUEUED and in range
  -> wait for shared cooldown and current attack to clear
  -> begin_cast()
Active CASTING
  -> stop active movement unless can_move_while_casting=true
  -> continuously face the current skill target
Successful delivery or terminal cancellation
  -> release active module
  -> return to guard-distance behavior
```

Rules:

- A currently playing basic attack is never interrupted. A queued skill starts after the attack and shared cooldown allow it.
- `cast_started` immediately starts the existing per-unit shared combat cooldown, preserving current basic-attack timing semantics.
- Skill-local cooldown starts only after `deliver_skill()` succeeds.
- During decision delay, guard wandering continues and no skill approach target is calculated.
- During queued approach, skill movement is the only horizontal movement producer for the frame.
- During cast, AllyBase keeps facing the skill target. Fireball uses `can_move_while_casting=false`, so active horizontal velocity is smoothed to zero.
- A forced combat disengage, invalid target, unmounted active module, or owner exit cancels the current skill request and releases movement ownership.
- When a cast fails final range validation, SkillModuleBase restarts its approved random decision wait for the same structurally valid target. AllyBase keeps that module active.
- Successful delivery releases the active slot while the module independently enters cooldown, allowing another future skill to be selected.

## SkillModuleBase Animation Extension

SkillModuleBase gains:

```gdscript
@export var cast_animation_name: StringName = &"cast"
```

Behavior:

- A successful `begin_cast()` plays the configured animation when it exists.
- The Profile `cast_time` remains authoritative; animation length does not decide delivery timing.
- Cancel, failure, successful delivery, reset, and exit restore `RESET`.
- Missing cast animation is valid for nonvisual skills and does not block casting.

No fireball visual or projectile logic enters the parent module.

## Fireball Skill Module

Planned files:

```text
Scripts/Combat/Skills/FireballSkill.gd
Scenes/Components/SkillModules/FireballSkill.tscn
Resources/Combat/Skills/MageFireballProfile.tres
```

Inherited scene shape:

```text
FireballSkill
├── CastOrigin
├── CastChargeVisual
│   ├── ChargeCore
│   ├── ChargeShell
│   └── ChargeParticles
├── DeliveryRoot
└── SkillAnimationPlayer
```

Profile defaults:

```text
display_name = "Mage Fireball"
target_faction = ENEMY
delivery_type = PROJECTILE
required_target_group = enemy_targets
cast_range = 6.0m
cast_range_tolerance = 0.25m
cast_time = 0.75s
skill_cooldown = 5.0s
decision_delay_min = 0.3s
decision_delay_max = 3.0s
extra_hesitation_chance = 0.10
extra_hesitation_min = 3.0s
extra_hesitation_max = 5.0s
ai_priority = 0
can_move_while_casting = false
```

FireballSkill exports projectile scene and launch parameters. Its override:

```gdscript
func deliver_skill(
    caster: Node3D,
    target: Node3D,
    target_position: Vector3
) -> bool
```

must:

1. Validate the projectile PackedScene, CastOrigin, scene tree, caster, and CharacterBody3D enemy target.
2. Instantiate the projectile under the current gameplay scene, not under Mage, so owner motion cannot drag the projectile.
3. Call the projectile's launch API using CastOrigin global position and current parameters.
4. Free the instance and return false when launch fails.
5. Return true only after a projectile successfully enters active flight.

Signals:

```gdscript
signal projectile_launched(projectile: Node3D)
signal projectile_impacted(position: Vector3)
signal fireball_hit(
    target: CharacterBody3D,
    hit_position: Vector3,
    hit_direction: Vector3
)
signal fireball_exploded(
    position: Vector3,
    targets: Array[CharacterBody3D]
)
```

The skill module forwards projectile events without applying gameplay results.

## Fireball Projectile

Implemented files:

```text
res://Scripts/Combat/Skills/FireballProjectile.gd
res://Scenes/Projectiles/FireBall.tscn
```

Node structure:

```text
FireBall (FireballProjectile.gd)
├── CollisionSweep
├── FireballFlightEffect (approved scene instance)
└── FireballExplosionEffect (approved scene instance)
```

Launch API:

```gdscript
func launch(
    caster: Node3D,
    target: CharacterBody3D,
    start_position: Vector3,
    initial_direction: Vector3,
    speed: float,
    turn_speed_degrees: float,
    lifetime: float,
    explosion_radius: float
) -> bool
```

Defaults supplied by FireballSkill:

```text
speed = 9.0m/s
turn_speed_degrees = 180°/s
maximum_lifetime = 3.0s
collision_radius = 0.18m
explosion_radius = 1.2m
```

### Steering

Each physics frame calculates the desired direction toward the target's current position plus a configurable height offset. Current direction rotates toward the desired direction by no more than `turn_speed_degrees * delta`. It never assigns the desired direction directly, so the projectile cannot snap-lock.

If the tracked target becomes invalid, the projectile retains its last direction, stops homing, and continues until impact or lifetime expiry.

### Swept Collision

Before movement, `CollisionSweep` performs a sphere sweep from the current position across the full proposed frame displacement. This prevents tunneling at high speed.

- Collision mask includes environment layer `1` and enemy layer `4`.
- The combined sweep mask is therefore exactly `5`.
- Bodies are enabled; areas are disabled in the prototype.
- Caster RID is excluded.
- Ally layer `2` is not included, so allies do not block the fireball.
- The first environment or enemy collision stops flight and creates an explosion at the collision point.

Lifetime expiry silently frees the projectile without explosion or hit signals.

## Explosion Query and Hit Semantics

At impact, the projectile performs one spherical physics query using `explosion_radius` and enemy collision mask `4`.

- Only `CharacterBody3D` nodes in `enemy_targets` are accepted.
- Results are deduplicated by instance ID.
- The direct collision target is inserted into the same result set when valid, preventing a separate duplicate direct-hit event.
- Each accepted target emits one `fireball_hit` event with explosion position and outward horizontal hit direction.
- One `fireball_exploded` event contains the complete deduplicated target array.
- Environment impact with no nearby enemies still emits `projectile_impacted` and `fireball_exploded` with an empty target array.
- A radius of exactly zero uses one exact point query instead of constructing an invalid zero-radius sphere.
- When a sweep reports multiple contacts, the first hit is chosen by projected progress along the world-space flight direction, with a stable tie-break, rather than by radial distance from the projectile.

No damage, health lookup, knockback, burning, hit-stop, camera shake, or target mutation occurs.

## Prototype Visuals

All visuals use built-in Godot meshes, StandardMaterial3D resources, particles, and lights.

### Visual-First Delivery Workflow

The prototype visuals are implemented and accepted before any Fireball AI scheduling,
skill delivery, homing, collision, or explosion-query work begins. Visuals are split into
three reusable effect scenes so each phase can be previewed, tuned, and replaced without
touching gameplay code:

```text
Effects/Skills/Fireball/
├── FireballCastChargeEffect.tscn
├── FireballFlightEffect.tscn
└── FireballExplosionEffect.tscn
```

Each effect has its own independent Preview scene. Work stops after every scene until the
user has opened the Preview, tested the effect, adjusted Inspector exports if desired, and
explicitly approved proceeding. The mandatory order is:

```text
Cast charge approval
  -> flight approval
  -> explosion approval
  -> complete visual sequence approval
  -> gameplay implementation planning
```

During this visual-only phase:

- No effect searches for targets, applies damage, performs collision queries, or depends on
  `AllyBase`, `SkillModuleBase`, Mage, or TestScene.
- Effect scripts expose playback methods and Inspector parameters only.
- Preview scenes own their cameras, environment, looping, and prototype stand-ins.
- During visual approval, `Scenes/Projectiles/FireBall.tscn`, Mage assembly, and TestScene remained unchanged. Final gameplay implementation later upgraded that existing projectile scene and mounted the approved effects as child instances; TestScene remained untouched.
- Final gameplay scenes will instantiate these accepted effects through their public
  playback interfaces rather than duplicating their meshes, particles, or lights.

Flight:

- `0.18m` warm white/yellow emissive core.
- `0.30m` translucent orange-red shell.
- Short orange particle trail with sparse dark-red sparks.
- Small local orange OmniLight3D with shadows disabled.

Cast:

- A small orange-yellow orb appears at CastOrigin, grows, and pulses during the `0.75s` cast.
- Delivery hides and resets the charge visual before the projectile begins flight.

Explosion:

- A fast expanding translucent orange-red sphere.
- A brief particle burst and local light pulse.
- The projectile node remains only long enough to finish the short explosion visual, then frees itself.

The effect must remain small enough not to obscure units or vision rings. No external image, model, shader, or animation asset is required.

## Mage Assembly

In `Scenes/ObjectScenes/Mage.tscn`:

- Remove the placeholder `SkillModuleBase` instance.
- Add `FireballSkill` directly under `VisualRoot/SkillModuleSocket`.
- Update `skill_module_path` to `VisualRoot/SkillModuleSocket/FireballSkill` for compatibility.
- Preserve Mage body, hat, focus mesh, materials, formation values, combat guard distance, and all unrelated properties.

Do not modify `Scenes/TestScene.tscn`. Existing Mage instances inherit source-scene updates automatically.

## Final Implemented Contract (2026-07-16)

The authoritative runtime paths are:

```text
Projectile scene: res://Scenes/Projectiles/FireBall.tscn
Projectile script: res://Scripts/Combat/Skills/FireballProjectile.gd
Skill module: res://Scenes/Components/SkillModules/FireballSkill.tscn
Mage mount: VisualRoot/SkillModuleSocket/FireballSkill
Profile: res://Resources/Combat/Skills/MageFireballProfile.tres
```

`AllyBase` now discovers and maintains a generic multi-skill registry. It exposes the existing primary-slot compatibility API, selects the highest `ai_priority` that can accept a request and has a valid target, resolves equal-priority ties randomly, and grants movement/cast ownership to one active skill slot at a time. Default host target resolution is `ENEMY` = current perceived enemy and `SELF` = the owner; `ALLY` deliberately returns null until a specialization such as Healer overrides it.

The active flow is decision wait, exclusive approach when out of range, shared-cooldown/basic-attack gating, cast, delivery, and either cooldown or retry/release. During Fireball's cast, Mage smooths horizontal velocity to zero and keeps facing the target. A final range failure restarts the approved decision wait while retaining the active slot. Invalid targets, reset/unmount, or cancellation release movement ownership and the active slot. The per-unit shared cooldown starts when the cast begins; the skill-local cooldown starts only after successful projectile launch. A failed cast validation or failed launch never starts the skill-local cooldown, and cancellation does not erase a shared cooldown already started.

The exact `MageFireballProfile.tres` defaults are:

```text
display_name = "Mage Fireball"
target_faction = ENEMY
delivery_type = PROJECTILE
required_target_group = "enemy_targets"
ai_priority = 0
can_move_while_casting = false
cast_range = 6.0
cast_range_tolerance = 0.25
cast_time = 0.75
skill_cooldown = 5.0
decision_delay_min = 0.3
decision_delay_max = 3.0
extra_hesitation_chance = 0.1
extra_hesitation_min = 3.0
extra_hesitation_max = 5.0
```

The module supplies `9.0m/s` speed, `180°/s` maximum turn rate, `3.0s` lifetime, and `1.2m` explosion radius. `FireBall.tscn` supplies the `0.18m` sphere sweep, environment+enemy sweep mask `5`, and enemy-only explosion mask `4`; allies are ignored. Loss of a tracked target preserves the last direction for straight continuation. Charge, flight, and explosion reuse the three approved effect scenes. The complete gameplay output remains signals only: no damage or health access, knockback, burn/status mutation, or hit-feedback bridge is included.

## Error Handling

- Missing Profile prevents request and leaves the unit in normal guard behavior.
- Missing projectile scene, CastOrigin, gameplay parent, or launch API makes delivery return false and prevents skill cooldown.
- Invalid or out-of-range cast target follows existing SkillModuleBase failure behavior.
- Invalid tracked target after launch does not crash or fake a hit; flight continues in its last direction.
- Missing visual resources do not prevent collision and signals.
- Active skill removal cancels and releases Ally movement ownership without clearing public cooldown already started.

## Validation

Automated tests cover:

- Multi-module discovery and runtime register/unregister behavior.
- Highest-priority selection and random tie handling under a controlled random seed/profile setup.
- Target selection extension points for ENEMY, SELF, and unimplemented ALLY.
- Decision wait preserving guard wandering.
- Queued out-of-range skill exclusively owning approach movement.
- Shared cooldown and current basic attack blocking cast start.
- Cast stopping movement and maintaining target facing.
- Successful projectile launch starting skill cooldown; failed launch not starting it.
- Cast animation playback and all reset paths.
- Turn-rate-limited homing and invalid-target straight continuation.
- Swept collision against enemies and environment.
- Explosion group filtering and instance-ID deduplication.
- Lifetime expiry without fake explosion or hit.
- Mage exact module path and other professions remaining unmounted.
- All existing attack, effect, and skill tests remaining green.
- Godot 4.7 headless smoke and MCP editor errors equal to zero.
- TestScene timestamp, size, and SHA-256 unchanged.

## Deferred Scope

- Damage and health systems.
- Burning or other status effects.
- Hit feedback bridge, hit-stop, camera shake, sound, and damage numbers.
- Advanced multi-skill scoring, resource costs, charges, combo skills, interrupt resistance, or cast-speed stats.
- Formal animation assets or external VFX textures.
