# AI Melee Combat System Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在新 UnitSystem 中实现玩家与 AI 共用 WeaponData、动画事件、近战 Hitbox 和反馈资源的通用 AI 近战攻击链，并由 Amy 装备 IronSword 完成第一例验证。

**Architecture:** `AIUnitBase` 提供空视觉插槽、运动执行和通用 `AICombatSystem`；具体 Ally/Enemy 场景装载标准视觉场景。`AllyBehaviorStateMachine` 只决定接近、保持和攻击时机，`AICombatSystem` 管理 GCD，`AIAttackController` 播放随机单段武器动画，通用 `MeleeHitboxComponent` 负责命中查询。

**Tech Stack:** Godot 4.7、GDScript、PackedScene、AnimationLibrary、PhysicsDirectSpaceState3D、项目现有 SceneTree headless 测试。

**Implementation Status (2026-07-25):** COMPLETE — Tasks 1–7 已实施；15 项
`UnitSystem/Tests/*.gd` 全部通过，Godot 4.7 项目扫描无脚本错误；当前活动目录没有
`Scenes/TestScene.tscn`，本次未创建或修改任何测试场景。

## Global Constraints

- 不修改 `res://Scenes/TestScene.tscn` 或其中任何单位实例。
- 不删除或改写旧 `Scenes/Components/AiAttackModules`、旧 Guardian、Warrior 等单位。
- 第一阶段不结算伤害、生命值、击退或死亡。
- 玩家与 AI 共用 `WeaponData`、AnimationLibrary、武器视觉和 Hitbox 数据。
- 所有新增字段和方法使用英文标识，代码添加详细简体中文注释。
- 项目不是 Git 仓库，各任务以测试结果代替提交。

---

### Task 1: 泛化玩家近战 Hitbox

**Files:**
- Create: `UnitSystem/Components/Combat/Common/MeleeHitboxComponent.gd`
- Create: `UnitSystem/Components/Combat/Common/MeleeHitboxComponent.tscn`
- Create: `UnitSystem/Tests/MeleeHitboxComponentTest.gd`
- Modify: `UnitSystem/Player/PlayerBase.tscn`
- Modify: `UnitSystem/Components/Combat/PlayerAttackController.gd`

**Interfaces:**
- Consumes: `WeaponData.hitbox_sizes`, `WeaponData.hitbox_center_offsets`, `UnitBase.is_hostile_to()`
- Produces:
  - `configure_owner(owner_unit: UnitBase) -> void`
  - `begin_detection(weapon_data: WeaponData, attack_index: int, locked_direction: Vector3) -> bool`
  - `end_detection() -> void`
  - `set_detection_suspended(active: bool) -> void`
  - `attack_hit(target: UnitBase, hit_position: Vector3, hit_direction: Vector3, attack_index: int)`

- [ ] **Step 1: Write the failing common-hitbox test**

Create a SceneTree test that loads the new scene path and verifies a real query:

```gdscript
var hitbox_scene := load(
	"res://UnitSystem/Components/Combat/Common/MeleeHitboxComponent.tscn"
) as PackedScene
_expect(hitbox_scene != null, "common melee hitbox scene loads")

var opened: bool = hitbox.begin_detection(
	weapon_data,
	1,
	Vector3.FORWARD
)
_expect(opened, "valid weapon hitbox profile opens detection")
_expect(hit_count == 1, "one hostile target emits once per window")
_expect(friendly_hit_count == 0, "friendly target is filtered by team relation")
```

- [ ] **Step 2: Verify RED**

Run:

```powershell
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' --headless --path 'G:\Godot\SipSip' -s 'res://UnitSystem/Tests/MeleeHitboxComponentTest.gd'
```

Expected: FAIL because the common scene does not exist.

- [ ] **Step 3: Move the existing behavior into the common component**

Preserve the current real-query implementation and rename combo terminology to attack terminology:

```gdscript
signal attack_hit(
	target: UnitBase,
	hit_position: Vector3,
	hit_direction: Vector3,
	attack_index: int
)

func begin_detection(
	weapon_data: WeaponData,
	attack_index: int,
	locked_direction: Vector3
) -> bool:
	var profile_index: int = attack_index - 1
	# Validate arrays, size and direction before enabling the window.
```

Keep debug transform reset, per-window instance-ID deduplication, hostility, targetable and dead checks.

- [ ] **Step 4: Point PlayerBase at the common scene**

Keep the instantiated node name `MeleeHitbox`, so `PlayerAttackController` retains its stable node contract. Update only type wording and parameter names where needed.

