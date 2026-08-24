# Mage Fireball Gameplay Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将已经批准的火球蓄力、飞行和爆炸视觉接入通用技能架构，使 Mage 能在战斗中自主接近、施法、发射追踪火球并发送去重后的范围命中信号。

**Architecture:** `AllyBase` 只负责通用技能注册、选择、目标提供、移动所有权、动作互斥与公共冷却；`SkillModuleBase` 负责决策等待、施法、最终校验和技能冷却；`FireballSkill` 只负责生成并发射投射物；`FireballProjectile` 负责转向、扫掠碰撞、爆炸查询和视觉播放。火球模块和投射物均不读取 `AllyBase` 的字段，也不应用伤害。

**Tech Stack:** Godot 4.7、GDScript、Resource、ShapeCast3D、PhysicsDirectSpaceState3D、现有 Fireball Effect 场景、SceneTree headless tests、Godot MCP Pro。

## Global Constraints

- 不修改或自动添加 `Scenes/TestScene.tscn` 中的任何单位实例。
- 复用已批准的三个视觉场景，不复制其中的 Mesh、粒子、灯光或材质。
- `Scenes/Projectiles/FireBall.tscn` 作为现有火球占位场景直接升级为正式投射物，避免创建第二个重复火球场景。
- AllyBase 不得出现火球专用字段、节点路径、投射物参数或命中规则。
- `SkillModuleBase` 和 `FireballProjectile` 不得依赖 AllyBase 或 Mage。
- 只有成功发射投射物才算技能交付成功并启动技能冷却；公共冷却仍在成功开始施法时启动。
- 本阶段不加入伤害、生命值、击退、燃烧、命中停顿、屏幕震动、音效或伤害数字。
- 所有字段、方法和信号使用英文标识；新增或修改的代码使用详细简体中文注释。
- 项目不是 Git 仓库，因此不创建提交，以每个任务的测试结果和最终哈希记录代替提交步骤。

---

### Task 1: Skill Profile 与施法动画公共能力

**Files:**
- Modify: `Scripts/Combat/Skills/SkillProfile.gd`
- Modify: `Scripts/Combat/Skills/SkillModuleBase.gd`
- Modify: `Scenes/Components/SkillModules/SkillModuleBase.tscn`
- Modify: `Tests/SkillModuleBaseTest.gd`

**Interfaces:**
- Produces profile fields: `ai_priority: int`, `can_move_while_casting: bool`.
- Produces module export: `cast_animation_name: StringName = &"cast"`.
- Produces getters: `get_ai_priority() -> int`, `get_target_faction() -> int`, `can_move_during_cast() -> bool`.
- Preserves all existing request, delivery, retry, cooldown, and signal interfaces.

- [x] **Step 1: Extend the failing base contract test**

  Add assertions that a duplicated profile exposes `ai_priority` and `can_move_while_casting`,
  the module exposes the three getters and `cast_animation_name`, and a temporary `cast`
  animation starts on `begin_cast()` then returns to `RESET` after success, cancel, failure,
  reset, and exit.

  ```gdscript
  _assert_equal(profile.get("ai_priority"), 0, "default AI priority")
  _assert_equal(profile.get("can_move_while_casting"), false, "default cast movement")
  _assert_true(module.has_method("get_ai_priority"), "missing priority getter")
  _assert_true(module.has_method("get_target_faction"), "missing faction getter")
  _assert_true(module.has_method("can_move_during_cast"), "missing cast movement getter")
  _assert_equal(module.get("cast_animation_name"), &"cast", "default cast animation")
  ```

- [x] **Step 2: Run the focused test and verify RED**

  ```powershell
  & 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' --headless --path 'G:\Godot\SipSip' --script res://Tests/SkillModuleBaseTest.gd
  ```

  Expected: exit code `1` because the new fields/getters do not exist.

