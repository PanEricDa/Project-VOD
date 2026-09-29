# Guardian 范围仇恨技能 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在现有单场景技能体系中实现 Guardian 以自身为圆心、半径 5 米、向范围内每个敌人直接增加固定仇恨值的长冷却自动技能。

**Architecture:** 不新增 SkillTemplate，也不新增第四种 Delivery 类型。扩展 `InstantTargetDeliveryConfig`，让既有瞬发交付支持“单一已解析目标”和“施法者中心范围目标”两种目标收集模式；新增一个只提交固定 `SKILL_BONUS` 的 `ThreatChangeSkillEffect`，最后由继承 `RangedSkillTemplate` 的 `GuardianTauntSkill.tscn` 组合两者。

**Tech Stack:** Godot 4.7、GDScript、SceneTree headless tests、AnimationLibrary、现有 SkillSystem 与 EnemyThreatComponent。

**Spec:** 本文件的“设计规范”章节即本计划实现的完整规格；设计与实施步骤保存在同一文档中。

## Global Constraints

- 技能俗称“嘲讽”，但系统语义仅为固定数值的范围仇恨注入；不得增加强制目标、嘲讽状态、持续接管、权级或特殊衰减。
- 每个命中敌人的最终增量严格等于 `threat_amount`；不得读取当前最高仇恨、自动补足接管线或使用技能根节点的伤害仇恨倍率二次放大。
- 新仇恨必须通过 `ThreatEvent.Kind.SKILL_BONUS` 和 `EnemyThreatComponent.submit_threat()` 进入原有仇恨池，并遵循原有接管比例与默认衰减。
- 范围中心固定为 Guardian 自身的世界坐标；第一版水平半径为 `5.0` 米。
- `GuardianTauntSkill` 继承 `RangedSkillTemplate`；不得创建新的 SkillTemplate。
- `GuardianTauntSkill` 是独立技能；不得替换或改变现有 `GuardianShieldSkill` 的行为。
- `InstantTargetDeliveryConfig` 的默认模式必须保持单体交付，确保 HolyLight、Guardian Shield Bash 等现有技能零配置兼容。
- Delivery 只负责收集效果目标并逐个调用 Effect；固定仇恨数值只能由 `ThreatChangeSkillEffect` 保存和结算。
- 默认验证参数为：效果半径 `5.0` 米、触发施法距离 `0.8` 米、固定仇恨 `200.0`、技能冷却 `15.0` 秒、基础施法时间 `0.2` 秒、AI 优先级 `80`。
- 所有新增 `@export` 字段必须紧邻简体中文说明，写明用途、单位或取值、默认行为和影响范围。
- 所有新增公开方法及其参数必须在声明附近提供简体中文职责与约束说明。
- 不得向 `res://Scenes/TestScene.tscn` 自动添加、删除或修改任何单位实例。
- 对 `ShieldAnimationLibrary.res` 的正式修改必须通过 Godot 编辑器 API 或 `ResourceSaver` 保存；交付前验证其 UID 有效且资源仍能加载为 `AnimationLibrary`。
- 本计划不创建新的外部 `.tres` Delivery 预设；Guardian 技能的 Delivery 使用技能场景内嵌 Resource。
- 保留工作区中与本功能无关的既有修改，不得覆盖或整理它们。

---

## 设计规范

### 1. 技能行为定义

Guardian 范围仇恨技能按以下顺序运行：

1. AI 从现有感知候选中选择一个敌方单位作为技能触发目标。
2. 触发目标必须进入 Guardian 现有的 0.8 米近战施法距离；现有 SkillBase 继续负责范围外排队与接近。
3. 动作动画到达唯一的 `release_action` 标记时，以 Guardian 世界坐标为圆心收集候选目标。
4. 对水平距离不超过 5 米、存活、可选取且与 Guardian 敌对的每个单位调用 `ThreatChangeSkillEffect`。
5. 每个目标的仇恨组件收到一条来源为 Guardian、基础量为 200、倍率为 1 的 `SKILL_BONUS` 事件。
6. 技能不保证敌人切换目标；是否切换完全由现有仇恨值、当前目标保持和挑战者接管倍率决定。
7. 成功交付后进入 15 秒技能冷却；该技能的 AI 释放后随机犹豫配置设为 0，避免把随机等待混入本次冷却验证。

技能触发目标与效果目标是两个概念：

```text
触发目标：使 AI 确认至少有一个敌人进入 Guardian 的近战接触距离
范围中心：Guardian
效果目标：Guardian 周围 5 米内全部有效敌方单位
```

这里必须区分 `cast_range` 与 `effect_radius`。现有 SkillHost 会把最高 AI 优先级自动技能的 `cast_range` 当作单位战术站位距离；若把本技能的 `cast_range` 设为 5 米，Guardian 会长期在 5 米外保持站位。因而本技能沿用 Guardian Shield Bash 的 `0.8` 米触发距离，只把 Delivery 的 `effect_radius` 设为 5 米。

