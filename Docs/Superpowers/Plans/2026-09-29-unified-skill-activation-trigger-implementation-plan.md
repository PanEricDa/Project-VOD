# Unified Skill Activation and Trigger Chain Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让同一个 `SkillBase` 场景能以角色常规施放或独立实例的命中触发方式运行，并以爆裂箭 → 最多三枚碎片 → 灼烧条件下最多九次末段伤害验证通用连锁。

**Architecture:** 保留 `SkillHost`、AI 选技和动画 Release；给 `SkillBase` 增加由请求上下文决定的直接触发入口，并与普通释放共用交付核心。每个子目标实例化一个完整技能场景；弧线投射物交付、每目标实际伤害结果、命中点附近查询和 `TriggerSkillEffect` 均为通用组件。

**Tech Stack:** Godot 4.7.1、GDScript、现有 `SceneTree` 脚本测试、Windows PowerShell。

**Spec:** `Docs/Superpowers/Specs/2026-09-29-unified-skill-activation-trigger-design.md`。旧版 `2026-09-29-reusable-projectile-chain-design.md` 的 Profile 方案已被取代。

## Global Constraints

- 每个新增或修改的 `@export` 参数与公开方法／信号在声明附近提供简体中文用途、单位、默认与约束说明；与行为同步。
- 不新增 `TriggeredSkillBase`、碎片命中 Profile 或独立伤害公式；A／B／C 全部继承同一个 `SkillBase.tscn`。
- 子技能各自检查自身条件和消耗；触发内容显式配置冷却 0、资源消耗 0，不设父技能代付或免冷却例外。
- 不将普通攻击、移动、闪避并入技能系统；不得由 Codex 向 `Scenes/TestScene.tscn` 添加或修改单位实例。
- 若需正式 `.tres`／`.res`，必须经 Godot 编辑器 API 或 `ResourceSaver` 保存，验证 `ResourceLoader.get_resource_uid(path) != ResourceUID.INVALID_ID`、强类型与 Inspector Quick Load；本计划优先使用技能场景内嵌 Delivery 子资源，不新增正式外部资源。
- 只提交本任务文件；现有工作区的其他修改与未跟踪文件属于用户，不能覆盖或顺手整理。
- 每个任务先写失败测试、运行确认失败、做最小实现、运行通过，再单独提交；命令失败不能只靠退出码判断，须核对测试输出中的 `PASS`／`FAIL`。

## Review Focus

1. AI 自动请求与脚本显式触发混淆：普通 AI 仍遵守 `AUTOMATIC_ONLY` 条件和释放后犹豫；触发请求使用 `EXPLICIT` 且不向角色申请动画。由 Task 1 的请求来源测试锁定。
2. 零实际扣血或同次命中才新加灼烧：不得分裂，也不得把后加状态当作“命中前灼烧”。由 Task 4、Task 7 测试锁定。
3. 命中点远离施法者索敌范围：仍须选中命中点附近合法敌人，不受 `get_perceived_candidates()` 半径裁剪。由 Task 6 测试锁定。
4. 子实例创建、消耗或交付失败：只终止该分支，不撤销父技能已造成的伤害，也不取消兄弟碎片。由 Task 7、Task 9 测试锁定。
5. 同屏多次释放及场景退出：不得覆盖在途 Runner、重复造成伤害或留下技能／投射物实例。由 Task 5、Task 9 测试与节点数采样锁定。

---

## 文件边界和执行顺序

1. `SkillContext.gd`、`SkillBase.gd`、`SkillHostComponent.gd`：一次请求与共同交付核心；不加入具体箭名称。
2. `SkillBase.gd`、`AllyBehaviorStateMachine.gd`：通用只读动作 payload，行为层不反查 `MeleeAction` 子节点。
3. `StatusEffectComponent.gd` 与通用状态 Effect：命名限时状态；不把灼烧特例写进组件。
4. `SkillHitOutcome.gd`、`SkillDeliveryResult.gd`、`SkillDeliveryRunner.gd`、`HealthChangeSkillEffect.gd`：每目标命中前状态和实际伤害。
5. `ArcProjectileDeliveryConfig.gd`、`ArcProjectileDeliverySession.gd`、Runner：既有两参数弧线投射物的技能交付适配。
6. `NearbySkillTargetQuery.gd`：命中点物理空间查询与目标筛选。
7. `TriggerSkillEffect.gd`：配置子技能场景、条件和目标范围；实例生命周期。
8. 爆裂箭／碎片／末段三个技能场景、弧线箭视觉场景、Firebolt 灼烧配置、Archer 技能槽：仅内容装配。
9. 端到端、回归、压力测试和策划配置文档。

