# AI Combat Inheritance Implementation Plan

**Goal:** Establish reusable AI combat base, melee specialization, and ranged specialization scenes without implementing projectile release yet.

1. Add an inheritance contract test for base, melee, and ranged combat scenes.
2. Refactor `AIAttackController` from direct melee-hitbox ownership to generic hit-window signals while preserving its `attack_hit` event bus for feedback consumers.
3. Make `AICombatSystem` a hitbox-free shared base that configures the controller and forwards confirmed hits.
4. Create `AIMeleeCombatSystem` to connect hit windows to `MeleeHitboxComponent` and migrate `AIUnitBase` default combat scene to it.
5. Create an empty `AIRangedCombatSystem` inheritance endpoint for the following projectile-delivery task.
6. Validate scene inheritance, test compilation, and main-scene startup without debugger errors.
