# HolyLight Combat Presentation Fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox syntax for tracking.

**Goal:** 修复 HolyLight 施法朝向、目标特效锚点和 Priest 普攻策略。

**Architecture:** SkillBase 负责通用表现锚点，行为状态机负责动作目标朝向和策略仲裁，具体技能与场景实例只保存配置。

**Tech Stack:** Godot 4.7、GDScript、现有 SkillSystem 与 UnitSystem。

## Global Constraints

- 不新增 HolyLight 专用算法分支。
- 不修改 `Scenes/TestScene.tscn`。
- 新增代码使用英文标识和简体中文注释。

---

### Task 1: Release 表现锚点

- [x] 在 `SingleSceneHolyLightTest.gd` 中先验证特效必须生成在治疗目标。
- [x] 确认测试因特效仍位于动作发射点而失败。
- [x] 在 `SkillBase.gd` 增加通用锚点枚举并为 HolyLight 配置目标锚点。
- [x] 确认 HolyLight 与 Firebolt 测试通过。

### Task 2: 技能目标朝向与动作策略

- [x] 新增运行测试，验证 BASIC_ONLY 不自动施法。
- [x] 通过运行诊断确认技能数据目标与施法朝向均为友方，错误来自表现锚点。
- [x] 确认 BASIC_ONLY 测试在当前实现下失败。
- [x] 修正状态机策略判断；保留已经正确工作的技能动作朝向链路。
- [x] 确认相关测试通过。

### Task 3: 场景实例和回归

- [x] 添加 TestScene2 Priest 策略契约测试并确认旧覆盖导致失败。
- [x] 将现有 Priest 实例策略修正为 2。
- [x] 运行完整相关测试、Godot 编辑器扫描和 MCP Output 检查。
