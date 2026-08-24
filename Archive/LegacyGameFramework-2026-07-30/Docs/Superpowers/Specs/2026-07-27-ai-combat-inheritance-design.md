# AI Combat Inheritance Design

## Goal

Separate AI melee and ranged delivery while keeping weapon equipment, attack animation, shared cooldown, and hit feedback in one reusable combat base.

## Scene hierarchy

```text
AICombatSystem.tscn
├── AttackController
└── HitFeedbackBridge

AIMeleeCombatSystem.tscn (inherits AICombatSystem)
└── MeleeHitbox

AIRangedCombatSystem.tscn (inherits AICombatSystem)
```

## Responsibilities

- `AICombatSystem`: weapon setup, target validation, attack range, global cooldown, common attack signals, and hit-feedback bridge wiring.
- `AIMeleeCombatSystem`: consumes hit-window events and uses `MeleeHitboxComponent` to emit confirmed hits.
- `AIRangedCombatSystem`: currently provides the ranged inheritance endpoint; the next task will add projectile release delivery.
- `AIAttackController`: owns animation state and exposes generic hit-window events. It does not own a melee hitbox.

## Compatibility

`AIUnitBase` now defaults to `AIMeleeCombatSystem`, preserving existing Guardian, Saber, and EnemyBase2 melee behavior. No TestScene unit instance was modified. Archer is not yet migrated to the ranged component; this is deferred until projectile release is implemented.
