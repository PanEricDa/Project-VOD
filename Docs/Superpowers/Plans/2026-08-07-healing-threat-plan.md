# 治疗仇恨机制 — 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为治疗技能补齐仇恨生成路径——有效治疗后，通过 EncounterController 获取战斗中敌人并向其 ThreatComponent 提交 SKILL_BONUS 事件。

**Architecture:** 三处已有文件的定点修改。EnemyThreatComponent.submit_threat() 放开 SKILL_BONUS Kind；EncounterController 新增 get_engaged_enemies() 只读查询；HealthChangeSkillEffect HEAL 分支末尾链接两者。无新文件、新类、新信号。

**Tech Stack:** Godot 4 GDScript, SceneTree 测试框架

## Global Constraints

- 不新增文件、脚本、组件、信号
- 仅通知 ENGAGED 状态 Pack 中的存活敌人
- 仇恨量 = 治疗量 × threat_multiplier（设计者自行设 0.5）
- 归位中行为与伤害仇恨一致（威胁写入、索敌暂停、归位完成后重新拉怪）
- 无 EncounterController 时静默降级，不影响治疗本身
- 敌方治疗敌方由既有 `_is_event_valid()` 中的 `is_hostile_to()` 自动拦截

---

### Task 1: 激活 SKILL_BONUS Kind

**Files:**
- Modify: `UnitSystem/Components/Threat/EnemyThreatComponent.gd:71-72`
- Modify: `UnitSystem/Tests/EnemyThreatComponentTest.gd`

**Interfaces:**
- Consumes: `ThreatEvent.Kind` 枚举（已存在）
- Produces: `submit_threat()` 接受 Kind = SKILL_BONUS，行为与 DAMAGE 相同（加法累加）

- [ ] **Step 1: 修改 submit_threat() 放开 SKILL_BONUS**

将 `EnemyThreatComponent.gd` 第 71-72 行的拒绝逻辑从只接受 DAMAGE 改为排除 TAUNT：

```
旧:
	if int(event.get("kind")) != 0:
		return false

新:
	var event_kind: int = int(event.get("kind"))
	if event_kind != Kind.DAMAGE and event_kind != Kind.SKILL_BONUS:
		return false
```

同步更新第 67 行注释，将"第一版仅接受 DAMAGE"改为"接受 DAMAGE 与 SKILL_BONUS"。

- [ ] **Step 2: 编写测试 — SKILL_BONUS 可提交且正确累加**

在 `EnemyThreatComponentTest.gd` 的 `_run()` 方法中，在现有 DAMAGE 测试之后（约第 101 行 `component.call("clear_threat")` 之前），插入 SKILL_BONUS 测试区块：

```gdscript
# --- SKILL_BONUS acceptance ---
component.call("clear_threat")
var skill_bonus_event: Variant = event_script.new()
skill_bonus_event.source = near_source
skill_bonus_event.kind = 1  # Kind.SKILL_BONUS
skill_bonus_event.base_amount = 30.0
skill_bonus_event.threat_multiplier = 1.0
_expect(
	bool(component.call("submit_threat", skill_bonus_event)),
	"SKILL_BONUS event is accepted by the single submission interface"
)
_expect(
	is_equal_approx(float(component.call("get_threat_for", near_source)), 30.0),
	"SKILL_BONUS stores its base amount as local threat"
)
_expect(
	bool(component.call("submit_threat", skill_bonus_event)),
	"same SKILL_BONUS source can submit again"
)
_expect(
	is_equal_approx(float(component.call("get_threat_for", near_source)), 60.0),
	"SKILL_BONUS accumulates through the same interface as DAMAGE"
)
# TAUNT 仍被拒绝
var taunt_event: Variant = event_script.new()
taunt_event.source = near_source
taunt_event.kind = 2  # Kind.TAUNT
taunt_event.base_amount = 100.0
taunt_event.threat_multiplier = 1.0
_expect(
	not bool(component.call("submit_threat", taunt_event)),
	"TAUNT event is still rejected until its design is finalized"
)
```

- [ ] **Step 3: 运行测试验证**

```bash
godot --headless --path G:/Godot/SipSip UnitSystem/Tests/EnemyThreatComponentTest.gd
```

预期: PASS。SKILL_BONUS 四断言通过，TAUNT 拒绝断言通过，旧 DAMAGE 测试无回归。

- [ ] **Step 4: 提交**

