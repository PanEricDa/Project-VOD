# Guardian 盾击技能特效实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 创建可配置、可循环预览的 Guardian 盾击技能单场景特效。

**Architecture:** 特效场景作为一次性 `Node3D` 表现，仅以自身局部坐标制作前方冲击弧与地面防御环。脚本只管理播放、复位、参数写入和生命周期；预览场景负责循环展示。

**Tech Stack:** Godot 4.7、GDScript、AnimationPlayer、MeshInstance3D、StandardMaterial3D。

## Global Constraints

- 新增 `@export` 参数必须有紧邻的简体中文说明。
- 不修改 `Scenes/TestScene.tscn`，不自动添加单位实例。
- 特效不得承担 Hitbox、伤害、仇恨或 Buff 算法。

---

### Task 1: 场景契约测试

**Files:**
- Create: `Effects/Skills/GuardianShield/GuardianShieldSkillEffectTest.gd`

- [x] **Step 1: 写入失败测试**：验证正式场景、Preview 场景、`ShieldArc`、`DefenseRing`、`AnimationPlayer` 与 `play/stop` 接口。
- [x] **Step 2: 运行测试并确认因场景不存在失败。**
- [x] **Step 3: 创建最小正式场景、脚本与 Preview 场景。**
- [x] **Step 4: 重跑测试并确认通过。**

### Task 2: 播放与编辑器验证

**Files:**
- Create: `Effects/Skills/GuardianShield/GuardianShieldSkillEffect.tscn`
- Create: `Effects/Skills/GuardianShield/GuardianShieldSkillEffect.gd`
- Create: `Effects/Skills/GuardianShield/GuardianShieldSkillEffectPreview.tscn`
- Create: `Effects/Skills/GuardianShield/GuardianShieldSkillEffectPreview.gd`

- [x] **Step 1: 实现 0.5 秒冲击弧和防御环动画。**
- [x] **Step 2: 在 Preview 中按完成信号循环重播。**
- [x] **Step 3: 运行特效契约测试与 Godot 编辑器扫描。**
