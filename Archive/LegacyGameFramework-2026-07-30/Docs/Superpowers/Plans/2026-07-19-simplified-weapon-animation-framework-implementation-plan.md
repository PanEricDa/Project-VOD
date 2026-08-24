# Simplified Weapon Animation Framework Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the preview-heavy one-hand-sword scene with a three-node runtime weapon scene that contains one visual, one skill socket, and one animation source while preserving PlayerBase equipment and three-step attacks.

**Architecture:** PlayerAttackController continues to own InputMap and combo state. WeaponBase exposes one `Animations` AnimationPlayer with `base` and optional `override` libraries; CharacterAnimationController copies the effective animations into the character-owned AnimationPlayer. Weapon scenes contain no reference character or preview helpers.

**Tech Stack:** Godot 4.7, GDScript, inherited `.tscn` scenes, AnimationPlayer, AnimationLibrary, Resource, PackedScene, SceneTree headless tests.

## Global Constraints

- Do not modify or add any unit instance in `res://Scenes/TestScene.tscn`.
- Do not modify old Hero, AI AttackModules, AI scenes, SkillSystem, hitboxes, damage, or effects.
- Keep `player_attack` bound through InputMap to mouse left.
- Keep PlayerBase movement, dash, gravity, targeting, and facing independent from PlayerCombatSystem.
- All identifiers use English; new or materially rewritten code uses detailed Simplified Chinese comments.
- The project is not a Git repository; replace commit steps with explicit verification checkpoints.
- Do not create animation-production preview scenes, reference characters, preview grounds, markers, editor plugins, or retargeting logic.

---

### Task 1: Simplify the WeaponBase Runtime Contract

**Files:**
- Modify: `WeaponCombatSystem/04-Tests/WeaponSceneContractsTest.gd`
- Modify: `WeaponCombatSystem/02-Core/WeaponBase.gd`

**Interfaces:**
- Consumes: `WeaponDefinition`.
- Produces:
  - `get_runtime_visual_root() -> Node3D`
  - `get_skill_socket() -> Node`
  - `get_animations_player() -> AnimationPlayer`
  - `get_base_animation_library() -> AnimationLibrary`
  - `get_override_animation_library() -> AnimationLibrary`
  - `get_effective_animation(animation_name: StringName) -> Animation`
  - `get_basic_attack_animation_names() -> Array[StringName]`
  - `configure_definition(definition: WeaponDefinition) -> void`

- [ ] **Step 1: Rewrite the contract test to describe the three-node weapon**

Build this in-memory tree:

```text
WeaponBase
├── VisualSlot
├── SkillSocket
└── Animations
```

Configure `Animations` with an AnimationLibrary named `base` containing
`basic_attack_1..3` and a library named `override` containing a same-name
`basic_attack_3`.

Assert:

```gdscript
_assert_equal(
    weapon.call("get_runtime_visual_root"),
    visual_slot,
    "VisualSlot is the only runtime visual container"
)
_assert_equal(
    weapon.call("get_animations_player"),
    animations,
    "one AnimationPlayer stores weapon actions"
)
_assert_equal(
    weapon.call("get_basic_attack_animation_names"),
    [&"basic_attack_1", &"basic_attack_2", &"basic_attack_3"],
    "continuous combo names are discovered"
)
_assert_equal(
    weapon.call("get_effective_animation", &"basic_attack_3"),
    override_attack_3,
    "same-name override wins"
)
```

Also assert the script no longer exposes these properties:

```text
base_animation_player_path
override_animation_player_path
reference_character_path
preview_root_path
animation_target_root_path
animation_profile
```

- [ ] **Step 2: Run the contract test and verify RED**

Run:

```powershell
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' --headless --path 'G:\Godot\SipSip' --script res://WeaponCombatSystem/04-Tests/WeaponSceneContractsTest.gd
```

Expected: FAIL because the current WeaponBase still expects separate BaseAnimations,
OverrideAnimations, and preview paths.

- [ ] **Step 3: Reduce WeaponBase exports to three direct node paths**

Use:

```gdscript
@export_node_path("Node3D")
var runtime_visual_root_path: NodePath = ^"VisualSlot"
@export_node_path("Node")
var skill_socket_path: NodePath = ^"SkillSocket"
@export_node_path("AnimationPlayer")
var animations_player_path: NodePath = ^"Animations"
```

Remove all editor-preview fields, `_process()`, preview visibility logic, and runtime
preview deletion.