执行前只确认独立工作区或现有分支已保护用户修改；不要因本计划而改动 `Scenes/TestScene.tscn`。测试统一使用：

```powershell
$godotExe = 'G:\Godot\Godot_v4.7.1-stable_win64_console.exe'
& $godotExe --headless --path 'G:\Godot\ProjectVOD' --script 'res://SkillSystem/05-Tests/<TestName>.gd'
```

### Task 1: 同一 `SkillBase` 的普通／直接激活入口

**Files:**
- Modify: `SkillSystem/01-Core/SkillContext.gd`
- Modify: `SkillSystem/01-Core/SkillBase.gd`
- Modify: `SkillSystem/01-Core/SkillHostComponent.gd`
- Create: `SkillSystem/05-Tests/TriggeredSkillActivationTest.gd`
- Regression: `SkillSystem/05-Tests/SingleSceneSkillBaseTest.gd`、`SingleSceneSkillHostTest.gd`、`SkillConditionScopeTest.gd`

**Interfaces:**
- Produces: `SkillContext.ExecutionMode { CHARACTER_ACTION, DIRECT_TRIGGER }`、`execution_mode` 默认前者、`activation_transform: Transform3D` 默认非有限原点、`trigger_scene_paths: Array[String]` 默认为空且在 `duplicate_context()` 中复制、`SkillBase.activate(context: SkillContext) -> bool`。旧 `request_skill(context)` 作为普通请求兼容入口；Host 改调 `activate()`。
- Direct 要求调用方提供有限发射变换及明确目标；其施法距离从 `activation_transform.origin` 计算。普通请求保持施法者为距离原点，并沿用动作信号和动画 Release。
- `SkillBase.release_action()` 和 DIRECT 分支共用私有 `_commit_release(context: SkillContext, launch_transform: Transform3D) -> bool`，包含成本提交、Release 表现、Runner 交付和技能自身冷却，不设触发例外。

- [ ] **Step 1: 写失败测试**：在 `TriggeredSkillActivationTest.gd` 断言普通入口仍发出一次 `action_requested`、DIRECT 不发动作请求而发 `release_started`／`delivery_started`、DIRECT 无有限发射点被拒、远处施法者不阻止从命中点 3 米内触发、`ALL_REQUESTS` 条件失败会拒绝直接触发、子技能消耗不足会拒绝；既有 AI 条件作用范围保持不变。
- [ ] **Step 2: 运行新测试和三项回归**；预期新测试因接口缺失而 FAIL，回归仍 PASS，记录基线；若回归本来失败，先归因，勿把既有用户修改当作本任务修复。
- [ ] **Step 3: 实现上述上下文、入口和共同交付核心**；保持 `request_skill()` 与现有 `release_action()` 的公开行为及信号顺序；DIRECT 标记请求来源为现有 `EXPLICIT`，不继承父 AI 的 `AI_AUTOMATIC`。
- [ ] **Step 4: 重跑上述测试**，新测试与三项回归均 PASS；检查释放失败后的成本退还、状态回到可用且不误发成功信号。
- [ ] **Step 5: 只提交本任务文件**，提交信息 `feat: add direct trigger activation to SkillBase`。

### Task 2: 行为层不反查具体技能子节点

**Files:**
- Modify: `SkillSystem/01-Core/SkillBase.gd`
- Modify: `UnitSystem/Components/Behavior/AllyBehaviorStateMachine.gd`
- Modify: `SkillSystem/05-Tests/SingleSceneSkillBaseTest.gd`
- Regression: `UnitSystem/Tests/AllyBehaviorStateMachineTest.gd`、`SkillSystem/05-Tests/GuardianTauntSkillTest.gd`

**Interfaces:**
- Produces: `SkillBase.get_action_payload() -> Dictionary`；只读，根技能负责从可选 `MeleeSkillAction` 取得 payload，没有该组件时返回空字典。行为层只能调用公开方法，不使用 `get_node_or_null(^"MeleeAction")`。