### 2. 文件与职责映射

**修改文件：**

- `SkillSystem/02-Delivery/InstantTargetDeliveryConfig.gd`
  - 新增目标收集模式、范围半径和范围目标关系配置。
  - 默认值维持原有单体瞬发语义。
- `SkillSystem/02-Delivery/SkillDeliveryRunner.gd`
  - 让 `_execute_instant_target()` 根据配置产生一个或多个效果目标。
  - 继续统一调用既有 `SkillEffectBase.apply()`。
- `SkillSystem/05-Tests/SingleSceneDeliveryRunnerTest.gd`
  - 覆盖单体回归、施法者范围筛选、边界和空范围失败。
- `Item/Weapon/Shield/ShieldAnimationLibrary.res`
  - 通过 Godot API 增加无 Hitbox 的 `basic_cast_1` 通用施法动画。
- `UnitSystem/Tests/ShieldAnimationLibraryTest.gd`
  - 验证新动画及方法轨道契约。
- `UnitSystem/AI/Ally/Units/Guardian.tscn`
  - 将新技能实例装配到既有 `SkillHost/SkillSocket`，保留 Shield Bash。
- `SkillSystem/04-Docs/SkillSystemUserGuide.md`
  - 说明 Instant Delivery 的单体/施法者范围模式及范围仇恨组合方式。

**新增文件：**

- `SkillSystem/03-Extensions/ThreatChangeSkillEffect.gd`
  - 对 Delivery 交付的单个敌方目标提交精确固定值的 `SKILL_BONUS`。
- `SkillSystem/05-Tests/ThreatChangeSkillEffectTest.gd`
  - 隔离验证固定值、累加、无效目标与敌我校验。
- `SkillSystem/00-Skills/GuardianTaunt/GuardianTauntSkill.tscn`
  - 单场景技能配置；内嵌扩展后的 Instant Delivery，并挂载仇恨 Effect。
- `SkillSystem/05-Tests/GuardianTauntSkillTest.gd`
  - 验证技能继承、参数、组件组合和精确范围交付。
- `UnitSystem/Tests/GuardianTauntIntegrationTest.gd`
  - 验证 Guardian 装配、动画释放、仇恨累加、目标接管与衰减链路。

### 3. Instant Delivery 扩展接口

`InstantTargetDeliveryConfig` 新增如下枚举与字段：

```gdscript
enum TargetCollectionMode {
	SINGLE,
	CASTER_RADIUS,
}

## 瞬发交付的效果目标收集方式。
## SINGLE 维持原有行为，只对 SkillContext.resolved_target 交付；CASTER_RADIUS 以施法者为圆心筛选候选快照。
## 默认 SINGLE，影响所有使用本配置实例的瞬发技能，不改变技能自身的触发目标解析。
@export var target_collection_mode: TargetCollectionMode = TargetCollectionMode.SINGLE

## CASTER_RADIUS 模式下的水平作用半径，单位为米；必须为有限且大于 0 的数值。
## 默认 5.0；SINGLE 模式忽略本字段，只影响瞬发交付的效果目标集合。
@export_range(0.0, 100.0, 0.1, "or_greater")
var effect_radius: float = 5.0

## CASTER_RADIUS 模式允许接收效果的单位关系复选集合；默认 HOSTILE，只影响范围目标过滤。
## SINGLE 模式继续使用 SkillBase 已解析目标并忽略本字段，避免改变现有单体技能契约。
@export_flags("Self", "Friendly", "Hostile", "Neutral")
var affected_relations: int = TargetResolver.TargetRelationFlag.HOSTILE
```

`validate_configuration()` 契约：

- `SINGLE` 始终保持当前空警告行为。
- `CASTER_RADIUS` 要求 `effect_radius` 有限且大于 0。
- `CASTER_RADIUS` 要求 `affected_relations != 0`。
- 不在 Resource 中缓存运行时目标或节点引用。

### 4. 范围目标收集契约

`SkillDeliveryRunner` 将现有私有入口调整为：

```gdscript
func _execute_instant_target(
	config: InstantTargetDeliveryConfig,
	context: SkillContext,
	launch_transform: Transform3D,
	effects: Array[SkillEffectBase]
) -> bool
```

新增私有辅助方法：

```gdscript
func _collect_instant_effect_targets(
	config: InstantTargetDeliveryConfig,
	context: SkillContext
) -> Array[Node3D]
```

收集规则：

