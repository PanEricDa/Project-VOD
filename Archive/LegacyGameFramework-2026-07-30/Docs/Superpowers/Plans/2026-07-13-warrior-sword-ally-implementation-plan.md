# Warrior Sword Ally Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a reusable Warrior ally that inherits AllyBase, approaches slightly farther than Guardian, and performs one of three non-repeating random-bag sword attacks.

**Architecture:** `Warrior.tscn` only configures AllyBase and equips a new `SwordAttack.tscn`. `SwordAttack.gd` subclasses `AIAttackModuleBase`, overrides only animation availability/selection, and leaves targeting, approach, cooldown, hitbox, hit feedback, cancellation, and lifecycle behavior in the existing parent systems.

**Tech Stack:** Godot 4.7, GDScript, inherited PackedScenes, AnimationPlayer, ShapeCast3D, Resource `.tres`, SceneTree headless tests.

## Global Constraints

- All fields and methods use English identifiers; new code includes detailed Simplified Chinese comments.
- Do not reuse the player `MeleeAttackModule.gd`; only adapt its temporary sword visual and three WeaponPivot motion curves.
- Warrior uses `attack_range = 1.0`, while Guardian remains `0.8`.
- Each random bag contains every valid sword animation exactly once; a new bag cannot begin with the previous bag's final animation.
- SwordAttack inherits the shared AI Hitbox and `HitFeedbackBridge`; do not duplicate detection or feedback code.
- Do not modify `Scripts/AI/AllyBase.gd`, AI attack parent behavior, or `Scenes/TestScene.tscn`.
- The project is not a Git repository; do not create commits, branches, or worktrees.

---

### Task 1: Define the Warrior and SwordAttack contract with a failing test

**Files:**
- Create: `Tests/WarriorSwordAttackTest.gd`

**Interfaces:**
- Consumes: `AIAttackModuleBase.request_attack(target) -> bool`, `can_attack() -> bool`, inherited Hitbox and HitFeedback nodes.
- Produces: an executable contract for all new scene, Profile, animation, random-bag, and assembly requirements.

- [ ] **Step 1: Create the failing integration test**

The test must load the planned paths only after checking `ResourceLoader.exists()`, accumulate readable failures instead of crashing on missing files, and then verify:

```gdscript
const WARRIOR_SCENE_PATH := "res://Scenes/ObjectScenes/Warrior.tscn"
const SWORD_SCENE_PATH := "res://Scenes/Components/AiAttackModules/SwordAttack.tscn"
const PROFILE_PATH := "res://Resources/Combat/AI/WarriorSwordAttackProfile.tres"

# Scene/profile contract
_assert_true(ResourceLoader.exists(WARRIOR_SCENE_PATH), "missing Warrior.tscn", failures)
_assert_true(ResourceLoader.exists(SWORD_SCENE_PATH), "missing SwordAttack.tscn", failures)
_assert_true(ResourceLoader.exists(PROFILE_PATH), "missing WarriorSwordAttackProfile.tres", failures)

# Module contract after files exist
_assert_float_equal(sword.call("get_attack_range"), 1.0, "sword range", failures)
_assert_float_equal(sword.call("get_attack_range_tolerance"), 0.1, "sword tolerance", failures)
_assert_float_equal(sword.call("get_approach_speed_multiplier"), 1.2, "approach multiplier", failures)
_assert_true(not sword.call("should_return_to_guard_after_attack"), "sword should hold melee", failures)
_assert_true(sword.get("hitbox_enabled") == true, "sword hitbox disabled", failures)
_assert_true(sword.has_node("HitFeedbackBridge"), "missing inherited feedback", failures)

# Animation contract
var expected_lengths := {
    &"attack_1": 0.32,
    &"attack_2": 0.36,
    &"attack_3": 0.45,
}
for animation_name: StringName in expected_lengths:
    _assert_true(player.has_animation(animation_name), "missing " + animation_name, failures)
    _assert_float_equal(
        player.get_animation(animation_name).length,
        expected_lengths[animation_name],
        animation_name + " length",
        failures
    )
```

The method-track inspection must allow only `_open_hit_window` and `_close_hit_window`; it must fail if `_open_combo_window`, `_close_combo_window`, `_request_lunge_for_current_attack`, or `_request_third_attack_spin` appears.