- [x] **Step 3: Add the profile fields and public getters**

  Add to `SkillProfile.gd`:

  ```gdscript
  @export_category("AI Selection")
  ## 数值越高越优先被通用宿主选择；同优先级由宿主随机选择。
  @export var ai_priority: int = 0

  ## 为 true 时宿主可以在施法计时期间继续执行自己的移动策略。
  @export var can_move_while_casting: bool = false
  ```

  Add to `SkillModuleBase.gd`:

  ```gdscript
  @export_category("Animation")
  @export_node_path("AnimationPlayer") var animation_player_path: NodePath = ^"SkillAnimationPlayer"
  ## 子技能可覆盖动画名称；缺少该动画不会阻止技能流程。
  @export var cast_animation_name: StringName = &"cast"

  func get_ai_priority() -> int:
      return skill_profile.ai_priority if skill_profile != null else 0

  func get_target_faction() -> int:
      return int(skill_profile.target_faction) if skill_profile != null else -1

  func can_move_during_cast() -> bool:
      return skill_profile != null and skill_profile.can_move_while_casting
  ```

- [x] **Step 4: Add deterministic cast-animation lifecycle handling**

  On successful `begin_cast()`, call:

  ```gdscript
  func _play_cast_animation() -> void:
      if not is_instance_valid(skill_animation_player):
          return
      if cast_animation_name.is_empty():
          return
      if skill_animation_player.has_animation(cast_animation_name):
          skill_animation_player.play(cast_animation_name)
  ```

  Keep `_reset_animation()` as the single cleanup path and ensure delivery success calls it
  before clearing the request. Add an empty `cast` animation to the base scene so inherited
  scenes may override it without changing the parent script.

- [x] **Step 5: Run the base and host regression tests**

  ```powershell
  $godot='G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe'
  & $godot --headless --path 'G:\Godot\SipSip' --script res://Tests/SkillModuleBaseTest.gd
  & $godot --headless --path 'G:\Godot\SipSip' --script res://Tests/AllySkillModuleHostTest.gd
  ```

  Expected: both tests print `PASS` and exit `0`.

---

### Task 2: AllyBase 多技能注册与通用 AI 调度

**Files:**
- Modify: `Scripts/AI/AllyBase.gd`
- Modify: `Scenes/ObjectScenes/AllyBase.tscn`
- Create: `Tests/AllySkillSchedulerTest.gd`
- Modify: `Tests/AllySkillModuleHostTest.gd`

**Interfaces:**
- Consumes: `SkillModuleBase.can_request_skill()`, `request_skill()`, `begin_cast()`, `get_skill_state()`, `get_cast_range()`, `get_cast_range_tolerance()`, `get_ai_priority()`, `get_target_faction()`, `can_move_during_cast()`.
- Produces: `register_skill_module(module)`, `unregister_skill_module(module)`, `get_registered_skill_modules()`, `get_active_skill_module()`, `select_skill_module(available_modules)`, `select_target_for_skill(module)`.
- Preserves: `skill_module_path`, `set_skill_module()`, `get_skill_module()`, `request_equipped_skill()`, `begin_equipped_skill_cast()` as primary-module compatibility APIs.

- [x] **Step 1: Write failing registration and scheduler tests**

  Cover these exact cases in `AllySkillSchedulerTest.gd` using synthetic base skill modules:

  ```gdscript
  _assert_equal(ally.call("get_registered_skill_modules").size(), 2, "socket discovery")
  _assert_true(selected == high_priority_module, "highest priority must win")
  _assert_true(ally.call("select_target_for_skill", enemy_module) == enemy, "enemy target")
  _assert_true(ally.call("select_target_for_skill", self_module) == ally, "self target")
  _assert_true(ally.call("select_target_for_skill", ally_module) == null, "ALLY is deferred")
  _assert_true(queued_out_of_range_owns_movement, "skill approach must be exclusive")
  _assert_true(not cast_started_during_attack, "basic attack must block cast")
  _assert_true(shared_cooldown_started_on_cast, "cast starts shared cooldown")
  _assert_true(active_slot_released_after_delivery, "delivery releases active slot")
  ```

  Also verify runtime registration/unregistration, invalid target cancellation, forced combat
  disengage cancellation, decision-wait guard wandering, casting movement stop, and other
  modules continuing their local cooldown while one module is active.