- `SINGLE` 返回仅含有效 `context.resolved_target` 的数组。
- `CASTER_RADIUS` 从 `context.candidate_targets` 的请求快照筛选，不重新扫描场景树。
- 若触发目标有效但调用方候选快照意外遗漏它，应将 `context.resolved_target` 合并到本次临时候选集合。
- 使用 `TargetResolver.is_candidate_valid()` 统一验证关系、存活和可选取状态。
- 距离只计算 XZ 平面：将 `candidate.global_position - caster.global_position` 的 `y` 设为 0。
- 接受 `distance <= effect_radius + 0.05`，与 SkillBase 既有施法距离容差一致。
- 按实例 ID 去重；不修改 `context.candidate_targets` 原数组。
- 没有有效效果目标时，`execute()` 返回 `false`，不发出成功交付信号。
- 每个目标的全部 Effect 均成功后，仅向 `result.affected_targets` 追加一次该目标。
- 任一 Effect 返回 `false` 时沿用现有 fail-fast 契约；不为此前已应用的 Effect 实现回滚系统。

### 5. 固定仇恨 Effect 接口

`ThreatChangeSkillEffect.gd` 的正式接口为：

```gdscript
class_name ThreatChangeSkillEffect
extends "res://SkillSystem/03-Extensions/SkillEffectBase.gd"

## 向每个 Delivery 目标的现有仇恨池增加的固定仇恨点数。
## 单位为基础仇恨点；默认 200.0，必须为有限且大于 0 的数值。
## 本值不读取当前最高仇恨，也不受 SkillBase.threat_multiplier 影响，只影响本 Effect 的 SKILL_BONUS 事件。
@export_range(0.0, 999999.0, 0.1, "or_greater")
var threat_amount: float = 200.0

## 向一个有效敌方 UnitBase 提交固定 SKILL_BONUS 仇恨。
## context.caster 必须是存活的 UnitBase；target 必须暴露有效仇恨组件。
## 返回值直接反映 EnemyThreatComponent.submit_threat() 是否接受事件。
func apply(
	context: SkillContext,
	_result: SkillDeliveryResult,
	target: Node3D
) -> bool
```

事件字段固定为：

```gdscript
event.source = context.caster
event.kind = ThreatEvent.Kind.SKILL_BONUS
event.base_amount = threat_amount
event.threat_multiplier = 1.0
```

Effect 不新增或使用 `ThreatEvent.Kind.TAUNT`。

### 6. GuardianTauntSkill 配置

`GuardianTauntSkill.tscn` 继承：

```text
res://SkillSystem/00-Templates/RangedSkillTemplate.tscn
```

技能根节点配置：

```text
skill_id = guardian_taunt
display_name = Guardian Taunt
ai_priority = 80
target_relations = HOSTILE
target_selection_mode = NEAREST
cast_range = 0.8
base_cast_time = 0.2
can_move_while_casting = false
can_turn_while_casting = true
skill_cooldown = 15.0
threat_multiplier = 1.0
automatic_cast_enabled = true
decision_delay_min = 0.0
decision_delay_max = 0.0
extra_hesitation_chance = 0.0
delivery = 内嵌 InstantTargetDeliveryConfig
```

内嵌 Delivery 配置：

```text
target_collection_mode = CASTER_RADIUS
effect_radius = 5.0
affected_relations = HOSTILE
```

直接子节点：

```text
ThreatEffect: ThreatChangeSkillEffect
threat_amount = 200.0
```

### 7. 动画契约

Guardian 装备的盾牌动画库必须提供 `basic_cast_1`，让 `RangedSkillTemplate` 继续走既有 AI 通用外部动作入口。

第一版动画契约：

```text
动画名：basic_cast_1
建议长度：0.60 秒
release_action：恰好一次，位于 0.20 秒
finish_action：恰好一次，位于 0.60 秒
open_attack_hit_window：零次
close_attack_hit_window：零次
request_attack_motion：零次
```

可以复制现有 `action_skill_1` 的视觉姿势轨道作为起点，但必须移除所有近战 Hitbox 与攻击位移方法键，只保留通用技能交付和完成标记。

### 8. 不在本次实现的内容

- 玩家聚怪技能及玩家技能输入层。
- 玩家嘲讽与 Guardian 仇恨技能之间的协作策略。
- 强制目标、限时嘲讽状态或仇恨权级。
- 根据当前最高仇恨动态计算技能仇恨量。
- 按地图或难度动态缩放半径、仇恨量或冷却。
- 新的技能 HUD、图标、音效或正式视觉特效。
- 对 `TestScene.tscn` 中任何单位实例的自动修改。

---

### Task 1: 扩展 Instant Delivery 的范围目标收集能力

**Files:**
- Modify: `SkillSystem/02-Delivery/InstantTargetDeliveryConfig.gd`
- Modify: `SkillSystem/02-Delivery/SkillDeliveryRunner.gd:35-68,87-109`
- Test: `SkillSystem/05-Tests/SingleSceneDeliveryRunnerTest.gd`

