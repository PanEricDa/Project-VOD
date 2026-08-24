# 最小伤害—生命—死亡闭环 Implementation Plan

> ⚠ 本文档历史上曾发生编码损坏（UTF-8 被误存为 GBK）。2026-08-24 已程序化恢复并人工校订；个别丢失的虚词/标点按上下文与同系列文档惯例补回，如与设计规格文档有出入，以规格文档为准。

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在现有玩家、AI 普攻 SkillSystem 命中链路上加入统一数值结算和可靠死亡状态，形成可测试的最小战斗闭环
**Architecture:** `UnitBase` 保存生命和最小战斗属性，`WeaponData` 与技能 Effect 只保存各自的攻击参数，静态 `CombatValueResolver` 统一计算伤害和治疗。现有 Hitbox、Projectile 与 Skill Delivery 继续负责命中确认，玩家与 AI 控制器只在既有命中出口调用结算器，不创建第二套检验或去重系统。
**Tech Stack:** Godot Engine 4.7、GDScript、CharacterBody3D、AnimationPlayer、ShapeCast3D、PackedScene、`.tres/.res`、Godot headless 测试
## Global Constraints

- 所有实现必须符合 Godot 4.7。
- 所有字段和方法使用英文标识；新增生产代码提供简体中文职责注释。
- 不得向 `res://Scenes/TestScene.tscn` 或 `res://Scenes/TestScene2.tscn` 添加、删除或修改任何单位实例。
- 不改变现有索敌、Hitbox、投射物飞行、技能目标选择、动画、卡刀和屏幕震动算法。
- 正式 `.tres/.res` 必须通过 Godot API、Godot MCP Resource 工具或 `ResourceSaver` 保存，并验证有效 UID；强类型 Resource 必须能被 Inspector Quick Load 检索。
- 项目当前不是 Git 仓库；每个任务用测试结果和文件检查作为验收检查点，不执行 Git 提交。
- 设计规格：`res://Docs/Superpowers/Specs/2026-07-31-minimum-combat-damage-loop-design.md`。
---

## File Map

### 新建

- `UnitSystem/Combat/CombatValueResolver.gd`：纯静态伤害与治疗公式
- `UnitSystem/Tests/CombatValueResolverTest.gd`：公式和边界测试
- `UnitSystem/Tests/BasicAttackDamageIntegrationTest.gd`：玩家与 AI 普攻命中接线测试
- `UnitSystem/Tests/UnitDeathLifecycleTest.gd`：目标资格、行动取消和复活测试
### 修改

- `UnitSystem/Base/00_UnitBase.gd`：攻击力、防御、只读接口和死亡目标过滤。
- `Item/Weapon/WeaponData.gd`：普通攻击基础伤害、攻击力倍率和连击倍率。
- `Item/Weapon/Sword/IronSwordData.tres`：第一版三段倍率。
- `UnitSystem/Components/Combat/PlayerAttackController.gd`：在玩家命中出口结算伤害。
- `UnitSystem/Components/Combat/AI/AICombatSystem.gd`：在 AI 通用命中出口结算伤害。
- `SkillSystem/03-Extensions/HealthChangeSkillEffect.gd`：技能伤害与治疗复用统一结算。
- `SkillSystem/00-Skills/Firebolt/FireboltSkill.tscn`：装配首个正式伤害 Effect。
- `SkillSystem/00-Skills/HolyLight/HolyLightSkill.tscn`：把旧 `amount` 字段迁移为 `base_amount`。
- `UnitSystem/Player/PlayerBase.gd`：死亡时收束玩家移动、冲刺、攻击、技能和锁定。
- `UnitSystem/Base/AIUnitBase.gd`：死亡时收束 AI 移动、攻击、技能和锁定。
- `SkillSystem/01-Core/SkillHostComponent.gd`：拒绝死亡施法者的新技能请求。
- 当前失效测试：迁移已删除的 Amy 夹具，修正视觉装配与反馈默认值断言。
- `Docs/CurrentSystemUserGuide.md`：补充战斗属性、武器伤害和死亡规则。
- `Docs/CurrentProgressReport.md`：记录第一版真实战斗闭环。
---

### Task 1: 恢复现行框架测试基线

**Files:**