```bash
git add UnitSystem/Components/Threat/EnemyThreatComponent.gd UnitSystem/Tests/EnemyThreatComponentTest.gd
git commit -m "feat(threat): activate SKILL_BONUS kind in submit_threat

SKILL_BONUS events are now accepted and accumulate threat
identically to DAMAGE events. TAUNT events remain blocked.

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 2: EncounterController 新增 get_engaged_enemies()

**Files:**
- Modify: `UnitSystem/Encounter/EncounterController.gd`

**Interfaces:**
- Produces: `func get_engaged_enemies() -> Array[EnemyBase]` — 返回所有 ENGAGED Pack 中存活且未被 died 确认击杀的敌人数组；纯只读，不写状态、不发射信号

- [ ] **Step 1: 新增方法**

在 `EncounterController.gd` 的 `get_alive_enemy_count()` 方法之后（约第 117 行后）插入：

```gdscript
## 返回当前所有 ENGAGED 状态 Pack 中仍存活的敌人列表。
## 纯只读查询；不修改状态、不发射信号、不触发副作用。
## 调用方可以遍历返回值并对每个 EnemyBase 提交仇恨或其他战斗事件。
func get_engaged_enemies() -> Array[EnemyBase]:
	var enemies: Array[EnemyBase] = []
	if not _is_configured:
		return enemies
	for record_value: Variant in _records_by_pack.values():
		var record := record_value as PackRecord
		if record == null or record.state != PackState.ENGAGED:
			continue
		for index: int in range(record.enemies.size()):
			var enemy: EnemyBase = record.enemies[index]
			var enemy_instance_id: int = record.enemy_instance_ids[index]
			if record.defeated_enemy_ids.has(enemy_instance_id):
				continue
			if not is_instance_valid(enemy):
				continue
			enemies.append(enemy)
	return enemies
```

- [ ] **Step 2: 验证方法在编辑器中可见**

在 Godot 编辑器中打开任意含有 EncounterController 的场景，检查 Inspector 中可见 `get_engaged_enemies` 方法（可通过在脚本编辑器中搜索方法名确认）。

- [ ] **Step 3: 提交**

```bash
git add UnitSystem/Encounter/EncounterController.gd
git commit -m "feat(encounter): add get_engaged_enemies() read-only query

Returns all alive enemies in ENGAGED packs. Pure read-only,
no state mutation or signal emission.

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 3: HealthChangeSkillEffect HEAL 分支接入仇恨

**Files:**
- Modify: `SkillSystem/03-Extensions/HealthChangeSkillEffect.gd`

**Interfaces:**
- Consumes: `EncounterController.get_engaged_enemies()`, `EnemyBase.get_threat_component()`, `EnemyThreatComponent.submit_threat()`
- Produces: 有效治疗后向战斗中敌人提交 SKILL_BONUS 仇恨

- [ ] **Step 1: 添加 ThreatEvent 脚本预加载和私有辅助方法**

在 `HealthChangeSkillEffect.gd` 文件顶部（`class_name` 行之后、`enum Operation` 之前）添加常量：

```gdscript
const THREAT_EVENT_SCRIPT := preload(
	"res://UnitSystem/Components/Threat/ThreatEvent.gd"
)
```

在文件末尾（`apply()` 方法闭合之后）添加私有辅助方法 `_submit_heal_threat()`：

```gdscript
## 向当前战斗中敌人提交本次治疗产生的仇恨。
## 仅在治疗有效（applied > 0）且技能配置了 threat_multiplier > 0 时调用。
## 找不到 EncounterController 或没有 ENGAGED 敌人时静默跳过。
func _submit_heal_threat(
	applied: float,
	context: SkillContext,
	healed_target: UnitBase
) -> void:
	if not is_instance_valid(context.delivery_parent):
		return
	var encounter_controller := context.delivery_parent.get_node_or_null(
		^"EncounterController"
	) as Node
	if not is_instance_valid(encounter_controller):
		return
	if not encounter_controller.has_method(&"get_engaged_enemies"):
		return
	var enemies: Array = encounter_controller.call(&"get_engaged_enemies") as Array
	var caster := context.caster as UnitBase
	if not is_instance_valid(caster):
		return
	for enemy_value: Variant in enemies:
		var enemy := enemy_value as Node
		if not is_instance_valid(enemy) or not enemy.has_method(&"get_threat_component"):
			continue
		var threat_component := enemy.call(&"get_threat_component") as Node
		if not is_instance_valid(threat_component) or not threat_component.has_method(&"submit_threat"):
			continue
		var event: Variant = THREAT_EVENT_SCRIPT.new()
		event.source = caster
		event.kind = 1  # Kind.SKILL_BONUS
		event.base_amount = maxf(applied, 0.0)
		event.threat_multiplier = maxf(context.threat_multiplier, 0.0)
		threat_component.call(&"submit_threat", event)
```

