# Combat Foundation Components Design

Date: 2026-07-16

## Objective

Introduce the minimum reusable combat-data foundation required by the future configurable skill system. The project gains a generic numeric resource pool, a health-specific specialization, and a faction/team component. These components are mounted on the Hero, AllyBase, and EnemyBase source scenes without changing their existing movement, AI, targeting, attack, gravity, or scene-placement behavior.

The components belong in the existing project organization rather than a separate skill-system directory.

## File Organization

```text
Scripts/Combat/Components/
├── ResourcePoolComponent.gd
├── HealthComponent.gd
└── FactionComponent.gd

Scenes/Components/Combat/
├── HealthComponent.tscn
└── FactionComponent.tscn

Tests/
└── CombatFoundationComponentsTest.gd
```

No new Resource asset is needed in this phase. Component defaults live in their scripts and reusable component scenes; per-unit overrides live in the owning source scene.

## ResourcePoolComponent

`ResourcePoolComponent` is a reusable `Node` for any bounded floating-point resource such as health, mana, stamina, or satiety. It is not a container for unrelated gameplay state.

Inspector configuration:

```gdscript
@export var resource_id: StringName = &"resource"
@export_range(0.0, 999999.0, 0.1, "or_greater") var maximum_value: float = 100.0
@export_range(0.0, 999999.0, 0.1, "or_greater") var starting_value: float = 100.0
```

Runtime state is initialized from `starting_value` and clamped to the current maximum. Runtime current value is not an exported authoring field.

Public API:

```gdscript
func get_current_value() -> float
func get_maximum_value() -> float
func get_value_ratio() -> float
func is_empty() -> bool
func set_current_value(value: float, source: Node = null) -> float
func modify_value(amount: float, source: Node = null) -> float
func try_consume(amount: float, source: Node = null) -> bool
func restore_full(source: Node = null) -> void
```

Return values from mutation methods represent the actual applied signed delta after clamping. `try_consume()` rejects negative values and performs no partial consumption when the available value is insufficient. A zero consumption succeeds without emitting a change signal.

Signals:

```gdscript
signal value_changed(
    previous_value: float,
    current_value: float,
    maximum_value: float,
    source: Node
)
signal depleted(source: Node)
signal restored_from_empty(source: Node)
```

`depleted` and `restored_from_empty` are transition signals: they fire only when crossing the empty boundary, not on repeated writes of the same value.

## HealthComponent

`HealthComponent` extends `ResourcePoolComponent` and supplies health semantics without becoming a parent for mana, mood, buffs, or other state.

Defaults:

```text
resource_id = health
maximum_value = 100.0
starting_value = 100.0
```

Public API:

```gdscript
func apply_damage(amount: float, source: Node = null) -> float
func apply_healing(amount: float, source: Node = null) -> float
func is_dead() -> bool
func revive(value: float = 1.0, source: Node = null) -> bool
```

Damage and healing reject negative inputs. Their return value is the positive amount actually removed or restored. Healing cannot revive a depleted component; revival must use `revive()`. `revive()` succeeds only while dead, clamps its requested value to at least a positive epsilon and at most maximum health, and emits the standard value transition plus `revived`.

Signals:

```gdscript
signal damaged(actual_amount: float, source: Node)
signal healed(actual_amount: float, source: Node)
signal died(source: Node)
signal revived(current_health: float, source: Node)
```

`died` fires once when health crosses from positive to zero. This phase does not queue-free the owner, disable AI, change collision, play animations, or otherwise interpret death.

## FactionComponent

`FactionComponent` is a reusable `Node` containing both descriptive identity and gameplay team membership.

Inspector configuration:

```gdscript
@export var faction_id: StringName = &"neutral"
@export var team_id: int = 0
@export var targetable: bool = true
```

Public relationship API:

```gdscript
func is_friendly_to(other: FactionComponent) -> bool
func is_hostile_to(other: FactionComponent) -> bool
func is_neutral_to(other: FactionComponent) -> bool
```

Relationship rules:

- Equal nonzero team IDs are friendly.
- Different nonzero team IDs are hostile.
- If either team ID is zero, the relationship is neutral.
- `faction_id` describes identity and does not independently determine hostility.
- A null or invalid other component is treated as neutral and never friendly or hostile.

`targetable` is metadata for future selectors. These relationship methods do not hide a component solely because `targetable` is false; the future query/selection layer applies targetability.

## Scene Assembly

The reusable packed scenes are mounted as direct children of each combatant root:

```text
Hero
├── HealthComponent
├── FactionComponent
└── existing nodes

AllyBase
├── HealthComponent
├── FactionComponent
└── existing nodes

EnemyBase
├── HealthComponent
├── FactionComponent
└── existing nodes
```

Exact source-scene defaults:

| Source scene | faction_id | team_id | health |
|---|---|---:|---:|
| `Scenes/ObjectScenes/Hero.tscn` | `player` | 1 | 100/100 |
| `Scenes/ObjectScenes/AllyBase.tscn` | `ally` | 1 | 100/100 |
| `Scenes/EnemyScenes/EnemyBase.tscn` | `enemy` | 2 | 100/100 |

Inherited Ally professions and Enemy Dummy receive these nodes through scene inheritance. Existing `enemy_targets` groups and collision layers remain unchanged. No unit is added to or removed from TestScene.

## Dependency Boundary

The three components depend only on Godot core Node, numeric, and signal APIs. They do not preload or reference HeroController, AllyBase, EnemyBase, SkillModuleBase, attack modules, concrete skills, or TestScene.

Existing character scripts do not gain component fields or behavior in this phase. Future systems discover the standard child nodes or receive component references through open interfaces. This keeps the current runtime behavior unchanged while establishing a stable integration contract.

## Error and Edge-Case Handling

- Maximum and starting values are clamped to nonnegative valid values during initialization.
- A zero maximum produces a safe value ratio of `0.0` rather than division by zero.
- Redundant writes do not emit value or transition signals.
- Negative damage, healing, or consumption requests are rejected without mutation.
- Missing faction counterparts resolve to neutral relationship results.
- Component scenes remain valid when instantiated outside a CharacterBody3D because they do not assume a specific owner type.

## Validation

Automated tests verify:

- Initial clamping and zero-maximum ratio behavior.
- Signed delta semantics for set and modify operations.
- Atomic consumption and negative-input rejection.
- Empty/restored transition signals firing exactly once per boundary crossing.
- Damage, healing, death, blocked healing while dead, and explicit revival.
- Friendly, hostile, and neutral team relationships.
- Exact Hero, AllyBase, and EnemyBase component paths and default configuration.
- Inherited Ally and Enemy scenes receive the components.
- Existing project scripts compile and all current headless tests remain green.

TestScene is not modified. If runtime observation in TestScene is useful, the user retains responsibility for adding unit instances according to the project collaboration rule.

## Deferred Scope

- Mana, stamina, satiety, attributes, mood, buffs, and debuffs.
- Damage formulas, healing formulas, armor, resistance, critical hits, or invulnerability.
- Death behavior, resurrection gameplay, UI bars, saving, replication, or persistence.
- Combat query service, target selection, and skill payload delivery.
- Migration of existing group-based enemy detection to FactionComponent.
