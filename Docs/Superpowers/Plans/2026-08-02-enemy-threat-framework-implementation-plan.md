# Enemy Threat Framework Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为每个敌方单位建立统一、本地化的仇恨结算与目标优先级框架，并把结果安全接入现有敌方索敌和行为状态机。

**Architecture:** `EnemyThreatComponent` 仅挂载在 `EnemyBase`，每个敌人维护自己的仇恨表。所有来源最终提交统一的运行时 `ThreatEvent`；组件是唯一能够修改仇恨表的地方。`AITargetingComponent` 仍是唯一持有 `locked_target` 的组件，它在刷新时可选地向仇恨组件询问候选优先级；敌方状态机不保存第二份目标，也不承担仇恨结算。

**Tech Stack:** Godot 4.7、GDScript、Godot headless 场景脚本测试。

## Global Constraints

- 不自动向 `res://Scenes/TestScene.tscn` 添加、删除或修改任何单位实例。
- 每个新增或修改的 `@export`、公开方法、信号和跨模块参数必须紧邻简体中文说明，包含用途、单位/取值、默认行为和影响范围。
- 本阶段不引入正式 `.tres`；`ThreatEvent` 仅为运行时数据，不要求设计师配置。
- 本阶段不实现坦克常规仇恨技能、嘲讽、职业倍率、暴击、治疗仇恨、装备修正或仇恨 UI。
- 所有仇恨来源都必须走 `EnemyThreatComponent` 的统一提交入口；禁止调用方直接改表或直接切换敌人目标。
- 项目不是 Git 仓库；不得创建提交。

---

## Planned File Structure

- Create: `res://UnitSystem/Components/Threat/ThreatEvent.gd` — 统一仇恨事件的运行时数据载体。
- Create: `res://UnitSystem/Components/Threat/EnemyThreatComponent.gd` — 敌人本地仇恨表、统一结算入口与候选优先级决策。
- Create: `res://UnitSystem/Components/Threat/EnemyThreatComponent.tscn` — 可手动挂载到敌人根节点的组件场景。
- Modify: `res://UnitSystem/Components/Targeting/AI/AITargetingComponent.gd` — 增加可选目标决策提供者；无提供者时保持现有策略。
- Modify: `res://UnitSystem/AI/Enemy/EnemyBase.tscn` — 实例化 `ThreatComponent`。
- Modify: `res://UnitSystem/AI/Enemy/EnemyBase.gd` — 配置组件、把实际受伤接入仇恨事件、在归位/死亡时清表。
- Modify: `res://UnitSystem/Components/Behavior/EnemyBehaviorStateMachine.gd` — 仅在明确归位时发出可供 EnemyBase 清表的现有状态变化，不新增目标存储。
- Create: `res://UnitSystem/Tests/EnemyThreatComponentTest.gd` — 仇恨表与统一入口契约测试。
- Modify: `res://UnitSystem/Tests/AITargetingComponentTest.gd` — 验证可选决策提供者与无提供者回退。
- Modify: `res://UnitSystem/Tests/EnemyBehaviorStateMachineTest.gd` — 验证归位时仇恨被清理且既有战斗移动不变。
- Modify: `res://Docs/Superpowers/Specs/2026-08-02-threat-and-aggro-design.md` — 记录最终节点路径、接口与验证结果。

## Unified Runtime Interfaces

```gdscript
# ThreatEvent.gd
class_name ThreatEvent
extends RefCounted

enum Kind { DAMAGE, SKILL_BONUS, TAUNT }

var source: UnitBase
var kind: Kind = Kind.DAMAGE
var base_amount: float = 0.0

static func create_damage(source_unit: UnitBase, applied_amount: float) -> ThreatEvent
```

```gdscript
# EnemyThreatComponent.gd
signal threat_changed(source: UnitBase, previous_value: float, current_value: float)

func configure(owner_enemy: UnitBase) -> bool
func submit_threat(event: ThreatEvent) -> bool
func resolve_target(
    owner_unit: UnitBase,
    current_target: UnitBase,
    candidates: Array[UnitBase],
    policy: TargetSelectionPolicy,
    acquisition_radius: float,
    retention_radius: float
) -> UnitBase
func clear_threat() -> void
func get_threat_for(source: UnitBase) -> float
```