**Interfaces:**
- Consumes: `SkillContext.caster`, `SkillContext.resolved_target`, `SkillContext.candidate_targets`, `TargetResolver.is_candidate_valid()`。
- Produces: `InstantTargetDeliveryConfig.TargetCollectionMode`、`target_collection_mode`、`effect_radius`、`affected_relations`；范围瞬发将每个有效目标传给现有 `SkillEffectBase.apply()`。

- [ ] **Step 1: 为 InstantTargetDeliveryConfig 编写失败测试**

在 `SingleSceneDeliveryRunnerTest.gd` 中增加配置验证与范围交付用例。构造 caster、两个 5 米内敌人、一个 5 米外敌人、一个范围内友方，并把四者放入 `context.candidate_targets`。核心断言必须包含：

```gdscript
var config := InstantTargetDeliveryConfig.new()
config.target_collection_mode = (
	InstantTargetDeliveryConfig.TargetCollectionMode.CASTER_RADIUS
)
config.effect_radius = 5.0
config.affected_relations = TargetResolver.TargetRelationFlag.HOSTILE

_expect(
	bool(runner.execute(config, context, Transform3D.IDENTITY, effects)),
	"caster-radius instant delivery succeeds with valid hostile targets"
)
_expect(
	effect.targets.size() == 2
	and effect.targets.has(inside_enemy_a)
	and effect.targets.has(inside_enemy_b),
	"caster-radius delivery affects every hostile inside five meters exactly once"
)
_expect(
	not effect.targets.has(outside_enemy)
	and not effect.targets.has(inside_friendly),
	"caster-radius delivery excludes out-of-range and friendly candidates"
)
```

另加以下边界断言：

```gdscript
_expect(
	effect.targets.has(enemy_at_exact_boundary),
	"caster-radius delivery includes a hostile at the configured boundary"
)
_expect(
	not runner.execute(config, empty_context, Transform3D.IDENTITY, effects),
	"caster-radius delivery rejects a request with no valid effect targets"
)
_expect(
	InstantTargetDeliveryConfig.new().validate_configuration().is_empty(),
	"default single-target configuration remains valid"
)
```

- [ ] **Step 2: 运行 Delivery 测试并确认按预期失败**

```powershell
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' --headless --path 'G:\Godot\ProjectVOD' --script 'res://SkillSystem/05-Tests/SingleSceneDeliveryRunnerTest.gd'
```

预期：FAIL，原因是 `TargetCollectionMode` 或新增字段尚不存在；原有单体测试仍能编译到失败点。

- [ ] **Step 3: 在配置 Resource 中实现最小字段与验证**

按照“Instant Delivery 扩展接口”章节增加枚举、三个导出字段和 `validate_configuration()`。每个 `@export` 必须带完整简体中文说明；不得创建新的 `.tres`。

- [ ] **Step 4: 在现有 Runner 中实现范围收集**

将调用改为：

```gdscript
return _execute_instant_target(
	config as InstantTargetDeliveryConfig,
	context,
	launch_transform,
	effects
)
```

新增 `_collect_instant_effect_targets(config, context)`，严格实现设计规范中的快照、关系、水平距离、容差和去重规则。`_execute_instant_target()` 对收集结果逐目标、逐 Effect 交付，并保证 `affected_targets` 每个单位最多出现一次。

- [ ] **Step 5: 运行 Delivery 测试并确认通过**

运行 Step 2 的命令。

预期：`SingleSceneDeliveryRunnerTest: PASS`；原有单体、投射物和地面区域用例全部保持通过。

- [ ] **Step 6: 提交独立 Delivery 改动**

```powershell
git add SkillSystem/02-Delivery/InstantTargetDeliveryConfig.gd SkillSystem/02-Delivery/SkillDeliveryRunner.gd SkillSystem/05-Tests/SingleSceneDeliveryRunnerTest.gd
git commit -m "feat(skill): support caster-radius instant delivery"
```

---

### Task 2: 新增固定仇恨 SkillEffect

**Files:**
- Create: `SkillSystem/03-Extensions/ThreatChangeSkillEffect.gd`
- Create: `SkillSystem/05-Tests/ThreatChangeSkillEffectTest.gd`

**Interfaces:**
- Consumes: `SkillEffectBase.apply(context, result, target)`、`UnitBase.get_threat_component()`、`EnemyThreatComponent.submit_threat(event)`、`ThreatEvent.Kind.SKILL_BONUS`。
- Produces: `ThreatChangeSkillEffect.threat_amount: float = 200.0`；每次成功调用向一个敌人的既有仇恨池精确增加该固定值。

- [ ] **Step 1: 编写 ThreatChangeSkillEffect 失败测试**

创建 SceneTree 测试，装配一个敌方 UnitBase、它的 EnemyThreatComponent 和一个友方 Guardian。至少覆盖：