- [ ] **Step 1: 写失败测试**：有／无 `MeleeAction` 的技能分别返回现有近战 payload／空字典；状态机源码或行为集成测试证明它仅消费公开接口，近战命中数值不变。
- [ ] **Step 2: 运行测试**；新增断言预期 FAIL，现有近战与嘲讽基线记录下来。
- [ ] **Step 3: 增加 `get_action_payload()` 并替换行为层特定子节点查找**，不修改 AI 选技和动画事件接口。
- [ ] **Step 4: 跑新测试及两项回归**；全部 PASS，无近战伤害或嘲讽行为变化。
- [ ] **Step 5: 只提交本任务文件**，提交信息 `refactor: expose skill action payload through SkillBase`。

### Task 3: 通用命名限时状态与施加效果

**Files:**
- Modify: `UnitSystem/Components/Status/StatusEffectComponent.gd`
- Create: `SkillSystem/03-Extensions/ApplyNamedStatusSkillEffect.gd`
- Modify: `UnitSystem/Tests/StatusEffectComponentTest.gd`
- Create: `SkillSystem/05-Tests/ApplyNamedStatusSkillEffectTest.gd`

**Interfaces:**
- Produces: `StatusEffectComponent.apply_named_status(status_id: StringName, duration_seconds: float) -> bool`、`has_named_status(status_id: StringName) -> bool`、`get_active_status_ids() -> Array[StringName]`。同 ID 重新施加刷新时长；持续时间必须有限且大于 0；到期、死亡和更换 Owner 时移除。与属性 Modifier 记录并列，不创建新 `.tres` 类型。
- `ApplyNamedStatusSkillEffect` 作为根技能直接子 Effect，Inspector 配置 `status_id` 与持续秒数；`apply(context, result, target) -> bool` 使用目标已有 `get_status_effect_component()`，不硬编码 `burning`。

- [ ] **Step 1: 写失败测试**：`burning` 施加、4 秒刷新、到期、死亡清理；空 ID／零或非有限时长拒绝；原有属性 Modifier 结果不变；通用 Effect 可对 UnitBase 施加配置的任意 ID。
- [ ] **Step 2: 运行两项测试**；新增断言预期 FAIL，既有 Modifier 断言保持 PASS。
- [ ] **Step 3: 实现状态 API 和通用 Effect**；确保状态 ID 与时长只由配置给出，`clear_all_modifiers()` 不清除命名状态；死亡和换 Owner 则清除两类状态。
- [ ] **Step 4: 重跑测试**，全部 PASS；确认无正式外部资源生成。
- [ ] **Step 5: 只提交本任务文件**，提交信息 `feat: add reusable timed named statuses`。

### Task 4: 每目标命中前快照与实际伤害结果

**Files:**
- Create: `SkillSystem/01-Core/SkillHitOutcome.gd`
- Modify: `SkillSystem/01-Core/SkillDeliveryResult.gd`
- Modify: `SkillSystem/02-Delivery/SkillDeliveryRunner.gd`
- Modify: `SkillSystem/03-Extensions/HealthChangeSkillEffect.gd`
- Create: `SkillSystem/05-Tests/SkillHitOutcomeTest.gd`
- Regression: `SkillSystem/05-Tests/SingleSceneDeliveryRunnerTest.gd`、`SingleSceneHolyLightTest.gd`

**Interfaces:**
- Produces: `SkillHitOutcome` 运行时 RefCounted：`target: Node3D`、`statuses_before_hit: Array[StringName]`、`actual_damage: float = 0.0`、`actual_healing: float = 0.0`、`impact_position: Vector3`；`SkillDeliveryResult.current_hit: SkillHitOutcome`。
- Runner 对每个 Effect 目标先建立独立 outcome 并读取 `get_active_status_ids()` 快照，再按原序应用 Effects；`HealthChangeSkillEffect` 将 `CombatValueResolver` 返回的实际扣血／治疗累加到 `current_hit`。布尔 `apply()` 仍只表示执行成功，不代表伤害为正。

- [ ] **Step 1: 写失败测试**：同一目标先伤害后状态、`statuses_before_hit` 不含新状态；伤害 0 时 `actual_damage == 0`；两目标 outcome 不串写；治疗只计入 `actual_healing`；过量伤害只记录实际掉血。
- [ ] **Step 2: 运行新测试及两个既有交付／治疗测试**；新测试 FAIL，既有测试记录基线。
- [ ] **Step 3: 实现 outcome、Runner 建立快照及 HealthChange 结果记录**；同时覆盖瞬发和现有追踪投射物效果循环；不改变数值结算器。
- [ ] **Step 4: 重跑测试**；全部 PASS，无重复伤害或治疗统计变化。
- [ ] **Step 5: 只提交本任务文件**，提交信息 `feat: expose per-target skill hit outcomes`。