`submit_threat()` 是唯一改变仇恨表的公开入口。第一版只接受 `Kind.DAMAGE`，其最终增加量等于已实际结算的伤害量；其余枚举值仅保留为未来统一入口的类型，不在本计划中产生行为。

```gdscript
# AITargetingComponent.gd
func set_target_decision_provider(provider: Node) -> void
```

提供者必须具有上面的 `resolve_target(...)` 方法。组件不保存提供者给出的第二份目标；它只把返回值写入自己唯一的 `_locked_target`。提供者为空、失效或方法不存在时，严格回退到已有 `TargetSelectionPolicy.select_target()`。

### Task 1: Build the Unified Threat Event and Local Enemy Table

**Files:**
- Create: `res://UnitSystem/Components/Threat/ThreatEvent.gd`
- Create: `res://UnitSystem/Components/Threat/EnemyThreatComponent.gd`
- Create: `res://UnitSystem/Components/Threat/EnemyThreatComponent.tscn`
- Create: `res://UnitSystem/Tests/EnemyThreatComponentTest.gd`

**Consumes:** `UnitBase`, `TargetSelectionPolicy`。

**Produces:** `ThreatEvent`、`EnemyThreatComponent.configure()`、`submit_threat()`、`resolve_target()`、`clear_threat()` 与只读查询接口。

- [ ] **Step 1: 写入失败测试，锁定统一入口和表的最小规则。**

```gdscript
var event := ThreatEvent.new()
event.source = attacker
event.kind = ThreatEvent.Kind.DAMAGE
event.base_amount = 12.0

_expect(component.submit_threat(event), "valid damage event is accepted")
_expect(is_equal_approx(component.get_threat_for(attacker), 12.0), "only the component changes the stored threat")
_expect(not component.submit_threat(ThreatEvent.new()), "event without a living UnitBase source is rejected")
component.clear_threat()
_expect(is_zero_approx(component.get_threat_for(attacker)), "clear removes every local record")
```

同时覆盖：多个来源独立累计；零或负基础量拒绝；死亡或不可选中来源不参与候选；无有效威胁记录时 `resolve_target()` 回退给最近目标策略；有记录时选取最高仇恨候选。

- [ ] **Step 2: 运行测试，确认当前项目中该组件尚不存在。**

Run:

```powershell
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' --headless --path 'G:\Godot\SipSip' --script 'res://UnitSystem/Tests/EnemyThreatComponentTest.gd'
```

Expected: FAIL，因为 `ThreatEvent` / `EnemyThreatComponent` 尚未定义。

- [ ] **Step 3: 实现最小运行时事件与组件。**

实现约束：

```gdscript
func submit_threat(event: ThreatEvent) -> bool:
    # 验证事件、来源、持有敌人与数量；只在此处写入 _threat_by_source_id。
    # Kind.DAMAGE 使用 maxf(event.base_amount, 0.0) 作为第一版结算值。
    # 成功后发出 threat_changed，并请求持有者的 AITargetingComponent 立即刷新。
    return accepted

func resolve_target(...) -> UnitBase:
    # 先由 policy 过滤阵营、死亡、可选中与距离。
    # 当前目标仍在保持半径且没有有效挑战者时保留它。
    # 否则选取候选中最高仇恨；若表中没有候选记录，回退 policy.select_target。
    return selected_target
```

`ThreatEvent` 只能包含事件事实，不保存 SceneTree 节点路径、目标锁定状态或设计师数值。组件场景只包含根节点与脚本，不生成 `.tres`。

- [ ] **Step 4: 运行组件测试。**

Run the command from Step 2.

Expected: `EnemyThreatComponentTest: PASS`。

### Task 2: Let Targeting Ask for a Priority Without Owning a Second Target

**Files:**
- Modify: `res://UnitSystem/Components/Targeting/AI/AITargetingComponent.gd:135-180`
- Modify: `res://UnitSystem/Tests/AITargetingComponentTest.gd`

**Consumes:** `EnemyThreatComponent.resolve_target(...)` interface, existing `TargetSelectionPolicy` filtering.

**Produces:** optional target decision provider injection while preserving current no-provider behavior.

- [ ] **Step 1: 先扩展测试，验证回退与优先级覆盖。**