- Modify: `UnitSystem/Tests/AIAttackControllerTest.gd`
- Modify: `UnitSystem/Tests/AICombatSystemTest.gd`
- Modify: `UnitSystem/Tests/AllyBehaviorStateMachineTest.gd`
- Modify: `UnitSystem/Tests/AllyInheritedRootRenameTest.gd`
- Modify: `UnitSystem/Tests/AllyMeleeCombatIntegrationTest.gd`
- Modify: `UnitSystem/Tests/UnitDirectoryLayoutTest.gd`

**Interfaces:**

- Consumes: 当前 `AIUnitBase`、`Saber.tscn`、`AllyVisual.tscn` 和 `DefaultAIHitFeedback.tres`
- Produces: 不再引用已删除的 Amy 场景、能够独立退出的现行测试基线
- [ ] **Step 1: 把 Amy 场景夹具迁移到 Saber**

在三个测试中统一使用
```gdscript
const ALLY_SCENE_PATH: String = \
	"res://UnitSystem/AI/Ally/Units/Saber.tscn"
const ALLY_FORMATION_POSITION_PATH: String = (
	"res://UnitSystem/AI/Ally/Formation/Positions/AttackingMid.tres"
)
```

同步把局部变量和断言文本中的 `amy` 改为 `ally` 或 `saber`。`AllyInheritedRootRenameTest.gd` 应断言继承根节点名为 `Saber`，而不是继续验证不存在的单位。
- [ ] **Step 2: 修正独立 AIAttackController 的视觉夹具**

`AIAttackControllerTest.gd` 使用 `AIUnitBase.tscn` 作为无具体职业的 owner，只挂载一个 `AllyVisual.tscn`，避免测试依赖已有 Visual 的 AllyBase

```gdscript
const AI_UNIT_SCENE_PATH := "res://UnitSystem/Base/AIUnitBase.tscn"

var owner := (
	load(AI_UNIT_SCENE_PATH) as PackedScene
).instantiate() as AIUnitBase
var runtime_visual := (
	load("res://UnitSystem/Visuals/Ally/AllyVisual.tscn")
	as PackedScene
).instantiate() as Node3D
runtime_visual.name = "RuntimeAllyVisual"
owner.get_node(^"Visual").add_child(runtime_visual)
```

保留“Visual 中存在无关装饰节点仍能解析正式视觉端点”的测试，但装饰节点必须放在正式视觉之后，且只能存在一个提供 `CharacterRoot/WeaponSocket` 的候选
- [ ] **Step 3: 修正 AICombatSystem 测试配置**

在 `AICombatSystemTest.gd` 的 owner 下加入一个 `AllyVisual.tscn` 后再配置 CombatSystem，并把命中停顿预显断言改为正式资源当前值：

```gdscript
_expect(
	is_equal_approx(feedback_profile.hit_stop_duration, 0.06),
	"AI hit stop uses the configured 0.06-second default"
)
```

测试不得修改 `DefaultAIHitFeedback.tres`。
- [ ] **Step 4: 更新 TestScene2 只读契约**

`UnitDirectoryLayoutTest.gd` 只更新当前场景节点断言为：

```gdscript
[
	"Hero",
	"EnemyBase2",
	"Caster",
	"Priest",
	"Archer",
	"Guardian",
]
```

只读`TestScene2.tscn`，不保存或改写场景
- [ ] **Step 5: 分别运行修复后的测试**

Run:

```powershell
$godot = 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe'
& $godot --headless --path 'G:\Godot\SipSip' --script 'res://UnitSystem/Tests/AIAttackControllerTest.gd'
& $godot --headless --path 'G:\Godot\SipSip' --script 'res://UnitSystem/Tests/AICombatSystemTest.gd'
& $godot --headless --path 'G:\Godot\SipSip' --script 'res://UnitSystem/Tests/AllyBehaviorStateMachineTest.gd'
& $godot --headless --path 'G:\Godot\SipSip' --script 'res://UnitSystem/Tests/AllyInheritedRootRenameTest.gd'
& $godot --headless --path 'G:\Godot\SipSip' --script 'res://UnitSystem/Tests/AllyMeleeCombatIntegrationTest.gd'
& $godot --headless --path 'G:\Godot\SipSip' --script 'res://UnitSystem/Tests/UnitDirectoryLayoutTest.gd'
```

