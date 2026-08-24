# Mage Fireball Visual Effects Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build and individually approve the Mage fireball cast-charge, flight, and explosion visuals before any gameplay integration.

**Architecture:** Three independent effect scenes live under `Effects/Skills/Fireball` and expose small playback APIs. Each effect has a dedicated Preview scene that owns only the preview environment and replay loop. No visual scene depends on Mage, AllyBase, SkillModuleBase, projectile collision, or TestScene.

**Tech Stack:** Godot 4.7, GDScript, MeshInstance3D, StandardMaterial3D, GPUParticles3D, OmniLight3D, AnimationPlayer, SceneTree headless tests.

## Global Constraints

- Complete one visual scene at a time and stop for user Preview approval before starting the next.
- Use only Godot built-in meshes, materials, particles, lights, and animations.
- All script fields and methods use English identifiers; all new code has detailed Simplified Chinese comments.
- Expose visual tuning parameters through `@export` wherever runtime-safe.
- Visual scenes do not target, collide, damage, home, or depend on combat hosts.
- Do not modify `Scenes/TestScene.tscn`, Mage, `Scenes/Projectiles/FireBall.tscn`, or gameplay scripts during this plan.
- The project is not a Git repository; record fresh verification evidence instead of commits.

---

### Task 1: Cast Charge Effect and Preview

**Files:**
- Create: `Effects/Skills/Fireball/FireballCastChargeEffect.gd`
- Create: `Effects/Skills/Fireball/FireballCastChargeEffect.tscn`
- Create: `Effects/Skills/Fireball/FireballCastChargeEffectPreview.gd`
- Create: `Effects/Skills/Fireball/FireballCastChargeEffectPreview.tscn`
- Create: `Tests/FireballCastChargeEffectTest.gd`

**Interfaces:**
- Produces: `play() -> void`, `stop() -> void`, `reset_effect() -> void`, `is_playing() -> bool`.
- Produces signals: `effect_started()` and `effect_finished()`.
- Exports: `autoplay`, `effect_duration`, three colors, core/shell sizes, particle amount, light energy, and light range.
- Depends on: Godot scene tree and built-in rendering nodes only.

- [x] **Step 1: Write the failing contract test**

  Create a SceneTree test that requires the effect and Preview resources, the public API,
  a `0.75s` default duration, exported color/dimension/light parameters, the expected core,
  shell, inward particles, local light, and AnimationPlayer nodes, and a Preview instance.

- [x] **Step 2: Run the test and verify RED**

  Run:

  ```powershell
  & 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' --headless --path 'G:\Godot\SipSip' --script res://Tests/FireballCastChargeEffectTest.gd
  ```

  Expected: fail because `FireballCastChargeEffect.tscn` does not exist.

- [x] **Step 3: Implement the reusable charge effect**

  Build a warm-white core inside a translucent orange shell, inward-moving orange sparks,
  and a shadowless orange local light. Animate hidden -> gather -> pulse-ready across `0.75s`.
  `play()` must restart cleanly; `stop()` and completion must leave a deterministic hidden
  state. Inspector values update scene-local materials, mesh sizes, particles, and light.

- [x] **Step 4: Implement the independent looping Preview**

  Create a dark neutral environment, fixed camera, small Mage-sized stand-in, a hand-height
  cast anchor, and a replay delay of `0.65s`. The Preview must not import Mage or TestScene.

- [x] **Step 5: Verify GREEN and project safety**

  Run the new test, all existing tests, Godot 4.7 headless smoke, MCP editor error scan, and
  verify the TestScene SHA-256 remains at the visual-phase baseline
  `DC4650265C9592A71416BA6E84093124554D33CB1D744BFAB73CEDCA5E566780`.

- [x] **Step 6: Open the Preview and stop for user approval**

  Open `res://Effects/Skills/Fireball/FireballCastChargeEffectPreview.tscn` in Godot. Do not
  create or edit flight or explosion files until the user explicitly approves this Preview.

  Status: Preview approved by the user on 2026-07-16.
  Tuning note: gathering particles now spawn on a `0.60m` sphere surface, start inward at only
  `0.10m/s`, then accelerate toward the core at `4.2m/s²`. Orbit sparks remain within a `0.14m`
  sphere. Gathering emission stops at `0.22s`, reserving the rest of the cast for accelerated
  convergence into the core.

---

### Task 2: Flight Effect and Preview

**Files:**
- Create: `Effects/Skills/Fireball/FireballFlightEffect.gd`
- Create: `Effects/Skills/Fireball/FireballFlightEffect.tscn`
- Create: `Effects/Skills/Fireball/FireballFlightEffectPreview.gd`
- Create: `Effects/Skills/Fireball/FireballFlightEffectPreview.tscn`
- Create: `Tests/FireballFlightEffectTest.gd`