```gdscript
component.set_target_decision_provider(threat_component)
threat_component.submit_threat(_damage_event(far_enemy, 20.0))
component.refresh_target()
_expect(component.get_locked_target() == far_enemy, "threat provider can choose a valid higher-threat candidate")

component.set_target_decision_provider(null)
component.clear_locked_target()
component.refresh_target()
_expect(component.get_locked_target() == nearer_enemy, "no provider preserves nearest-policy fallback")
```

还要验证：失效的 provider、没有 `resolve_target()` 的 Node、以及 provider 返回无效候选时，都安全回退到原始策略；已有锁定目标在保持半径内且仇恨排序没有有效挑战者时不更换。

- [ ] **Step 2: 运行目标组件测试并确认失败。**

Run:

```powershell
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' --headless --path 'G:\Godot\SipSip' --script 'res://UnitSystem/Tests/AITargetingComponentTest.gd'
```

Expected: FAIL，因为尚无 `set_target_decision_provider()`。

- [ ] **Step 3: 在一次 `refresh_target()` 中完成候选快照与唯一提交。**

实现规则：

```gdscript
var candidates := _collect_policy_candidates()
var resolved_target := _resolve_target_from_provider_or_policy(candidates)
_set_locked_target(resolved_target)
```

不要让 provider 修改 `_locked_target`；不要让 `AITargetingComponent` 保存 provider 的推荐结果。保留原有检测暂停、关闭检测、缺少 Policy 警告、保持半径验证和调试圆环同步行为。

- [ ] **Step 4: 运行目标组件与仇恨组件测试。**

Run the Task 1 and Task 2 commands.

Expected: 两个测试均 PASS；原有最近目标、保持半径与调试圆环断言仍通过。

### Task 3: Assemble the Component on EnemyBase and Feed It Actual Damage

**Files:**
- Modify: `res://UnitSystem/AI/Enemy/EnemyBase.tscn`
- Modify: `res://UnitSystem/AI/Enemy/EnemyBase.gd`
- Modify: `res://UnitSystem/Components/Behavior/EnemyBehaviorStateMachine.gd:422-455`
- Modify: `res://UnitSystem/Tests/EnemyBehaviorStateMachineTest.gd`
- Create or extend: `res://UnitSystem/Tests/EnemyThreatIntegrationTest.gd`

**Consumes:** Task 1 component and Task 2 provider interface; existing `UnitBase.apply_damage()` actual returned damage amount.

**Produces:** all `EnemyBase` instances have a configured local threat component; actual damage automatically becomes baseline threat; return-home/death clear the table.

- [ ] **Step 1: 写入失败的 EnemyBase 装配与伤害接入测试。**

```gdscript
var enemy := _instantiate_enemy(Vector3.ZERO)
var attacker := _instantiate_friendly(Vector3(0.0, 0.0, -4.0))
var threat := enemy.get_threat_component()

_expect(threat != null, "EnemyBase owns an EnemyThreatComponent")
var applied := enemy.apply_damage(15.0, attacker)
_expect(is_equal_approx(applied, 15.0), "damage still resolves through UnitBase")
_expect(is_equal_approx(threat.get_threat_for(attacker), applied), "actual applied damage is submitted once as baseline threat")
```

还要验证：同一来源的第二次伤害累加；伤害来源为空不创建记录；敌人死亡清表；状态机进入 `RETURN_HOME` 时清表；归位后再受伤从空表重新开始。

- [ ] **Step 2: 运行集成测试，确认失败。**

Run:

```powershell
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' --headless --path 'G:\Godot\SipSip' --script 'res://UnitSystem/Tests/EnemyThreatIntegrationTest.gd'
```

Expected: FAIL，因为 EnemyBase 尚未装配或配置仇恨组件。

- [ ] **Step 3: 以 EnemyBase 为唯一组装点接入。**

实现规则：

```gdscript
func apply_damage(amount: float, source: Node = null) -> float:
    var applied_amount := super.apply_damage(amount, source)
    if applied_amount > 0.0 and source is UnitBase and is_instance_valid(_threat_component):
        _threat_component.submit_threat(ThreatEvent.create_damage(source, applied_amount))
    return applied_amount
```