### Task 5: 两参数 Arc 投射物的独立交付会话

**Files:**
- Create: `SkillSystem/02-Delivery/ArcProjectileDeliveryConfig.gd`
- Create: `SkillSystem/02-Delivery/ArcProjectileDeliverySession.gd`
- Modify: `SkillSystem/02-Delivery/SkillDeliveryRunner.gd`
- Create: `SkillSystem/05-Tests/ArcProjectileDeliveryTest.gd`
- Regression: `SkillSystem/05-Tests/SingleSceneDeliveryRunnerTest.gd`、`UnitSystem/Tests/BasicAttackDamageIntegrationTest.gd`

**Interfaces:**
- `ArcProjectileDeliveryConfig extends SkillDeliveryConfig`；`projectile_scene: PackedScene` 必须支持 `launch(target, start_position) -> bool` 和 `projectile_hit(target, position, direction)`；其他飞行参数仍在投射物场景中配置。
- `ArcProjectileDeliverySession.start(config: ArcProjectileDeliveryConfig, context: SkillContext, launch_transform: Transform3D, effects: Array[SkillEffectBase]) -> bool`，发出与 Runner 可转发的完成／失败信号。Runner `execute()` 对 Arc 类型新建会话；各会话独立持有命中数据，不能复用根 Runner 的单一 `_busy` 状态。

- [ ] **Step 1: 写失败测试**：Arrow 契约下成功命中并应用一次伤害、飞行中目标消失无伤害、两个会话同时在途不互相覆盖、场景退出清理、原 Bow 普攻仍按旧接口工作。
- [ ] **Step 2: 运行新测试和两项回归**；新测试因配置类型未实现而 FAIL，旧投射物／普攻保持基线。
- [ ] **Step 3: 实现 Arc config、session 和 Runner 分派**；只做技能侧适配，不修改 `Item/Projectiles/TrackingArcProjectile.gd` 的普通攻击公开契约；命中时使用 Task 4 的 per-target outcome。
- [ ] **Step 4: 重跑测试**；全部 PASS，重复释放与异步结束后 Runner 不残留会话。
- [ ] **Step 5: 只提交本任务文件**，提交信息 `feat: add independent arc projectile skill delivery`。

### Task 6: 从命中点查询可配置数量的附近目标

**Files:**
- Create: `SkillSystem/01-Core/NearbySkillTargetQuery.gd`
- Create: `SkillSystem/05-Tests/NearbySkillTargetQueryTest.gd`
- Regression: `SkillSystem/05-Tests/TargetResolverTest.gd`

**Interfaces:**
- Produces: `NearbySkillTargetQuery.select_targets(world: World3D, caster: Node3D, origin: Vector3, radius_m: float, max_targets: int, relation_flags: int, excluded: Node3D) -> Array[Node3D]`。
- 在调用时做一次 `PhysicsDirectSpaceState3D` 范围查询；MVP 单位碰撞层使用现有 Ally=2、Enemy=4，即单位查询掩码 6；查询结果容量必须足以覆盖所有被命中的候选，不能因默认 `max_results` 截断而漏掉排序后最近的 N 个。查询后再按水平距离、阵营、存活、可选取、排除目标、实例 ID 去重并稳定排序。查询形状的垂直容差覆盖既有单位胶囊体，不能让高低位置导致非预期漏选；非法参数返回空结果。

- [ ] **Step 1: 写失败测试**：0／1／3／超过 3 名目标；命中点距施法者 20 米但附近敌人仍入选；友军／自身／死亡／排除对象过滤；相同距离稳定顺序；不同高度目标验证；超过物理查询默认容量时仍选出最近 N 个；不依赖 AI Provider。
- [ ] **Step 2: 运行新测试和 `TargetResolverTest.gd`**；新测试 FAIL，原筛选测试仍 PASS。
- [ ] **Step 3: 实现查询 helper**；不逐帧扫描场景、不把 `3` 写死、不修改 AI 当前感知接口。
- [ ] **Step 4: 重跑测试**；全部 PASS，碰撞查询结果中非单位物体被安全过滤。
- [ ] **Step 5: 只提交本任务文件**，提交信息 `feat: query nearby skill targets at impact position`。

### Task 7: 通用 `TriggerSkillEffect` 与子实例生命周期

