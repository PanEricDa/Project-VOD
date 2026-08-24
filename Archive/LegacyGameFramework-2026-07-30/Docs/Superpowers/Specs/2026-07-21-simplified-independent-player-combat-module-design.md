# Simplified Independent Player Combat Module Design

## 1. Goal

Replace the current PlayerBase weapon-combat assembly with a smaller, independent
combat module while keeping the legacy Hero combat system frozen as a behavioral
reference.

The new system must:

- Keep Unit and Combat responsibilities separate.
- Support editor assembly and runtime weapon replacement.
- Use one flat data Resource per concrete weapon.
- Keep attack animations outside weapon scenes.
- Preserve open interfaces without introducing databases, entry Resources or
  nested configuration profiles.
- Preserve the useful behavior of the legacy three-hit sword attack.

## 2. Legacy System Boundary

The following legacy files remain unchanged, unreferenced by the new system and
available as a working comparison:

```text
res://Scenes/ObjectScenes/Hero.tscn
res://Scenes/Components/MeleeAttackModule.tscn
res://Scripts/HeroController.gd
res://Scripts/Combat/MeleeAttackModule.gd
res://Scripts/Combat/MeleeHitDetector.gd
res://Effects/Combat/
```

The new system may use the legacy behavior and parameter values as reference, but
must not preload, instantiate, inherit or call any legacy combat file.

## 3. Unit Boundary

`PlayerBase` contains only unit concerns:

```text
PlayerBase
├── Visual
│   └── CharacterActionRig
│       ├── BodyRoot
│       └── WeaponSocket
├── CollisionShape3D
└── TargetingSystem
```

`PlayerBase.gd` continues to own:

- Movement and acceleration.
- Visual facing.
- Dash.
- Gravity.
- Target acquisition and target-facing behavior.

PlayerBase does not reference:

- A combat controller or combat module.
- An attack AnimationPlayer.
- A melee hitbox.
- A weapon data Resource.
- A weapon animation library.
- A combat database.

## 4. New Filesystem Layout

The replacement subsystem uses a small, unnumbered layout:

```text
WeaponCombatSystem/
├── README.md
├── PlayerCombatModule.gd
├── PlayerCombatModule.tscn
├── WeaponData.gd
│
├── Weapons/
│   └── IronSword/
│       ├── IronSwordData.tres
│       ├── IronSword.tscn
│       ├── IronSwordVisual.tscn
│       └── IronSwordAnimations.tres
│
├── Authoring/
│   ├── PlayerCombatTestCharacter.tscn
│   └── IronSwordWorkbench.tscn
│
└── Tests/
```

The existing numbered WeaponCombatSystem is removed only after the replacement
module passes its independent tests.

## 5. Flat Weapon Data

Every concrete weapon owns exactly one flat `WeaponData` Resource:

```gdscript
class_name WeaponData
extends Resource

@export var display_name: String
@export var weapon_scene: PackedScene
@export var attack_animation_library: AnimationLibrary
@export var hitbox_size: Vector3
@export var hitbox_offset: Vector3
```

`IronSwordData.tres` directly references:

- `IronSword.tscn`.
- `IronSwordAnimations.tres`.
- The sword hitbox size.
- The sword hitbox offset.

There is no WeaponType, Race, AnimationEntry, AnimationDatabase, Setup Resource,
Animation Profile or custom Resource nested inside WeaponData.

Inventory, save and equipment systems can retain a `WeaponData` reference and call
the combat module directly at runtime.

## 6. Combat Module Scene

The new module is one scene with one script:

```text
PlayerCombatModule
├── AttackAnimationPlayer
├── MeleeHitbox
└── DebugHitbox
```

- `PlayerCombatModule` is the scripted root.
- `AttackAnimationPlayer` holds the currently equipped external library.
- `MeleeHitbox` is a plain `ShapeCast3D` without another behavior script.
- `DebugHitbox` visualizes the configured box while authoring or debugging.

The module exposes strongly typed node references:

```gdscript
@export var owner_body: CharacterBody3D
@export var body_root: Node3D
@export var weapon_socket: Node3D
@export var starting_weapon: WeaponData
```

Designers assign these nodes through the Inspector. The module does not expose
manual NodePath strings and does not depend on `PlayerBase.gd`.

## 7. Public Interface

```gdscript
func configure(
    owner_body: CharacterBody3D,
    body_root: Node3D,
    weapon_socket: Node3D
) -> bool

func equip_weapon(weapon_data: WeaponData) -> bool
func unequip_weapon() -> void

func request_attack() -> void
func cancel_attack() -> void
func is_attacking() -> bool
func get_equipped_weapon_data() -> WeaponData
```

Runtime equipment uses:

```gdscript
combat_module.equip_weapon(selected_weapon_data)
```

Failed equipment is atomic: the currently valid weapon and animation library
remain installed until the replacement has been fully validated and instantiated.

## 8. Input and Combo Behavior

The module reads InputMap directly:

```gdscript
@export var attack_action: StringName = &"player_attack"
@export var input_buffer_duration: float = 0.15
@export var combo_reset_duration: float = 0.7
@export var hold_to_attack: bool = true
@export var hold_restart_delay: float = 0.3
```

Animation names are discovered automatically:

```text
RESET
basic_attack_1
basic_attack_2
basic_attack_3
...
```

