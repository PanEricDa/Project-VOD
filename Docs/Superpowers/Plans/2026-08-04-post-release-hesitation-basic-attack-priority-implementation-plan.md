# 技能释放后犹豫与普攻优先级实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 技能释放后的随机犹豫不再阻止可普攻单位在共享行动冷却结束后恢复普攻。

**Architecture:** `SkillHostComponent` 提供一个只表达“当前技能动作是否仍在执行”的查询接口。`AllyBehaviorStateMachine` 仅以该接口决定是否让出普攻链路；技能的犹豫和独立冷却继续由 `SkillBase` 自己维护。

**Tech Stack:** Godot 4.7、GDScript、现有 SceneTree 契约测试。

## Global Constraints

- 所有新增公开接口和可配置参数均提供紧邻的简体中文说明。
- 不修改 `TestScene` 中任何单位实例。
- 不创建新的外部 Godot Resource。

---

### Task 1: 为技能动作占用状态建立契约测试

**Files:**
- Modify: `SkillSystem/05-Tests/SingleSceneSkillHostTest.gd`

**Interfaces:**
- Consumes: `SkillHostComponent.get_active_skill()` 和真实 `SkillBase` 释放生命周期。
- Produces: 对 `is_active_skill_action_in_progress() -> bool` 的回归约束。

- [x] **Step 1: 写入失败测试**

在技能请求后断言 Host 返回 `true`，在 `release_active_action()` 成功后、`finish_active_action()` 前断言返回 `false`。

- [x] **Step 2: 运行测试确认失败**

Run: `& 'G:\Godot\Godot_v4.7.1-stable_win64_console.exe' --headless -s res://SkillSystem/05-Tests/SingleSceneSkillHostTest.gd`

Expected: FAIL，因为公开查询接口尚不存在。

- [x] **Step 3: 最小实现接口与行为状态机调用**

在 `SkillHostComponent` 中把 `QUEUED`、`ACTION_REQUESTED`、`CASTING` 归为动作占用；在 `AllyBehaviorStateMachine` 中改用该接口，令释放后犹豫返回到普通攻击链路。

- [x] **Step 4: 运行契约与行为测试**

Run: `SingleSceneSkillHostTest.gd`、`AllyBehaviorStateMachineTest.gd`、`AllySkillCombatPolicyTest.gd`。

- [x] **Step 5: 编辑器扫描**

Run: `& 'G:\Godot\Godot_v4.7.1-stable_win64_console.exe' --headless --editor --quit`

Expected: exit code 0 且无脚本解析错误。
