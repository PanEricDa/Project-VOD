# Player Combat Hit Feedback Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 PlayerBase 的统一 Effects 插槽中复用旧 HitFeedbackBridge，为新玩家攻击系统增加局部卡刀和摄像机震动。

**Architecture:** `PlayerAttackController.attack_hit` 继续作为统一输入；旧 `HitFeedbackBridge` 负责计时、合并和 Camera3D 偏移；PlayerAttackController、PlayerBase 与 PlayerMeleeHitbox 分别提供局部暂停接口。所有模块只通过公开方法连接，不使用全局时间缩放。

**Tech Stack:** Godot 4.7、GDScript、AnimationPlayer、CharacterBody3D、Camera3D、现有 HitFeedbackProfile 资源。

## Global Constraints

- 所有字段和方法使用英文标识，新增代码提供详细简体中文注释。
- 直接复用 `Effects/Combat/HitFeedbackBridge.tscn` 与 `DefaultMeleeHitFeedback.tres`。
- 不修改旧 `Scenes/ObjectScenes/Hero.tscn`、旧 `Scenes/Components/MeleeAttackModule.tscn` 或 `Scenes/TestScene.tscn`。
- 不使用 `Engine.time_scale`。
- 卡刀不停止玩家 WASD、重力、AI、游戏世界或摄像机震动。
- 本阶段不实现伤害、击退、硬直、音效或粒子。
- 项目不是 Git 仓库，不创建提交或 worktree。

---

### Task 1: PlayerBase 攻击位移暂停接口

**Files:**
- Modify: `UnitSystem/PlayerBase.gd`
- Modify: `UnitSystem/Tests/PlayerBaseMovementTest.gd`

**Interfaces:**
- Produces: `set_attack_motion_suspended(active: bool) -> void`
- Produces: `is_attack_motion_suspended() -> bool`

- [x] 先写失败测试，验证暂停时不叠加攻击速度、不消耗剩余距离，普通移动仍可执行，恢复后继续，取消攻击位移会清除暂停状态。
- [x] 运行 `PlayerBaseMovementTest.gd` 确认因接口缺失而失败。
- [x] 增加 `_attack_motion_suspended` 状态和两个公开接口；在 `_apply_attack_motion_velocity()` 开头安全返回。
- [x] 运行测试确认通过。

---

### Task 2: PlayerMeleeHitbox 查询暂停接口

**Files:**
- Modify: `UnitSystem/Combat/PlayerMeleeHitbox.gd`
- Modify: `UnitSystem/Tests/PlayerMeleeHitboxTest.gd`

**Interfaces:**
- Produces: `set_detection_suspended(active: bool) -> void`
- Produces: `is_detection_suspended() -> bool`

- [x] 先写失败测试：暂停后窗口保持开启、调试盒继续跟随、进入范围的新目标不命中；恢复后新目标可命中；结束窗口清除暂停状态。
- [x] 运行专项测试确认 RED。
- [x] 在每物理帧更新共享 Transform 后、执行 `intersect_shape()` 前判断暂停状态。
- [x] 运行专项测试确认 GREEN。

---

### Task 3: PlayerAttackController 局部卡刀

**Files:**
- Modify: `UnitSystem/Combat/PlayerAttackController.gd`
- Modify: `UnitSystem/Tests/PlayerWeaponCombatTest.gd`

**Interfaces:**
- Consumes: PlayerBase 与 PlayerMeleeHitbox 暂停接口
- Produces: `set_hit_stop_active(active: bool) -> void`
- Produces: `is_hit_stop_active() -> bool`

- [x] 先写失败测试，验证暂停动画、冻结状态计时、保留输入缓存、暂停位移与查询、恢复原动画位置，以及冲刺/取消/卸装清理卡刀。
- [x] 运行攻击测试确认 RED。
- [x] 实现幂等卡刀接口；`_process()` 中先处理冲刺，再允许缓存攻击输入，卡刀时停止其余计时。
- [x] `cancel_combo()`、卸装、换装和退出树统一解除卡刀。
- [x] 运行攻击与移动测试确认 GREEN。

---

### Task 4: 统一 Effects 插槽与旧桥装配

