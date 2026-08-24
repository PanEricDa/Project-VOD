# UnitBase Skill Host Injection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give every `UnitBase` descendant a common, initially empty `SkillHost/SkillSocket` assembly that configures its parent unit as the skill caster.

**Architecture:** `UnitBase.tscn` instances `SkillHostComponent.tscn` as `SkillHost`, with its inherited `SkillSocket` child remaining empty. `SkillHostComponent` automatically calls `configure_owner()` for its direct `Node3D` parent after child skills are discovered. `UnitBase.gd` does not import, type, or directly operate on the skill system.

**Tech Stack:** Godot 4.7, GDScript, PackedScenes, Godot headless SceneTree tests.

## Global Constraints

- Do not modify `res://Scenes/TestScene.tscn`.
- Keep `SkillHostComponent` independently reusable outside UnitBase.
- Do not add AI target selection, automatic casting, combat logic, or per-unit skills in this step.
- Unit scenes configure skills solely by placing `SkillBase` scene instances directly below `SkillHost/SkillSocket`.

---

### Task 1: Establish the UnitBase Skill Slot Contract

**Files:**
- Modify: `UnitSystem/Tests/UnitDirectoryLayoutTest.gd`
- Modify: `UnitSystem/Base/00_UnitBase.tscn`
- Modify: `SkillSystem/01-Core/SkillHostComponent.gd`

**Interfaces:**
- Produces the fixed node path `^"SkillHost/SkillSocket"` on every `UnitBase` instance.
- Produces `@export var auto_configure_parent_owner: bool = true` on `IndependentSkillHostComponent`.

- [ ] **Step 1: Add a failing UnitBase assembly assertion**

```gdscript
var unit := (load("res://UnitSystem/Base/00_UnitBase.tscn") as PackedScene).instantiate()
var host := unit.get_node_or_null(^"SkillHost") as IndependentSkillHostComponent
_assert_true(host != null, "UnitBase contains SkillHost")
_assert_true(host.get_node_or_null(^"SkillSocket") != null, "SkillHost contains SkillSocket")
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```powershell
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' --headless --path 'G:\Godot\SipSip' --script res://UnitSystem/Tests/UnitDirectoryLayoutTest.gd
```

Expected: failure because `UnitBase` does not contain `SkillHost`.

- [ ] **Step 3: Add the SkillHost packed-scene instance and parent-owner configuration**

```gdscript
@export var auto_configure_parent_owner: bool = true

func _ready() -> void:
	random_generator.randomize()
	if auto_discover_skills:
		discover_skills()
	if auto_configure_parent_owner:
		call_deferred("_configure_parent_owner")

func _configure_parent_owner() -> void:
	configure_owner(get_parent() as Node3D)
```

`00_UnitBase.tscn` instances `res://SkillSystem/01-Core/SkillHostComponent.tscn` as a child named `SkillHost`.

- [ ] **Step 4: Run test to verify it passes**

Run the Task 1 command. Expected: exit code 0.

### Task 2: Verify Owner Propagation to an Equipped Skill

**Files:**
- Modify: `SkillSystem/11-Tests/SkillHostComponentTest.gd`
- Modify: `UnitSystem/Tests/UnitDirectoryLayoutTest.gd`

**Interfaces:**
- `SkillHost` configures its direct `Node3D` parent as `skill_owner`.
- Any direct `SkillSocket` child registered by `discover_skills()` receives the same caster through `SkillBase.configure_owner(caster, host)`.

- [ ] **Step 1: Add a failing owner-propagation assertion**

```gdscript
unit.add_child(host)
root.add_child(unit)
await process_frame
_assert_equal(host.skill_owner, unit, "SkillHost uses its direct UnitBase parent as caster")
```

- [ ] **Step 2: Run the SkillHost test to verify the assertion fails**

Run:

```powershell
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' --headless --path 'G:\Godot\SipSip' --script res://SkillSystem/11-Tests/SkillHostComponentTest.gd
```

Expected: the host does not yet configure its parent as owner.

- [ ] **Step 3: Keep the automatic configuration deferred**

The `call_deferred()` in Task 1 guarantees the socket and its skill children have completed their own `_ready()` callbacks before `configure_owner()` propagates the caster.

- [ ] **Step 4: Run both regression tests and the editor scan**

Run:

```powershell
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' --headless --path 'G:\Godot\SipSip' --script res://UnitSystem/Tests/UnitDirectoryLayoutTest.gd
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' --headless --path 'G:\Godot\SipSip' --script res://SkillSystem/11-Tests/SkillHostComponentTest.gd
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' --headless --path 'G:\Godot\SipSip' --editor --quit
```

Expected: all commands exit 0, with no parse errors.