Expected: 六个测试均输出 `PASS` 并以退出码 `0` 结束；没有缺少 `Amy.tscn`、重复视觉或配置失败错误
---

### Task 2: 建立 UnitBase 战斗属性与统一结算
**Files:**

- Create: `UnitSystem/Combat/CombatValueResolver.gd`
- Create: `UnitSystem/Tests/CombatValueResolverTest.gd`
- Modify: `UnitSystem/Base/00_UnitBase.gd`
- Modify: `UnitSystem/Tests/UnitRootConfigurationTest.gd`

**Interfaces:**

- Consumes: `UnitBase.apply_damage()`、`UnitBase.apply_healing()`
- Produces:
  - `UnitBase.get_attack_power() -> float`
  - `UnitBase.get_defense() -> float`
  - `CombatValueResolver.calculate_damage(...) -> float`
  - `CombatValueResolver.apply_damage(...) -> float`
  - `CombatValueResolver.calculate_healing(...) -> float`
  - `CombatValueResolver.apply_healing(...) -> float`

- [ ] **Step 1: 编写结算器失败测试**

`CombatValueResolverTest.gd` 使用运行时构造的 `UnitBase.new()`，覆盖以下精确结果：

```gdscript
source.attack_power = 20.0
target.defense = 100.0
_expect_equal(
	CombatValueResolver.calculate_damage(
		source, target, 10.0, 1.0, 1.5
	),
	22.5,
	"damage applies power, defense and multiplier"
)
_expect_equal(
	CombatValueResolver.calculate_healing(source, 5.0, 0.5, 2.0),
	30.0,
	"healing ignores target defense"
)
```

还必须测试：

- 负基础值、负倍率归零
- `source == null` 时只使用基础值
- `target == null` 时 `apply_damage()` 返回 `0.0`
- 过量伤害和治疗返回实际扣除/恢复量
- [ ] **Step 2: 运行测试确认失败**

Run:

```powershell
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' `
  --headless --path 'G:\Godot\SipSip' `
  --script 'res://UnitSystem/Tests/CombatValueResolverTest.gd'
```

Expected: FAIL，原因是 `CombatValueResolver`、`attack_power` 和 `defense` 尚不存在
- [ ] **Step 3: 向 UnitBase 增加最小战斗属性**

增加
```gdscript
@export_category("Combat Stats")
@export_range(0.0, 1000000.0, 0.1, "or_greater")
var attack_power: float = 10.0

@export_range(0.0, 1000000.0, 0.1, "or_greater")
var defense: float = 0.0


func get_attack_power() -> float:
	return maxf(attack_power, 0.0)


func get_defense() -> float:
	return maxf(defense, 0.0)
```

同时把目标资格收紧为
```gdscript
func is_targetable() -> bool:
	return targetable and not is_dead()
```

- [ ] **Step 4: 实现静态结算器**

核心计算必须等价于：

```gdscript
class_name CombatValueResolver
extends RefCounted


static func calculate_damage(
	source: UnitBase,
	target: UnitBase,
	base_damage: float,
	power_ratio: float = 1.0,
	multiplier: float = 1.0
) -> float:
	if not is_instance_valid(target) or target.is_dead():
		return 0.0
	var source_power := source.get_attack_power() if is_instance_valid(source) else 0.0
	var raw_value := maxf(base_damage, 0.0) + source_power * maxf(power_ratio, 0.0)
	var defense_multiplier := 100.0 / (100.0 + target.get_defense())
	return raw_value * defense_multiplier * maxf(multiplier, 0.0)
```

`apply_damage()` 必须调用 `target.apply_damage(calculated_value, source)`；治疗使用相同边界规则但不读取目标防御
- [ ] **Step 5: 更新 UnitBase Inspector 契约测试**

在 `UnitRootConfigurationTest.gd` 中验证新字段和 getter 存在，并验证死亡单位：
```gdscript
unit.apply_damage(unit.get_current_health())
_assert_true(unit.is_dead(), "fatal damage marks the unit dead")
_assert_true(not unit.is_targetable(), "dead units are not targetable")
```

- [ ] **Step 6: 运行结算器和 UnitBase 测试**

Run:

```powershell
& $godot --headless --path 'G:\Godot\SipSip' --script 'res://UnitSystem/Tests/CombatValueResolverTest.gd'
& $godot --headless --path 'G:\Godot\SipSip' --script 'res://UnitSystem/Tests/UnitRootConfigurationTest.gd'
```