```gdscript
effect.threat_amount = 200.0
_expect(
	effect.apply(context, SkillDeliveryResult.new(), enemy),
	"fixed threat effect accepts a hostile unit with a threat component"
)
_expect(
	is_equal_approx(threat_component.get_threat_for(guardian), 200.0),
	"first application stores exactly 200 threat"
)
_expect(
	effect.apply(context, SkillDeliveryResult.new(), enemy)
	and is_equal_approx(threat_component.get_threat_for(guardian), 400.0),
	"repeated application adds the same fixed amount"
)
```

再验证 `context.threat_multiplier = 50.0` 时仍只增加 200，以及友方目标、缺少仇恨组件的目标、无效 caster、`threat_amount <= 0` 均返回 `false` 且不改表。

- [ ] **Step 2: 运行测试并确认按预期失败**

```powershell
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' --headless --path 'G:\Godot\ProjectVOD' --script 'res://SkillSystem/05-Tests/ThreatChangeSkillEffectTest.gd'
```

预期：FAIL，原因是 `ThreatChangeSkillEffect.gd` 尚不存在或无法加载。

- [ ] **Step 3: 实现最小固定仇恨 Effect**

按“固定仇恨 Effect 接口”章节实现。必须显式创建 `SKILL_BONUS` 事件并固定 `threat_multiplier = 1.0`；不得调用伤害结算器，也不得使用 `SkillBase.threat_multiplier`。

- [ ] **Step 4: 运行 Effect 与仇恨组件测试**

```powershell
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' --headless --path 'G:\Godot\ProjectVOD' --script 'res://SkillSystem/05-Tests/ThreatChangeSkillEffectTest.gd'
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' --headless --path 'G:\Godot\ProjectVOD' --script 'res://UnitSystem/Tests/EnemyThreatComponentTest.gd'
```

预期：两个测试均 PASS；既有 DAMAGE 和 SKILL_BONUS 行为无回归，TAUNT Kind 仍未启用。

- [ ] **Step 5: 提交独立 Effect 改动**

```powershell
git add SkillSystem/03-Extensions/ThreatChangeSkillEffect.gd SkillSystem/05-Tests/ThreatChangeSkillEffectTest.gd
git commit -m "feat(skill): add fixed threat skill effect"
```

---

### Task 3: 创建并验证 GuardianTauntSkill 单场景技能

**Files:**
- Create: `SkillSystem/00-Skills/GuardianTaunt/GuardianTauntSkill.tscn`
- Create: `SkillSystem/05-Tests/GuardianTauntSkillTest.gd`

**Interfaces:**
- Consumes: `RangedSkillTemplate.tscn`、Task 1 的范围 Instant Delivery、Task 2 的固定仇恨 Effect。
- Produces: `guardian_taunt` 技能场景；默认效果半径 5 米、触发施法距离 0.8 米、固定仇恨 200、冷却 15 秒。

- [ ] **Step 1: 编写技能装配失败测试**

测试必须加载场景并验证以下契约：

```gdscript
_expect(skill is SkillBase, "Guardian Taunt inherits the shared SkillBase")
_expect(skill.skill_id == &"guardian_taunt", "Guardian Taunt exposes its stable skill id")
_expect(skill.target_relations == TargetResolver.TargetRelationFlag.HOSTILE, "Guardian Taunt uses a hostile trigger target")
_expect(skill.target_selection_mode == TargetResolver.TargetSelectionMode.NEAREST, "Guardian Taunt selects the nearest perceived hostile")
_expect(is_equal_approx(skill.cast_range, 0.8), "Guardian Taunt preserves the Guardian melee engagement distance")
_expect(is_equal_approx(skill.skill_cooldown, 15.0), "Guardian Taunt has the designed long cooldown")
_expect(skill.ai_priority == 80, "Guardian Taunt outranks Shield Bash when both are ready")
_expect(skill.delivery is InstantTargetDeliveryConfig, "Guardian Taunt reuses Instant Delivery")
_expect(skill.delivery.target_collection_mode == InstantTargetDeliveryConfig.TargetCollectionMode.CASTER_RADIUS, "Guardian Taunt enables caster-radius collection")
_expect(is_equal_approx(skill.delivery.effect_radius, 5.0), "Guardian Taunt delivery radius is five meters")
_expect(skill.get_node_or_null(^"ThreatEffect") is ThreatChangeSkillEffect, "Guardian Taunt owns one fixed threat effect")
```

同时断言技能没有 `MeleeAction` 子节点、没有独立脚本根类、Delivery 为场景内嵌 Resource，不引用新增外部 `.tres`。

- [ ] **Step 2: 运行技能测试并确认按预期失败**

```powershell
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' --headless --path 'G:\Godot\ProjectVOD' --script 'res://SkillSystem/05-Tests/GuardianTauntSkillTest.gd'
```

预期：FAIL，原因是正式技能场景尚不存在。

- [ ] **Step 3: 创建单场景技能**