Implement:

```gdscript
func get_animations_player() -> AnimationPlayer:
    return get_node_or_null(animations_player_path) as AnimationPlayer

func get_base_animation_library() -> AnimationLibrary:
    return _get_named_animation_library(&"base")

func get_override_animation_library() -> AnimationLibrary:
    return _get_named_animation_library(&"override")
```

Keep same-name override resolution and continuous combo discovery. Configuration
warnings only check `VisualSlot`, `Animations/base`, and combo-number gaps.

- [ ] **Step 4: Run the contract test and verify GREEN**

Expected: `WeaponSceneContractsTest: PASS`, exit code 0.

---

### Task 2: Replace the Preview-Heavy Sword Scenes

**Files:**
- Modify: `WeaponCombatSystem/04-Tests/WeaponAuthoringSceneTest.gd`
- Modify: `WeaponCombatSystem/04-Tests/IronSwordExampleTest.gd`
- Rewrite: `WeaponCombatSystem/01-WeaponTypes/Sword/SwordBase.tscn`
- Rewrite: `WeaponCombatSystem/00-Weapons/IronSword/IronSword.tscn`
- Keep: `WeaponCombatSystem/00-Weapons/IronSword/IronSwordVisual.tscn`
- Keep: `WeaponCombatSystem/00-Weapons/IronSword/IronSwordDefinition.tres`

**Interfaces:**
- Consumes: Task 1 WeaponBase node paths and animation-library names.
- Produces:
  - A three-direct-child `SwordBase`.
  - A concrete inherited `IronSword` containing exactly one visual instance.
  - Base animations `RESET`, `basic_attack_1`, `basic_attack_2`, `basic_attack_3`.

- [ ] **Step 1: Rewrite the scene tests before changing scenes**

Assert `SwordBase` has exactly these direct children:

```gdscript
_assert_equal(
    _get_direct_child_names(base_weapon),
    [&"VisualSlot", &"SkillSocket", &"Animations"],
    "base weapon exposes only the three runtime responsibilities"
)
```

Assert:

```gdscript
_assert_true(
    base_weapon.find_child("*Preview*", true, false) == null,
    "base weapon contains no preview nodes"
)
_assert_true(
    base_weapon.find_child("*Reference*", true, false) == null,
    "base weapon contains no reference character"
)
_assert_equal(
    concrete_weapon.get_node(^"VisualSlot").get_child_count(),
    1,
    "concrete sword contains one visual instance"
)
```

Assert `Animations/base` contains the four required animations and every non-RESET
track starts with either `BodyRoot` or `WeaponSocket`. Assert the default concrete
sword has no custom override animation.

- [ ] **Step 2: Run both scene tests and verify RED**

Run:

```powershell
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' --headless --path 'G:\Godot\SipSip' --script res://WeaponCombatSystem/04-Tests/WeaponAuthoringSceneTest.gd
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' --headless --path 'G:\Godot\SipSip' --script res://WeaponCombatSystem/04-Tests/IronSwordExampleTest.gd
```

Expected: FAIL because current scenes contain RuntimeWeapon, AnimationData,
AnimationPreview, and two IronSwordVisual instances.

- [ ] **Step 3: Rewrite SwordBase with three direct children**

Create:

```text
SwordBase (WeaponBase)
├── VisualSlot (Node3D)
├── SkillSocket (Node)
└── Animations (AnimationPlayer)
```

`Animations` contains:

```text
base/RESET
base/basic_attack_1  length 0.32
base/basic_attack_2  length 0.36
base/basic_attack_3  length 0.45
override             empty library
```

Reuse the current simple BodyRoot and WeaponSocket transform keys. Do not add
BodyRoot or WeaponSocket nodes to the weapon scene; those paths are the character
animation contract.

- [ ] **Step 4: Rewrite concrete IronSword**

Keep inherited root and add only:

```text
VisualSlot
└── IronSwordVisual
```

Remove `PreviewIronSwordVisual` and the demonstration attack-3 override. The
default concrete sword inherits all three base animations unchanged.

- [ ] **Step 5: Run both scene tests and verify GREEN**

Expected:

```text
WeaponAuthoringSceneTest: PASS
IronSwordExampleTest: PASS
```

---

### Task 3: Preserve Equipment, Character Playback, and Player Combo