- [x] **Step 2: Run scheduler tests and verify RED**

  ```powershell
  & 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' --headless --path 'G:\Godot\SipSip' --script res://Tests/AllySkillSchedulerTest.gd
  ```

  Expected: exit `1` because the registry and scheduler APIs are absent.

- [x] **Step 3: Add registry state and socket discovery**

  Add these fields and APIs to `AllyBase.gd`:

  ```gdscript
  @export_node_path("Node3D") var skill_module_socket_path: NodePath = ^"VisualRoot/SkillModuleSocket"

  var registered_skill_modules: Array[SkillModuleBaseType] = []
  var active_skill_module: SkillModuleBaseType

  func register_skill_module(module: SkillModuleBaseType) -> bool:
      if not is_instance_valid(module) or registered_skill_modules.has(module):
          return false
      registered_skill_modules.append(module)
      _connect_skill_module_signals(module)
      module.configure_skill_owner(self)
      return true

  func unregister_skill_module(module: SkillModuleBaseType) -> bool:
      if not registered_skill_modules.has(module):
          return false
      if active_skill_module == module:
          module.cancel_skill()
          active_skill_module = null
      _disconnect_skill_module_signals(module)
      module.configure_skill_owner(null)
      registered_skill_modules.erase(module)
      if skill_module == module:
          skill_module = null
      return true

  func get_registered_skill_modules() -> Array[SkillModuleBaseType]:
      return registered_skill_modules.duplicate()

  func get_active_skill_module() -> SkillModuleBaseType:
      return active_skill_module if is_instance_valid(active_skill_module) else null
  ```

  `_ready()` scans only direct children under `skill_module_socket_path`. `set_skill_module()`
  first registers the module and then assigns it as the primary compatibility shortcut; it
  must not unregister unrelated socket children.

- [x] **Step 4: Add overridable selection methods**

  Implement:

  ```gdscript
  func select_skill_module(
      available_modules: Array[SkillModuleBaseType]
  ) -> SkillModuleBaseType:
      if available_modules.is_empty():
          return null
      var highest_priority: int = -2147483648
      var candidates: Array[SkillModuleBaseType] = []
      for module: SkillModuleBaseType in available_modules:
          var priority: int = module.get_ai_priority()
          if priority > highest_priority:
              highest_priority = priority
              candidates.clear()
              candidates.append(module)
          elif priority == highest_priority:
              candidates.append(module)
      return candidates[random_generator.randi_range(0, candidates.size() - 1)]

  func select_target_for_skill(module: SkillModuleBaseType) -> Node3D:
      if not is_instance_valid(module):
          return null
      match module.get_target_faction():
          SkillProfileType.SkillTargetFaction.ENEMY:
              return current_visible_enemy if is_instance_valid(current_visible_enemy) else null
          SkillProfileType.SkillTargetFaction.SELF:
              return self
          _:
              return null
  ```

  Use the existing preloaded `SkillProfile` type or add a dedicated preload constant; do not
  hardcode enum integers.

- [x] **Step 5: Add one-owner-per-frame skill scheduling**

  Add `_process_skill_scheduler(delta: float) -> bool` and call it before ordinary basic-attack
  movement. Its return value means the skill owns horizontal movement for the current frame.

  ```gdscript
  func _process_skill_scheduler(delta: float) -> bool:
      if activity_mode != ActivityMode.COMBAT:
          _cancel_active_skill_request()
          return false
      if not is_instance_valid(active_skill_module):
          _try_request_available_skill()
      if not is_instance_valid(active_skill_module):
          return false

      var target: Node3D = active_skill_module.get_current_target()
      if not is_instance_valid(target):
          _release_active_skill_module(true)
          return false

      if active_skill_module.is_casting():
          _face_skill_target(target)
          if active_skill_module.can_move_during_cast():
              return false
          _stop_horizontal_movement(delta)
          return true

      if active_skill_module.is_queued():
          if not _is_skill_target_in_host_range(active_skill_module, target):
              _move_into_skill_range(active_skill_module, target, delta)
              return true
          if basic_attack_global_cooldown_remaining <= 0.0 and not _is_basic_attack_playing():
              active_skill_module.begin_cast()
              _stop_horizontal_movement(delta)
              return true
      return false
  ```

  `DECISION_WAIT` deliberately returns `false`, so existing combat guard wandering continues.
  `_move_into_skill_range()` uses the same constrained target and movement helpers as basic
  attack approach but uses the active skill's cast range. During `CASTING`, keep facing the
  skill target. Signal callbacks must bind the source module so only the matching module can
  release `active_skill_module`.

