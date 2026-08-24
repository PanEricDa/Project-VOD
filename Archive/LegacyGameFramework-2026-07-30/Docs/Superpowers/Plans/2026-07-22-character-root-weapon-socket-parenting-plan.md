# CharacterRoot WeaponSocket Parenting Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让 WeaponSocket 成为 CharacterRoot 的正式子节点，并同步所有运行时、动画和工作台引用。

**Architecture:** 保持 HeroVisual 现有节点数量不变，只迁移固定 NodePath。动画关键帧数据原样保留，控制器仍通过无 Inspector 配置的内部约定查找视觉端点。

**Tech Stack:** Godot 4.7、GDScript、AnimationLibrary、PackedScene、SceneTree headless tests。

## Global Constraints

- 不改变用户当前 IronSword 动画时长、关键帧时间或关键帧数值。
- 不修改 PlayerBase 移动、WeaponData、TestScene 或旧战斗系统。
- 不增加导出 NodePath、包装节点或同步脚本。

---

### Task 1: Update hierarchy tests

**Files:**
- Modify: `UnitSystem/Tests/HeroVisualAssemblyTest.gd`
- Modify: `UnitSystem/Tests/PlayerWeaponCombatTest.gd`

- [ ] 断言 `CharacterRoot/WeaponSocket` 存在，旧的根级 `WeaponSocket` 不存在。
- [ ] 测试 rig 与 Hero/Workbench 路径全部改为嵌套路径。
- [ ] 运行测试并确认因旧引用而失败。

### Task 2: Migrate runtime and animation paths

**Files:**
- Modify: `UnitSystem/Combat/PlayerAttackController.gd`
- Modify: `UnitSystem/Players/Hero/Weapons/IronSword/IronSwordAnimations.tres`

- [ ] 控制器内部固定路径改为 `CharacterRoot/WeaponSocket`。
- [ ] 所有 WeaponSocket 动画轨道增加 `CharacterRoot/` 前缀，不改变任何 key 数据。
- [ ] 运行 Hero 和连击测试确认通过。

### Task 3: Align the current workbench

**Files:**
- Modify: `UnitSystem/Players/Hero/HeroAnimationWorkbench.tscn`

- [ ] 将当前 WeaponSocket override、IronSwordVisual 实例和本地 RESET 轨道迁移到新层级。
- [ ] 保留用户当前 Workbench 的动画库命名和其他编辑内容。
- [ ] 运行 Godot 4.7 编辑器扫描与全部 UnitSystem 测试。

## Implementation Result

- Completed: 2026-07-22.
- WeaponSocket runtime path: `CharacterRoot/WeaponSocket`.
- Migrated animation paths: `10`; remaining old root-level WeaponSocket animation paths: `0`.
- Preserved current animation lengths: `0.5 / 0.56666666 / 0.7s`.
- UnitSystem tests: `11/11` passed.
- Godot 4.7 editor scan: `0` problems.
- Headless runtime scan: `0` problems.