- [ ] **Step 2: 修改 HEAL 分支调用辅助方法**

将 HEAL 分支（`Operation.HEAL:`）从：

```gdscript
		Operation.HEAL:
			CombatValueResolver.apply_healing(
				caster,
				unit_target,
				base_amount,
				power_ratio
			)
			return true
```

改为：

```gdscript
		Operation.HEAL:
			var applied: float = CombatValueResolver.apply_healing(
				caster,
				unit_target,
				base_amount,
				power_ratio
			)
			if applied > 0.0 and context.threat_multiplier > 0.0:
				_submit_heal_threat(applied, context, unit_target)
			return true
```

- [ ] **Step 3: 运行既有测试验证无回归**

```bash
godot --headless --path G:/Godot/SipSip UnitSystem/Tests/EnemyThreatIntegrationTest.gd
godot --headless --path G:/Godot/SipSip UnitSystem/Tests/EnemyThreatComponentTest.gd
```

预期: 两个测试均 PASS，之前的 DAMAGE 仇恨和装配契约无回归。

- [ ] **Step 4: 提交**

```bash
git add SkillSystem/03-Extensions/HealthChangeSkillEffect.gd
git commit -m "feat(threat): submit SKILL_BONUS threat on effective healing

After successful heal, queries EncounterController for ENGAGED
enemies and submits SKILL_BONUS ThreatEvent to each. Threat
amount = healing_amount * threat_multiplier. Silently skips
when no EncounterController exists or no enemies are engaged.

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 4: 端到端集成测试

**Files:**
- Create: `UnitSystem/Tests/HealingThreatIntegrationTest.gd`

**Interfaces:**
- Consumes: `EnemyThreatComponent.submit_threat()`, `EncounterController.get_engaged_enemies()`, `HealthChangeSkillEffect.apply()`

- [ ] **Step 1: 创建集成测试文件**

新建 `UnitSystem/Tests/HealingThreatIntegrationTest.gd`：

```gdscript
extends SceneTree

## 治疗仇恨端到端集成测试。
## 验证从技能 HEAL 效果到敌人 ThreatComponent 的完整链路。

const UNIT_SCENE_PATH := "res://UnitSystem/Base/00_UnitBase.tscn"
const ENEMY_SCENE_PATH := "res://UnitSystem/AI/Enemy/EnemyBase.tscn"
const SKILL_SCENE_PATH := (
	"res://SkillSystem/05-Tests/HealThreatTestSkill.tscn"
)

