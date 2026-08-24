# 武器普攻仇恨与伤害浮动实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为全部普通攻击加入武器级伤害浮动和仇恨倍率。

**Architecture:** `WeaponData` 只保存两个数值；`CombatValueResolver` 对每次命中一次性计算浮动伤害；玩家和 AI 普攻出口把武器倍率传给现有 EnemyBase 仇恨入口。

**Tech Stack:** Godot 4.7、GDScript、ResourceSaver、SceneTree headless 测试。

## Global Constraints

- 每个 `@export` 参数紧邻简体中文说明。
- 不修改 TestScene 或 TestCombatRoom 的单位实例。
- 修改现有 `.tres` 后通过 Godot `ResourceSaver` 保存，并验证有效 UID。

---

### Task 1: 写入普攻数值契约测试

**Files:**
- Modify: `UnitSystem/Tests/WeaponDataInheritanceTest.gd`
- Modify: `UnitSystem/Tests/BasicAttackDamageIntegrationTest.gd`

- [x] 写入并运行失败测试：WeaponData 必须暴露伤害浮动与普攻仇恨倍率；零浮动保留固定伤害；盾牌和弓拥有指定配置。
- [x] 写入并运行失败测试：对 EnemyBase 的一次普通攻击会以“实际扣血 × 武器倍率”写入仇恨。

### Task 2: 接入统一结算与三条普攻出口

**Files:**
- Modify: `Item/Weapon/WeaponData.gd`
- Modify: `UnitSystem/Combat/CombatValueResolver.gd`
- Modify: `UnitSystem/Components/Combat/PlayerAttackController.gd`
- Modify: `UnitSystem/Components/Combat/AI/AICombatSystem.gd`

- [x] 增加带中文说明的武器数据字段。
- [x] 在统一结算器以单次随机倍率计算普通攻击浮动；默认值为零时保留旧公式。
- [x] 玩家、AI 近战和 AI 远程统一传递武器伤害浮动与普攻仇恨倍率。
- [x] 运行 Task 1 测试至通过。

### Task 3: 保存初始资源值与回归验证

**Files:**
- Modify via ResourceSaver: `Item/Weapon/Shield/IronSieldData.tres`
- Modify via ResourceSaver: `Item/Weapon/Bow/BowData.tres`

- [x] Iron Shield 保存为浮动 5%、普攻仇恨倍率 1.6；Bow 保存为浮动 10%、普攻仇恨倍率 1.0。
- [x] 用 `ResourceLoader.get_resource_uid()` 验证两份资源 UID 有效，强类型加载正确。
- [x] 运行武器继承、普攻伤害、敌方仇恨测试与 Godot 编辑器扫描。