The random-bag section must place a real `CharacterBody3D` target in the tree, request and manually finish three attacks, assert three unique names, then request a fourth attack and assert it differs from the third:

```gdscript
var selected: Array[StringName] = []
for index: int in range(3):
    _assert_true(sword.call("request_attack", target), "request failed", failures)
    var current: StringName = sword.get("attack_animation_name")
    selected.append(current)
    sword.call("_on_animation_finished", current)
_assert_true(_unique_count(selected) == 3, "bag repeated before exhaustion", failures)

_assert_true(sword.call("request_attack", target), "fourth request failed", failures)
var fourth: StringName = sword.get("attack_animation_name")
_assert_true(fourth != selected[2], "bag boundary repeated", failures)
```

Warrior assembly assertions:

```gdscript
_assert_true(warrior is CharacterBody3D, "Warrior must inherit AllyBase body", failures)
_assert_float_equal(warrior.get("combat_guard_distance"), 1.5, "guard distance", failures)
_assert_true(
    warrior.get("attack_module_path") == NodePath("VisualRoot/AttackModuleSocket/SwordAttack"),
    "Warrior attack_module_path is incorrect",
    failures
)
_assert_true(warrior.has_node("VisualRoot/AttackModuleSocket/SwordAttack"), "missing sword module", failures)
```

- [ ] **Step 2: Run the test and verify RED**

```powershell
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' --headless --path 'G:\Godot\SipSip' --script res://Tests/WarriorSwordAttackTest.gd
```

Expected: exit code `1`, with failures for the three missing planned resources.

### Task 2: Implement the AI sword random-bag selector

**Files:**
- Create: `Scripts/Combat/AI/SwordAttack.gd`

**Interfaces:**
- Consumes: `AIAttackModuleBase`, `attack_state`, `attack_profile`, `attack_animation_player`, and `attack_animation_name`.
- Produces: `attack_animation_names`, overridden `can_attack() -> bool`, and overridden `request_attack(target: CharacterBody3D) -> bool`.

- [ ] **Step 1: Add the minimal selector implementation**

```gdscript
class_name AISwordAttack
extends AIAttackModuleBase

## 可由具体剑类武器在 Inspector 中替换的普通攻击动画集合。
@export var attack_animation_names: Array[StringName] = [
    &"attack_1",
    &"attack_2",
    &"attack_3"
]

## 当前尚未使用的随机袋；只保存 AnimationPlayer 中真实存在的动画。
var animation_bag: Array[StringName] = []

## 上一次实际发动的动画，用于防止两个随机袋的边界连续重复。
var last_selected_animation: StringName = &""

## 避免无有效动画时由 AllyBase 每帧重复输出相同警告。
var missing_animation_warning_emitted: bool = false


## AllyBase 在进入接近阶段前会先调用本方法，因此必须按动画数组而不是父类单一动画名判断。
func can_attack() -> bool:
    return (
        attack_state == AttackState.IDLE
        and attack_profile != null
        and attack_animation_player != null
        and not _get_valid_animation_names().is_empty()
    )


## 仅在目标和模块状态有效时消耗随机袋，再复用父类完整攻击生命周期。
func request_attack(target: CharacterBody3D) -> bool:
    if not can_attack():
        _warn_if_no_valid_animation()
        return false
    if not is_instance_valid(target) or not target.is_inside_tree():
        return false
    if animation_bag.is_empty():
        _refill_animation_bag()
    if animation_bag.is_empty():
        _warn_if_no_valid_animation()
        return false

    attack_animation_name = animation_bag.pop_back()
    last_selected_animation = attack_animation_name
    return super.request_attack(target)


## 过滤空名称、不存在的动画和重复配置，使一袋内每种有效动作只出现一次。
func _get_valid_animation_names() -> Array[StringName]:
    var valid_names: Array[StringName] = []
    if attack_animation_player == null:
        return valid_names
    for animation_name: StringName in attack_animation_names:
        if (
            animation_name != &""
            and attack_animation_player.has_animation(animation_name)
            and not valid_names.has(animation_name)
        ):
            valid_names.append(animation_name)
    return valid_names


## 新建随机袋，并通过交换袋尾保证下一次 pop_back() 不会重复上一招。
func _refill_animation_bag() -> void:
    animation_bag = _get_valid_animation_names()
    animation_bag.shuffle()
    if (
        animation_bag.size() > 1
        and last_selected_animation != &""
        and animation_bag.back() == last_selected_animation
    ):
        var swap_value: StringName = animation_bag[0]
        animation_bag[0] = animation_bag[animation_bag.size() - 1]
        animation_bag[animation_bag.size() - 1] = swap_value
    if not animation_bag.is_empty():
        missing_animation_warning_emitted = false


func _warn_if_no_valid_animation() -> void:
    if missing_animation_warning_emitted:
        return
    missing_animation_warning_emitted = true
    push_warning("AISwordAttack: attack_animation_names has no valid animations.")
```