在 Godot 中继承 `RangedSkillTemplate.tscn`，保存为 `GuardianTauntSkill.tscn`，按“GuardianTauntSkill 配置”章节填写根节点和内嵌 Delivery，并添加唯一 `ThreatEffect` 直接子节点。不得创建额外 Definition `.tres` 或专用技能根脚本。

- [ ] **Step 4: 运行技能、Delivery 和 Effect 测试**

```powershell
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' --headless --path 'G:\Godot\ProjectVOD' --script 'res://SkillSystem/05-Tests/GuardianTauntSkillTest.gd'
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' --headless --path 'G:\Godot\ProjectVOD' --script 'res://SkillSystem/05-Tests/SingleSceneDeliveryRunnerTest.gd'
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' --headless --path 'G:\Godot\ProjectVOD' --script 'res://SkillSystem/05-Tests/ThreatChangeSkillEffectTest.gd'
```

预期：三个测试全部 PASS。

- [ ] **Step 5: 提交技能场景**

```powershell
git add SkillSystem/00-Skills/GuardianTaunt/GuardianTauntSkill.tscn SkillSystem/05-Tests/GuardianTauntSkillTest.gd
git commit -m "feat(guardian): add area threat skill scene"
```

---

### Task 4: 为盾牌补充无 Hitbox 通用施法动画

**Files:**
- Modify through Godot API: `Item/Weapon/Shield/ShieldAnimationLibrary.res`
- Modify: `UnitSystem/Tests/ShieldAnimationLibraryTest.gd`
- Test: `UnitSystem/Tests/AISkillActionAnimationTest.gd`

**Interfaces:**
- Consumes: `AIAttackController` 对 `weapon/basic_cast_1`、唯一 `release_action` 和 `finish_action` 的既有契约。
- Produces: Shield `AnimationLibrary` 中合法的 `basic_cast_1`，释放标记 0.20 秒，完成标记 0.60 秒，无攻击 Hitbox 或攻击位移标记。

- [ ] **Step 1: 为盾牌动画库编写失败契约测试**

在 `ShieldAnimationLibraryTest.gd` 增加：

```gdscript
var cast_animation := library.get_animation(&"basic_cast_1")
_expect(cast_animation != null, "Shield library provides basic_cast_1 for non-melee skills")
_expect(_count_method(cast_animation, &"release_action") == 1, "Shield cast has exactly one release marker")
_expect(_count_method(cast_animation, &"finish_action") == 1, "Shield cast has exactly one finish marker")
_expect(_count_method(cast_animation, &"open_attack_hit_window") == 0, "Shield cast never opens a melee hit window")
_expect(_count_method(cast_animation, &"close_attack_hit_window") == 0, "Shield cast never closes a melee hit window")
_expect(_count_method(cast_animation, &"request_attack_motion") == 0, "Shield cast never requests attack motion")
```

若测试中尚无 `_count_method()`，增加一个只遍历 `Animation.TYPE_METHOD` 轨道并统计指定方法名的私有辅助函数。

- [ ] **Step 2: 运行盾牌动画测试并确认按预期失败**

```powershell
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' --headless --path 'G:\Godot\ProjectVOD' --script 'res://UnitSystem/Tests/ShieldAnimationLibraryTest.gd'
```

预期：FAIL，原因是 `basic_cast_1` 尚不存在。

- [ ] **Step 3: 通过 Godot API 创建并正式保存 basic_cast_1**

在 Godot 编辑器或一次性受控 `EditorScript` 中读取 `ShieldAnimationLibrary.res`，复制 `action_skill_1` 的视觉姿势轨道，删除全部方法轨道后创建新的方法轨道，并写入：

```gdscript
animation.track_insert_key(method_track, 0.20, {"method": &"release_action", "args": []})
animation.track_insert_key(method_track, 0.60, {"method": &"finish_action", "args": []})
```

将动画命名为 `basic_cast_1`，通过 `ResourceSaver.save(library, SHIELD_LIBRARY_PATH)` 正式保存。一次性脚本不得作为正式运行时依赖；若创建临时脚本，验证后删除。

- [ ] **Step 4: 验证动画 Resource UID 和动作契约**

测试中保留以下 UID 断言：

```gdscript
_expect(
	ResourceLoader.get_resource_uid(LIBRARY_PATH) != ResourceUID.INVALID_ID,
	"ShieldAnimationLibrary.res keeps a valid UID"
)
```

运行：

```powershell
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' --headless --path 'G:\Godot\ProjectVOD' --script 'res://UnitSystem/Tests/ShieldAnimationLibraryTest.gd'
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' --headless --path 'G:\Godot\ProjectVOD' --script 'res://UnitSystem/Tests/AISkillActionAnimationTest.gd'
```

预期：两个测试均 PASS；盾牌原有 RESET、普攻和 `action_skill_1` 契约无回归。

- [ ] **Step 5: 提交正式动画资源改动**