- `EnemyBase.tscn` 根节点下实例化 `ThreatComponent`，与 `AITargetingComponent`、`BehaviorStateMachine` 同级。
- `EnemyBase._ready()` 先配置仇恨组件，再把它注册为 Targeting 的决策提供者，然后配置状态机。
- `EnemyBase` 对外提供只读 `get_threat_component()`，供未来技能通过统一接口提交事件；不把仇恨表暴露给 Inspector。
- 敌人死亡、进入 `RETURN_HOME`、重新复活时调用 `clear_threat()`。不要在普通 `CHASE` / `ATTACK` 状态切换时清表。
- 不修改 `CombatValueResolver`；它已经把最终实际伤害交给目标 `apply_damage()`，因此 EnemyBase 覆盖可统一接住现有与未来的伤害来源。

- [ ] **Step 4: 运行集成与回归测试。**

Run:

```powershell
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' --headless --path 'G:\Godot\SipSip' --script 'res://UnitSystem/Tests/EnemyThreatIntegrationTest.gd'
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' --headless --path 'G:\Godot\SipSip' --script 'res://UnitSystem/Tests/EnemyBehaviorStateMachineTest.gd'
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' --headless --path 'G:\Godot\SipSip' --script 'res://UnitSystem/Tests/AITargetingComponentTest.gd'
```

Expected: 全部 PASS；敌方原有待机、追击、攻击距离、战斗游荡、归位与队友预定位置行为不回归。

### Task 4: Verify the Boundary and Record the Final Contract

**Files:**
- Modify: `res://Docs/Superpowers/Specs/2026-08-02-threat-and-aggro-design.md`
- Inspect: `res://UnitSystem/Components/Threat/`, `res://UnitSystem/AI/Enemy/`, `res://UnitSystem/Components/Targeting/AI/`

**Consumes:** completed component, targeting injection and EnemyBase integration.

**Produces:** documented final paths and evidence that no second target state or secondary threat mutation API exists.

- [ ] **Step 1: 更新设计备忘的最终实现记录。**

记录节点路径 `EnemyBase/ThreatComponent`、统一入口 `submit_threat(event)`、Targeting 的 provider 入口，以及第一版只处理 `DAMAGE` 的范围。明确技能仇恨、嘲讽、治疗和暴击仍未实现。

- [ ] **Step 2: 检查接口边界。**

Run:

```powershell
rg -n "_threat_by_source_id|submit_threat|set_locked_target|resolve_target" UnitSystem -g '*.gd'
```

Expected: 仇恨表写入只存在于 `EnemyThreatComponent`；`_locked_target` 只在 `AITargetingComponent` 内部写入；其他模块只通过公开接口提交事件或请求刷新。

- [ ] **Step 3: 执行全量相关测试与编辑器扫描。**

Run:

```powershell
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' --headless --path 'G:\Godot\SipSip' --script 'res://UnitSystem/Tests/EnemyThreatComponentTest.gd'
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' --headless --path 'G:\Godot\SipSip' --script 'res://UnitSystem/Tests/EnemyThreatIntegrationTest.gd'
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' --headless --path 'G:\Godot\SipSip' --script 'res://UnitSystem/Tests/AITargetingComponentTest.gd'
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' --headless --path 'G:\Godot\SipSip' --script 'res://UnitSystem/Tests/EnemyBehaviorStateMachineTest.gd'
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' --headless --editor --path 'G:\Godot\SipSip' --quit
```

Expected: 所有测试输出 `PASS`，编辑器扫描无脚本解析或场景加载错误。扫描后通过 Godot MCP 刷新项目，再检查编辑器输出没有新增错误。

## Plan Self-Review

- **Spec coverage:** Task 1 实现本地表与统一入口；Task 2 保持唯一锁定目标；Task 3 接入伤害、归位、死亡和现有行为；Task 4 验证边界与文档。常规仇恨技能、嘲讽、数值、暴击、治疗和 UI 均明确不在本计划内。
- **Placeholder scan:** 计划没有 `TODO`、`TBD` 或“适当处理”类未定义步骤；每项测试、接口与命令均有具体定义。
- **Type consistency:** `ThreatEvent` 由 `EnemyThreatComponent.submit_threat()` 消费；其 `resolve_target()` 被 `AITargetingComponent` 调用；`EnemyBase` 是唯一场景组装点。