- [ ] **Step 2: Run the test again**

Expected: the script itself parses, while the test still exits `1` because the SwordAttack, Profile, and Warrior resources do not yet exist.

### Task 3: Build SwordAttack, Profile, and three sword animations

**Files:**
- Create: `Resources/Combat/AI/WarriorSwordAttackProfile.tres`
- Create: `Scenes/Components/AiAttackModules/SwordAttack.tscn`

**Interfaces:**
- Consumes: `AttackModuleBase.tscn`, `AISwordAttack`, `AIAttackProfile`, inherited Hitbox, and inherited HitFeedbackBridge.
- Produces: a complete equippable sword attack module.

- [ ] **Step 1: Create the Profile**

```ini
[gd_resource type="Resource" script_class="AIAttackProfile" load_steps=2 format=3]

[ext_resource type="Script" path="res://Scripts/Combat/AI/AttackProfile.gd" id="1_profile"]

[resource]
script = ExtResource("1_profile")
display_name = "Warrior Sword Attack"
attack_range = 1.0
attack_range_tolerance = 0.1
approach_speed_multiplier = 1.2
return_to_guard_after_attack = false
```

- [ ] **Step 2: Create the inherited SwordAttack scene**

Use `AttackModuleBase.tscn` as the root instance, replace the root script with `SwordAttack.gd`, assign the Warrior Profile, enable `hitbox_enabled`, and add:

```text
WeaponPivot/WeaponVisualRoot/Blade
  CSGBox3D.size = Vector3(0.02, 0.6, 0.08)
WeaponPivot/WeaponVisualRoot/Handle
  CSGBox3D.size = Vector3(0.06, 0.13, 0.05)
```

Reuse `MatGridYellow.tres` for the prototype sword. Preserve the player's current Blade and Handle local transforms under an identity `WeaponVisualRoot`.

Override the inherited detector:

```text
HitboxDetector.position = Vector3(0, 0.35, -0.65)
HitboxDetector.debug_hitbox_enabled = true
HitboxShapeCast.shape = BoxShape3D(size = Vector3(1.0, 0.7, 0.9))
HitboxShapeCast.collision_mask = 4
```

- [ ] **Step 3: Add RESET and three animations**

Copy only the `WeaponPivot:position` and `WeaponPivot:rotation` value tracks from the player's `RESET`, `attack_1`, `attack_2`, and `attack_3` animations. Add these AI method tracks:

```text
attack_1 length 0.32: _open_hit_window at 0.10, _close_hit_window at 0.22
attack_2 length 0.36: _open_hit_window at 0.12, _close_hit_window at 0.25
attack_3 length 0.45: _open_hit_window at 0.18, _close_hit_window at 0.34
```

Do not copy `_open_combo_window`, `_close_combo_window`, `_request_lunge_for_current_attack`, or `_request_third_attack_spin`.

- [ ] **Step 4: Run the focused test**

Expected: only Warrior scene assertions remain failing; SwordAttack Profile, visual, animations, Hitbox, feedback inheritance, and random-bag assertions pass.

### Task 4: Assemble the Warrior Ally scene

**Files:**
- Create: `Scenes/ObjectScenes/Warrior.tscn`

**Interfaces:**
- Consumes: `AllyBase.tscn`, `SwordAttack.tscn`, and `MatGridRed.tres`.
- Produces: a ready-to-manually-instance Warrior source scene.

