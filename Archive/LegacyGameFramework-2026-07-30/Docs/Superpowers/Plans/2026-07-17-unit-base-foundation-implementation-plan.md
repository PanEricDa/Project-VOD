# UnitBase Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为项目建立一个不依赖 AI、技能或表现系统的 UnitBase，统一提供生命、阵营关系与可选目标接口。

**Architecture:** `00_UnitBase.tscn` 保持单一 `CharacterBody3D` 根节点并挂载 `UnitBase.gd`。所有配置通过根节点 Inspector 字段覆盖；当前生命属于每个场景实例，不使用共享 Resource，也不创建 Health/Faction 子节点。

**Tech Stack:** Godot 4.7、GDScript、SceneTree headless tests。

## Global Constraints

- 不修改 `Scenes/TestScene.tscn`。
- 不加入 AI、移动、技能、动画、装备或临时阵营切换。
- 所有字段与方法使用英文标识，新增代码使用简体中文详细注释。
- 项目不是 Git 仓库，不创建提交。

---

### Task 1: UnitBase 行为契约

**Files:**
- Create: `UnitSystem/Tests/UnitBaseTest.gd`
- Create: `UnitSystem/00_UnitBase.gd`
- Modify: `UnitSystem/00_UnitBase.tscn`

**Interfaces:**
- Produces: `apply_damage()`, `apply_healing()`, `revive()`, `is_dead()`
- Produces: `is_friendly_to()`, `is_hostile_to()`, `is_neutral_to()`
- Produces: `get_current_health()`, `get_health_ratio()`, `is_targetable()`

- [ ] **Step 1: 编写失败测试**

测试实例化真实场景，覆盖生命边界、信号、复活、友方/敌对/中立关系和
`targetable` 查询，并确认场景不再依赖旧 Health/Faction 子组件。

- [ ] **Step 2: 验证 RED**

Run:

```powershell
Godot_v4.7-stable_win64_console.exe --headless --path G:\Godot\SipSip --script res://UnitSystem/Tests/UnitBaseTest.gd
```

Expected: FAIL，原因是 UnitBase 公共方法尚不存在。

- [ ] **Step 3: 实现最小 UnitBase**

根脚本提供导出的最大/初始生命、阵营标识、队伍编号和可选目标开关；运行时初始化
独立当前生命，并提供与现有 HealthComponent/FactionComponent 等价的最小接口。

- [ ] **Step 4: 装配场景**

将脚本挂载到 `00_UnitBase.tscn` 根节点，不增加 Health/Faction 子节点。

- [ ] **Step 5: 验证 GREEN 与回归**

运行 UnitBase 测试、Godot 4.7 编辑器扫描和现有 SkillSystem 测试。确认
`TestScene.tscn` 哈希不变。