```powershell
git add Item/Weapon/Shield/ShieldAnimationLibrary.res UnitSystem/Tests/ShieldAnimationLibraryTest.gd
git commit -m "feat(guardian): add non-melee shield cast animation"
```

---

### Task 5: 装配 Guardian 并验证完整运行链路

**Files:**
- Modify: `UnitSystem/AI/Ally/Units/Guardian.tscn`
- Create: `UnitSystem/Tests/GuardianTauntIntegrationTest.gd`

**Interfaces:**
- Consumes: `GuardianTauntSkill.tscn`、Shield `basic_cast_1`、`SkillHost.request_best_skill()`、`AICombatSystem` 外部动作、`EnemyThreatComponent.resolve_target()`。
- Produces: Guardian 默认同时装配 `guardian_taunt` 与 `guardian_shield_bash`；范围仇恨技能通过真实动画标记完成交付并进入冷却。

- [ ] **Step 1: 编写 Guardian 装配与端到端失败测试**

测试实例化正式 Guardian，并验证：

```gdscript
var host := guardian.get_node(^"SkillHost") as SkillHostComponent
var skill := _find_registered_skill(host, &"guardian_taunt")
_expect(skill != null, "Guardian registers the area threat skill")
_expect(_find_registered_skill(host, &"guardian_shield_bash") != null, "Guardian keeps Shield Bash")
```

测试文件同时提供以下私有查询辅助函数，不要求扩展 SkillHost 的公开 API：

```gdscript
func _find_registered_skill(
	host: SkillHostComponent,
	skill_id: StringName
) -> SkillBase:
	for skill: SkillBase in host.get_registered_skills():
		if skill.skill_id == skill_id:
			return skill
	return null
```

随后创建三个敌人和一个高仇恨友方来源：

```text
EnemyA：距离 Guardian 3.0 米
EnemyB：距离 Guardian 5.0 米
EnemyC：距离 Guardian 5.1 米
ExistingSource：在 EnemyA/EnemyB 中各有 150 点仇恨
```

把 EnemyA、EnemyB、EnemyC 注入 Guardian 的技能候选 Provider，发起 `host.request_best_skill(nearest_enemy)`，推进 `CharacterAnimationEventPlayer` 越过 0.20 秒释放点，然后断言：

```gdscript
_expect(is_equal_approx(enemy_a_threat.get_threat_for(guardian), 200.0), "EnemyA receives exactly 200 Guardian threat")
_expect(is_equal_approx(enemy_b_threat.get_threat_for(guardian), 200.0), "EnemyB at the boundary receives exactly 200 Guardian threat")
_expect(is_zero_approx(enemy_c_threat.get_threat_for(guardian)), "EnemyC outside the radius receives no Guardian threat")
_expect(enemy_a_targeting.get_locked_target() == guardian, "existing threat resolution can select Guardian after the burst")
_expect(skill.get_cooldown_remaining() > 0.0, "successful delivery starts the long skill cooldown")
```

另外用高于 `200 / guardian.threat_takeover_ratio` 的当前目标仇恨构造一轮，断言 Guardian 不会被保证接管，以证明技能没有隐藏强制目标语义。

- [ ] **Step 2: 运行集成测试并确认按预期失败**

```powershell
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' --headless --path 'G:\Godot\ProjectVOD' --script 'res://UnitSystem/Tests/GuardianTauntIntegrationTest.gd'
```

预期：FAIL，原因是 Guardian 尚未装配 `guardian_taunt`。

- [ ] **Step 3: 在 Guardian 源场景装配新技能**

在 `Guardian.tscn` 的 `SkillHost/SkillSocket` 下增加 `GuardianTauntSkill` 实例，同时保留现有 `GuardianShieldSkill`。不得修改 `Scenes/TestScene.tscn` 中的 Guardian 实例。

- [ ] **Step 4: 运行端到端测试并验证衰减**

运行 Step 2 的集成测试。测试还应将敌人 `threat_half_life` 设置为短测试值，推进 `_process(delta)` 或场景帧，并断言 Guardian 仇恨从 200 降低到大于 0 且小于 200；不得期待线性衰减或在测试中复制 S 形曲线公式。

预期：`GuardianTauntIntegrationTest: PASS`。

- [ ] **Step 5: 运行相关回归测试**

```powershell
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' --headless --path 'G:\Godot\ProjectVOD' --script 'res://SkillSystem/05-Tests/SingleSceneSkillHostTest.gd'
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' --headless --path 'G:\Godot\ProjectVOD' --script 'res://SkillSystem/05-Tests/SingleSceneDeliveryRunnerTest.gd'
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' --headless --path 'G:\Godot\ProjectVOD' --script 'res://UnitSystem/Tests/EnemyThreatComponentTest.gd'
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' --headless --path 'G:\Godot\ProjectVOD' --script 'res://UnitSystem/Tests/EnemyThreatIntegrationTest.gd'
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' --headless --path 'G:\Godot\ProjectVOD' --script 'res://UnitSystem/Tests/AISkillActionAnimationTest.gd'
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' --headless --path 'G:\Godot\ProjectVOD' --script 'res://UnitSystem/Tests/ShieldAnimationLibraryTest.gd'
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' --headless --path 'G:\Godot\ProjectVOD' --script 'res://SkillSystem/05-Tests/GuardianTauntSkillTest.gd'
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' --headless --path 'G:\Godot\ProjectVOD' --script 'res://UnitSystem/Tests/GuardianTauntIntegrationTest.gd'
```

