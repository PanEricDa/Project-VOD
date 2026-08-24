# 玩家锁定仇恨提示实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为玩家锁定的敌人提供 125% 仇恨切换缓冲和无侵入的血条外框提示。

**Architecture:** 仇恨组件统一执行切换缓冲并提供只读快照；PlayerBase 的只读提示控制器把状态传给已有世界血条。提示层不写入 AI 或仇恨数据。

**Tech Stack:** Godot 4.7、GDScript、现有 UnitBase/WorldHealthBar/EnemyThreatComponent。

## Global Constraints

- 不自动修改 `Scenes/TestScene.tscn` 的单位实例。
- 所有新增 `@export`、公共方法与信号均提供紧邻简体中文说明。
- 不创建正式 `.tres` 或 `.res` 外部资源。
- 项目不是 Git 仓库，不创建提交。

---

### Task 1: 仇恨缓冲与只读快照

**Files:**
- Modify: `UnitSystem/Components/Threat/EnemyThreatComponent.gd`
- Modify: `UnitSystem/Tests/EnemyThreatComponentTest.gd`

- [x] 先添加断言：125% 以内保留当前目标、超过 125% 切换、清表会通知、快照不暴露内部字典。
- [x] 运行 `EnemyThreatComponentTest.gd` 确认新增断言失败。
- [x] 最小化实现目标切换缓冲、快照和清表信号。
- [x] 重跑该测试确认通过。

### Task 2: 血条外框视觉接口

**Files:**
- Modify: `UnitSystem/Components/UI/WorldHealthBar.tscn`
- Modify: `UnitSystem/Components/UI/WorldHealthBar.gd`
- Modify: `UnitSystem/Tests/WorldHealthBarTest.gd`

- [x] 添加断言：默认无外框、黄色/红色状态可设置、清除后隐藏。
- [x] 运行 `WorldHealthBarTest.gd` 确认失败。
- [x] 增加不影响生命条显示逻辑的外框绘制层与有限公开接口。
- [x] 重跑该测试确认通过。

### Task 3: 玩家仇恨焦点控制器

**Files:**
- Create: `UnitSystem/Components/UI/PlayerThreatFocusController.gd`
- Create: `UnitSystem/Components/UI/PlayerThreatFocusController.tscn`
- Modify: `UnitSystem/Player/PlayerBase.tscn`
- Create: `UnitSystem/Tests/PlayerThreatFocusControllerTest.gd`
- Modify: `UnitSystem/Debug/Threat/ThreatDebugDisplay.gd`
- Modify: `UnitSystem/AI/Enemy/EnemyBase.tscn`

- [x] 添加集成断言：只读取玩家锁定敌人、红色当前目标、黄色风险目标、解锁和清表均清除。
- [x] 运行新测试确认失败。
- [x] 实现控制器，装配到 PlayerBase，并令头顶仇恨文本默认关闭且能响应清表。
- [x] 重跑集成测试及相关既有仇恨测试。

### Task 4: 编辑器与运行验证

**Files:**
- Modify: `Docs/Superpowers/Specs/2026-08-03-player-threat-focus-design.md`

- [x] 运行仇恨、血条、焦点控制器测试。
- [x] 运行 Godot 4.7 headless editor scan。
- [x] 在设计文档记录验证命令和结果。
