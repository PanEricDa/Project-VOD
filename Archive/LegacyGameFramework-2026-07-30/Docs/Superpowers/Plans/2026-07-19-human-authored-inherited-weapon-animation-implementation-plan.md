# Human-Authored Inherited Weapon Animation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the Resource-heavy weapon ActionSet prototype with a directly editable inherited weapon scene that contains a reference character, three base combo animations, per-weapon animation overrides, a visual slot, and a future skill socket.

**Architecture:** `WeaponDefinition.tres` remains the lightweight inventory entry and points to a concrete `WeaponBase` PackedScene. `SwordBase.tscn` is the animation-authoring parent scene; `IronSword.tscn` inherits it, supplies the model, and may override animations by exact name. Player components merge base and override animations into the character-owned AnimationPlayer and discover `basic_attack_1..N` without ActionDefinition Resources.

**Tech Stack:** Godot 4.7, GDScript, inherited `.tscn` scenes, AnimationPlayer, AnimationLibrary, Resource, PackedScene, InputMap, SceneTree headless tests.

## Global Constraints

- Do not modify or add unit instances in `res://Scenes/TestScene.tscn`.
- Do not modify old Hero, old MeleeAttackModule, AI AttackModule, AI scenes, or SkillSystem.
- Keep `player_attack` bound through InputMap; current binding is mouse left.
- All identifiers remain English and all new code receives detailed Simplified Chinese comments.
- Reference characters are manual authoring aids only; do not implement skeleton detection, retargeting, or automatic model adaptation.
- A derived weapon overrides a base animation by exact animation name and inherits every animation it does not override.
- Discover basic combo segments from the continuous sequence `basic_attack_1`, `basic_attack_2`, `basic_attack_3`, and so on.
- Keep PlayerBase movement, dash, gravity, targeting, and facing independent from the removable combat system.
- The project is not a Git repository; replace commit steps with explicit test checkpoints.

---

### Task 1: Weapon Scene Runtime Contract

**Files:**
- Create: `WeaponCombatSystem/02-Core/WeaponBase.gd`
- Modify: `WeaponCombatSystem/02-Core/WeaponDefinition.gd`
- Create: `WeaponCombatSystem/04-Tests/WeaponSceneContractsTest.gd`

**Interfaces:**
- Produces:
  - `WeaponDefinition.weapon_scene: PackedScene`
  - `WeaponBase.get_base_animation_library() -> AnimationLibrary`
  - `WeaponBase.get_override_animation_library() -> AnimationLibrary`
  - `WeaponBase.get_effective_animation(animation_name: StringName) -> Animation`
  - `WeaponBase.get_basic_attack_animation_names() -> Array[StringName]`
  - `WeaponBase.configure_definition(definition: WeaponDefinition) -> void`
  - `WeaponBase.get_runtime_visual_root() -> Node3D`
  - `WeaponBase.get_skill_socket() -> Node`

- [ ] **Step 1: Write the failing contract test**

Create a real Node tree with `RuntimeWeapon/VisualSlot`, `RuntimeWeapon/SkillSocket`,
`AnimationData/BaseAnimations`, and `AnimationData/OverrideAnimations`. Attach the
new script dynamically and assert:

