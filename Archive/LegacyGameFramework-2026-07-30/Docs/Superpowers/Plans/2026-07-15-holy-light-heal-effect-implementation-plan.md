# Holy Light Heal Effect Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a reusable 0.5-second, gold-and-white, single-target holy-light healing visual effect with no health-system dependency.

**Architecture:** `HolyLightHealEffect.tscn` owns all built-in meshes, particles, light, and the fixed 0.5-second AnimationPlayer timeline. `HolyLightHealEffect.gd` applies Inspector parameters, scales playback speed to `effect_duration`, exposes lifecycle methods/signals, and performs exact reset/cleanup. A separate preview scene exists only for visual inspection.

**Tech Stack:** Godot 4.7, GDScript, MeshInstance3D, TorusMesh, CylinderMesh, QuadMesh, GPUParticles3D, ParticleProcessMaterial, OmniLight3D, AnimationPlayer, SceneTree headless tests.

## Global Constraints

- Use only warm gold, ivory white, and pure white; no green visual element.
- Default duration is `0.5s` and is adjustable through `effect_duration` without editing animation keys.
- Use only Godot built-in resources; no external texture, third-party plugin, complex shader, camera shake, or global environment modification.
- Keep the effect independent from health values, Healer AI, StaffAttack, target selection, and cooldown logic.
- All fields and methods use English identifiers; new production code has detailed Simplified Chinese comments.
- All transparent meshes cast no shadow; default particle amount is `18`; default light range is `1.5m`.
- Do not add or modify any effect or unit instance in `Scenes/TestScene.tscn`.
- The project is not a Git repository; do not create branches, commits, or worktrees.

## File Map

- Create `Effects/Healing/HolyLightHealEffect.gd`: parameter application and playback lifecycle.
- Create `Effects/Healing/HolyLightHealEffect.tscn`: production effect scene and resources.
- Create `Effects/Healing/HolyLightHealEffectPreview.gd`: repeated preview-only playback.
- Create `Effects/Healing/HolyLightHealEffectPreview.tscn`: camera, target block, environment, and effect preview.
- Create `Tests/HolyLightHealEffectTest.gd`: scene, color, timing, interface, replay, and cleanup contract.
- Modify `Docs/CurrentImplementationSummary.md`: record the reusable effect and deferred healing logic.

---

### Task 1: Define the Effect Contract

**Files:**
- Create: `Tests/HolyLightHealEffectTest.gd`

**Interfaces:**
- Produces the required scene contract before production files exist.

- [x] **Step 1: Write a failure-accumulating SceneTree test**

The test must first check `ResourceLoader.exists()` and fail cleanly if the scene is absent. After the scene exists, instantiate it with `autoplay=false` and `auto_free_on_finished=false`, add it to the tree, and verify:

```gdscript
const EFFECT_SCENE_PATH := "res://Effects/Healing/HolyLightHealEffect.tscn"
const EFFECT_SCRIPT_PATH := "res://Effects/Healing/HolyLightHealEffect.gd"

var effect: Node3D = effect_scene.instantiate() as Node3D
effect.set("autoplay", false)
effect.set("auto_free_on_finished", false)
root.add_child(effect)
await process_frame

_assert_true(effect.get_script().resource_path == EFFECT_SCRIPT_PATH, "dedicated script")
_assert_true(effect.has_method("play"), "play()")
_assert_true(effect.has_method("stop"), "stop()")
_assert_true(effect.has_method("reset_effect"), "reset_effect()")
_assert_true(effect.has_method("is_playing"), "is_playing()")
_assert_true(effect.has_signal("effect_started"), "effect_started")
_assert_true(effect.has_signal("effect_finished"), "effect_finished")

for node_path: NodePath in [
    ^"GroundRing",
    ^"LightColumn",
    ^"RisingParticles",
    ^"HealFlash/VerticalRay",
    ^"HealFlash/HorizontalRay",
    ^"HealingLight",
    ^"AnimationPlayer",
]:
    _assert_true(effect.has_node(node_path), "missing " + str(node_path))
```

Verify default exports exactly: duration `0.5`, colors `#FFD36A`, `#FFF4D6`, `#FFFFFF`, ring radius `0.65`, column height `1.2`, column radius `0.32`, particle amount `18`, light energy `1.2`, and light range `1.5`.