预期：全部 PASS，且 headless 输出不新增解析错误、无效 Resource UID 或孤立节点警告。

- [ ] **Step 6: 提交 Guardian 装配与集成测试**

```powershell
git add UnitSystem/AI/Ally/Units/Guardian.tscn UnitSystem/Tests/GuardianTauntIntegrationTest.gd
git commit -m "feat(guardian): equip area threat skill"
```

---

### Task 6: 同步技能文档并执行最终验收

**Files:**
- Modify: `SkillSystem/04-Docs/SkillSystemUserGuide.md`
- Review only: `Scenes/TestScene.tscn`

**Interfaces:**
- Consumes: Tasks 1–5 的最终接口和正式场景。
- Produces: 设计师可按文档使用 Instant Delivery 的范围模式组合其他范围 Effect；完整功能通过回归套件。

- [ ] **Step 1: 更新 SkillSystem 使用指南**

在 Delivery 说明中增加：

```markdown
- `InstantTargetDeliveryConfig`：立即交付 Effect。默认 `SINGLE` 只影响已解析目标；`CASTER_RADIUS` 以施法者为中心，从本次候选快照筛选指定关系和半径内的多个目标，并对每个目标复用同一组 Effect。
```

增加 Guardian 组合示例，明确“固定仇恨效果不是强制目标，且范围模式仍属于 Instant Delivery”。同步修正文档中任何把 Ranged 模板误写成“只能用于远距离目标”的表述。

- [ ] **Step 2: 执行配置和场景扫描**

```powershell
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' --headless --editor --path 'G:\Godot\ProjectVOD' --quit
```

预期：项目扫描完成，无新增脚本解析错误、场景加载错误或资源 UID 错误。

- [ ] **Step 3: 确认 TestScene 约束**

只读检查 `git diff -- Scenes/TestScene.tscn`，预期无输出。若需要在 TestScene 中增加额外 Guardian 或敌人进行人工试玩，停止自动修改并向用户说明需要添加的源场景、父节点、位置和 Inspector 参数。

- [ ] **Step 4: 执行最终测试清单**

重新执行 Task 5 Step 5 的全部测试命令，确认每项均为 PASS。随后运行：

```powershell
git diff --check
git status --short
```

预期：`git diff --check` 无输出；`git status --short` 只包含本功能文件和用户原有未提交修改。

- [ ] **Step 5: 提交文档更新**

```powershell
git add SkillSystem/04-Docs/SkillSystemUserGuide.md
git commit -m "docs(skill): document caster-radius instant effects"
```

---

## 实施顺序与检查点

严格顺序：

```text
Task 1 范围 Instant Delivery
  ↓
Task 2 固定仇恨 Effect
  ↓
Task 3 GuardianTauntSkill 场景
  ↓
Task 4 Shield 通用施法动画
  ↓
Task 5 Guardian 装配与端到端验证
  ↓
Task 6 文档和最终回归
```

每个 Task 都形成独立、可审查的提交。Task 1 和 Task 2 在代码依赖上可以并行，但执行计划默认顺序完成，避免并行工作覆盖共享测试基础。

## 设计验收清单

- [ ] 未创建新的 SkillTemplate。
- [ ] 未创建新的 Delivery 子类。
- [ ] Instant Delivery 默认单体行为零配置兼容。
- [ ] Guardian 技能以自身为范围中心，水平半径精确为 5 米。
- [ ] Guardian Taunt 的触发施法距离保持 0.8 米，不把 Guardian 的战斗站位拉远到 5 米。
- [ ] 每个有效敌人收到精确固定的 200 点新增仇恨。
- [ ] 新仇恨进入既有池并按既有机制衰减。
- [ ] 仇恨不足时不会强制敌人切换目标。
- [ ] Guardian Shield Bash 仍然存在且行为不变。
- [ ] Guardian Taunt 使用 RangedSkillTemplate 和无 Hitbox 的通用施法动画。
- [ ] 技能成功后进入 15 秒长冷却。
- [ ] 未修改 TestScene 中的单位实例。
- [ ] 所有新增导出参数和公开接口均有完整简体中文说明。
- [ ] ShieldAnimationLibrary 保持有效 UID。
- [ ] 所有相关测试、项目扫描和 `git diff --check` 通过。