```gdscript
var weapon: Node = load(WEAPON_BASE_SCRIPT_PATH).new()
weapon.add_child(runtime_weapon)
weapon.add_child(animation_data)

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

Also assert that `basic_attack_1` plus `basic_attack_3` produces only
`[&"basic_attack_1"]` and records a configuration warning condition.

- [ ] **Step 2: Run the contract test and verify RED**

Run:

```powershell
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' --headless --path 'G:\Godot\SipSip' --script res://WeaponCombatSystem/04-Tests/WeaponSceneContractsTest.gd
```

Expected: FAIL because `WeaponBase.gd` and `weapon_scene` do not exist.

- [ ] **Step 3: Implement `WeaponDefinition` as inventory data**

Keep `weapon_id`, `display_name`, and optional presentation fields. Replace
`visual_scene`, `action_set`, and socket offsets with:

```gdscript
@export var icon: Texture2D
@export_multiline var description: String = ""
@export var weapon_scene: PackedScene
```

The concrete scene owns its model and animation authoring. The Definition owns no
live Node and does not reference AnimationLibrary directly.

- [ ] **Step 4: Implement `WeaponBase`**

Use exported typed node paths with these defaults:

```gdscript
@export_node_path("Node3D")
var runtime_visual_root_path := ^"RuntimeWeapon/VisualSlot"
@export_node_path("Node")
var skill_socket_path := ^"RuntimeWeapon/SkillSocket"
@export_node_path("AnimationPlayer")
var base_animation_player_path := ^"AnimationData/BaseAnimations"
@export_node_path("AnimationPlayer")
var override_animation_player_path := ^"AnimationData/OverrideAnimations"
@export_node_path("Node3D")
var reference_character_path := ^"AnimationPreview/ReferenceCharacterSlot"
@export var animation_target_root_path := ^""
@export var animation_profile: StringName = &"csg_box"
```

`get_effective_animation()` checks the override library first. Combo discovery
increments from 1 and stops at the first missing segment. Do not cache results so
editor animation changes are immediately observable.

- [ ] **Step 5: Run the contract test and verify GREEN**

Expected: `WeaponSceneContractsTest: PASS`, exit code 0, no warnings.

---

### Task 2: Human-Editable Iron Sword Parent and Child Scenes

**Files:**
- Create: `WeaponCombatSystem/01-WeaponTypes/Sword/SwordBase.tscn`
- Create: `WeaponCombatSystem/00-Weapons/IronSword/IronSword.tscn`
- Modify: `WeaponCombatSystem/00-Weapons/IronSword/IronSwordDefinition.tres`
- Create: `WeaponCombatSystem/04-Tests/WeaponAuthoringSceneTest.gd`

**Interfaces:**
- Consumes: `WeaponBase` and `WeaponDefinition.weapon_scene`.
- Produces:
  - A directly openable authoring parent containing reference content and base animations.
  - A concrete inherited scene containing `IronSwordVisual.tscn`.
  - A Definition that points to the concrete inherited scene.

- [ ] **Step 1: Write the failing authoring-scene test**

Assert the parent scene has:

```text
RuntimeWeapon/VisualSlot
RuntimeWeapon/SkillSocket
AnimationData/BaseAnimations
AnimationData/OverrideAnimations
AnimationPreview/ReferenceCharacterSlot/BodyRoot/BodyMesh
AnimationPreview/ReferenceCharacterSlot/WeaponSocket
```

Assert `BaseAnimations` contains `RESET` and three basic attacks, each animation
drives only `BodyRoot` and `WeaponSocket` relative to the preview target root.
Assert `IronSword.tscn` inherits the parent, contains a visual, and
`IronSwordDefinition.tres.weapon_scene` points to it.

- [ ] **Step 2: Run the authoring-scene test and verify RED**

Expected: FAIL because the new parent and inherited scenes do not exist.

- [ ] **Step 3: Create `SwordBase.tscn`**

Store a visible CSGBox reference body and WeaponSocket in the scene. Configure both
AnimationPlayers so the Animation panel can edit tracks against
`AnimationPreview/ReferenceCharacterSlot`.

Create:

```text
RESET
basic_attack_1 (0.32 s)
basic_attack_2 (0.36 s)
basic_attack_3 (0.45 s)
```

Each attack has preparation, strike, and return keys for:

```text
BodyRoot:position
BodyRoot:rotation
WeaponSocket:position
WeaponSocket:rotation
```

Do not add method tracks, hitboxes, damage, movement, or feedback.

- [ ] **Step 4: Create concrete inherited `IronSword.tscn`**

Inherit `SwordBase.tscn`, add the existing
`IronSwordVisual.tscn` below `RuntimeWeapon/VisualSlot`, and leave
`SkillSocket` empty. Add a local `basic_attack_3` to `OverrideAnimations` so the
minimal example visibly proves same-name override behavior while segments 1 and 2
remain inherited.

- [ ] **Step 5: Update `IronSwordDefinition.tres`**

Set:

```text
weapon_id = iron_sword
display_name = Iron Sword
weapon_scene = IronSword.tscn
```

- [ ] **Step 6: Run the authoring-scene test and verify GREEN**

Expected: `WeaponAuthoringSceneTest: PASS`.

---

### Task 3: Scene-Based Equipment and Animation Loading

**Files:**
- Modify: `WeaponCombatSystem/03-Components/CharacterAnimationController.gd`
- Modify: `WeaponCombatSystem/03-Components/WeaponEquipmentComponent.gd`
- Rewrite: `WeaponCombatSystem/04-Tests/WeaponCombatComponentsTest.gd`

**Interfaces:**
- Consumes: Task 1 `WeaponBase` and `WeaponDefinition`.
- Produces:
  - `CharacterAnimationController.load_weapon_animations(weapon: WeaponBase) -> bool`
  - `CharacterAnimationController.play_weapon_animation(animation_name: StringName) -> bool`
  - `WeaponEquipmentComponent.equip_definition(definition: WeaponDefinition) -> bool`
  - `WeaponEquipmentComponent.register_weapon_instance(weapon: WeaponBase) -> bool`
  - `WeaponEquipmentComponent.get_equipped_definition() -> WeaponDefinition`
  - `WeaponEquipmentComponent.get_equipped_weapon() -> WeaponBase`

- [ ] **Step 1: Rewrite the failing component pipeline test**

Build an in-memory WeaponBase with base attacks 1–3 and an override attack 3.
Verify:

```gdscript
_assert_true(equipment.call("equip_definition", definition), "definition equips")
_assert_equal(socket.get_child_count(), 1, "one weapon scene instance")
_assert_true(
    animator.call("play_weapon_animation", &"basic_attack_3"),
    "effective override animation plays"
)
```

Also add a pre-instanced WeaponBase below the socket and verify
`register_weapon_instance()` uses it without duplication.

- [ ] **Step 2: Run the component test and verify RED**

Expected: FAIL because components still require `WeaponActionSet`.

- [ ] **Step 3: Refactor `CharacterAnimationController`**

Replace ActionSet loading with effective animation merging:

```gdscript
func load_weapon_animations(weapon: WeaponBase) -> bool
func clear_weapon_animations() -> void
func play_weapon_animation(animation_name: StringName) -> bool
```

Create one runtime library named `weapon_actions`, duplicate base animations into
it, then replace same-name entries with override animations. Validate every track
against the character AnimationPlayer root before playing. On failure, return
`false` without changing the current player pose.

- [ ] **Step 4: Refactor `WeaponEquipmentComponent`**

`starting_weapon` remains typed as `WeaponDefinition`. On ready:

1. Look for an existing direct `WeaponBase` child in WeaponSocket.
2. Register it if found.
3. Otherwise instantiate `starting_weapon.weapon_scene`.

When replacing a weapon, validate the new scene and animation set before removing
the old weapon. Inject the Definition only when the weapon was equipped through
Definition.

- [ ] **Step 5: Run the component test and verify GREEN**

Expected: `WeaponCombatComponentsTest: PASS`.

---

### Task 4: Player Three-Step Combo Controller

**Files:**
- Modify: `WeaponCombatSystem/03-Components/PlayerAttackController.gd`
- Create: `WeaponCombatSystem/04-Tests/PlayerWeaponComboTest.gd`

**Interfaces:**
- Consumes:
  - `WeaponEquipmentComponent.get_equipped_weapon() -> WeaponBase`
  - `CharacterAnimationController.play_weapon_animation(name) -> bool`
- Produces:
  - `request_basic_attack() -> bool`
  - `cancel_attack() -> void`
  - `is_attacking() -> bool`
  - `get_combo_index() -> int`

- [ ] **Step 1: Write the failing combo test**

Equip a weapon with `basic_attack_1..3`. Assert:

```gdscript
_assert_true(attacker.request_basic_attack(), "first segment starts")
_assert_equal(attacker.get_combo_index(), 1, "first combo index")
_assert_true(attacker.request_basic_attack(), "second segment is buffered")
```

Wait for completion and verify segments 2 and 3 play in order, a fourth request
does not create `basic_attack_4`, and timeout/cancel resets the index to 0.

- [ ] **Step 2: Run the combo test and verify RED**

Expected: FAIL because the old controller only requests `basic_attack`.

- [ ] **Step 3: Implement minimal combo sequencing**

Keep:

```gdscript
@export var attack_action: StringName = &"player_attack"
@export_range(0.0, 2.0, 0.05)
var combo_reset_duration: float = 0.7
```

While a segment is active, one additional request sets a boolean next-segment
buffer. On natural animation completion, consume the buffer and play the next
discovered segment. Segment 3 completion always resets. Do not add GCD, method
tracks, input windows, lunge, or hit detection.

- [ ] **Step 4: Run the combo test and verify GREEN**

Expected: `PlayerWeaponComboTest: PASS`.

---

### Task 5: PlayerBase Migration and Old ActionSet Removal

**Files:**
- Modify: `UnitSystem/PlayerBase.tscn`
- Modify: `UnitSystem/Tests/PlayerBaseMovementTest.gd`
- Rewrite: `WeaponCombatSystem/04-Tests/PlayerWeaponExampleAssemblyTest.gd`
- Rewrite: `WeaponCombatSystem/04-Tests/IronSwordExampleTest.gd`
- Delete: `WeaponCombatSystem/04-Tests/WeaponResourceContractsTest.gd`
- Delete: `WeaponCombatSystem/02-Core/AttackActionDefinition.gd`
- Delete: `WeaponCombatSystem/02-Core/WeaponActionSet.gd`
- Delete: `WeaponCombatSystem/01-ActionSets/Sword/CSGBox/SwordAnimations.tres`
- Delete: `WeaponCombatSystem/01-ActionSets/Sword/CSGBox/SwordActionSet.tres`

**Interfaces:**
- Consumes: Tasks 1–4.
- Produces: PlayerBase with default scene-based one-hand sword and no old ActionSet references.

- [ ] **Step 1: Rewrite the PlayerBase assembly test before migration**

Verify stable action rig paths, default Definition equipment, concrete WeaponBase
instance, three effective combo names, mouse-left InputMap binding, attack playback,
and removable `PlayerCombatSystem`.

- [ ] **Step 2: Run the assembly test and verify RED**

Expected: FAIL while PlayerBase still loads the old definition/action set.

- [ ] **Step 3: Migrate PlayerBase component configuration**

Keep existing action rig, body, socket, targeting, collision, movement script, and
default Definition assignment. Update component paths only where required by the
new scene-based APIs. Do not add any unit to TestScene.

- [ ] **Step 4: Remove old ActionSet files and stale tests**

Use `rg` before deletion:

```powershell
rg -n 'WeaponActionSet|AttackActionDefinition|01-ActionSets|action_set' .
```

Only delete the listed WeaponCombatSystem prototype files after all production
references have migrated. Do not delete old Hero or AI files that use unrelated
animation systems.

- [ ] **Step 5: Run rewritten and existing PlayerBase tests**

Run:

```powershell
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' --headless --path 'G:\Godot\SipSip' --script res://WeaponCombatSystem/04-Tests/PlayerWeaponExampleAssemblyTest.gd
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' --headless --path 'G:\Godot\SipSip' --script res://UnitSystem/Tests/PlayerBaseMovementTest.gd
```

Expected: both PASS.

---

### Task 6: Complete Verification

**Files:**
- Verify only.

- [ ] **Step 1: Run every WeaponCombatSystem test**

Expected: all tests exit 0 with no errors or warnings.

- [ ] **Step 2: Run every UnitSystem test**

Expected: all tests exit 0 with no errors or warnings.

- [ ] **Step 3: Run existing SkillSystem and root Tests**

Record unrelated pre-existing failures separately. Do not modify Mage, AI, SkillSystem,
or effects to make unrelated tests pass.

- [ ] **Step 4: Run Godot 4.7 editor scan and headless startup**

```powershell
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' --headless --editor --path 'G:\Godot\SipSip' --quit
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' --headless --path 'G:\Godot\SipSip' --quit-after 10
```

Expected: exit code 0.

- [ ] **Step 5: Verify through Godot MCP Pro**

Reload the project, load `SwordBase.tscn`, load the concrete inherited
`IronSword.tscn`, and load `PlayerBase.tscn`. Confirm the reference character,
animation players, concrete visual, default Definition, and PlayerCombatSystem are
visible with no new file-backed script errors.

- [ ] **Step 6: Verify project rule**

Confirm `Scenes/TestScene.tscn` was not modified by this implementation.