- [x] **Step 6: Enforce action exclusion and cleanup**

  Update `_try_start_basic_attack()` to reject while `active_skill_module` is casting. Cancel
  and release the active skill on target invalidation, forced disengage, formation transition,
  module unmount, and owner exit. Do not clear `basic_attack_global_cooldown_remaining` during
  any cleanup. Continue starting that shared cooldown only inside the cast-start callback.

- [x] **Step 7: Run scheduler and all existing Ally tests**

  ```powershell
  $godot='G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe'
  & $godot --headless --path 'G:\Godot\SipSip' --script res://Tests/AllySkillSchedulerTest.gd
  & $godot --headless --path 'G:\Godot\SipSip' --script res://Tests/AllySkillModuleHostTest.gd
  & $godot --headless --path 'G:\Godot\SipSip' --script res://Tests/AllyBasicAttackTest.gd
  & $godot --headless --path 'G:\Godot\SipSip' --script res://Tests/AllyAttackDistanceTest.gd
  ```

  Expected: all four tests print `PASS` and exit `0`.

---

### Task 3: FireBall 追踪投射物、扫掠碰撞与爆炸查询

**Files:**
- Create: `Scripts/Combat/Skills/FireballProjectile.gd`
- Modify: `Scenes/Projectiles/FireBall.tscn`
- Create: `Tests/FireballProjectileTest.gd`

**Interfaces:**
- Consumes visuals: `FireballFlightEffect.start()/stop()` and `FireballExplosionEffect.play()/stop()`.
- Produces: `launch(caster, target, start_position, initial_direction, speed, turn_speed_degrees, lifetime, explosion_radius) -> bool`.
- Produces signals: `projectile_impacted(position)`, `fireball_hit(target, hit_position, hit_direction)`, `fireball_exploded(position, targets)`.
- Has no dependency on SkillModuleBase, AllyBase, Mage, damage, or health.

- [x] **Step 1: Write the failing projectile contract and physics tests**

  Test scene loading, exact node paths, launch validation, `9m/s` motion, maximum turn angle,
  straight continuation after target deletion, ShapeCast collision with environment and enemy,
  caster exclusion, ally-layer pass-through, explosion group/layer filtering, deduplication,
  direct-hit inclusion, empty environment explosion, and silent lifetime expiry.

  ```gdscript
  _assert_true(projectile.has_method("launch"), "missing launch API")
  _assert_true(projectile.has_signal("projectile_impacted"), "missing impact signal")
  _assert_true(projectile.has_signal("fireball_hit"), "missing hit signal")
  _assert_true(projectile.has_signal("fireball_exploded"), "missing explosion signal")
  _assert_equal(shape_cast.collision_mask, 5, "environment plus enemy mask")
  _assert_equal(explosion_targets.size(), 2, "deduplicated valid enemies")
  ```

- [x] **Step 2: Run the test and verify RED**

  ```powershell
  & 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' --headless --path 'G:\Godot\SipSip' --script res://Tests/FireballProjectileTest.gd
  ```

  Expected: exit `1` because `FireballProjectile.gd` and the required scene structure are absent.

