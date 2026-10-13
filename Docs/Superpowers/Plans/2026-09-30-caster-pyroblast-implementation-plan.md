# Caster 炎爆术 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为 Caster 装配可自动施放的炎爆术：一次释放前锁定主要目标及所有灼烧敌人，同帧向每人发射一枚单体投射物，命中后消耗灼烧。

**Architecture:** 沿用 `SkillBase`、`SkillHost`、`ArcProjectileDeliveryConfig/Session` 和现有命中 Effect 管线。新增可配置的状态目标查询资源，交付会话保存投射物到目标的映射；状态消耗和 AI 门槛各作为通用 Effect/Condition 子节点。

**Tech Stack:** Godot 4.7.1、GDScript、`.tscn` 场景、`SceneTree` headless 测试。

**Spec:** `Docs/Superpowers/Specs/2026-09-30-caster-pyroblast-design.md`

## Global Constraints

- 现有工作区有未提交的 RapidShot、Firebolt 8 秒灼烧及用户场景改动；保留它们，不清理或覆盖。
- 每个新增/修改的 `@export`、公开方法及信号遵循 AGENTS.md 的紧邻简体中文说明规范。
- 不向 `res://Scenes/TestScene.tscn` 添加或修改单位实例。
- 不新建正式 `.tres/.res`；目标查询作为技能场景内嵌 Resource 配置。
- 每项代码按 RED→GREEN 执行；结束时跑项目全部可独立运行的 `SceneTree` 测试。

## Review Focus

- 主要目标已有灼烧时仍只获一枚投射物：Task 2/4 测试去重。
- 目标在齐射后死亡、离树或失去灼烧：Task 2/4 测试独立终结，不拖住其他投射物。
- 同步命中/退出与多枚同帧发射：Task 2 测试不会覆盖会话或漏记命中。
- 无 EncounterController 的独立测试场景：Task 2/3 测试仍可查询同一战斗场景中的合法敌人。
- 自动 AI 条件与显式指令不能互相污染：Task 3/4 测试两条入口。

---

### Task 1: 通用命名状态移除效果

**Files:**
- Modify: `UnitSystem/Components/Status/StatusEffectComponent.gd`
- Create: `SkillSystem/03-Extensions/ConsumeNamedStatusSkillEffect.gd`
- Test: `UnitSystem/Tests/StatusEffectComponentTest.gd`
- Create: `SkillSystem/05-Tests/ConsumeNamedStatusSkillEffectTest.gd`

**Interfaces:**
- Produces: `StatusEffectComponent.remove_named_status(status_id: StringName) -> bool`；`ConsumeNamedStatusSkillEffect.status_id: StringName`，`apply(context: SkillContext, result: SkillDeliveryResult, target: Node3D) -> bool`。

- [ ] **Step 1:** 测试先断言按 ID 移除只影响该状态、发送一次 `named_status_changed(id, false)`、重复移除安全；Effect 在有效单体命中时移除配置状态，无状态时不让交付失败。
- [ ] **Step 2:** 分别运行两个测试，确认因缺少接口/脚本而失败。
- [ ] **Step 3:** 实现上述两个接口及中文参数文档，不增加灼烧特例。
- [ ] **Step 4:** 复跑两个测试并确认 PASS。

### Task 2: 释放前目标快照与同帧多目标 Arc 交付

**Files:**
- Create: `SkillSystem/02-Delivery/SkillTargetExpansion.gd`
- Create: `SkillSystem/02-Delivery/MarkedHostileTargetExpansion.gd`
- Modify: `SkillSystem/02-Delivery/ArcProjectileDeliveryConfig.gd`
- Modify: `SkillSystem/02-Delivery/ArcProjectileDeliverySession.gd`
- Create: `SkillSystem/05-Tests/MarkedTargetVolleyTest.gd`
- Existing regressions: `SkillSystem/05-Tests/MultiShotArcDeliveryTest.gd`, `SkillSystem/05-Tests/ExplosiveArrowChainIntegrationTest.gd`

**Interfaces:**
- Produces: `SkillTargetExpansion.select_targets(context: SkillContext, primary: UnitBase) -> Array[UnitBase]`；`MarkedHostileTargetExpansion.marked_targets(context: SkillContext) -> Array[UnitBase]`，`status_id: StringName`；`ArcProjectileDeliveryConfig.target_expansion: SkillTargetExpansion`，默认空即原单目标连射。
- Consumes: Task 1 的状态查询/移除契约；Arc 投射物现有 `launch(UnitBase, Vector3) -> bool` 与 `projectile_hit` 信号。