The sequence ends at the first missing number. `basic_attack_1` is mandatory and
gaps inside a discovered combo are rejected during equipment validation.

Behavior:

- A single press plays attack 1.
- A valid buffered press advances to the next attack.
- Combo continuation remains available for `combo_reset_duration`.
- Holding the action automatically advances the combo.
- Holding through the final attack starts a new sequence after
  `hold_restart_delay`.
- Movement, dash, gravity and target-facing remain controlled by PlayerBase.

## 9. Animation Ownership

`IronSwordAnimations.tres` is authored against the real composed character
hierarchy in `IronSwordWorkbench.tscn`.

Animations control:

- `BodyRoot`.
- `WeaponSocket`.

The third-hit counter-clockwise windup and clockwise rotation are animation
tracks, not specialized controller code.

Animation method tracks may call only these generic module hooks:

```gdscript
func animation_open_hitbox() -> void
func animation_close_hitbox() -> void
func animation_request_lunge(distance: float, duration: float) -> void
```

The module does not know that attack 3 is a spin attack.

## 10. Hitbox, Lunge and Hit Stop

When a weapon is equipped:

- `WeaponData.hitbox_size` updates the box shape.
- `WeaponData.hitbox_offset` updates the ShapeCast position.
- DebugHitbox reads the same values.

During an open hit window:

- ShapeCast updates every physics frame.
- Only valid enemy targets on the configured mask and target group are accepted.
- The owner body is excluded.
- Every target is emitted once per window.
- Closing the window clears detection state and hides the debug shape.

Lunge is a generic module operation requested by animation method tracks. It moves
the owner body horizontally without modifying PlayerBase velocity ownership after
the requested duration ends.

On a valid hit, the module applies a short local hit stop:

- Attack animation pauses.
- Lunge progression pauses.
- Hitbox progression pauses.
- PlayerBase movement, gravity, target-facing and the rest of the world continue.

Camera shake, sound, particles and damage are not embedded in the module. They can
listen to `attack_hit` later.

## 11. Signals

The external signal surface is intentionally small:

```gdscript
signal weapon_equipped(weapon_data: WeaponData)
signal weapon_unequipped()
signal attack_started(combo_index: int)
signal attack_finished(combo_index: int)
signal attack_hit(
    target: CharacterBody3D,
    hit_position: Vector3,
    hit_direction: Vector3,
    combo_index: int
)
```

Internal combo and hit-window state does not create additional public signals.

## 12. Composition and Authoring

`PlayerCombatTestCharacter.tscn` inherits PlayerBase and adds one module:

```text
PlayerCombatTestCharacter
└── PlayerCombatModule
```

The scene assigns:

- Owner Body to the inherited character root.
- Body Root to the inherited BodyRoot.
- Weapon Socket to the inherited WeaponSocket.
- Starting Weapon to IronSwordData.

It requires no binder script.

`IronSwordWorkbench.tscn` instances the test character and adds only the ground,
light and camera needed for animation authoring and direct preview.

## 13. Error Handling

- Missing owner, body root or socket disables combat without affecting unit
  movement.
- Missing WeaponData ignores attack input.
- Missing weapon scene rejects equipment.
- Missing animation library rejects equipment.
- Missing `basic_attack_1` rejects equipment.
- Invalid animation track targets reject equipment.
- Failed weapon scene instantiation preserves the current weapon.
- Missing hitbox configuration disables hit detection but does not stop animation.

Configuration failures are reported once with clear context and do not create
per-frame error spam.

## 14. Safe Migration

1. Create the new flat files and failing tests.
2. Implement the new module without referencing legacy Hero files.
3. Build IronSwordData, IronSword animations and the authoring scenes.
4. Verify new equipment, combo, hitbox, lunge, rotation and hit stop.
5. Remove current combat nodes and resource references from PlayerBase.
6. Verify PlayerBase movement, dash, gravity, facing and targeting independently.
7. Delete the superseded numbered WeaponCombatSystem implementation only after
   the replacement tests pass.
8. Keep the legacy Hero combat system unchanged.

The migration does not add, remove or replace any unit instance in
`Scenes/TestScene.tscn`.

## 15. Verification

New automated coverage:

```text
PlayerBasePurityTest
WeaponDataTest
PlayerCombatModuleTest
PlayerCombatComboTest
PlayerCombatHitboxTest
PlayerCombatTestCharacterTest
LegacyHeroIsolationTest
```

Required results:

- The new system has no references to legacy Hero combat files.
- The legacy system has no references to the new system.
- PlayerBase contains no combat nodes or combat resources.
- PlayerCombatModule does not depend on `PlayerBase.gd`.
- IronSword can be equipped, unequipped and equipped again at runtime.
- Single press, buffered combo, hold combo and sequence restart work.
- Hitbox timing, per-window deduplication and hit stop work.
- Attack lunge and third-hit animation match the reference behavior closely enough
  for side-by-side testing.
- Removing the module leaves unit movement and targeting functional.
- Existing UnitSystem tests pass.
- Godot 4.7 completes a full import with no errors or warnings.
- Legacy file hashes remain unchanged.
- TestScene content hash remains unchanged.

After implementation, the user manually adds
`PlayerCombatTestCharacter.tscn` to TestScene for comparison if desired.

