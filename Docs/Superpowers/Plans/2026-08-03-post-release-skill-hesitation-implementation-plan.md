# 技能释放后犹豫实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 AI 技能的随机犹豫从请求前迁移到成功释放后，并保证普通攻击与公共冷却不被阻塞。

**Architecture:** `SkillHostComponent` 立即提交自动技能请求；`SkillBase` 新增释放后等待状态并独占其计时。等待结束后调用既有冷却入口，保持 Delivery、伤害和动画接口不变。

**Tech Stack:** Godot 4.7、GDScript、既有 SceneTree headless 契约测试。

## Global Constraints

- 所有新增或变更的 `@export` 参数必须紧邻简体中文说明。
- 不修改 `Scenes/TestScene.tscn` 或 `Scenes/TestCombatRoom.tscn` 的单位实例。
- 不创建新的正式外部 Resource。

---

### Task 1: 释放后等待契约测试

**Files:**
- Modify: `SkillSystem/05-Tests/SingleSceneSkillBaseTest.gd`
- Test: `SkillSystem/05-Tests/SingleSceneSkillBaseTest.gd`

- [x] **Step 1: 写入失败测试**

建立一次即时交付技能：设置 `decision_delay_min/max = 0.5`、额外犹豫关闭、冷却为 `3.0`。断言成功 `release_action()` 后：状态不是 `READY`、冷却为零、尚未发送 `cooldown_started`；物理推进 `0.5s` 后：状态为 `COOLDOWN`、冷却为 `3.0`。

- [x] **Step 2: 运行并确认失败**

Run: `G:\Godot\Godot_v4.7.1-stable_win64_console.exe --headless --path G:\Godot\SipSip -s res://SkillSystem/05-Tests/SingleSceneSkillBaseTest.gd`

Expected: FAIL，因为当前成功释放会立即开始冷却。

- [x] **Step 3: 补充 Host 首发无前置等待失败测试**

在 `SingleSceneSkillHostTest.gd` 将自动技能的等待数值设为非零，断言 `request_best_skill()` 同帧令 SkillBase 进入 `QUEUED/ACTION_REQUESTED`，而不是仅由 Host 保存 pending 请求。

- [x] **Step 4: 运行并确认失败**

Run: `G:\Godot\Godot_v4.7.1-stable_win64_console.exe --headless --path G:\Godot\SipSip -s res://SkillSystem/05-Tests/SingleSceneSkillHostTest.gd`

Expected: FAIL，因为当前 Host 在请求前等待。

### Task 2: 迁移运行时等待职责

**Files:**
- Modify: `SkillSystem/01-Core/SkillBase.gd`
- Modify: `SkillSystem/01-Core/SkillHostComponent.gd`

- [x] **Step 1: 在 SkillBase 增加释放后状态与计时**

添加 `POST_RELEASE_HESITATION` 状态、`_post_release_hesitation_remaining`，以及公开只读查询 `get_post_release_hesitation_remaining()`。成功 Delivery 启动后计算一次常规随机等待与可选额外等待；等待结束后调用既有 `_start_cooldown()`。

- [x] **Step 2: 更新 Inspector 说明**

把五个 AI Usage 字段的简体中文说明改成“成功释放后的等待”，明确它们不再延迟首发施法、也不占用公共冷却。

- [x] **Step 3: 移除 Host 的前置随机等待**

让 `_begin_decision()` 直接调用 `_activate_pending_request()`；删除 `_decision_wait_remaining`、`_calculate_decision_delay()` 及其物理帧分支。Host 仍保持活动技能直到动作释放/取消的既有生命周期。

- [x] **Step 4: 运行两项契约测试确认通过**

Run both Task 1 commands.

Expected: PASS。

### Task 3: 回归验证与文档同步

**Files:**
- Modify: `SkillSystem/04-Docs/SkillTemplateAndDeliveryWorkflow.md`

- [x] **Step 1: 更新使用说明**

将 AI Usage 章节改为“首发立即施放、成功释放后随机犹豫、犹豫后开始技能冷却”，注明普通攻击可由单位行为层在期间填充。

- [x] **Step 2: 运行相关回归测试**

Run:
`G:\Godot\Godot_v4.7.1-stable_win64_console.exe --headless --path G:\Godot\SipSip -s res://SkillSystem/05-Tests/SingleSceneSkillBaseTest.gd`

`G:\Godot\Godot_v4.7.1-stable_win64_console.exe --headless --path G:\Godot\SipSip -s res://SkillSystem/05-Tests/SingleSceneSkillHostTest.gd`

`G:\Godot\Godot_v4.7.1-stable_win64_console.exe --headless --path G:\Godot\SipSip -s res://UnitSystem/Tests/RepeatedSkillCastingLifecycleTest.gd`

- [x] **Step 3: 编辑器扫描**

Run: `G:\Godot\Godot_v4.7.1-stable_win64_console.exe --headless --path G:\Godot\SipSip --editor --quit`

Expected: 退出码 0，且没有由本次改动引入的脚本解析错误。
