# Intervention Response & Protect Allies 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 `TargetSelectionPolicy` 上增加 `PROTECT_ALLIES` 模式和 `intervention_response` 参数，利用现有 `EnemyThreatComponent` 计算威胁比例修正评分，让 Guardian 优先接走不打自己的敌人。

**Architecture:** `intervention_response` 是 `TargetSelectionPolicy` 上的导出参数，不在 `UnitBase`。`PROTECT_ALLIES` 模式下 `calculate_priority` 读取候选敌人的威胁组件，计算 owner 的威胁占比，套入 IR 修正公式。Guardian 装配新的 `GuardianProtect.tres`。

**Tech Stack:** Godot 4.7、GDScript、现有 `TargetSelectionPolicy` / `EnemyThreatComponent` / `AITargetingComponent`、Godot headless 测试。

## Global Constraints

- 不修改 `Scenes/TestScene.tscn` 中的任何单位实例。
- `@export` 参数提供简体中文注释。
- 不新增场景组件、不订阅新信号、不修改 `EncounterController` 和 `UnitBase`。
- `.tres` 资源必须通过 Godot 编辑器生成有效 UID。
- 项目不是 Git 仓库，不创建提交。

---

### Task 1: TargetSelectionPolicy 扩展

**Files:**
- Modify: `UnitSystem/Components/Targeting/AI/Policies/TargetSelectionPolicy.gd`

**Interfaces:**
- Produces: `PriorityMode.PROTECT_ALLIES`，`@export var intervention_response: float = 1.0`，`_calculate_threat_ratio()`，`_calculate_protect_priority()`

- [ ] **Step 1: 新增枚举、参数和公开方法**

在 `enum PriorityMode` 中追加 `PROTECT_ALLIES`。

添加导出参数：

```gdscript
@export_category("Protect Allies")
## 保护模式下对不打自己的敌人的介入意愿。数值越低越激进，1.0 表示不介入。
@export_range(0.0, 2.0, 0.05)
var intervention_response: float = 1.0
```

添加公开威胁比例查询方法（供未来其他模式复用）：

```gdscript
## 返回 owner 对候选敌人的威胁占该敌人最高威胁的比例，范围 0~1。
## 本方法只读数据不做决策；任何 PriorityMode 均可复用。
func get_threat_ratio(owner_unit: UnitBase, candidate: UnitBase) -> float:
	if not is_instance_valid(owner_unit) or not is_instance_valid(candidate):
		return 0.0
	var threat_component: Node = candidate.get_node_or_null(^"ThreatComponent")
	if not is_instance_valid(threat_component) or not threat_component.has_method(&"get_threat_for"):
		return 0.0
	var my_threat: float = float(threat_component.call("get_threat_for", owner_unit))
	var snapshot: Array = threat_component.call("get_threat_snapshot") as Array
	var highest_threat: float = 0.0
	for entry: Dictionary in snapshot:
		highest_threat = maxf(highest_threat, float(entry.get("value", 0.0)))
	if highest_threat <= 0.0:
		return 0.0
	return clampf(my_threat / highest_threat, 0.0, 1.0)
```

- [ ] **Step 2: 实现 PROTECT_ALLIES 评分**

在 `calculate_priority` 中增加分支：

```gdscript
PriorityMode.PROTECT_ALLIES:
	return _calculate_protect_priority(owner_unit, candidate)
```

私有方法：

```gdscript
func _calculate_protect_priority(
	owner_unit: UnitBase,
	candidate: UnitBase
) -> float:
	var base_priority := _get_horizontal_distance_squared(owner_unit, candidate)
	if not is_instance_valid(owner_unit) or not is_instance_valid(candidate):
		return base_priority

	var candidate_target := candidate.get_locked_target()
	if candidate_target == owner_unit:
		return base_priority

	var ratio := get_threat_ratio(owner_unit, candidate)
	var ir: float = clampf(intervention_response, 0.0, 2.0)
	var factor: float = ir + (1.0 - ir) * ratio
	return base_priority * clampf(factor, 0.0, 1.0)
```