**Interfaces:**
- Produces: `start() -> void`, `stop() -> void`, `reset_effect() -> void`, `is_active() -> bool`.
- Exports: core/shell colors and radii, trail amount/lifetime, spark amount, light energy/range.
- Depends on: approved Task 1 only for palette consistency; no scene dependency is required.

- [x] **Step 1: Write and run a failing flight-effect contract test**

  Require the scene, API, warm core, translucent flame shell, trail particles, dark-red sparks,
  local light, and independent Preview. Verify RED because the flight scene is absent.

- [x] **Step 2: Implement the reusable flight visual**

  Keep the effect centered at local origin and aligned toward local `-Z`. It must render only;
  the future projectile owns world movement and steering.

- [x] **Step 3: Implement a fixed-path looping Preview**

  Move a parent preview carrier repeatedly across the camera at the planned `9m/s` visual
  speed while the effect itself remains unaware of velocity or targets.

- [x] **Step 4: Run full verification and stop for user approval**

  Run the new test, all existing tests, smoke test, MCP error scan, TestScene hash check, then
  open `FireballFlightEffectPreview.tscn`. Do not begin Task 3 without explicit approval.

  Status: full verification passed; Preview approved by the user on 2026-07-16.

---

### Task 3: Explosion Effect and Preview

**Files:**
- Create: `Effects/Skills/Fireball/FireballExplosionEffect.gd`
- Create: `Effects/Skills/Fireball/FireballExplosionEffect.tscn`
- Create: `Effects/Skills/Fireball/FireballExplosionEffectPreview.gd`
- Create: `Effects/Skills/Fireball/FireballExplosionEffectPreview.tscn`
- Create: `Tests/FireballExplosionEffectTest.gd`

**Interfaces:**
- Produces: `play() -> void`, `stop() -> void`, `reset_effect() -> void`, `is_playing() -> bool`.
- Produces signals: `effect_started()` and `effect_finished()`.
- Exports: `effect_duration`, visual radius, colors, burst amount, light energy, and light range.
- Depends on: approved fireball palette; no gameplay collision or target list.

- [x] **Step 1: Write and run a failing explosion-effect contract test**

  Require the API, `0.35s` default duration, expanding translucent sphere, radial burst,
  embers, light pulse, deterministic reset, and independent Preview.

- [x] **Step 2: Implement the reusable compact explosion visual**

  Keep the visible radius near the planned `1.2m` gameplay radius without filling the screen.
  Natural completion emits `effect_finished`; active stop does not fake completion.

- [x] **Step 3: Implement the looping stationary Preview**

  Replay at a clear interval against a unit-sized stand-in and vision-ring-sized reference.

- [x] **Step 4: Run full verification and stop for user approval**

  Run the new test, all existing tests, smoke test, MCP error scan, TestScene hash check, then
  open `FireballExplosionEffectPreview.tscn`. Do not begin Task 4 without explicit approval.

  Status: full verification passed; Preview approved by the user on 2026-07-16.

---

### Task 4: Complete Visual Sequence Preview

**Files:**
- Create: `Effects/Skills/Fireball/FireballVisualSequencePreview.gd`
- Create: `Effects/Skills/Fireball/FireballVisualSequencePreview.tscn`
- Create: `Tests/FireballVisualSequencePreviewTest.gd`

**Interfaces:**
- Consumes: the three approved effect scene public APIs.
- Produces: a preview-only sequence of charge -> release -> flight -> explosion.

- [x] **Step 1: Write and run a failing sequence Preview test**

  Require exactly one instance of each accepted effect and verify that the Preview references
  no Mage, AllyBase, SkillModuleBase, TestScene, collision query, or target-search script.

- [x] **Step 2: Implement the preview-only timeline**

  Play charge for `0.75s`, hide it on release, move the flight carrier across a fixed path,
  stop flight at the endpoint, play explosion, wait, and repeat.

- [x] **Step 3: Run final visual-plan verification**

  Run all visual tests, the complete existing test suite, headless smoke, MCP editor error scan,
  and the TestScene hash check.

- [x] **Step 4: Open the sequence Preview and stop for final visual approval**

  No Fireball skill, projectile behavior, Mage assembly, or AllyBase scheduling work begins
  until the user explicitly approves the complete visual sequence.

  Status: complete sequence Preview approved by the user on 2026-07-16.

  Final verification evidence (2026-07-16): all `17/17` headless tests passed, Godot 4.7
  headless smoke exited with code `0`, and `Scenes/TestScene.tscn` retained SHA-256
  `DC4650265C9592A71416BA6E84093124554D33CB1D744BFAB73CEDCA5E566780`.

## Visual Phase Result

The approved reusable visual set now contains independent charge, flight, and explosion
effects plus a preview-only complete sequence. Gameplay delivery, target selection, collision,
damage, and Mage skill assembly remain intentionally outside this visual implementation phase.