- [ ] **Step 5: Verify GREEN and player regression**

Run the new test, the existing shield/ranged resource tests and a Godot editor scan. Expected: common test passes and no player script error or warning is introduced.

---

### Task 2: Extract AI visual scenes

**Files:**
- Create: `UnitSystem/AI/Ally/Visuals/AllyBaseVisual.tscn`
- Create: `UnitSystem/AI/Enemy/Visuals/EnemyBaseVisual.tscn`
- Create: `UnitSystem/Tests/AIVisualContractTest.gd`
- Modify: `UnitSystem/Base/AIUnitBase.tscn`
- Modify: `UnitSystem/AI/Ally/AllyBase2.tscn`
- Modify: `UnitSystem/AI/Enemy/EnemyBase2.tscn`

**Interfaces:**
- Consumes: current blue/red materials and `CharacterAnimationEventPlayer.gd`
- Produces visual endpoint contract:
  - `CharacterRoot`
  - `CharacterRoot/WeaponSocket`
  - `CharacterAnimationPlayer`

- [ ] **Step 1: Write the failing visual-contract test**

```gdscript
for scene_path: String in [
	"res://UnitSystem/AI/Ally/Visuals/AllyBaseVisual.tscn",
	"res://UnitSystem/AI/Enemy/Visuals/EnemyBaseVisual.tscn",
]:
	var visual := (load(scene_path) as PackedScene).instantiate() as Node3D
	_expect(visual.get_node_or_null(^"CharacterRoot") != null, "CharacterRoot exists")
	_expect(
		visual.get_node_or_null(^"CharacterRoot/WeaponSocket") != null,
		"WeaponSocket exists"
	)
	_expect(
		visual.get_node_or_null(^"CharacterAnimationPlayer")
			is CharacterAnimationEventPlayer,
		"event AnimationPlayer exists"
	)
```

Also assert that a direct `AIUnitBase` has an empty `Visual` slot, while AllyBase2 and EnemyBase2 each mount exactly one visual scene.

- [ ] **Step 2: Verify RED**

Run `AIVisualContractTest.gd`. Expected: FAIL because the two visual scenes are missing and AIUnitBase still owns BodyMesh.

- [ ] **Step 3: Create the visual scenes**

Move the existing 0.5m CSGBox appearance into each visual scene. Keep the blue ally material and red enemy material unchanged. Add `WeaponSocket` at the same temporary location used by HeroVisual and attach `CharacterAnimationEventPlayer.gd` to the AnimationPlayer.

- [ ] **Step 4: Replace inherited visual content**

Remove `BodyMesh` from `AIUnitBase.tscn`. Instance AllyBaseVisual under AllyBase2/Visual and EnemyBaseVisual under EnemyBase2/Visual.

- [ ] **Step 5: Verify GREEN**

Run visual, locomotion, targeting and inherited-root-rename tests. Expected: visual contract passes and movement/targeting remain unchanged.

---

### Task 3: Add shared weapon attack range

**Files:**
- Modify: `Item/Weapon/WeaponData.gd`
- Modify: `Item/Weapon/Sword/IronSwordData.tres`
- Create: `UnitSystem/Tests/WeaponAttackRangeTest.gd`

**Interfaces:**
- Produces:
  - `WeaponData.attack_range: float`
  - `WeaponData.attack_range_tolerance: float`

- [ ] **Step 1: Write the failing resource test**

```gdscript
var sword := load(
	"res://Item/Weapon/Sword/IronSwordData.tres"
) as WeaponData
_expect(is_equal_approx(sword.attack_range, 1.0), "IronSword range is 1m")
_expect(
	is_equal_approx(sword.attack_range_tolerance, 0.1),
	"IronSword tolerance is 0.1m"
)
```

- [ ] **Step 2: Verify RED**

Run `WeaponAttackRangeTest.gd`. Expected: script parse/property failure because WeaponData does not expose the fields.

- [ ] **Step 3: Add the fields and configure IronSword**

```gdscript
@export_category("Attack Range")
@export_range(0.1, 10.0, 0.1, "or_greater")
var attack_range: float = 1.0

@export_range(0.0, 2.0, 0.05)
var attack_range_tolerance: float = 0.1
```

- [ ] **Step 4: Verify GREEN**

Run weapon-range and current weapon resource tests. Expected: all pass without changing player attack behavior.

---

### Task 4: Add collision-aware AI attack motion