- [ ] **Step 1:** 写测试覆盖 0/1/多灼烧目标、主要目标去重、释放前状态快照、全部投射物同帧启动、每枚独立单体命中、死亡和同步回调，以及旧 `shot_count` 连射语义。
- [ ] **Step 2:** 运行新测试，确认缺少查询类/多目标行为而失败。
- [ ] **Step 3:** 实现查询与会话映射；只在有扩展配置时额外筛选，`shot_count` 表示每个目标发射次数，Pyro 配 1；不改变 Runner 对其它 Delivery 的调度。
- [ ] **Step 4:** 新测试与两个旧回归 PASS。

### Task 3: AI 自动施放的灼烧数量门槛

**Files:**
- Create: `SkillSystem/03-Extensions/Conditions/MarkedHostileCountCondition.gd`
- Create: `SkillSystem/05-Tests/MarkedHostileCountConditionTest.gd`

**Interfaces:**
- Consumes: Task 2 的 `MarkedHostileTargetExpansion.marked_targets(context)`。
- Produces: `MarkedHostileCountCondition.target_query: MarkedHostileTargetExpansion`、`minimum_count: int = 2`；继承 `SkillConditionBase`，默认 `AUTOMATIC_ONLY`。

- [ ] **Step 1:** 写失败测试：0/1 灼烧目标拒绝 AI，2 个接受，显式请求跳过条件，过期/死亡目标不计数。
- [ ] **Step 2:** 跑测试确认 RED。
- [ ] **Step 3:** 实现通用条件及 Inspector 中文文档。
- [ ] **Step 4:** 复跑条件和既有 `TargetHealthCondition` 测试，确认 PASS。

### Task 4: 炎爆场景、Caster 第二槽和战斗集成

**Files:**
- Create: `Item/Projectiles/PyroblastProjectile.tscn`
- Create: `SkillSystem/00-Skills/Pyroblast/PyroblastSkill.tscn`
- Modify: `UnitSystem/AI/Ally/Units/Caster.tscn`
- Create: `SkillSystem/05-Tests/PyroblastAssemblyTest.gd`
- Create: `SkillSystem/05-Tests/PyroblastIntegrationTest.gd`
- Modify: `UnitSystem/Tests/CharacterSkillSlotAssemblyTest.gd`
- Modify: `SkillSystem/04-Docs/SkillSystemUserGuide.md`

**Interfaces:**
- Consumes: Tasks 1–3；新投射物复用 `TrackingArcProjectile.gd`，仅视觉和飞行配置不同。

- [ ] **Step 1:** 失败装配与真实交付测试：Caster 两槽、1.2 秒施法、6 秒冷却、优先于 Firebolt、AI 门槛；主目标及每个灼烧敌人各一枚、无范围溅射、实际命中才消耗状态，单一投射物失败不取消其余命中。
- [ ] **Step 2:** 跑新测试确认 RED。
- [ ] **Step 3:** 创建技能/投射物场景并装配 `HealthChangeSkillEffect`、`ConsumeNamedStatusSkillEffect`、状态目标策略、条件；单枚伤害初测配置为基础 20 + 攻击力 × 1.25（高于 Firebolt 的 10 + 攻击力 × 1）。Caster 第二槽指向新技能，保留现有 Firebolt 覆写。
- [ ] **Step 4:** 跑新测试、Firebolt、Arc 连射、Archer 连锁回归并检查新 `.tscn` UID 可被编辑器索引。
- [ ] **Step 5:** 更新技能使用文档；全项目可独立启动的 `SceneTree` 测试零失败，记录其余非入口辅助脚本。

## 收尾

只把本任务文件纳入提交；不夹带用户其他未提交改动。为技能与投射物提供编辑器可见场景，供用户在当前测试场景自行观察；不修改 `TestScene.tscn` 的实例。

## 实施记录

- 2026-09-30：状态移除、目标快照、同帧多目标 Arc、AI 软条件及 Caster 技能场景均已实现。
- Godot 4.7.1 编辑器头less 扫描成功；105 个可独立运行的 `SceneTree` 测试全部通过。`RangedAttackPipelineTest.gd` 是非 `SceneTree` 入口脚本，不纳入逐文件启动列表。
- 原工作区已有 RapidShot 等未提交改动，Arc 配置和会话与它们共用文件；为避免把既有改动误归到本任务，本次除通用状态移除的独立提交外暂不提交重叠文件，也未推送 GitHub。