- [x] **Step 3: Upgrade the existing FireBall scene**

  Build this exact structure:

  ```text
  FireBall (Node3D, FireballProjectile.gd)
  ├── CollisionSweep (ShapeCast3D, SphereShape3D radius 0.18, mask 5)
  ├── FireballFlightEffect (approved scene instance, autoplay=false)
  └── FireballExplosionEffect (approved scene instance, autoplay=false, auto_free=false)
  ```

  `CollisionSweep` uses bodies only, excludes the caster RID, has `maximum_results = 32`, and
  remains disabled outside active flight.

- [x] **Step 4: Implement launch and limited homing**

  Validate all arguments, normalize the horizontal-safe initial direction, position the node,
  configure caster exclusion, start the flight visual, and enable physics processing. Each
  physics frame rotates toward `target.global_position + Vector3.UP * 0.25` by no more than:

  ```gdscript
  var maximum_turn: float = deg_to_rad(turn_speed_degrees) * delta
  var angle_to_target: float = current_direction.angle_to(desired_direction)
  if angle_to_target > 0.0001:
      current_direction = current_direction.slerp(
          desired_direction,
          minf(maximum_turn / angle_to_target, 1.0)
      ).normalized()
  var displacement: Vector3 = current_direction * speed * delta
  ```

  When the target becomes invalid, retain `current_direction` and continue without homing.

- [x] **Step 5: Implement swept impact and explosion query**

  Before movement, set the ShapeCast target to the complete frame displacement, call
  `force_shapecast_update()`, and use the nearest collision point. On impact:

  ```gdscript
  func _explode(impact_position: Vector3, direct_target: CharacterBody3D = null) -> void:
      flight_is_active = false
      set_physics_process(false)
      collision_sweep.enabled = false
      flight_effect.stop()
      global_position = impact_position
      projectile_impacted.emit(impact_position)
      var targets: Array[CharacterBody3D] = _query_explosion_targets(
          impact_position,
          direct_target
      )
      for target: CharacterBody3D in targets:
          var direction: Vector3 = target.global_position - impact_position
          direction.y = 0.0
          if direction.length_squared() <= 0.0001:
              direction = current_direction
          fireball_hit.emit(target, impact_position, direction.normalized())
      fireball_exploded.emit(impact_position, targets)
      explosion_effect.play()
  ```

  `_query_explosion_targets()` uses `PhysicsShapeQueryParameters3D` with a `SphereShape3D`,
  enemy mask `4`, bodies enabled, areas disabled, caster excluded, group `enemy_targets`, and
  an instance-ID dictionary. Insert a valid direct enemy into the same dictionary before
  returning the typed array. Free the projectile only when the explosion effect finishes;
  missing visuals fall back to immediate cleanup without suppressing gameplay signals.

- [x] **Step 6: Run projectile and accepted visual tests**

  ```powershell
  $godot='G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe'
  & $godot --headless --path 'G:\Godot\SipSip' --script res://Tests/FireballProjectileTest.gd
  & $godot --headless --path 'G:\Godot\SipSip' --script res://Tests/FireballFlightEffectTest.gd
  & $godot --headless --path 'G:\Godot\SipSip' --script res://Tests/FireballExplosionEffectTest.gd
  ```

  Expected: all three tests print `PASS` and exit `0`.

---

### Task 4: FireballSkill 可装卸技能模块与 Profile

**Files:**
- Create: `Scripts/Combat/Skills/FireballSkill.gd`
- Create: `Scenes/Components/SkillModules/FireballSkill.tscn`
- Create: `Resources/Combat/Skills/MageFireballProfile.tres`
- Create: `Tests/FireballSkillTest.gd`

**Interfaces:**
- Consumes: SkillModuleBase lifecycle and `FireBall.tscn` launch API.
- Produces override: `deliver_skill(caster, target, target_position) -> bool`.
- Produces signals: `projectile_launched`, `projectile_impacted`, `fireball_hit`, `fireball_exploded`.
- Exports: `projectile_scene`, `projectile_speed`, `turn_speed_degrees`, `maximum_lifetime`, `explosion_radius`, `cast_origin_path`.

