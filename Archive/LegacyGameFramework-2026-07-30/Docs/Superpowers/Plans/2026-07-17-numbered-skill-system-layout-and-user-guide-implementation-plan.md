# 编号化技能系统目录与使用说明实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将独立技能系统迁移到连续编号目录，并交付一份可按编号完成新技能配置与角色装配的简明中文使用说明。

**Architecture:** 保留所有脚本、场景、资源及 `.uid` 的内容与职责，只移动目录并更新项目内的 `res://SkillSystem/...` 引用。使用一个编号布局自动测试锁定最终结构，再通过完整 SkillSystem、HolyLight、Firebolt、Mage2 和 Godot 编辑器扫描验证迁移没有改变运行行为。

**Tech Stack:** Godot 4.7、GDScript、PackedScene、Resource、PowerShell、SceneTree headless tests、SHA-256。

## Global Constraints

- 不修改或添加 `res://Scenes/TestScene.tscn` 中的任何单位实例。
- 不改变技能、Host、Delivery、Payload 或 AI 请求桥的运行逻辑与默认参数。
- 保留并随文件移动全部 `.uid` 文件。
- 不创建旧路径兼容副本、符号链接或重复脚本。
- 项目不是 Git 仓库；使用项目外压缩备份和文件哈希作为回滚依据。
- 已知旧 `MageSkillAssemblyTest.gd` 可能因 `Mage.ranger_path` 当前为 `../Mage2` 而与旧预期 `../Ranger` 不一致；不得把该既有差异误判为本次迁移回归。

---

### Task 1: 基线、备份与编号布局 RED 测试

**Files:**
- Create externally: `G:/Godot/SipSip_MigrationBackups/2026-07-17-pre-numbered-skill-layout.zip`
- Create externally: `G:/Godot/SipSip_MigrationBackups/2026-07-17-pre-numbered-skill-layout.sha256.txt`
- Create: `SkillSystem/Tests/SkillSystemNumberedLayoutTest.gd`

**Interfaces:**
- Consumes: 当前未编号目录和 Godot 4.7 测试入口。
- Produces: 可回滚备份、迁移前哈希、明确要求新编号路径存在且旧路径消失的失败测试。

- [ ] 记录 `Scenes/TestScene.tscn`、`Scenes/ObjectScenes/AllyBase.tscn`、`Scenes/ObjectScenes/Healer.tscn`、`Scenes/ObjectScenes/Mage2.tscn` 的 SHA-256。
- [ ] 在项目外创建排除 `.godot` 的源码压缩备份和 SHA-256 清单。
- [ ] 运行全部 `SkillSystem/Tests/*.gd` 以及 HolyLight、Firebolt、Mage2 关键集成测试，记录迁移前结果。
- [ ] 创建编号布局测试，检查 `00-Skills` 至 `11-Tests`、Delivery 子目录、Core/Firebolt/HolyLight 资源和主说明文件。
- [ ] 运行编号布局测试，要求因 `01-Core` 等新目录尚不存在而退出 `1`。

### Task 2: 一次性编号目录迁移与引用更新

**Files:**
- Move: `SkillSystem/Core` → `SkillSystem/01-Core`
- Move: `SkillSystem/Conditions` → `SkillSystem/02-Conditions`
- Move: `SkillSystem/Targeting` → `SkillSystem/03-Targeting`
- Move: `SkillSystem/Decisions` → `SkillSystem/04-Decisions`
- Move: `SkillSystem/Costs` → `SkillSystem/05-Costs`
- Move: `SkillSystem/Presentation` → `SkillSystem/06-Presentation`
- Move: `SkillSystem/Delivery` → `SkillSystem/07-Delivery`
- Move: `SkillSystem/Payloads` → `SkillSystem/08-Payloads`
- Move: `SkillSystem/Presets` → `SkillSystem/09-Presets`
- Move: `SkillSystem/Docs` → `SkillSystem/10-Docs`
- Move: `SkillSystem/Tests` → `SkillSystem/11-Tests`
- Move: `SkillSystem/07-Delivery/Agents` → `SkillSystem/07-Delivery/00-Agents`
- Move: `SkillSystem/07-Delivery/Trajectories` → `SkillSystem/07-Delivery/01-Trajectories`
- Move: `SkillSystem/07-Delivery/Collisions` → `SkillSystem/07-Delivery/02-Collisions`
- Move: `SkillSystem/07-Delivery/Impacts` → `SkillSystem/07-Delivery/03-Impacts`
- Modify mechanically: all project `.gd`, `.tscn`, `.tres`, and `.md` files containing old `res://SkillSystem/...` paths

