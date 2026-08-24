# Hostile Melee Hitbox Mask Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Allow the shared AI melee Hitbox to discover hostile player and ally bodies while preserving team-based friendly-fire filtering.

**Architecture:** The physics mask is only a broad-phase candidate filter. `MeleeHitboxComponent` will query both existing combat body layers (2 and 4); its established `UnitBase.is_hostile_to()` check remains the final relationship decision. No enemy-specific combat component or duplicate damage path is introduced.

**Tech Stack:** Godot 4.7, GDScript, `PhysicsDirectSpaceState3D` shape query tests.

## Global Constraints

- Do not modify unit instances in `TestScene.tscn` or `TestCombatRoom.tscn`.
- Keep `MeleeHitboxComponent` reusable by players, allies, and enemies.
- Preserve existing `AICombatSystem → CombatValueResolver → UnitBase.apply_damage()` execution path.

---

### Task 1: Add the enemy-to-ally detection regression

**Files:**
- Modify: `UnitSystem/Tests/MeleeHitboxComponentTest.gd`

**Interfaces:**
- Consumes: default `MeleeHitboxComponent.target_collision_mask`, `configure_owner(owner)`, `begin_detection(weapon, index, direction)`.
- Produces: proof that an enemy-layer owner can detect a hostile ally-layer body and still ignores a same-team body.

- [x] **Step 1: Change the existing real physics fixture**

Set the owner to team `2`, collision layer `4`; set the hostile target to team `1`, collision layer `2`; set the friendly target to team `2`, collision layer `2`.

- [x] **Step 2: Run the test and observe RED**

Run:

```powershell
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' --headless --path 'G:\Godot\SipSip' --script 'res://UnitSystem/Tests/MeleeHitboxComponentTest.gd'
```

Expected: hostile target is not hit because the default query mask only includes layer `4`.

### Task 2: Widen common candidates, preserve hostile filtering

**Files:**
- Modify: `UnitSystem/Components/Combat/Common/MeleeHitboxComponent.gd`

**Interfaces:**
- Produces: default `target_collision_mask = 6`, meaning layer 2 plus layer 4.

- [x] **Step 1: Update the default mask and its Chinese Inspector documentation**

Set the default to `6` and describe that layer 2 contains player/allies and layer 4 contains enemies. State that the later hostility check, not the mask, prevents friendly fire.

- [x] **Step 2: Run the focused test and observe GREEN**

Run the Task 1 command. Expected: `MeleeHitboxComponentTest: PASS`.

### Task 3: Verify damage delivery remains unchanged

**Files:**
- Modify: `Docs/Superpowers/Plans/2026-08-01-hostile-melee-hitbox-mask-implementation-plan.md`

- [x] **Step 1: Run combat and editor checks**

Run `MeleeHitboxComponentTest.gd`, `BasicAttackDamageIntegrationTest.gd`, `UnitDeathLifecycleTest.gd`, and Godot's headless editor scan.

- [x] **Step 2: Record the result**

Mark every task complete only after all commands return exit code `0`; list expected test warnings separately from errors.

**Result (2026-08-01):** The RED test proved an enemy-layer owner could not discover a hostile ally-layer body with mask `4`. With the common mask set to `6`, `MeleeHitboxComponentTest`, `BasicAttackDamageIntegrationTest`, `AICombatSystemTest`, `UnitDeathLifecycleTest`, and the Godot editor scan all passed without errors. `BasicAttackDamageIntegrationTest` was also updated from an obsolete 13.5 expectation to the current Iron Sword default of 15 damage; this changes no runtime data or formula.
