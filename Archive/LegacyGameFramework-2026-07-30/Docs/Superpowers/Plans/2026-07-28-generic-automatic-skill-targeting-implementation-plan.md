# Generic Automatic Skill Targeting Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让自动技能使用 SkillBase 现有目标参数，从通用候选集合中选择目标，并允许友方技能在没有敌方锁定时释放。

**Architecture:** UnitBase 只登记技能候选能力；SkillHost 收集但不分类候选；SkillBase 使用现有目标字段完成唯一筛选；Ally 行为状态机在 Formation 与 Combat 中共享自动技能请求入口。

**Tech Stack:** Godot 4.7、GDScript、SceneTree groups、现有 SkillSystem 与 UnitSystem。

## Global Constraints

- 不新增重复的友军/敌军目标配置。
- 不修改 `res://Scenes/TestScene.tscn`。
- 所有字段和方法使用英文标识，新增代码使用详细简体中文注释。
- 正式外部资源必须由 Godot 正式保存并具有有效 UID；本计划不新增 `.tres/.res`。

---

### Task 1: 通用候选来源与既有目标筛选

**Files:**
- Modify: `UnitSystem/Base/00_UnitBase.gd`
- Modify: `SkillSystem/01-Core/SkillHostComponent.gd`
- Modify: `SkillSystem/01-Core/SkillBase.gd`
- Test: `SkillSystem/05-Tests/SingleSceneSkillHostTest.gd`

**Interfaces:**
- Produces: `SkillHostComponent.request_best_skill(preferred_target: Node3D = null) -> bool`
- Consumes: `SkillBase.target_source`、`target_relation` 和 `SkillContext.candidate_targets`

- [x] **Step 1: 添加失败测试**

验证 Host 可发现已进入场景树的候选，并由 HolyLight 的 FRIENDLY 规则选择其他友方，
排除施法者自身和敌方。

- [x] **Step 2: 运行测试并确认因候选数组为空而失败**

Run:
`godot --headless --path G:\Godot\SipSip --script res://SkillSystem/05-Tests/SingleSceneSkillHostTest.gd`

- [x] **Step 3: 实现最小候选登记与收集**

UnitBase 自动加入 `skill_target_candidates`；Host 将该组中有效 Node3D 写入每个候选
SkillContext；FRIENDLY 排除施法者自身。

- [x] **Step 4: 运行测试并确认通过**

使用与 Step 2 相同的命令，预期 PASS。

### Task 2: 无敌方锁定时自动治疗

**Files:**
- Create: `UnitSystem/Tests/PriestHolyLightAutomaticRuntimeTest.gd`
- Modify: `UnitSystem/Components/Behavior/AllyBehaviorStateMachine.gd`

**Interfaces:**
- Consumes: `SkillHostComponent.request_best_skill(preferred_target)`
- Produces: Formation 与 Combat 共用的自动技能机会检查

- [x] **Step 1: 添加失败的 Priest 运行测试**

只创建 Priest、玩家和一个友方目标，不创建敌人；将友方目标降至 50 点生命，
验证 Priest 在范围内自动完成 HolyLight。

- [x] **Step 2: 运行测试并确认因没有敌方战斗目标而失败**

Run:
`godot --headless --path G:\Godot\SipSip --script res://UnitSystem/Tests/PriestHolyLightAutomaticRuntimeTest.gd`

- [x] **Step 3: 将自动技能检查移到状态分支之前**

状态机每帧先维护公共冷却和 Host，然后在 Formation 或 Combat 都调用同一自动技能入口；
技能正在决策或施法时不重复创建请求。普通攻击仍只在 Combat 状态运行。

- [x] **Step 4: 运行新增测试和既有 Firebolt 回归**

预期 Priest 自动治疗通过，`CasterFireboltRuntimeTest.gd` 继续通过。

### Task 3: 完整回归

**Files:**
- Modify: `Docs/Superpowers/Plans/2026-07-28-generic-automatic-skill-targeting-implementation-plan.md`

- [x] **Step 1: 运行相关 SkillSystem 与 UnitSystem 测试**

至少包含 SkillHost、SkillBase、HolyLight、Firebolt、AllyBehavior、Caster 与 Priest。

- [x] **Step 2: 运行 Godot 4.7 编辑器扫描**

Run:
`godot --headless --editor --path G:\Godot\SipSip --quit`

- [x] **Step 3: 通过 MCP 启动主场景并检查 Output/Debugger**

不得修改或自动添加 TestScene 单位；确认没有新增 ERROR 或 WARNING。
