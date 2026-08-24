# Pack 协同开战实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Pack 内任意敌人进入战斗时，全部存活成员立即协同攻击同一有效目标。

**Architecture:** AITargetingComponent 保存经验证的运行时协同目标；EnemyBase 提供包装接口；EncounterController 仅在 Pack 首次进入战斗时广播，重置和清除时统一撤销。

**Tech Stack:** Godot 4.7、GDScript、SceneTree 测试。

## Global Constraints

- 不修改 TestScene 中单位实例。
- 不写入仇恨表或新增仇恨结算标准。
- 新增公开接口提供紧邻简体中文说明。

---

### Task 1: 受验证的协同目标接口

**Files:** `AITargetingComponent.gd`、`EnemyBase.gd`、相关契约测试。

- [ ] 先写失败测试：EnemyBase 可接受有效敌对目标、拒绝无效/友方目标、撤销后不保留覆盖。
- [ ] 实现 Targeting 运行时协同覆盖与 EnemyBase 包装接口。
- [ ] 运行目标组件和敌人测试。

### Task 2: Pack 广播与撤销

**Files:** `EncounterController.gd`、`EncounterControllerTest.gd`。

- [ ] 先写失败测试：Pack A 一名敌人进入战斗后，Pack A 全部成员锁定同一目标，Pack B 不受影响；reset 后覆盖清除。
- [ ] 在首次 `IN_COMBAT` 信号广播有效目标，避免递归重复；在 reset/clear 清除覆盖。
- [ ] 运行遭遇控制器、敌人行为与编辑器扫描。
