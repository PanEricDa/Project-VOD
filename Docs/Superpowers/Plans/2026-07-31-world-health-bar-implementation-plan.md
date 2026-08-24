# World Health Bar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为所有 UnitBase 单位提供受伤时显示、延迟红条消退并自动隐藏的可拆卸头顶血条。

**Architecture:** 使用独立 `WorldHealthBar.tscn` 封装 SubViewport、Control 和 Sprite3D。组件单向订阅 UnitBase 的生命信号；UnitBase 只提供 `WorldUIRoot` 插槽与一个默认组件实例，不在脚本中依赖 UI。

**Tech Stack:** Godot 4.7、GDScript、SubViewport、ProgressBar、Sprite3D、Tween、SceneTree headless tests。

## Global Constraints

- 不修改 `Scenes/TestScene.tscn` 或 TestScene2 中的任何单位实例。
- 所有字段和方法使用英文标识，新增代码提供详细简体中文注释。
- 不新增配置 `.tres`；血条参数集中在组件根节点 Inspector。
- UnitBase 不得持有或调用 WorldHealthBar。
- 正式场景必须具有可由 ResourceLoader 查询的有效 UID。
- 项目不是 Git 仓库，以 RED/GREEN 输出、文件检查和 MCP 验证作为交付依据。

---

### Task 1: WorldHealthBar 行为组件

**Files:**
- Create: `UnitSystem/Components/UI/WorldHealthBar.gd`
- Create: `UnitSystem/Components/UI/WorldHealthBar.tscn`
- Create: `UnitSystem/Tests/WorldHealthBarTest.gd`

**Interfaces:**
- Consumes: `UnitBase.health_changed`, `UnitBase.damaged`,
  `UnitBase.get_current_health() -> float`,
  `UnitBase.get_maximum_health() -> float`
- Produces:
  `bind_health_source(source: UnitBase) -> void`,
  `unbind_health_source() -> void`,
  `refresh_immediately() -> void`,
  `show_temporarily() -> void`,
  `hide_immediately() -> void`,
  `is_bound() -> bool`

- [ ] **Step 1: 写入失败测试**

测试加载 `WorldHealthBar.tscn`，实例化到真实 `UnitBase` 下，断言初始隐藏、自动绑定、
公开接口、绿条/红条节点和有效 UID。由于场景尚不存在，测试必须以资源缺失失败。

- [ ] **Step 2: 运行测试确认 RED**

```powershell
& $godot --headless --path 'G:\Godot\SipSip' `
  --script 'res://UnitSystem/Tests/WorldHealthBarTest.gd'
```

预期：exit 1，报告 WorldHealthBar 场景不存在。

- [ ] **Step 3: 创建最小场景和脚本**

场景节点严格使用：

```text
WorldHealthBar
├── HealthBarViewport
│   └── BarRoot
│       ├── EmptySlot
│       ├── DamageBar
│       ├── HealthBar
│       └── Border
└── BarSprite
```

脚本实现自动向上查找 UnitBase、信号绑定、两条 Tween、样式配置和公开接口。绿色条
实时变化；红条延迟收缩；只有 `damaged` 调用 `show_temporarily()`。

- [ ] **Step 4: 扩展行为测试**

使用短测试时长验证：

```text
damage -> visible
green -> current ratio immediately
red -> previous ratio then current ratio
healing while hidden -> remains hidden
second damage -> resets visibility timeout
unbind -> later damage does not change bar
```

- [ ] **Step 5: 运行测试确认 GREEN**

运行 `WorldHealthBarTest.gd`，预期 PASS、exit 0、无 orphan/warning。

---

### Task 2: UnitBase 世界 UI 插槽装配

**Files:**
- Modify: `UnitSystem/Base/00_UnitBase.tscn`
- Modify: `UnitSystem/Tests/WorldHealthBarTest.gd`
- Modify: `UnitSystem/Tests/UnitRootConfigurationTest.gd`

**Interfaces:**
- Consumes: `WorldHealthBar.tscn`
- Produces: `UnitBase/WorldUIRoot/WorldHealthBar`

- [ ] **Step 1: 写入失败装配测试**

实例化 `00_UnitBase.tscn`，断言存在 `WorldUIRoot`、默认血条实例，并验证 UnitBase
脚本没有 `world_health_bar`、`show_health_bar` 等反向 UI API。

- [ ] **Step 2: 运行测试确认 RED**

预期：缺少 `WorldUIRoot/WorldHealthBar`。

- [ ] **Step 3: 修改 UnitBase 场景**

在 `Visual` 后增加 `WorldUIRoot: Node3D`，其下实例化
`res://UnitSystem/Components/UI/WorldHealthBar.tscn`。不修改
`00_UnitBase.gd`。

- [ ] **Step 4: 运行装配与回归测试**

```powershell
WorldHealthBarTest.gd
UnitRootConfigurationTest.gd
UnitDeathLifecycleTest.gd
```

预期全部 PASS。

---

### Task 3: 编辑器、资源与文档验证

**Files:**
- Modify: `Docs/CurrentSystemUserGuide.md`
- Modify: `Docs/CurrentProgressReport.md`

**Interfaces:**
- Consumes: 已完成的 WorldHealthBar 组件和测试结果
- Produces: 面向设计师的配置说明与真实验证记录

- [ ] **Step 1: 更新使用指南**

记录组件位置、显示规则、关键 Inspector 参数、如何调整不同角色头顶高度，以及
UnitBase 与 UI 的单向依赖。

- [ ] **Step 2: 更新进度报告**

记录 warning 参数重命名、血条组件、测试和暂缓项。暂缓项仅包括全局血条管理器、
遮挡淡化和团队样式差异。

- [ ] **Step 3: 运行最终验证**

运行新增测试、生命/死亡回归、Godot headless editor scan；通过 MCP reload 后检查：

```text
editor errors = 0
Output 无新增 warning/error
WorldHealthBar.tscn UID 有效
```

- [ ] **Step 4: 自审**

确认未修改 TestScene/TestScene2，未新增 `.tres`，UnitBase 脚本无 UI 依赖，所有
可配置时长均在 Inspector，且文档不预告未实现功能。