- [ ] **Step 1: Create the inherited scene**

```text
Warrior (instance of AllyBase.tscn)
  combat_guard_distance = 1.5
  attack_module_path = NodePath("VisualRoot/AttackModuleSocket/SwordAttack")

VisualRoot/BodyMesh
  type = CSGBox3D
  position = Vector3(0, 0.25, 0)
  size = Vector3(0.5, 0.5, 0.5)
  material_override = MatGridRed.tres

VisualRoot/AttackModuleSocket/SwordAttack
  instance = SwordAttack.tscn
```

- [ ] **Step 2: Run `WarriorSwordAttackTest.gd`**

Expected: `WarriorSwordAttackTest: PASS`, exit code `0`.

### Task 5: Regression, documentation, and editor verification

**Files:**
- Modify: `Docs/CurrentImplementationSummary.md`
- Verify only: `Scenes/TestScene.tscn`

**Interfaces:**
- Produces: a documented, regression-checked Warrior module without automatic TestScene changes.

- [ ] **Step 1: Document the delivered source scene, Profile, attack range, random-bag rule, and manual TestScene requirement**

Add a concise section recording:

```text
Warrior source: res://Scenes/ObjectScenes/Warrior.tscn
Weapon module: res://Scenes/Components/AiAttackModules/SwordAttack.tscn
Attack range: 1.0m
Selection: three-animation random bag, no immediate boundary repeat
TestScene: user manually instances Warrior under the scene's unit parent
```

- [ ] **Step 2: Run the complete combat test set**

```powershell
$godot = 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe'
$tests = @(
  'AIAttackHitboxTest.gd',
  'AIAttackModuleBaseTest.gd',
  'AIHitFeedbackTest.gd',
  'AllyAttackDistanceTest.gd',
  'AllyBasicAttackTest.gd',
  'GuardianShieldAttackTest.gd',
  'WarriorSwordAttackTest.gd'
)
foreach ($test in $tests) {
  & $godot --headless --path 'G:\Godot\SipSip' --script ("res://Tests/" + $test)
  if ($LASTEXITCODE -ne 0) { exit 1 }
}
```

Expected: seven test scripts print `PASS` and exit `0`.

- [ ] **Step 3: Smoke-test the main scene without editing it**

```powershell
& $godot --headless --path 'G:\Godot\SipSip' --quit-after 10
```

Expected: exit code `0`, no parse or runtime errors.

- [ ] **Step 4: Check Godot MCP editor errors and TestScene preservation**

Call `get_editor_errors(max_lines: 200)` and expect `count: 0`. Confirm `Scenes/TestScene.tscn` was not edited during implementation.

- [ ] **Step 5: Give the user manual placement guidance**

Tell the user to drag `res://Scenes/ObjectScenes/Warrior.tscn` into the same parent node that currently contains Guardian in `TestScene`, then choose a non-overlapping initial ground position. Do not add the instance automatically.

## Implementation Result

- Warrior source scene, AI SwordAttack module, Profile, three animations, random-bag selector, Hitbox, and inherited hit-stop feedback are implemented.
- The random bag is lazily created on the first valid attack request, contains each valid animation once, and prevents an immediate repeat across bag boundaries.
- Parent-module exit cleanup and per-instance debug BoxMesh isolation were strengthened during final review.
- Seven combat tests pass, main-scene Headless smoke exits `0`, and Godot MCP reports zero editor errors.
- `TestScene.tscn` was not modified by Codex. A user/external Warrior instance was already present during final verification and was preserved unchanged.
- Follow-up diagnosis confirmed that a non-attacking Warrior can be caused by scene assembly rather than combat code: the weapon node had been named `VisualRoot_AttackModuleSocket#SwordAttack` and placed under the Warrior root. The valid structure is a node named only `SwordAttack`, directly parented to `VisualRoot/AttackModuleSocket`, with `attack_module_path = NodePath("VisualRoot/AttackModuleSocket/SwordAttack")`.
- After correcting the node name and parent relationship, Inspector edits to unrelated Warrior parameters no longer invalidate attack-module lookup. Warrior material is independent of this fix and must not be changed as part of node-path repair.