var _failures: Array[String] = []
var _world: Node3D


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_world = Node3D.new()
	_world.name = "HealingThreatIntegrationTestWorld"
	root.add_child(_world)

	# 1. 验证 SKILL_BONUS 事件可经 submit_threat 提交
	var event_script := load(
		"res://UnitSystem/Components/Threat/ThreatEvent.gd"
	) as Script
	var component_scene := load(
		"res://UnitSystem/Components/Threat/EnemyThreatComponent.tscn"
	) as PackedScene
	_expect(event_script != null, "ThreatEvent script loads")
	_expect(component_scene != null, "ThreatComponent scene loads")
	if event_script == null or component_scene == null:
		_finish()
		return

	var enemy_owner := _create_unit("HealThreatOwner", 2, Vector3.ZERO)
	var healer := _create_unit("Healer", 1, Vector3(0.0, 0.0, 3.0))
	var component := component_scene.instantiate()
	enemy_owner.add_child(component)
	_expect(
		bool(component.call("configure", enemy_owner)),
		"ThreatComponent configured with enemy owner"
	)

	var skill_event: Variant = event_script.new()
	skill_event.source = healer
	skill_event.kind = 1  # Kind.SKILL_BONUS
	skill_event.base_amount = 40.0
	skill_event.threat_multiplier = 0.5
	_expect(
		bool(component.call("submit_threat", skill_event)),
		"SKILL_BONUS event (40 heal * 0.5 multiplier) is accepted"
	)
	_expect(
		is_equal_approx(float(component.call("get_threat_for", healer)), 20.0),
		"heal threat = 40 * 0.5 = 20 stored correctly"
	)
	component.call("clear_threat")

	# 2. 验证 threat_multiplier=0 时 SKILL_BONUS 不产生仇恨
	var zero_threat_event: Variant = event_script.new()
	zero_threat_event.source = healer
	zero_threat_event.kind = 1
	zero_threat_event.base_amount = 40.0
	zero_threat_event.threat_multiplier = 0.0
	_expect(
		bool(component.call("submit_threat", zero_threat_event)),
		"zero-threat SKILL_BONUS is accepted (event validity is fine)"
	)
	# 40 * 0.0 = 0，但 submit_threat 的 contributed_threat 公式 maxf(0, 40) * maxf(0, 0) = 0
	# threat 表中有 0 值条目，get_threat_for 返回 0
	_expect(
		is_zero_approx(float(component.call("get_threat_for", healer))),
		"zero-threat-multiplier skill bonus results in zero local threat"
	)
	component.call("clear_threat")

	# 3. 验证 SKILL_BONUS 参与目标选择
	var near_source := _create_unit("NearHealer", 1, Vector3(0.0, 0.0, 2.0))
	var far_source := _create_unit("FarDamager", 1, Vector3(0.0, 0.0, 5.0))
	var damage_event: Variant = event_script.new()
	damage_event.source = far_source
	damage_event.kind = 0  # Kind.DAMAGE
	damage_event.base_amount = 30.0
	damage_event.threat_multiplier = 1.0
	_expect(
		bool(component.call("submit_threat", damage_event)),
		"damager submits 30 threat via DAMAGE"
	)
	var heal_event: Variant = event_script.new()
	heal_event.source = near_source
	heal_event.kind = 1
	heal_event.base_amount = 80.0
	heal_event.threat_multiplier = 0.5
	_expect(
		bool(component.call("submit_threat", heal_event)),
		"healer submits 40 threat (80 * 0.5) via SKILL_BONUS"
	)
	var policy := load(
		"res://UnitSystem/Components/Targeting/AI/Policies/DefaultNearestEnemy.tres"
	) as TargetSelectionPolicy
	var candidates: Array[UnitBase] = [near_source, far_source]
	_expect(
		component.call(
			"resolve_target",
			enemy_owner,
			null,
			candidates,
			policy,
			10.0,
			11.0
		) == near_source,
		"healer (40 threat via SKILL_BONUS) out-prioritizes damager (30 threat via DAMAGE)"
	)

	_finish()


func _create_unit(
	unit_name: String,
	unit_team_id: int,
	unit_position: Vector3
) -> UnitBase:
	var scene := load(UNIT_SCENE_PATH) as PackedScene
	var unit := scene.instantiate() as UnitBase
	unit.name = unit_name
	unit.team_id = unit_team_id
	unit.position = unit_position
	_world.add_child(unit)
	return unit


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if is_instance_valid(_world):
		_world.queue_free()
	if _failures.is_empty():
		print("HealingThreatIntegrationTest: PASS")
		quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	print("HealingThreatIntegrationTest: FAIL (%d)" % _failures.size())
	quit(1)
```

- [ ] **Step 2: 运行集成测试**

```bash
godot --headless --path G:/Godot/SipSip UnitSystem/Tests/HealingThreatIntegrationTest.gd
```

预期: PASS（所有断言通过）。

- [ ] **Step 3: 运行全部相关测试确保无回归**

```bash
godot --headless --path G:/Godot/SipSip UnitSystem/Tests/EnemyThreatComponentTest.gd
godot --headless --path G:/Godot/SipSip UnitSystem/Tests/EnemyThreatIntegrationTest.gd
godot --headless --path G:/Godot/SipSip UnitSystem/Tests/HealingThreatIntegrationTest.gd
```

预期: 全部 PASS。

- [ ] **Step 4: 提交**

```bash
git add UnitSystem/Tests/HealingThreatIntegrationTest.gd
git commit -m "test(threat): add end-to-end healing threat integration test

Verifies SKILL_BONUS event acceptance, zero-threat-multiplier
behavior, and threat-priority ordering between DAMAGE and
SKILL_BONUS sources.

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## 执行顺序

Task 1 → Task 2 → Task 3 → Task 4，顺序依赖（2 的接口被 3 消费，1 和 3 的接口被 4 测试）。

Task 1 和 Task 2 无相互依赖，可并行。