Expected: PASS?
---

### Task 3: 扩充 WeaponData 普攻参数并正式保存铁剑资源
**Files:**

- Modify: `Item/Weapon/WeaponData.gd`
- Modify through ResourceSaver: `Item/Weapon/Sword/IronSwordData.tres`
- Modify: `UnitSystem/Tests/WeaponDataInheritanceTest.gd`

**Interfaces:**

- Consumes: 现有 `WeaponData` 继承关系
- Produces:
  - `basic_attack_base_damage: float`
  - `basic_attack_power_ratio: float`
  - `combo_damage_multipliers: Array[float]`
  - `get_combo_damage_multiplier(attack_index: int) -> float`

- [ ] **Step 1: 添加失败断言**

在 `WeaponDataInheritanceTest.gd` 中验证：

```gdscript
_expect(is_equal_approx(sword.basic_attack_base_damage, 5.0), "Sword stores base damage")
_expect(is_equal_approx(sword.basic_attack_power_ratio, 1.0), "Sword stores power ratio")
_expect(
	is_equal_approx(sword.get_combo_damage_multiplier(1), 0.9)
	and is_equal_approx(sword.get_combo_damage_multiplier(2), 1.0)
	and is_equal_approx(sword.get_combo_damage_multiplier(3), 1.25),
	"Sword stores three combo damage multipliers"
)
_expect(
	is_equal_approx(sword.get_combo_damage_multiplier(99), 1.0),
	"missing combo data safely falls back to one"
)
```

- [ ] **Step 2: 运行测试确认失败**

Run:

```powershell
& $godot --headless --path 'G:\Godot\SipSip' --script 'res://UnitSystem/Tests/WeaponDataInheritanceTest.gd'
```

Expected: FAIL，缺少新字段和方法
- [ ] **Step 3: 实现 WeaponData 字段和倍率读取**

```gdscript
@export_category("Basic Attack")
@export_range(0.0, 1000000.0, 0.1, "or_greater")
var basic_attack_base_damage: float = 5.0
@export_range(0.0, 100.0, 0.05, "or_greater")
var basic_attack_power_ratio: float = 1.0
@export var combo_damage_multipliers: Array[float] = []


func get_combo_damage_multiplier(attack_index: int) -> float:
	var array_index := attack_index - 1
	if array_index < 0 or array_index >= combo_damage_multipliers.size():
		return 1.0
	return maxf(combo_damage_multipliers[array_index], 0.0)
```

- [ ] **Step 4: 使用 ResourceSaver 正式保存 IronSwordData**

通过 Godot MCP 编辑器脚本执行：

```gdscript
var path := "res://Item/Weapon/Sword/IronSwordData.tres"
var sword := load(path) as MeleeWeaponData
sword.basic_attack_base_damage = 5.0
sword.basic_attack_power_ratio = 1.0
sword.combo_damage_multipliers = [0.9, 1.0, 1.25]
var save_error := ResourceSaver.save(sword, path)
_mcp_print(str(save_error))
```

不得用纯文本写入代替 `ResourceSaver.save()`。
- [ ] **Step 5: 验证 UID、类型和测试**

在测试中追加
```gdscript
_expect(
	ResourceLoader.get_resource_uid(SWORD_PATH) != ResourceUID.INVALID_ID,
	"Iron Sword keeps an editor-indexed UID"
)
```

Run:

```powershell
& $godot --headless --path 'G:\Godot\SipSip' --script 'res://UnitSystem/Tests/WeaponDataInheritanceTest.gd'
& $godot --headless --path 'G:\Godot\SipSip' --script 'res://UnitSystem/Tests/ResourceUidAuditTest.gd'
```

Expected: PASS；IronSwordData 仍加载为 `MeleeWeaponData`，并能在强类型 WeaponData 字段的 Quick Load 中检索
---

### Task 4: 接通玩家与 AI 普通攻击伤害
**Files:**

- Create: `UnitSystem/Tests/BasicAttackDamageIntegrationTest.gd`
- Modify: `UnitSystem/Components/Combat/PlayerAttackController.gd`
- Modify: `UnitSystem/Components/Combat/AI/AICombatSystem.gd`

**Interfaces:**