**Files:**
- Modify: `UnitSystem/Base/AIUnitBase.gd`
- Modify: `UnitSystem/Tests/AIUnitBaseLocomotionMigrationTest.gd`

**Interfaces:**
- Produces:
  - `request_attack_motion(direction: Vector3, distance: float, speed: float) -> bool`
  - `cancel_attack_motion() -> void`
  - `set_attack_motion_suspended(active: bool) -> void`
  - `is_attack_motion_active() -> bool`

- [ ] **Step 1: Write the failing motion test**

```gdscript
_expect(
	ai.request_attack_motion(Vector3.FORWARD, 0.5, 2.0),
	"valid attack motion is accepted"
)
_expect(ai.is_attack_motion_active(), "attack motion becomes active")
ai.set_attack_motion_suspended(true)
_expect(ai.is_attack_motion_suspended(), "attack motion can be locally paused")
ai.cancel_attack_motion()
_expect(not ai.is_attack_motion_active(), "attack motion cancels cleanly")
```

- [ ] **Step 2: Verify RED**

Run `AIUnitBaseLocomotionMigrationTest.gd`. Expected: missing method failure.

- [ ] **Step 3: Implement attack motion as a movement-layer state**

Add `ATTACK_MOVING` to `MotionState`. Store locked direction, speed, remaining distance and suspension state. Process it before regular navigation, retain gravity and the single `move_and_slide()`, and subtract actual post-slide displacement.

- [ ] **Step 4: Verify GREEN**

Run locomotion test and editor scan. Expected: attack motion APIs pass; dash and regular movement tests remain green.

---

### Task 5: Build AIAttackController and AICombatSystem

**Files:**
- Create: `UnitSystem/Components/Combat/AI/AIAttackController.gd`
- Create: `UnitSystem/Components/Combat/AI/AICombatSystem.gd`
- Create: `UnitSystem/Components/Combat/AI/AICombatSystem.tscn`
- Create: `UnitSystem/Tests/AIAttackControllerTest.gd`
- Create: `UnitSystem/Tests/AICombatSystemTest.gd`
- Modify: `UnitSystem/Base/AIUnitBase.gd`
- Modify: `UnitSystem/Base/AIUnitBase.tscn`

**Interfaces:**
- Consumes: visual endpoint contract, WeaponData, CharacterAnimationEventPlayer, MeleeHitboxComponent, DefaultAIHitFeedback
- Produces the interfaces and signals in section 10 of the approved design spec.

- [ ] **Step 1: Write the failing attack-controller test**

Use a real visual scene and IronSword:

```gdscript
_expect(controller.configure(owner, hitbox), "controller configures")
_expect(controller.equip_weapon(sword), "IronSword equips")
_expect(controller.request_attack(enemy), "valid hostile target starts attack")
_expect(controller.is_attacking(), "controller reports attacking")
_expect(
	controller.get_current_attack_index() in [1, 2, 3],
	"one valid sword animation is selected"
)
```

Repeat requests across completed animations and assert each bag contains all three unique indices before refill.

- [ ] **Step 2: Verify controller RED**

Run `AIAttackControllerTest.gd`. Expected: class/script missing.

- [ ] **Step 3: Implement AIAttackController**

Resolve one visual child and the three fixed endpoints. Atomically validate and equip the visual scene and animation library under library name `weapon`. Discover contiguous `basic_attack_1...n`, choose through a shuffled index bag and preserve the previous index across refills.

Connect:

```gdscript
animation_finished -> finish current attack
attack_motion_requested -> owner.request_attack_motion(...)
hit_window_open_requested -> hitbox.begin_detection(...)
hit_window_close_requested -> hitbox.end_detection()
hitbox.attack_hit -> controller.attack_hit
```

Implement local hit stop by pausing AnimationPlayer, attack motion and Hitbox detection only.

- [ ] **Step 4: Write the failing combat-system test**

```gdscript
combat.base_global_cooldown_duration = 1.0
_expect(combat.configure(owner), "combat system configures")
_expect(combat.equip_weapon(sword), "combat system equips sword")
_expect(combat.request_basic_attack(enemy), "first request succeeds")
_expect(
	is_equal_approx(combat.get_global_cooldown_remaining(), 1.0),
	"successful request starts one-second GCD"
)
_expect(
	not combat.request_basic_attack(enemy),
	"GCD blocks a second attack request"
)
```

Also verify failed/invalid requests do not start GCD, cancellation does not clear it and debug properties are read-only/non-storage.

- [ ] **Step 5: Verify combat-system RED**