- [x] **Step 1: Write the failing skill-module test**

  Verify inheritance, exact Profile defaults, CastOrigin, approved charge visual instance,
  valid launch parenting, launch parameter forwarding, signal forwarding, failed-delivery
  cleanup, no cooldown on failure, charge start/reset behavior, and absence of AllyBase/Mage
  dependencies in the script text.

  ```gdscript
  _assert_equal(profile.get("display_name"), "Mage Fireball", "display name")
  _assert_near(float(profile.get("cast_range")), 6.0, 0.001, "cast range")
  _assert_near(float(profile.get("cast_time")), 0.75, 0.001, "cast time")
  _assert_near(float(profile.get("skill_cooldown")), 5.0, 0.001, "skill cooldown")
  _assert_equal(profile.get("required_target_group"), &"enemy_targets", "target group")
  ```

- [x] **Step 2: Run the test and verify RED**

  ```powershell
  & 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' --headless --path 'G:\Godot\SipSip' --script res://Tests/FireballSkillTest.gd
  ```

  Expected: exit `1` because the skill module and Profile are absent.

- [x] **Step 3: Create the reusable Profile**

  Configure `MageFireballProfile.tres`:

  ```text
  display_name = "Mage Fireball"
  target_faction = ENEMY
  delivery_type = PROJECTILE
  required_target_group = &"enemy_targets"
  cast_range = 6.0
  cast_range_tolerance = 0.25
  cast_time = 0.75
  skill_cooldown = 5.0
  decision_delay_min = 0.3
  decision_delay_max = 3.0
  extra_hesitation_chance = 0.10
  extra_hesitation_min = 3.0
  extra_hesitation_max = 5.0
  ai_priority = 0
  can_move_while_casting = false
  ```

- [x] **Step 4: Create the inherited FireballSkill scene**

  Scene shape:

  ```text
  FireballSkill (inherits SkillModuleBase)
  ├── CastOrigin
  │   └── FireballCastChargeEffect (approved instance, autoplay=false)
  ├── DeliveryRoot
  └── SkillAnimationPlayer
  ```

  Assign the Mage Profile and existing `FireBall.tscn`. Keep the charge visual under
  `CastOrigin` so future hand/socket replacement changes only the module transform.

- [x] **Step 5: Implement delivery and signal forwarding**

  `deliver_skill()` must validate caster, `CharacterBody3D` target, group, projectile scene,
  CastOrigin, scene tree, instantiated launch API, and gameplay parent. Parent the projectile
  to `get_tree().current_scene`; in isolated tests where `current_scene` is null, use a test
  world explicitly assigned as current scene rather than silently parenting under Mage.

  ```gdscript
  var projectile: Node3D = projectile_scene.instantiate() as Node3D
  gameplay_parent.add_child(projectile)
  var initial_direction: Vector3 = target.global_position - cast_origin.global_position
  if not bool(projectile.call(
      "launch",
      caster,
      target,
      cast_origin.global_position,
      initial_direction,
      projectile_speed,
      turn_speed_degrees,
      maximum_lifetime,
      explosion_radius
  )):
      projectile.queue_free()
      return false
  _connect_projectile_signals(projectile)
  projectile_launched.emit(projectile)
  return true
  ```

  Listen to the base lifecycle signals: start charge on `cast_started`; stop/reset it on
  delivery request, cancellation, failure, reset, and exit. Forward projectile signals
  unchanged and never mutate hit targets.

- [x] **Step 6: Run skill, base, projectile, and charge tests**

  ```powershell
  $godot='G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe'
  & $godot --headless --path 'G:\Godot\SipSip' --script res://Tests/FireballSkillTest.gd
  & $godot --headless --path 'G:\Godot\SipSip' --script res://Tests/SkillModuleBaseTest.gd
  & $godot --headless --path 'G:\Godot\SipSip' --script res://Tests/FireballProjectileTest.gd
  & $godot --headless --path 'G:\Godot\SipSip' --script res://Tests/FireballCastChargeEffectTest.gd
  ```

  Expected: all four tests print `PASS` and exit `0`.