- Consumes:
  - `CombatValueResolver.apply_damage(...)`
  - `WeaponData.get_combo_damage_multiplier(...)`
  - 玩家与 AI 现有 `attack_hit` 信号
- Produces: 所有普通攻击在现有命中出口结算一次实际伤害
- [ ] **Step 1: 编写玩家 AI 失败集成测试**

测试使用 100 HP 零防御目标，来源攻击力 10，铁剑第一段预期：

```text
(5 + 10 × 1) × 0.9 = 13.5
```

玩家部分
```gdscript
var hero := (load(HERO_PATH) as PackedScene).instantiate() as PlayerBase
var controller := hero.get_node(^"AttackController") as PlayerAttackController
var before := enemy.get_current_health()
controller.call(
	"_on_melee_hitbox_attack_hit",
	enemy,
	enemy.global_position,
	Vector3.FORWARD,
	1
)
_expect_equal(before - enemy.get_current_health(), 13.5, "player hit applies sword damage")
```

AI 部分
```gdscript
var combat := saber.get_combat_system()
var before := enemy.get_current_health()
combat.report_attack_hit(enemy, enemy.global_position, Vector3.FORWARD, 1)
_expect_equal(before - enemy.get_current_health(), 13.5, "AI hit uses the same resolver")
```

为两条链路分别连接 `attack_hit`，验证命中信号仍只发送一次
- [ ] **Step 2: 运行集成测试确认失败**

Run:

```powershell
& $godot --headless --path 'G:\Godot\SipSip' --script 'res://UnitSystem/Tests/BasicAttackDamageIntegrationTest.gd'
```

Expected: FAIL，生命值尚未变化
- [ ] **Step 3: 在玩家命中出口结算**

在 `_on_melee_hitbox_attack_hit()` 中先结算、后发送信号：

```gdscript
func _on_melee_hitbox_attack_hit(
	target: UnitBase,
	hit_position: Vector3,
	hit_direction: Vector3,
	combo_index: int
) -> void:
	_apply_basic_attack_damage(target, combo_index)
	attack_hit.emit(target, hit_position, hit_direction, combo_index)
```

辅助方法只读取父节点与当前装备：

```gdscript
func _apply_basic_attack_damage(target: UnitBase, attack_index: int) -> float:
	var source := get_parent() as UnitBase
	if source == null or _equipped_weapon == null:
		return 0.0
	return CombatValueResolver.apply_damage(
		source,
		target,
		_equipped_weapon.basic_attack_base_damage,
		_equipped_weapon.basic_attack_power_ratio,
		_equipped_weapon.get_combo_damage_multiplier(attack_index)
	)
```

- [ ] **Step 4: 在 AI 通用命中出口结算**