Inspect the `heal` animation: length `0.5`, method keys `_start_particles` near `0.08` and `_stop_particles` near `0.34`, and value tracks for ring/column/flash transparency and scale plus light energy.

Exercise the real lifecycle: `play()` emits started once and returns true from `is_playing()`, a second `play()` restarts without adding a second connection/task, `stop()` returns to not playing and zero light energy, manual natural completion emits finished once, and an auto-free instance becomes invalid after completion.

- [x] **Step 2: Run and verify RED**

```powershell
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' --headless --path 'G:\Godot\SipSip' --script res://Tests/HolyLightHealEffectTest.gd
```

Expected: exit code `1` only because the planned effect scene/script do not exist.

---

### Task 2: Implement Playback Lifecycle

**Files:**
- Create: `Effects/Healing/HolyLightHealEffect.gd`

**Interfaces:**
- Produces `play()`, `stop()`, `reset_effect()`, `is_playing()`, `_start_particles()`, `_stop_particles()`, `effect_started`, and `effect_finished`.

- [x] **Step 1: Implement the script after RED**

Use exported defaults from the design. Cache all scene nodes with typed `@onready` fields. In `_ready()`, duplicate or use local-to-scene mesh/material resources, connect `animation_finished`, apply parameters, reset, and defer autoplay.

The lifecycle must follow this exact logic:

```gdscript
const BASE_ANIMATION_DURATION: float = 0.5
const HEAL_ANIMATION_NAME: StringName = &"heal"

func play() -> void:
    reset_effect()
    animation_player.speed_scale = BASE_ANIMATION_DURATION / max(effect_duration, 0.01)
    playback_is_active = true
    animation_player.play(HEAL_ANIMATION_NAME)
    effect_started.emit()

func stop() -> void:
    playback_is_active = false
    animation_player.stop()
    reset_effect()

func reset_effect() -> void:
    rising_particles.emitting = false
    ground_ring.scale = Vector3.ONE * 0.2
    ground_ring.transparency = 1.0
    light_column.scale = Vector3(0.55, 0.05, 0.55)
    light_column.transparency = 1.0
    heal_flash.scale = Vector3.ONE * 0.2
    vertical_ray.transparency = 1.0
    horizontal_ray.transparency = 1.0
    healing_light.light_energy = 0.0

func _on_animation_finished(animation_name: StringName) -> void:
    if animation_name != HEAL_ANIMATION_NAME or not playback_is_active:
        return
    playback_is_active = false
    rising_particles.emitting = false
    effect_finished.emit()
    if auto_free_on_finished:
        queue_free()
```

`_apply_parameters()` sets TorusMesh radii, CylinderMesh dimensions, particle amount, OmniLight range/color, and material colors. All affected subresources must be instance-local.

- [x] **Step 2: Run the focused test**

Expected: still RED because the scene is not yet present, while the script itself parses in Headless editor scan.

---

### Task 3: Build the Production Effect Scene

**Files:**
- Create: `Effects/Healing/HolyLightHealEffect.tscn`

**Interfaces:**
- Consumes the lifecycle script and exposes all required visual nodes.
- Produces the reusable effect scene.

- [x] **Step 1: Create local resources and nodes**

Use local-to-scene resources and these defaults:

```text
GroundRing: TorusMesh inner_radius=0.58, outer_radius=0.65, position.y=0.02
LightColumn: CylinderMesh height=1.2, top_radius=0.24, bottom_radius=0.32, position.y=0.6
RisingParticles: amount=18, lifetime=0.42, one_shot=true, explosiveness=0.85
ParticleProcessMaterial: emission cylinder radius=0.3, height=0.45, direction=(0,1,0), initial velocity 1.0–1.8
HealFlash: position.y=0.38
VerticalRay QuadMesh: size=(0.055,0.42), billboard material
HorizontalRay QuadMesh: size=(0.42,0.055), billboard material
HealingLight: color=#FFF4D6, energy=0, omni_range=1.5, shadow=false
```

All mesh materials are unshaded, transparent/additive where suitable, and have shadow casting disabled on the MeshInstance3D.

- [x] **Step 2: Create RESET and heal animations**

`RESET` length `0.01` stores the exact reset properties. `heal` length `0.5` contains:

```text
GroundRing scale: 0.00=(0.2), 0.08=(1.0), 0.34=(1.08), 0.50=(1.2)
GroundRing transparency: 0.00=0.65, 0.08=0.05, 0.34=0.35, 0.50=1.0
LightColumn scale: 0.00=(0.55,0.05,0.55), 0.04=same, 0.15=(1,1,1), 0.34=(0.9,1,0.9), 0.50=(0.2,1,0.2)
LightColumn transparency: 0.00=1, 0.04=1, 0.15=0.12, 0.34=0.38, 0.50=1
HealFlash scale: 0.00=(0.2), 0.10=(0.2), 0.16=(1.0), 0.24=(1.25), 0.50=(1.25)
Both ray transparency: 0.00=1, 0.10=1, 0.15=0.0, 0.24=1, 0.50=1
HealingLight energy: 0.00=0, 0.08=0, 0.15=1.2, 0.26=0.4, 0.50=0
Method keys: 0.08=_start_particles(), 0.34=_stop_particles()
```

- [x] **Step 3: Run and verify GREEN**

Run the focused command from Task 1.

Expected: `HolyLightHealEffectTest: PASS`, exit code `0`.

---

### Task 4: Build an Independent Preview

**Files:**
- Create: `Effects/Healing/HolyLightHealEffectPreview.gd`
- Create: `Effects/Healing/HolyLightHealEffectPreview.tscn`

**Interfaces:**
- Consumes the effect scene.
- Produces a standalone preview that never touches TestScene.

- [x] **Step 1: Create preview script and scene**

The preview contains a neutral ground plane, a `0.5m` Tiffany-blue target block, WorldEnvironment, DirectionalLight3D, Camera3D, and one effect instance with `autoplay=true`, `auto_free_on_finished=false`.

The preview script repeats playback every `1.2s`:

```gdscript
extends Node3D

@onready var effect: Node3D = $PreviewTarget/HolyLightHealEffect

func _ready() -> void:
    effect.effect_finished.connect(_on_effect_finished)

func _on_effect_finished() -> void:
    await get_tree().create_timer(0.7).timeout
    if is_instance_valid(effect):
        effect.play()
```

- [x] **Step 2: Run the preview through Godot MCP**

Open and play only `HolyLightHealEffectPreview.tscn`. Capture frames around `0.08s`, `0.16s`, and `0.32s`; verify the gold-white palette, readable ring/column/flash, and no scene-wide overexposure. Stop the preview afterward.

---

### Task 5: Regression and Documentation

**Files:**
- Modify: `Docs/CurrentImplementationSummary.md`
- Modify: `Docs/Superpowers/Plans/2026-07-15-holy-light-heal-effect-implementation-plan.md`
- Verify only: `Scenes/TestScene.tscn`

**Interfaces:**
- Produces final verification evidence and maintenance notes.

- [x] **Step 1: Run full verification**

Run `HolyLightHealEffectTest.gd`, the existing 9 combat tests, and:

```powershell
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' --headless --path 'G:\Godot\SipSip' --quit-after 10
```

Expected: 10 test scripts pass and Smoke exits `0`.

- [x] **Step 2: Confirm TestScene preservation**

Compare TestScene timestamp, length, and SHA-256 with the pre-implementation baseline. Do not save, restore, or edit TestScene.

- [x] **Step 3: Update documentation**

Record the effect path, `0.5s` default duration, gold-white palette, public lifecycle API, Inspector controls, preview scene, lack of healing logic, test count, Smoke result, MCP observation, and unchanged TestScene hash.

---

## Implementation Result (2026-07-15)

- Implemented the reusable effect, dedicated script, standalone looping preview, and contract test.
- Added per-instance animation resource isolation so the exported `light_energy` value controls the actual animation peak without affecting sibling instances.
- Visually inspected the preview through Godot MCP: the ring, column, rising particles, flash, and local light are readable in the approved gold-white palette.
- Passed `HolyLightHealEffectTest.gd` plus the existing 9 combat test scripts.
- Godot 4.7 Headless Smoke exited with code `0`; Godot MCP reported `0` editor errors.
- `Scenes/TestScene.tscn` was not edited: timestamp `2026-07-14 01:08:42`, length `4525`, SHA-256 `179A711803F0C03ECEFC8C91F3807DBC1C5AE64F6F044134E9E9C66AEB643B7E`.
