# Pack Target Handoff Design

## Goal

When an enemy cannot retain or acquire a local target, it may continue the encounter by adopting a valid target that another living combatant in the same Pack is already fighting.

## Design

`AITargetingComponent` remains the sole owner of a unit's current locked target. It resolves targets in this order:

1. Retain a valid local target inside its normal retention radius.
2. Select a valid candidate inside its normal perception radius through its existing `TargetSelectionPolicy`.
3. Only if local resolution yields no target, ask an injected Pack fallback resolver for a valid target currently held by another member of the same Pack.

The fallback resolver is a `Callable` supplied by `EncounterController`; it is not an exported scene reference and does not create a second target field. `EncounterController` owns Pack membership and returns only targets held by living, in-combat members of the requester's own Pack. It filters invalid, dead, non-targetable, and non-hostile targets, de-duplicates them, and chooses the nearest valid target to the requester.

## Pack Activation and Cleanup

The existing permanent `pack_assist_target` override is removed. When the first Pack member enters combat, `EncounterController` asks every living member to refresh normally. The original discoverer keeps its local target; the other members receive that target through the same Pack fallback path. This unifies initial Pack engagement and end-of-fight handoff.

If no member holds a valid target, the fallback returns `null`; the existing targeting and combat-reset behavior proceeds unchanged. Pack reset and Pack clear detach the fallback resolver from every member.

## Constraints

- Only a requester's own Pack may provide fallback targets; the controller never searches the whole room.
- Pack fallback never overrides a valid local target.
- No new Inspector parameter or Resource is required.
- The change does not add or modify unit instances in `TestScene.tscn`.
- All public APIs introduced by the implementation must have adjacent Simplified Chinese documentation.

## Verification

- A member outside local perception can join a Pack's first combat target through fallback resolution.
- A member with no local candidate can adopt a valid target currently held by a Pack ally.
- A valid local candidate takes priority over a Pack target.
- Dead, invalid, non-hostile, or out-of-combat providers cannot supply a target.
- Reset and clear remove Pack fallback behavior.