`AICombatSystem.report_attack_hit()` 使用 `_owner_body` 与 `get_equipped_weapon()` 执行同样的结算，然后原样发送 `attack_hit``
- [ ] **Step 5: 验证近战、远程与反馈没有重复**

Run:

```powershell
& $godot --headless --path 'G:\Godot\SipSip' --script 'res://UnitSystem/Tests/BasicAttackDamageIntegrationTest.gd'
& $godot --headless --path 'G:\Godot\SipSip' --script 'res://UnitSystem/Tests/AllyMeleeCombatIntegrationTest.gd'
& $godot --headless --path 'G:\Godot\SipSip' --script 'res://UnitSystem/Tests/AICombatSystemTest.gd'
```

Expected: PASS；原 `attack_hit` 次数不变，AI 卡刀仍由既有反馈桥消费
---

### Task 5: 让技能伤害与治疗复用统一结算

**Files:**

- Modify: `SkillSystem/03-Extensions/HealthChangeSkillEffect.gd`
- Modify: `SkillSystem/02-Delivery/SkillDeliveryRunner.gd`
- Modify: `Item/Projectiles/FireballProjectile.gd`
- Modify: `SkillSystem/00-Skills/Firebolt/FireboltSkill.tscn`
- Modify: `SkillSystem/00-Skills/HolyLight/HolyLightSkill.tscn`
- Modify: `SkillSystem/05-Tests/SingleSceneHolyLightTest.gd`
- Modify: `SkillSystem/05-Tests/SingleSceneFireboltTest.gd`
- Modify: `SkillSystem/05-Tests/SingleSceneDeliveryRunnerTest.gd`

**Interfaces:**

- Consumes: `CombatValueResolver.apply_damage()`、`CombatValueResolver.apply_healing()`?- Produces:
  - `base_amount: float`
  - `power_ratio: float`
  -  `SkillEffectBase.apply(...) -> bool`?
- [ ] **Step 1: 先把技能测试改为新字段并加入数值断言**

HolyLight 测试读取
```gdscript
_expect(
	is_equal_approx(float(effects[0].get("base_amount")), 25.0),
	"effect stores 25 base healing"
)
_expect(
	is_zero_approx(float(effects[0].get("power_ratio"))),
	"HolyLight keeps fixed-value healing in the first version"
)
```

Firebolt 测试把内置 `TestUnit` 改为继承 `UnitBase`，使用 `team_id` 表达关系，并给目标设置 `defense = 100.0`。保留现有非零发射点和投射物朝向断言，再等待投射物命中，验证目标生命值只减少一次
- [ ] **Step 2: 运行技能测试确认失*

Run:

```powershell
& $godot --headless --path 'G:\Godot\SipSip' --script 'res://SkillSystem/05-Tests/SingleSceneHolyLightTest.gd'
& $godot --headless --path 'G:\Godot\SipSip' --script 'res://SkillSystem/05-Tests/SingleSceneFireboltTest.gd'
```

Expected: FAIL，旧字段仍为 `amount` 且 DAMAGE 尚未应用防御
- [ ] **Step 3: 修改 HealthChangeSkillEffect**

删除 `amount`，新增：

```gdscript
@export_range(0.0, 999999.0, 0.1, "or_greater")
var base_amount: float = 10.0
@export_range(0.0, 100.0, 0.05, "or_greater")
var power_ratio: float = 0.0
```

`apply()` 必须要求 `context != null` 且目标为 `UnitBase`。HEAL 调用 `CombatValueResolver.apply_healing()`，DAMAGE 调用 `CombatValueResolver.apply_damage()`；只要目标类型和上下文合法，即使满血或最终变化为零也返回 `true`，保持当前技能生命周期不会因满血卡死
- [ ] **Step 4: 为 Firebolt 单场景装配伤害 Effect**

在 `FireboltSkill.tscn` 中增加唯一的直接 Effect 子节点：

```text
FireboltSkill
├── DeliveryRunner
├── RuntimeEffects
└── DamageEffect
```

配置
```text
script = HealthChangeSkillEffect.gd
operation = DAMAGE
base_amount = 10.0
power_ratio = 1.0
```

Fireball 投射物仍只负责飞行、碰撞和返回命中目标；SkillBase 在交付成功后把 `DamageEffect` 应用于结果目标。不得把伤害字段复制到 `FireballProjectile.gd` 或 `TrackingProjectileDeliveryConfig`。
实现时通过通用投射交付契约补齐 Effect 执行：投射物以标准可选信号 `projectile_targets_resolved` 先上报自身判定目标，再发送 `projectile_impacted`；`SkillDeliveryRunner` 保存异步 effects，对 `SkillDeliveryResult.affected_targets` 统一执行。没有目标上报的兼容投射物回退到原目标。不得让具体 Effect 自行监听 SkillBase，也不得在 Runner 中识别 Firebolt 类型
- [ ] **Step 5: 迁移 HolyLight 场景字段**

把 `HolyLightSkill.tscn` 中效果节点的旧字段：
```text
amount = 25.0
```

迁移为：

```text
base_amount = 25.0
power_ratio = 0.0
```

不改变 HolyLight 的目标关系、Delivery 或视觉场景
- [ ] **Step 6: 运行全部 SkillSystem 单场景测试**

Run:

```powershell
& $godot --headless --path 'G:\Godot\SipSip' --script 'res://SkillSystem/05-Tests/SingleSceneHolyLightTest.gd'
& $godot --headless --path 'G:\Godot\SipSip' --script 'res://SkillSystem/05-Tests/SingleSceneFireboltTest.gd'
& $godot --headless --path 'G:\Godot\SipSip' --script 'res://SkillSystem/05-Tests/SingleSceneDeliveryRunnerTest.gd'
& $godot --headless --path 'G:\Godot\SipSip' --script 'res://SkillSystem/05-Tests/SingleSceneSkillHostTest.gd'
```

Expected: PASS；HolyLight 仍治疗友军并跟随目标，Firebolt 的发射点、飞行和爆炸不发生回归
---

### Task 6: 收束死亡单位的行动生命周期
**Files:**

- Create: `UnitSystem/Tests/UnitDeathLifecycleTest.gd`
- Modify: `UnitSystem/Player/PlayerBase.gd`
- Modify: `UnitSystem/Base/AIUnitBase.gd`
- Modify: `UnitSystem/Components/Combat/PlayerAttackController.gd`
- Modify: `UnitSystem/Components/Combat/AI/AICombatSystem.gd`
- Modify: `SkillSystem/01-Core/SkillHostComponent.gd`

**Interfaces:**

- Consumes: `UnitBase.died`、`UnitBase.revived`、现有取消和清锁接口
- Produces: 死亡单位无法移动、攻击、施法或保留锁定；复活后可以接受新行动，但不会恢复旧动作
- [ ] **Step 1: 编写死亡生命周期失败测试**

覆盖
```gdscript
unit.apply_damage(unit.get_current_health(), attacker)
_expect(unit.is_dead(), "fatal damage marks death")
_expect(not unit.is_targetable(), "death removes target eligibility")
_expect(died_count == 1, "death emits once")
unit.apply_damage(10.0, attacker)
_expect(died_count == 1, "repeated damage does not emit death again")
```

玩家测试在攻击、冲刺或锁定存在时造成致命伤害，验证：

```gdscript
not attack_controller.is_attacking()
not player.is_player_dashing()
player.get_locked_target() == null
```

AI 测试在攻击和移动目标存在时致死，验证
```gdscript
not combat.is_attacking()
not ai.has_movement_target()
targeting.get_locked_target() == null
```

随后调用 `revive(25.0)`，验证单位重新可成为目标，但原攻击、技能、冲刺和锁定均没有自动恢复
- [ ] **Step 2: 运行生命周期测试确认失败**

Run:

```powershell
& $godot --headless --path 'G:\Godot\SipSip' --script 'res://UnitSystem/Tests/UnitDeathLifecycleTest.gd'
```

Expected: FAIL，因为 PlayerBase/AIUnitBase 尚未收束行动
- [ ] **Step 3: 玩家死亡收束**

`PlayerBase._ready()` 连接自身 `died` 与 `revived`。死亡回调必须：

```gdscript
cancel_attack_motion()
_dash_remaining_distance = 0.0
_dash_direction = Vector3.ZERO
_regular_horizontal_velocity = Vector2.ZERO
velocity.x = 0.0
velocity.z = 0.0
clear_locked_target()
```

并调用：

```gdscript
AttackController.cancel_combo()
SkillHost.cancel_active_skill(&"owner_died")
```

`_physics_process()` 在 `is_dead()` 时忽略 InputMap，只保留重力和 `move_and_slide()`，避免尸体悬空或穿透地面
- [ ] **Step 4: AI 死亡收束**

`AIUnitBase` 死亡回调必须
```gdscript
clear_movement_target()
cancel_attack_motion()
_reset_motion_runtime_state()
velocity.x = 0.0
velocity.z = 0.0
```

并安全调用可选组件：

```gdscript
CombatSystem.cancel_current_action()
SkillHost.cancel_active_skill(&"owner_died")
AITargetingComponent.clear_locked_target()
```

`_physics_process()` 在死亡时不得调用 `_update_ai_movement()`，只执行水平停止、重力和碰撞移动。这使得 Ally 状态机、Enemy 行为和未来 AI 子类不需要各写一套死亡判断
- [ ] **Step 5: 在动作入口拒绝死 owner**

玩家 `request_attack()`、AI `can_request_basic_attack()` 与 SkillHost 的技能请求资格检查都加入
```gdscript
if owner is UnitBase and (owner as UnitBase).is_dead():
	return false