**Files:**
- Create: `SkillSystem/03-Extensions/TriggerSkillEffect.gd`
- Create: `SkillSystem/05-Tests/TriggerSkillEffectTest.gd`
- Modify: `SkillSystem/01-Core/SkillBase.gd`（仅必要的完成／清理接口）
- Regression: `SkillSystem/05-Tests/TriggeredSkillActivationTest.gd`、`ArcProjectileDeliveryTest.gd`

**Interfaces:**
- `TriggerSkillEffect extends SkillEffectBase`；Inspector 配置 `child_skill_scene: PackedScene`、`required_status_id: StringName`（空为不限）、`require_positive_damage: bool = true`、`radius_m: float`、`max_targets: int`、`relation_flags: int`、`exclude_hit_target: bool = true`。字段都写紧邻简体中文说明。
- `apply(context: SkillContext, result: SkillDeliveryResult, target: Node3D) -> bool` 从 `result.current_hit` 读取本目标正数实际伤害与命中前状态，经 Task 6 查询，为每个目标实例化并配置 `SkillBase`，提交 Task 1 的 DIRECT 请求。正常无候选／条件未满足及单个子技能失败不使父技能的 Effect 返回失败；直接自引用给配置警告，运行时用 `context.trigger_scene_paths` 的场景路径祖先链拒绝间接循环，并阻止创建。

- [ ] **Step 1: 写失败测试**：零伤害、命中前无灼烧、同次才加灼烧均不触发；已灼烧最多生成配置数量；每个子实例有不同 instance ID；子技能有非零消耗且付不起只跳过该分支；兄弟分支仍完成；直接／间接循环引用被拒；飞行结束后实例释放。
- [ ] **Step 2: 运行新测试与两项回归**；新测试因组件缺失 FAIL，原激活／Arc 测试仍 PASS。
- [ ] **Step 3: 实现 Effect、子场景实例化与销毁绑定**；按真实交付完成／失败清理，不在投射物发射时释放；父技能状态与子实例隔离；不要另建触发型技能父类。
- [ ] **Step 4: 重跑测试**；全部 PASS，无递归无限生成或节点泄漏。
- [ ] **Step 5: 只提交本任务文件**，提交信息 `feat: trigger reusable skills from hit effects`。

### Task 8: 装配爆裂箭、碎片、末段伤害和灼烧来源

**Files:**
- Create: `SkillSystem/00-Skills/ExplosiveArrow/ExplosiveArrowSkill.tscn`
- Create: `SkillSystem/00-Skills/ExplosiveFragment/ExplosiveFragmentSkill.tscn`
- Create: `SkillSystem/00-Skills/BurningSplash/BurningSplashSkill.tscn`
- Create: `Item/Projectiles/ExplosiveArrow.tscn`、`Item/Projectiles/ExplosiveFragment.tscn`
- Modify: `SkillSystem/00-Skills/Firebolt/FireboltSkill.tscn`
- Modify: `UnitSystem/AI/Ally/Units/Archer.tscn`
- Modify: `Item/Weapon/Bow/BowAnimationLibrary.res`（若当前 Bow 没有符合外部技能施放要求的 `basic_cast_1`；通过 Godot 编辑器 API／ResourceSaver 修改，不直接改二进制）
- Create: `SkillSystem/05-Tests/ExplosiveArrowAssemblyTest.gd`

**Interfaces:**
- 三个技能继承 `RangedSkillTemplate.tscn`，并间接继承唯一 `SkillBase.tscn`；主箭放 Archer 一个常规槽，Archer 的 `combat_action_policy` 从当前 `BASIC_ONLY` 改为 `SKILL_PRIORITY_THEN_BASIC`；碎片和末段只通过 `TriggerSkillEffect.child_skill_scene` 引用。
- 主箭／碎片使用 Task 5 的 Arc Delivery；末段使用现有 `InstantTargetDeliveryConfig.SINGLE`。主箭、碎片各用 Task 7 的同一附近目标策略（半径首轮均 3m，最多 3，排除本次受击者）；碎片额外要求命中前 `burning`。Firebolt 使用 Task 3 的通用状态 Effect 施加 `burning`，首轮持续 4 秒。B、C 的 `skill_cooldown = 0` 且没有成本组件。
- 首轮可沿用旧设计的测试数值：主箭基础 10、攻击倍率 0.6；碎片基础 3、倍率 0.25；末段基础 2、倍率 0.1；主箭冷却 7 秒。数值只是验证样例，用户可在 Inspector 调整。