---

### Task 5: Mage 源场景装配与端到端 AI 测试

**Files:**
- Modify: `Scenes/ObjectScenes/Mage.tscn`
- Modify: `Tests/MageSkillAssemblyTest.gd`

**Interfaces:**
- Consumes: `FireballSkill.tscn` and generic Ally skill scheduler.
- Produces: Mage source scene with one FireballSkill mounted at `VisualRoot/SkillModuleSocket/FireballSkill`.
- Does not modify: `Scenes/TestScene.tscn` or Mage formation script.

- [x] **Step 1: Update the assembly test first**

  Change the expected path to:

  ```gdscript
  const EXPECTED_MODULE_PATH := ^"VisualRoot/SkillModuleSocket/FireballSkill"
  ```

  Verify only Mage mounts a skill, the mounted script is `FireballSkill.gd`, the Profile is
  `MageFireballProfile.tres`, owner injection succeeds, a visible enemy causes decision wait,
  out-of-range Mage approaches exclusively, in-range Mage starts casting after shared cooldown,
  successful delivery spawns one world-owned projectile, and local cooldown begins only after
  launch succeeds.

- [x] **Step 2: Run assembly test and verify RED**

  ```powershell
  & 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' --headless --path 'G:\Godot\SipSip' --script res://Tests/MageSkillAssemblyTest.gd
  ```

  Expected: exit `1` because Mage still mounts `SkillModuleBase`.

- [x] **Step 3: Replace only the Mage skill instance**

  In `Mage.tscn`:

  - Replace the placeholder PackedScene resource with `FireballSkill.tscn`.
  - Replace the child node with `FireballSkill` under `VisualRoot/SkillModuleSocket`.
  - Set `skill_module_path = NodePath("VisualRoot/SkillModuleSocket/FireballSkill")`.
  - Preserve body, hat, magic focus, all materials, formation values, ranger coordination,
    combat guard distance, movement, dash, gravity, and collision properties byte-for-byte.

- [x] **Step 4: Run the Mage and unrelated-profession regressions**

  ```powershell
  $godot='G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe'
  & $godot --headless --path 'G:\Godot\SipSip' --script res://Tests/MageSkillAssemblyTest.gd
  & $godot --headless --path 'G:\Godot\SipSip' --script res://Tests/GuardianShieldAttackTest.gd
  & $godot --headless --path 'G:\Godot\SipSip' --script res://Tests/WarriorSwordAttackTest.gd
  & $godot --headless --path 'G:\Godot\SipSip' --script res://Tests/RangerCrossbowAttackTest.gd
  ```

  Expected: all four tests print `PASS`; Warrior negative-path warnings remain allowed only
  where that test intentionally verifies invalid animation configuration.

---

### Task 6: 文档、全量验证与编辑器交付

**Files:**
- Modify: `Docs/Superpowers/Specs/2026-07-15-mage-fireball-skill-design.md`
- Modify: `Docs/Superpowers/Plans/2026-07-16-mage-fireball-gameplay-implementation-plan.md`
- Modify: the existing project progress summary Markdown document that records combat systems

**Interfaces:**
- Records exact final paths, public APIs, Inspector defaults, deferred scope, and verification evidence.
- Preserves the project rule that unit instances in TestScene are user-managed.

- [x] **Step 1: Record the implementation refinement**

  Update the design document so the canonical projectile path is the upgraded existing
  `res://Scenes/Projectiles/FireBall.tscn`, while the script remains
  `res://Scripts/Combat/Skills/FireballProjectile.gd`. Record the final Mage module path and
  the fact that the accepted visual scenes are reused as child instances.