```

玩家 `request_attack()` 当前返回 `void`，保持签名不变并直接 `return`。不得用死亡回调永久改写用户配置的技能开关
- [ ] **Step 6: 复活只恢复资格**

复活回调只清理残余速度和通知属性调试刷新，不重新请求攻击、技能、锁定或移动目标。`UnitBase.is_targetable()` 会因生命恢复自动重新返回 Inspector 中配置的 `targetable`。
- [ ] **Step 7: 运行死亡及既有行为测*

Run:

```powershell
& $godot --headless --path 'G:\Godot\SipSip' --script 'res://UnitSystem/Tests/UnitDeathLifecycleTest.gd'
& $godot --headless --path 'G:\Godot\SipSip' --script 'res://UnitSystem/Tests/PlayerDashComboContinuityTest.gd'
& $godot --headless --path 'G:\Godot\SipSip' --script 'res://UnitSystem/Tests/RepeatedSkillCastingLifecycleTest.gd'
& $godot --headless --path 'G:\Godot\SipSip' --script 'res://UnitSystem/Tests/AllyBehaviorStateMachineTest.gd'
```

Expected: PASS；存活单位原行为完全保持，死亡后没有新行动
---

### Task 7: 文档、资源审计和最终验证
**Files:**

- Modify: `Docs/CurrentSystemUserGuide.md`
- Modify: `Docs/CurrentProgressReport.md`

**Interfaces:**

- Consumes: 前六个任务完成后的最终接口- Produces: 面向设计师的配置说明和可复查的交付记录
- [ ] **Step 1: 更新使用指南**

在“配置阵营与生命”后增加“配置基础战斗数值”：

```text
Attack Power：单位所有普通攻击、伤害技能和治疗技能可读取的基础强度
Defense：只参与伤害减免，不减少治疗```

在 WeaponData 章节增加：
```text
Basic Attack Base Damage
Basic Attack Power Ratio
Combo Damage Multipliers
```

说明连击数组第 0 项对应 `basic_attack_1`，缺项时回退 `1.0`。
- [ ] **Step 2: 更新进度报告**

记录
- 玩家与 AI 普攻已造成真实伤害
- 近战和远程共用 AI 通用命中出口
- 技能伤害与治疗复用统一数值公式
- 死亡单位停止行动且不再可选中- 暴击、Buff、护盾、威胁、掉落和关卡失败仍未实现
- [ ] **Step 3: 运行资源 UID 审计**

Run:

```powershell
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' `
  --headless --path 'G:\Godot\SipSip' `
  --script 'res://UnitSystem/Tests/ResourceUidAuditTest.gd'
```

