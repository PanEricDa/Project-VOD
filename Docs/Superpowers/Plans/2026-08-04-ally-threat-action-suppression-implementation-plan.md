# 友方仇恨行动节流实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让非坦克友方以与相对仇恨连续关联的概率，同时节流自动技能与普通攻击。

**Architecture:** 敌方本地仇恨组件提供只读竞争者比率；UnitBase 提供每单位的 125% 概率配置；友方行为状态机在所有自动行动共同上游掷骰，并以已有共享行动冷却完成一次暂缓。

**Tech Stack:** Godot 4.7、GDScript、现有 SceneTree 契约测试。

## Global Constraints

- 每个新增 `@export`、公开方法与输入参数都提供紧邻简体中文说明。
- 不修改 `TestScene` 中的单位实例。
- 不新增外部 `.tres` 或 `.res` 资源。
- 仇恨数值继续只通过 `EnemyThreatComponent.submit_threat()` 统一结算。

---

### Task 1: 仇恨竞争者比率与单位配置契约

**Files:**
- Modify: `UnitSystem/Tests/EnemyThreatComponentTest.gd`
- Modify: `UnitSystem/Tests/UnitRootConfigurationTest.gd`
- Modify: `UnitSystem/Components/Threat/EnemyThreatComponent.gd`
- Modify: `UnitSystem/Base/00_UnitBase.gd`
- Modify: `UnitSystem/AI/Ally/Units/Guardian.tscn`

**Interfaces:**
- Produces: `EnemyThreatComponent.get_threat_ratio_against_highest_competitor(source: UnitBase) -> float`。
- Produces: `UnitBase.threat_action_suppression_at_125: float`。

- [x] **Step 1: 写失败测试**

以真实本地仇恨表验证：120 对 100 返回 1.2；没有其他竞争者返回 0；UnitBase 默认值为 0.7 且 Guardian 覆盖为 0。

- [x] **Step 2: 运行失败测试**

Run: `& 'G:\Godot\Godot_v4.7.1-stable_win64_console.exe' --headless -s res://UnitSystem/Tests/EnemyThreatComponentTest.gd`

Expected: FAIL，因为竞争者比率接口和单位配置尚不存在。

- [x] **Step 3: 最小实现**

在 `EnemyThreatComponent` 只读扫描已清理的记录，排除传入来源并返回最高其他来源；在 UnitBase 加入有说明的概率字段；Guardian 源场景覆盖为 0。

- [x] **Step 4: 运行契约测试**

Run: `EnemyThreatComponentTest.gd`、`UnitRootConfigurationTest.gd`。

### Task 2: 统一行动许可门

**Files:**
- Modify: `UnitSystem/Tests/AllyBehaviorStateMachineTest.gd`
- Modify: `UnitSystem/Components/Behavior/AllyBehaviorStateMachine.gd`

**Interfaces:**
- Consumes: Task 1 的竞争者比率和 `threat_action_suppression_at_125`。
- Produces: 纯函数式概率计算与技能、普攻共享的行动许可判定。

- [x] **Step 1: 写失败测试**

验证 0 配置产生 0 概率，0.7 配置在 125% 返回 0.7、150% 高于 0.7 且低于 0.9；无竞争者不节流。

- [ ] **Step 2: 运行失败测试**

Run: `& 'G:\Godot\Godot_v4.7.1-stable_win64_console.exe' --headless -s res://UnitSystem/Tests/AllyBehaviorStateMachineTest.gd`

Expected: FAIL，因为状态机尚未公开概率计算接口。

- [x] **Step 3: 最小实现**

将自动行动链路重排为“共享冷却就绪 → 仇恨许可 → 自动技能 → 技能策略阻止判断 → 普攻”。许可失败时启动已有共享行动冷却并继续战斗游荡。

- [x] **Step 4: 运行状态机和技能策略测试**

Run: `AllyBehaviorStateMachineTest.gd`、`AllySkillCombatPolicyTest.gd`、`SingleSceneSkillHostTest.gd`。

### Task 3: 全量验证

**Files:**
- Modify: 本计划的完成复选框。

- [x] **Step 1: 运行技能与战斗生命周期回归**

Run: `RepeatedSkillCastingLifecycleTest.gd`、`SkillApproachRecoveryTest.gd`、`BasicAttackDamageIntegrationTest.gd`。

- [x] **Step 2: 运行 Godot 编辑器扫描**

Run: `& 'G:\Godot\Godot_v4.7.1-stable_win64_console.exe' --headless --editor --quit`

Expected: exit code 0，且无脚本解析错误。
