# Ranged Attack Movement and Combat Boundary Design

## Goal

Prevent ranged units from continuously kiting and firing while leaving the player’s combat area, while retaining their existing attack-gap movement and combat positioning.

## Weapon-Owned Attack Movement

- `WeaponData` gains `attack_movement_speed_multiplier`, a `0.0–1.0` basic-attack setting.
- `1.0` is the inherited default and preserves existing movement for all current melee weapons.
- Bow overrides it to `0.0`: while its normal attack animation is active, the Archer has no horizontal combat movement; immediately after the action ends, existing combat movement resumes.
- Future ranged weapons may set values such as `0.4` without script changes.
- `AllyBehaviorStateMachine` consumes this through `AICombatSystem`; it does not branch on bow, ranged type, or a unit name.

## Bidirectional Player Combat Boundary

- Rename the existing `maximum_player_target_distance` to `maximum_combat_player_distance`, retaining its default `12m` and Inspector configurability.
- Force the existing disengage-and-return chain when either the enemy target or the ally itself exceeds this horizontal distance from the player.
- Return continues to use the existing formation reposition, dash, and targeting suspension paths. No new retreat state or movement system is added.

## Boundaries

- No retreat charges, retreat cooldown, target radius changes, attack-rate changes, or melee special cases are added.
- Player-controlled attack movement is not changed in this pass.
- No TestScene unit instance is modified.
