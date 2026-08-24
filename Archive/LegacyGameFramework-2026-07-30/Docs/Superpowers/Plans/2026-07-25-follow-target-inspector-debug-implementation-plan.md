# Follow Target Inspector Debug Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为伙伴状态机提供只读、非持久化的当前跟随对象 Inspector 调试字段。

**Architecture:** 使用 Godot `_get_property_list()` 和 `_get()` 暴露动态只读属性，直接读取状态机现有 `_player` 运行状态。`set_follow_target()` 仍是唯一写入口，并负责通知 Inspector 刷新。

**Tech Stack:** Godot 4.7、GDScript、项目现有 headless 测试。

## Global Constraints

- 不暴露默认跟随阵营或跟随节点配置。
- 不修改 `Scenes/TestScene.tscn`。
- 调试字段不参与场景存储和运行决策。

---

### Task 1: 只读跟随目标调试字段

**Files:**
- Modify: `UnitSystem/Tests/AllyBehaviorStateMachineTest.gd`
- Modify: `UnitSystem/Components/Behavior/AllyBehaviorStateMachine.gd`

**Interfaces:**
- Consumes: `set_follow_target(target: CharacterBody3D) -> void`
- Produces: Inspector 动态属性 `debug_current_follow_target`

- [x] **Step 1: 写入失败测试**

验证属性列表包含 `debug_current_follow_target`，具有
`PROPERTY_USAGE_READ_ONLY`、不具有 `PROPERTY_USAGE_STORAGE`，并在默认玩家、
显式目标和恢复玩家三种情况下返回实际跟随对象。

- [x] **Step 2: 运行测试并确认 RED**

运行：
`Godot --headless --path G:\Godot\SipSip -s res://UnitSystem/Tests/AllyBehaviorStateMachineTest.gd`

预期：因调试属性尚不存在而失败。

- [x] **Step 3: 实现最小动态 Inspector 属性**

在状态机中实现 `_get_property_list()` 与 `_get()`；属性 usage 仅包含编辑器显示
与只读标记。`set_follow_target()` 更新目标后调用 `notify_property_list_changed()`。

- [x] **Step 4: 运行回归验证**

运行状态机、继承改名、索敌集成测试，再运行 Godot 4.7 headless 编辑器扫描。
预期：全部通过且无脚本错误或警告。