- [x] **Step 2: Run every headless test fresh**

  ```powershell
  $godot='G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe'
  $tests=Get-ChildItem Tests -Filter '*Test.gd' | Sort-Object Name
  $failed=@()
  foreach($test in $tests){
      & $godot --headless --path 'G:\Godot\SipSip' --script ('res://Tests/'+$test.Name)
      if($LASTEXITCODE -ne 0){$failed += $test.Name}
  }
  Write-Output ('TEST_COUNT='+$tests.Count)
  Write-Output ('FAILED_COUNT='+$failed.Count)
  if($failed.Count -gt 0){$failed; exit 1}
  ```

  Expected: `FAILED_COUNT=0`.

- [x] **Step 3: Run smoke, TestScene integrity, and dependency scans**

  ```powershell
  $godot='G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe'
  & $godot --headless --path 'G:\Godot\SipSip' --quit-after 10
  if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}
  (Get-FileHash 'Scenes\TestScene.tscn' -Algorithm SHA256).Hash
  rg -n "AllyBase|Mage\.tscn" Scripts/Combat/Skills/FireballProjectile.gd Scripts/Combat/Skills/FireballSkill.gd
  ```

  Expected: smoke exit `0`; TestScene SHA-256 remains
  `DC4650265C9592A71416BA6E84093124554D33CB1D744BFAB73CEDCA5E566780`;
  dependency scan returns no matches.

- [x] **Step 4: Refresh Godot and inspect the editor**

  Through Godot MCP Pro, refresh/reopen the project, open
  `res://Scenes/Components/SkillModules/FireballSkill.tscn`, clear Output, and verify editor
  error count is `0`. Then run `res://Scenes/ObjectScenes/Mage.tscn` only for isolated runtime
  inspection if its required player/ranger paths are supplied by a test harness; do not edit
  or add any TestScene unit instance.

  2026-07-16 final evidence: after a full saved editor restart, Godot MCP reconnected and
  `get_project_info` reported project `SipSip` on Godot `4.7-stable`. Opened the exact module
  scene, cleared Output, waited 1.5 seconds, and `get_editor_errors(max_lines=200)` returned
  `count=0` with `errors=[]`. Earlier read-only inspection also confirmed its tree, exports,
  Profile, projectile, and five direct dependencies.

- [x] **Step 5: Hand off manual TestScene observation instructions**

  Ask the user to use the Mage instance they already placed, or manually add
  `res://Scenes/ObjectScenes/Mage.tscn` under the TestScene root if none exists. Required
  conditions: Mage `player_path` resolves to Hero, `ranger_path` resolves to Ranger when used,
  and at least one Dummy is within Mage perception/player engagement limits. Codex must not
  perform this TestScene unit insertion.

### Task 6 verification evidence (2026-07-16)

- Headless tests: `TEST_COUNT=20`, `FAILED_COUNT=0`.
- Warning classification: only the approved Warrior negative-path configuration warning appeared
  twice; no new test warnings/errors.
- Project smoke: `SMOKE_EXIT=0`, with no smoke warning/error diagnostics.
- Dependency scans: no matches for `AllyBase|Mage\.tscn|TestScene|damage|health` in the Fireball
  module/projectile, and no `Fireball|FireBall` matches in `AllyBase.gd`.
- TestScene SHA-256: `DC4650265C9592A71416BA6E84093124554D33CB1D744BFAB73CEDCA5E566780`.
- Godot MCP scene: `res://Scenes/Components/SkillModules/FireballSkill.tscn`; after a full saved
  editor restart, final editor error count `0` with `errors=[]` on Godot `4.7-stable` project
  `SipSip`.

## Completion Criteria

- Mage autonomously selects Fireball while in combat, waits the configured random delay,
  approaches to `6.0m`, respects active basic attacks and the per-unit shared cooldown, casts
  for `0.75s`, and successfully launches a world-owned projectile.
- Fireball travels at `9.0m/s`, turns at no more than `180°/s`, sweeps environment and enemy
  layers, ignores allies, performs a `1.2m` enemy-only deduplicated explosion query, and sends
  signals without applying damage.
- Charge, flight, and explosion visuals are the exact previously approved reusable scenes.
- Failed cast or failed launch does not start the skill cooldown; successful launch does.
- Other professions preserve current behavior and no TestScene unit instance changes occur.