- [ ] **Step 3: 运行 TargetSelectionPolicyTest 确认回归**

```powershell
& $GodotConsole --headless --path 'G:\Godot\SipSip' --script 'res://UnitSystem/Tests/TargetSelectionPolicyTest.gd'
```

---

### Task 2: Guardian 装配

**Files:**
- Create: `UnitSystem/Components/Targeting/AI/Policies/GuardianProtect.tres`
- Modify: `UnitSystem/AI/Ally/Units/Guardian.tscn`

- [ ] **Step 1: 创建 GuardianProtect.tres**

内容：

```
[gd_resource type="Resource" script_class="TargetSelectionPolicy" format=3]

[ext_resource type="Script" path="res://UnitSystem/Components/Targeting/AI/Policies/TargetSelectionPolicy.gd" id="1_policy"]

[resource]
script = ExtResource("1_policy")
priority_mode = 1
intervention_response = 0.3
```

- [ ] **Step 2: 编辑器扫描生成 UID**

```powershell
& $GodotConsole --headless --editor --path 'G:\Godot\SipSip' --quit
```

- [ ] **Step 3: Guardian.tscn 的 AITargetingComponent 覆盖 selection_policy**

引用 `res://UnitSystem/Components/Targeting/AI/Policies/GuardianProtect.tres`。

- [ ] **Step 4: 验证 UID**

```powershell
& $GodotConsole --headless --path 'G:\Godot\SipSip' --script 'res://UnitSystem/Tests/ResourceUidAuditTest.gd'
```

---

### Task 3: 测试

**Files:**
- Create: `UnitSystem/Tests/ProtectAlliesPolicyTest.gd`

- [ ] **Step 1: 写测试**

场景：一个 Guardian、两个敌人 E1（锁定 Guardian）和 E2（锁定 Saber）。Guardian 用 PROTECT_ALLIES 模式。

- 有威胁数据时：IR=0.3，E2 优先级应比 E1 更高（被修正后的分数更低）。
- IR=1.0 时：E1、E2 都不修正，按 NEAREST 排。
- 敌人无 ThreatComponent 时降级：`get_threat_ratio` 返回 0，修正系数退化为 IR，锁定目标不是 owner 的被优先。
- Saber 用 NEAREST 时，`intervention_response` 不被读取，行为不受影响。

```powershell
& $GodotConsole --headless --path 'G:\Godot\SipSip' --script 'res://UnitSystem/Tests/ProtectAlliesPolicyTest.gd'
```

---

### Task 4: 全量回归

- [ ] **Step 1: 运行全部相关测试**

```powershell
& $GodotConsole --headless --path 'G:\Godot\SipSip' --script 'res://UnitSystem/Tests/TargetSelectionPolicyTest.gd'
& $GodotConsole --headless --path 'G:\Godot\SipSip' --script 'res://UnitSystem/Tests/ProtectAlliesPolicyTest.gd'
& $GodotConsole --headless --path 'G:\Godot\SipSip' --script 'res://UnitSystem/Tests/AllyBehaviorStateMachineTest.gd'
& $GodotConsole --headless --path 'G:\Godot\SipSip' --script 'res://UnitSystem/Tests/AllyMeleeCombatIntegrationTest.gd'
& $GodotConsole --headless --path 'G:\Godot\SipSip' --script 'res://UnitSystem/Tests/AITargetingComponentTest.gd'
& $GodotConsole --headless --path 'G:\Godot\SipSip' --script 'res://UnitSystem/Tests/UnitRootConfigurationTest.gd'
& $GodotConsole --headless --path 'G:\Godot\SipSip' --script 'res://UnitSystem/Tests/ResourceUidAuditTest.gd'
& $GodotConsole --headless --path 'G:\Godot\SipSip' --script 'res://UnitSystem/Tests/UnitDirectoryLayoutTest.gd'
```

- [ ] **Step 2: 编辑器扫描**

```powershell
& $GodotConsole --headless --editor --path 'G:\Godot\SipSip' --quit
```