**Files:**
- Modify: `UnitSystem/PlayerBase.tscn`
- Modify: `UnitSystem/Tests/PlayerBaseMovementTest.gd`
- Modify: `UnitSystem/Tests/PlayerWeaponCombatTest.gd`

**Interfaces:**
- Consumes: `Effects/Combat/HitFeedbackBridge.tscn`
- Consumes: `Effects/Combat/DefaultMeleeHitFeedback.tres`
- Configures: `attack_source_path = ../../AttackController`

- [x] 先写失败测试，验证 `PlayerBase/Effects/HitFeedbackBridge` 节点、来源路径、Profile 身份及运行时信号连接。
- [x] 运行测试确认 RED。
- [x] 在 PlayerBase 添加 Node3D `Effects` 和旧桥实例，配置新攻击来源与旧 Profile。
- [x] 运行测试确认 GREEN。

---

### Task 5: 真实命中反馈集成测试

**Files:**
- Create: `UnitSystem/Tests/PlayerHitFeedbackTest.gd`
- Modify only if a test exposes a defect: `Effects/Combat/HitFeedbackBridge.gd`

**Interfaces:**
- Exercises: `attack_hit → HitFeedbackBridge → hit stop + Camera3D shake`

- [x] 创建真实 Hero、敌人和 Camera3D，触发真实 `attack_hit`。
- [x] 验证动画、攻击位移与 Hitbox 查询暂停，Camera3D 产生非零局部偏移。
- [x] 验证 Profile 三段倍率读取为 `1.2 / 1.3 / 1.5`。
- [x] 验证 `minimum_feedback_interval` 内多目标反馈只开始一次。
- [x] 验证计时结束后攻击恢复、Camera3D 精确回到初始局部位置。
- [x] 验证删除桥后攻击接口仍可使用。

---

### Task 6: 全量验证与文档回填

**Files:**
- Modify: `Docs/Superpowers/Plans/2026-07-22-player-combat-hit-feedback-implementation-plan.md`

- [x] 逐个运行 `UnitSystem/Tests/*.gd`，要求全部 PASS 且无 ERROR、WARNING 或 FAIL。
- [x] 运行 Godot 4.7 editor scan 与 headless runtime scan，要求零问题。
- [x] 核对旧 Hero、旧 MeleeAttackModule 与 TestScene SHA-256 不变。
- [x] 回填最终节点、参数、测试数量与验证结果。

---

## 实施结果（2026-07-22）

最终装配路径：

```text
PlayerBase
├── AttackController
├── MeleeHitbox
└── Effects
    └── HitFeedbackBridge
```

- `HitFeedbackBridge.attack_source_path`：`../../AttackController`
- `HitFeedbackBridge.effect_profile`：`DefaultMeleeHitFeedback.tres`
- 旧 Profile 的三段强度倍率继续为 `1.2 / 1.3 / 1.5`。
- 卡刀期间暂停攻击动画、攻击位移消耗、Hitbox 新查询和攻击状态计时；普通移动、重力、世界逻辑与摄像机震动继续更新。
- 冲刺、取消连击、换装、卸装或退出树都会解除局部停顿，不遗留冻结状态。
- `Effects/HitFeedbackBridge` 可整体删除；删除后攻击、连击和 Hitbox 仍可独立运行。

验证结果：

- `UnitSystem/Tests/*.gd`：13/13 PASS，0 ERROR，0 WARNING，0 FAIL。
- Godot 4.7 `--headless --editor --quit`：退出码 0。
- Godot 4.7 主场景 `--headless --quit-after 5`：退出码 0。
- 受保护文件 SHA-256 保持不变：
  - `Scenes/ObjectScenes/Hero.tscn`：`A00DE9820394CA6702615C5905CE5E637D42727273910E6ECDF823D0832E9F38`
  - `Scenes/Components/MeleeAttackModule.tscn`：`17B6C6301097937D955AA703B837A54E9F43A3A0305F9A893DC311B435DE506A`
  - `Scenes/TestScene.tscn`：`ED61E6208F63EAB5FF28EEA2D6142BD321A13B5A077D87E28DBC4DBFA0C723A1`