**Files:**
- Modify: `WeaponCombatSystem/04-Tests/WeaponCombatComponentsTest.gd`
- Modify: `WeaponCombatSystem/04-Tests/PlayerWeaponExampleAssemblyTest.gd`
- Verify: `WeaponCombatSystem/03-Components/CharacterAnimationController.gd`
- Verify: `WeaponCombatSystem/03-Components/WeaponEquipmentComponent.gd`
- Verify: `WeaponCombatSystem/03-Components/PlayerAttackController.gd`
- Verify: `UnitSystem/PlayerBase.tscn`

**Interfaces:**
- Consumes: Task 1 WeaponBase getters and Task 2 weapon scene.
- Produces: unchanged runtime equipment and player combo behavior.

- [ ] **Step 1: Remove preview-specific assertions from component tests**

Delete assertions that wait for or inspect `AnimationPreview`. Replace them with:

```gdscript
_assert_equal(
    equipped_weapon.get_runtime_visual_root().get_child_count(),
    1,
    "runtime weapon exposes one visual"
)
_assert_true(
    equipped_weapon.get_node_or_null(^"Animations") != null,
    "runtime weapon retains its animation data source"
)
```

Update the expected effective third attack duration from the removed child override
`0.5` back to the base duration `0.45`.

- [ ] **Step 2: Run component and PlayerBase tests**

Run:

```powershell
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' --headless --path 'G:\Godot\SipSip' --script res://WeaponCombatSystem/04-Tests/WeaponCombatComponentsTest.gd
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' --headless --path 'G:\Godot\SipSip' --script res://WeaponCombatSystem/04-Tests/PlayerWeaponExampleAssemblyTest.gd
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' --headless --path 'G:\Godot\SipSip' --script res://WeaponCombatSystem/04-Tests/PlayerWeaponComboTest.gd
```

Expected: tests may fail only where they still assume the old scene hierarchy or
old override duration. A failure in equipment, playback, or combo sequencing is a
real regression and must be fixed before continuing.

- [ ] **Step 3: Make only required compatibility changes**

`CharacterAnimationController` should continue calling:

```gdscript
weapon.get_base_animation_library()
weapon.get_override_animation_library()
```

No PlayerAttackController behavior change is expected. No PlayerBase node-path
change is expected. If a compatibility change is necessary, keep the public APIs
and responsibilities unchanged rather than introducing a new adapter layer.

- [ ] **Step 4: Verify the runtime tests are GREEN**

Expected:

```text
WeaponCombatComponentsTest: PASS
PlayerWeaponExampleAssemblyTest: PASS
PlayerWeaponComboTest: PASS
```

- [ ] **Step 5: Verify movement remains independent**

Run:

```powershell
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' --headless --path 'G:\Godot\SipSip' --script res://UnitSystem/Tests/PlayerBaseMovementTest.gd
```

Expected: `PlayerBaseMovementTest: PASS`.

---

### Task 4: Complete Regression and Editor Verification

**Files:**
- Verify only.

**Interfaces:**
- Consumes: Tasks 1–3.
- Produces: evidence that the simplified framework loads in Godot 4.7 without changing TestScene.

- [ ] **Step 1: Run every WeaponCombatSystem and UnitSystem test**

Enumerate `*Test.gd` below both directories and run each through the Godot 4.7
console executable. Expected: all tests exit 0.

- [ ] **Step 2: Run old SkillSystem and root Tests**

Record unrelated pre-existing failures separately. Do not change Mage, AI,
SkillSystem, effects, or old combat modules to make unrelated tests pass.

- [ ] **Step 3: Run editor scan and headless startup**

```powershell
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' --headless --editor --path 'G:\Godot\SipSip' --quit
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' --headless --path 'G:\Godot\SipSip' --quit-after 10
```

Expected: both commands exit 0.

- [ ] **Step 4: Verify through Godot MCP Pro**

Reload the project and open:

```text
res://WeaponCombatSystem/01-WeaponTypes/Sword/SwordBase.tscn
res://WeaponCombatSystem/00-Weapons/IronSword/IronSword.tscn
res://UnitSystem/PlayerBase.tscn
```

Confirm:

- Base sword has exactly VisualSlot, SkillSocket, Animations.
- Concrete sword has one IronSwordVisual.
- PlayerBase still has CharacterActionRig and PlayerCombatSystem.
- No newly generated file-backed script error appears.

- [ ] **Step 5: Verify project rule**

Confirm `Scenes/TestScene.tscn` was not written or changed by this implementation.