Run `AICombatSystemTest.gd`. Expected: scene/script missing.

- [ ] **Step 6: Implement AICombatSystem**

Make the root node own `starting_weapon`, `base_global_cooldown_duration` and `debug_hitbox_enabled`. Delegate equipment and animation execution to its child controller. Start GCD only after `request_attack()` succeeds, decrement it in `_process()`, and expose the approved public queries/signals.

- [ ] **Step 7: Mount the system on AIUnitBase**

Instance `AICombatSystem.tscn` as `CombatSystem` in `AIUnitBase.tscn`. Configure it from `AIUnitBase._ready()` and expose:

```gdscript
func get_combat_system() -> AICombatSystem:
	return _combat_system if is_instance_valid(_combat_system) else null
```

- [ ] **Step 8: Verify GREEN**

Run both new tests, common Hitbox test, visual test, locomotion test and editor scan.

---

### Task 6: Integrate melee combat into Ally behavior and Amy

**Files:**
- Modify: `UnitSystem/Components/Behavior/AllyBehaviorStateMachine.gd`
- Modify: `UnitSystem/AI/Ally/AllyBase2.gd`
- Modify: `UnitSystem/AI/Ally/Units/Amy.tscn`
- Modify: `UnitSystem/Tests/AllyBehaviorStateMachineTest.gd`
- Create: `UnitSystem/Tests/AllyMeleeCombatIntegrationTest.gd`

**Interfaces:**
- Consumes: `AICombatSystem` public API and current AITargetingComponent
- Produces: `BehaviorState.COMBAT_ATTACK`

- [ ] **Step 1: Write the failing state-machine assertions**

```gdscript
_expect(
	AllyBehaviorStateMachine.BehaviorState.has("COMBAT_ATTACK"),
	"behavior state enum contains COMBAT_ATTACK"
)
_expect(
	is_equal_approx(
		state_machine.get_effective_combat_distance(),
		sword.attack_range
	),
	"equipped weapon supplies combat distance"
)
```

Use a real configured combat system. Place the enemy within range, tick the behavior state and assert successful request enters `COMBAT_ATTACK`.

- [ ] **Step 2: Verify RED**

Run `AllyBehaviorStateMachineTest.gd`. Expected: missing state/query and no attack transition.

- [ ] **Step 3: Add the combat-system dependency**

Extend configure without making combat mandatory:

```gdscript
func configure(
	owner_body: AIUnitBase,
	targeting_component: AITargetingComponent,
	combat_system: AICombatSystem = null
) -> bool:
```

Use weapon distance when valid, otherwise retain `preferred_combat_distance`. Add
`combat_approach_speed_multiplier = 1.2`. In hold, request an attack only when ready.
During `COMBAT_ATTACK`, clear regular movement and keep target facing.

- [ ] **Step 4: Connect AllyBase2**

Pass `get_combat_system()` into the state machine. Do not move attack logic into AllyBase2.

- [ ] **Step 5: Equip Amy**

Override only:

```text
CombatSystem.starting_weapon = res://Item/Weapon/Sword/IronSwordData.tres
```

- [ ] **Step 6: Write and run the integration test**

Verify Amy:

- equips IronSword;
- approaches to `1.0m ± 0.1m`;
- enters COMBAT_ATTACK when GCD is ready;
- remains unable to request another attack during GCD;
- returns to approach/hold after animation;
- cancels attack and enters RETURN when target becomes invalid.

- [ ] **Step 7: Verify GREEN**

Run behavior, targeting, root-rename, melee integration, AI combat, player Hitbox and locomotion tests.

---

### Task 7: Final verification and documentation

**Files:**
- Modify: `Docs/CurrentImplementationSummary.md`
- Modify: this implementation plan checkbox state

**Interfaces:**
- Consumes: all completed tasks
- Produces: current implementation record and verification evidence

- [ ] **Step 1: Run all UnitSystem tests**

Execute every `UnitSystem/Tests/*.gd` SceneTree test with Godot 4.7. Expected: exit code 0 for every test.

- [ ] **Step 2: Run editor scan**

```powershell
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' --headless --editor --path 'G:\Godot\SipSip' --quit
```

Expected: no script error or warning.

- [ ] **Step 3: Confirm protected files**

Verify `Scenes/TestScene.tscn` was not modified and old AI attack module paths still exist.

- [ ] **Step 4: Update documentation**

Record the new AI melee architecture, Amy example, GCD, shared Hitbox and deferred damage scope in `Docs/CurrentImplementationSummary.md`.