**Interfaces:**
- Consumes: Task 1 失败测试和完整旧路径映射。
- Produces: 单一编号路径体系，全部运行资源和测试改用新路径。

- [ ] 验证所有移动源位于 `G:/Godot/SipSip/SkillSystem` 且目标不存在。
- [ ] 先移动 Delivery 子目录，再移动全部顶层目录，保留原文件名与 `.uid`。
- [ ] 按最长路径优先批量替换所有旧 `res://SkillSystem/...` 引用。
- [ ] 扫描旧运行路径，要求 `.gd`、`.tscn`、`.tres` 中无旧目录引用。
- [ ] 运行迁移后的 `res://SkillSystem/11-Tests/SkillSystemNumberedLayoutTest.gd`，要求结构部分转绿；主说明文件将在 Task 3 创建。
- [ ] 运行全部 `11-Tests`，修复任何纯路径迁移错误，不改变运行逻辑。

### Task 3: 简明使用说明与入口文档

**Files:**
- Create: `SkillSystem/10-Docs/SkillSystemUserGuide.md`
- Rewrite: `SkillSystem/README.md`
- Modify: `SkillSystem/10-Docs/Architecture.md`
- Modify: `SkillSystem/10-Docs/ExtensionPoints.md`
- Modify: `SkillSystem/10-Docs/InspectorAssemblyGuide.md`
- Modify mechanically: moved historical SkillSystem documents containing old paths

**Interfaces:**
- Consumes: 最终编号目录与 HolyLight、Firebolt 的真实 Inspector 配置。
- Produces: 可独立完成新技能三文件创建、Definition/Delivery 配置、Host 装配和 AI 自动请求的中文说明。

- [ ] 编写五分钟快速开始和 `00` 至 `11` 目录地图。
- [ ] 以九步主流程说明标准三文件技能创建与装配。
- [ ] 提供 Inspector 字段到编号目录的精确映射表。
- [ ] 提供基础瞬发、HolyLight 和 Firebolt 三类示例。
- [ ] 说明何时只需 Inspector、何时新增通用脚本、何时新增投射物脚本。
- [ ] 说明 Node3D SkillHost/SkillSocket、世界空间 DeliverySocket、直接子节点自动发现、Faction/Health 依赖、冷却和 AI 请求桥注意事项。
- [ ] 将 README 改为简短入口并链接主说明、架构和扩展点。
- [ ] 运行编号布局测试，要求主说明存在且所有检查通过。

### Task 4: 全量验证与交付核对

**Files:**
- Verify: `SkillSystem/00-Skills/HolyLight/*`
- Verify: `SkillSystem/00-Skills/Firebolt/*`
- Verify: `Scenes/ObjectScenes/AllyBase.tscn`
- Verify: `Scenes/ObjectScenes/Healer.tscn`
- Verify: `Scenes/ObjectScenes/Mage2.tscn`
- Verify unchanged: `Scenes/TestScene.tscn`

**Interfaces:**
- Consumes: 编号目录、更新后的全部引用和使用说明。
- Produces: Godot 4.7 可加载、测试通过、TestScene 未变化的迁移结果。

- [ ] 运行全部 `SkillSystem/11-Tests/*.gd`。
- [ ] 运行 `Mage2FireboltAssemblyTest.gd`、`HealerHolyLightAutoSkillTest.gd`、`AllySkillRequestBridgeTest.gd`、`AllyIndependentSkillMovementTest.gd` 和 `AllyIndependentSkillHostAssemblyTest.gd`。
- [ ] 运行旧 Fireball Skill、Projectile 和 Cast Effect 回归测试。
- [ ] 执行 Godot 4.7 `--headless --editor --quit` 编辑器扫描。
- [ ] 扫描旧目录名和断开的 `res://SkillSystem` 引用。
- [ ] 对比迁移前后 `TestScene.tscn` SHA-256，要求完全相同。
- [ ] 列出最终编号目录和主说明文件，记录已知旧 Mage 测试差异但不修改其场景配置。