Expected: PASS；所有活动 `.tres` 都具有有效 UID。
- [ ] **Step 4: 运行重点回归测试**

Run:

```powershell
$godot = 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe'
& $godot --headless --path 'G:\Godot\SipSip' --script 'res://UnitSystem/Tests/CombatValueResolverTest.gd'
& $godot --headless --path 'G:\Godot\SipSip' --script 'res://UnitSystem/Tests/BasicAttackDamageIntegrationTest.gd'
& $godot --headless --path 'G:\Godot\SipSip' --script 'res://UnitSystem/Tests/UnitDeathLifecycleTest.gd'
& $godot --headless --path 'G:\Godot\SipSip' --script 'res://SkillSystem/05-Tests/SingleSceneHolyLightTest.gd'
& $godot --headless --path 'G:\Godot\SipSip' --script 'res://SkillSystem/05-Tests/SingleSceneFireboltTest.gd'
& $godot --headless --path 'G:\Godot\SipSip' --script 'res://UnitSystem/Tests/AllyMeleeCombatIntegrationTest.gd'
```

Expected: 全部 PASS。
- [ ] **Step 5: 执行 Godot 4.7 编辑器扫描和主场景无窗口启动**

Run:

```powershell
& $godot --headless --path 'G:\Godot\SipSip' --editor --quit
& $godot --headless --path 'G:\Godot\SipSip' --quit-after 120
```

Expected:

- 两条命令退出码 `0`。
- 无脚本解析错误、资源缺失、无 UID 或节点配置错误。
- 不保存、不增删 TestScene2 中的任何单位实例。
- [ ] **Step 6: 使用 Godot MCP 检查编辑器**

刷新项目后检查：

- Editor error count 为 `0`。
- Output 没有新增 error 或 warning。
- `IronSwordData.tres` 的 UID 有效。
- `IronSwordData.tres` 能按类型被 Quick Load 检索。
- [ ] **Step 7: 记录最终验证结果**

把实际执行日期、Godot 版本、通过的重点测试、编辑器扫描与 MCP 错误数追加到 `Docs/CurrentProgressReport.md`。若任何测试失败，不得把阶段标记为完成。