- [ ] **Step 1: 写失败装配测试**：A/B/C 均为 `SkillBase` 且无专用根脚本；A 装 Archer 常规槽、Archer 使用 `SKILL_PRIORITY_THEN_BASIC`、B/C 不装槽；A、B 同一通用 Trigger Effect 且数量均配置 3；B/C 冷却 0、无成本；C 无 Trigger；Firebolt 有通用状态 Effect；引用的箭场景加载成功；Bow 或角色动画库存在带且仅带一个 `release_action` 方法标记的 `basic_cast_1`。
- [ ] **Step 2: 运行装配测试**；预期缺少新技能场景而 FAIL，既有 Archer／Firebolt 测试基线另行记录。
- [ ] **Step 3: 创建五个场景并装配 Firebolt 与 Archer**；沿用模板、已有健康变化 Effect 和简易视觉。若 Bow 缺少技能释放动画，用 Godot API 在 `BowAnimationLibrary.res` 中由现有弓动作制作 `basic_cast_1` 并设置唯一 `release_action` 标记，保存后验证原资源 UID 仍有效；不改 `Scenes/TestScene.tscn`，不新增正式外部 `.tres`。
- [ ] **Step 4: 重跑装配与 Firebolt 回归**；全部 PASS，Godot 编辑器可打开三种技能并在 Inspector 看到清楚的触发配置。
- [ ] **Step 5: 只提交本任务文件**，提交信息 `feat: assemble explosive arrow skill chain`。

### Task 9: 端到端、性能与策划交付

**Files:**
- Create: `SkillSystem/05-Tests/ExplosiveArrowChainIntegrationTest.gd`
- Create: `SkillSystem/05-Tests/ExplosiveArrowStressTest.gd`
- Create: `SkillSystem/04-Docs/TriggeredSkillConfigurationGuide.md`
- Modify: `SkillSystem/04-Docs/SkillSystemUserGuide.md`（只增新入口与本例链接）
- Regression: Tasks 1–8 的新增测试，以及 `SingleSceneFireboltTest.gd`、`SingleSceneHolyLightTest.gd`、`GuardianTauntSkillTest.gd`、`RepeatedSkillCastingLifecycleTest.gd`、`BasicAttackDamageIntegrationTest.gd`。

**Interfaces:**
- 对外不增加新运行 API。集成测试必须走真实 Archer SkillHost → 动画 Release 或与其等价的测试驱动 → 主箭 → 子碎片 → 末段技能链；不能只做文本存在性断言。

- [ ] **Step 1: 写失败集成与压力测试**：无灼烧只造成主箭＋碎片伤害；有灼烧按 1+3+9 的上限发生伤害事件（场上须提供足够合法目标）；目标途中死亡／零伤害／子分支失败分别安全收束；同一场景在槽内与触发中同时实例化不串状态；多轮连锁后技能与投射物节点数回到基线，并记录峰值活跃实例、峰值投射物与帧耗时。
- [ ] **Step 2: 运行新测试**；预期在未完成真实链路或断言条件下 FAIL，先修复测试夹具而非降低断言。
- [ ] **Step 3: 只修复新链路范围内的集成缺口**；完善文档，说明技能槽装配、Trigger Inspector 参数、状态与冷却配置、可复用范围及“同一技能场景可被两处实例化”。
- [ ] **Step 4: 运行完整新增与列出的旧测试、`--headless --editor --quit` 导入检查**；核查输出中的 PASS；记录压力数据，不预设性能阈值或提前添加对象池。若非本任务的工作区修改使回归失败，单独报告而不覆盖。
- [ ] **Step 5: 只提交本任务文件**，提交信息 `test: verify explosive arrow chaining and document configuration`。

## 计划完成判据

一套 `SkillBase` 场景可以分别作为槽位常规技能或 Trigger 引用的独立实例；子实例自身配置冷却／消耗，父技能不代付。主箭和碎片共用可配置数量的命中点附近目标策略；分裂只在实际正数伤害后发生，碎片的下一轮还要求目标命中前已灼烧。AI 行为不识别具体子组件，旧技能与弓普攻回归通过；压力测试显示连锁结束后实例与投射物可回收。后续若用户要在 `Scenes/TestScene.tscn` 观察新技能，仅告知应手动添加的源场景、父节点和必要位置／Inspector 配置，不代替用户添加单位。
