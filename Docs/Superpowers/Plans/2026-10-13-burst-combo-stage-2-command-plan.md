# 爆发连携阶段二 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** 将阶段一专注账务接入1—4实时伙伴指令，验证等待、动作锁、目标意图、重复施放和失败退款，复用现有技能作为测试内容。

**Architecture:** 队伍控制器负责请求与账务，SkillHost负责本伙伴等待队列，既有行为/动作控制器负责合法出手机会；SkillBase与通用Delivery继续执行技能。一次根请求保存身份及动作/全部交付生命周期，追踪弹改为独立交付会话；UI只读，不增加第二套技能或AI执行体系。

**Tech Stack:** Godot 4.7、GDScript、PackedScene、InputMap、SceneTree headless测试、Godot MCP Pro。

**Spec:** [已通过的阶段二详细设计](../Specs/2026-10-13-burst-combo-stage-2-command-design.md)，上位[四阶段路线](2026-10-12-burst-combo-four-stage-roadmap.md)。

> 日期：2026-10-13。状态：用户已确认书面计划并授权当前会话逐项实施，选择保持当前Godot项目目录；Task 1—8已实施及后台验收完成；最终126/126通过，独立审查3项Important均经RED→GREEN修复；人工操作手感待用户验证。基线：`0a2b21edbb1dc5de18b5692c0f9feffa985ca172`。四组是阶段二内部检查点，不是替代整个系统的四阶段。

## Global Constraints

- 编辑优先Godot MCP Pro；Markdown不受其脚本/场景/资源编辑接口支持，使用apply_patch并说明回退原因。不得覆盖编辑器未保存内容。
- 不向`Scenes/TestScene.tscn`添加或修改单位，不改变`Scenes/TestCombatRoom.tscn`阵容、位置和专注参数；允许按已通过设计修改四伙伴源场景的SkillSocket装配。
- 四个验证技能复用已有技能内容/动画/VFX，但使用独立实例。常规两个槽、数值、自动AI优先级和仇恨不变；没有指挥控制器时仍运行原玩法。
- 连携根为CHAIN + EXPLICIT + CHARACTER_ACTION；忽略自身CD、AI犹豫和公共冷却，保留动作占用、存活、施法封锁、目标、ALL_REQUESTS条件及其他资源成本。
- 开发默认费用20/10、等待8秒；仅预览初始专注100。等待截止包含旧动作和接近，实际动作开始后停止，不因换目标重置。这些不是最终平衡值。
- 不实施伤害窗口、评分、终结、玩家Q/E、地板瞄准、控制debuff内容、连锁减免或最终职业连携设计。不在GameRunController植入临时轮次逻辑。
- 每个伙伴最多一条尚未开始动作的pending；实际开始后允许再缓存一条。已开始动作不被普通AI、新指令或换锁定覆盖。
- 新增配置类型仅7项：Host1、费用组件2、队伍控制器3、UI1。身份、用途、轮次、交付计数和内部故障兜底不export；公开接口与exports均提供邻近简体中文说明。
- 不新增正式`.tres/.res`或VFX；7个新场景经Godot保存、验证UID及引用。如实施确需外部Resource，先说明范围变化并遵循AGENTS.md的正式保存、UID、类型索引规则。
- 本计划不自动提交、推送、合并或进入阶段三；每任务保留可review差异，版本记录另按用户授权执行。

## Review Focus

1. 同步Instant/GroundArea先产生效果后报告失败：先接受/收费，后报告最终失败，不能免费退款；Task 2/5测试。
2. 同一技能旧追踪弹失败时新动作已开始：旧context/token只结束旧交付，不清新动作、不二次退款；Task 2/3/6测试。
3. 同一伙伴前序失败、后序已预留重复上界：30点预留实际只扣20并释放10，不遗留账目；Task 5测试。
4. 接近中不断换锁定、保护或脱战触发：允许刷新未开始目标，但不重置8秒截止、不饿死指令或覆盖已开始动作；Task 4测试。
5. 取得轮次后受理失败、解绑时还有子碎片：通知零活请求、清理未释放承诺，旧回调不串新世界且无强引用循环；Task 5/6测试。

---

## 文件与装配冻结

新增14个`.gd`（运行/预览6，测试8）、7个`.tscn`、0个`.tres/.res`；`.gd.uid`由Godot生成。既有生产文件修改15个，兼容测试、指南和验收文档另列，不隐藏在该数字内。

| 新文件 | 职责与任务 |
| --- | --- |
| `SkillSystem/01-Core/SkillCommandRequest.gd` | 根身份、等待、动作和交付token，Task 1/6 |
| `SkillSystem/03-Extensions/ComboFocusCost.gd` | 两项费用配置，Node而非SkillCostBase，Task 1 |
| `SkillSystem/02-Delivery/TrackingProjectileDeliverySession.gd` | 提取既有追踪交付状态，Task 2 |
| `UnitSystem/Components/Combat/Squad/SquadChainCommandController.gd/.tscn` | 四槽请求、专注与轮次接口，Task 5/7 |
| `UnitSystem/Components/UI/SquadChainCommandDisplay.gd/.tscn` | 只读四张卡片，Task 7 |
| `Scenes/Previews/SquadChainCommandPreview.gd/.tscn` | 继承正式房间、显式开发批次，Task 7 |
| `SkillSystem/00-Skills/Combo_GuardianBash/ComboGuardianBashSkill.tscn` | 复用GuardianShield，独立`combo_guardian_bash` |
| `SkillSystem/00-Skills/Combo_GreaterHeal/ComboGreaterHealSkill.tscn` | 复用GreaterHeal，独立`combo_greater_heal` |
| `SkillSystem/00-Skills/Combo_Firebolt/ComboFireboltSkill.tscn` | 复用Firebolt，独立`combo_firebolt` |
| `SkillSystem/00-Skills/Combo_RapidShot/ComboRapidShotSkill.tscn` | 复用RapidShot，独立`combo_rapid_shot` |

四个技能场景均套用对应现有场景/模板；复用强类型Delivery资源、Effects脚本、动作和VFX，不新增专用技能脚本。根节点直接挂ComboFocusCost，20/10；自动施放关闭、自身CD0、AI犹豫关闭。运行规则仍通过purpose实现，不能依赖这些占位配置才能忽略冷却。

15个既有生产文件：

- `SkillSystem/01-Core/SkillContext.gd`、`SkillBase.gd`、`SkillHostComponent.gd`：上下文、统一预检/释放、一个连携槽与等待。
- `SkillSystem/02-Delivery/SkillDeliveryRunner.gd`、`SkillSystem/03-Extensions/TriggerSkillEffect.gd`：接受契约、并发追踪与子交付清理。
- `UnitSystem/Components/Behavior/AllyBehaviorStateMachine.gd`：连携优先合法衔接、目标与移动。
- `UnitSystem/Components/Combat/AI/AICombatSystem.gd`、`AIAttackController.gd`：真实动作占用及带ID通知。
- `UnitSystem/Components/Combat/Squad/SquadFocusComponent.gd`、`ComboCostLedger.gd`：绑定只读接口、非变更计价预览。
- `UnitSystem/AI/Ally/Units/Guardian.tscn`、`Priest.tscn`、`Caster.tscn`、`Archer.tscn`：SkillHost/SkillSocket各装一个独立验证技能、引用combo_skill。
- `project.godot`：仅通过MCP InputMap增加四个动作。

八个新测试按后续任务列明；已有测试迁移候选为SingleSceneDeliveryRunnerTest、SingleSceneSkillBaseTest、SkillSlotContractTest、SkillSlotRoutingTest、CharacterSkillSlotAssemblyTest、RepeatedSkillCastingLifecycleTest、AISkillActionAnimationTest。只修改确受本设计改变的契约断言，不修改当前伤害/目标/治疗参数迎合实现。发现其他必要迁移时在验收记录逐项说明。

新增指南`SkillSystem/04-Docs/SquadChainCommandConfigurationGuide.md`；实施完成后创建`Docs/Superpowers/Plans/2026-10-13-burst-combo-stage-2-validation.md`。本计划阶段不创建空验收记录。

## 验证方式与交付检查点

首选Godot MCP Pro：`run_headless_script({script_path: "res://…Test.gd", timeout_sec: 120})`。等效命令：

```powershell
& 'G:/Godot/Godot_v4.7-stable_win64.exe/Godot_v4.7-stable_win64.exe' --headless --path 'G:/Godot/ProjectVOD' --script 'res://SkillSystem/05-Tests/SkillCommandSlotContractTest.gd'
```

每个新测试extends SceneTree，成功输出`文件名去扩展名: PASS`并quit(0)，失败quit(1)并列出断言。RED使用路径/方法存在性守卫及动态load，不能将尚未导入class_name的解析报错算行为失败；最低接口外壳导入后仍须证明行为RED再实现。

| 组 | 任务 | 可独立检查的成果 |
| --- | --- | --- |
| 1 共用请求与交付 | 1—2 | 槽位/费用可配置；普通兼容；追踪交付不会覆盖上下文 |
| 2 伙伴动作接入 | 3—4 | 等旧动作、接近、当前锁定、请求标识与施放锁可测试 |
| 3 队伍账务与清理 | 5—6 | 预留/提交/退款、重复费用、根子生命周期不串场 |
| 4 输入与可见交付 | 7—8 | 1—4卡片、四技能、独立预览、全回归及独立review |

每任务结束核对中文说明、新增exports和diff，记录测试证据。组间先review再继续；不把中间绿灯当整个阶段验收。

## Task 1：请求数据、费用组件与连携槽

**Files:** Create SkillCommandRequest.gd、ComboFocusCost.gd（路径见清单）；Modify `SkillSystem/01-Core/SkillContext.gd`、`SkillBase.gd`、`SkillHostComponent.gd`；Test `SkillSystem/05-Tests/SkillCommandSlotContractTest.gd`。

**Interfaces:**

- `SkillContext.Purpose { REGULAR, CHAIN }`；内部`purpose: int = REGULAR`、`preferred_target: Node3D`、`command_request: SkillCommandRequest`、`delivery_token_id: int = 0`。duplicate_context深复制damage_context、共享request、复制用途/首选目标/token。
- `ComboFocusCost extends Node`；`base_focus_cost: float = 20.0`、`repeat_focus_cost: float = 10.0`，有限非负；`validate_configuration() -> PackedStringArray`。只配置，不commit/refund。
- `SkillBase.get_combo_focus_cost() -> ComboFocusCost`：恰好一个合法直接子节点才返回，否则null并提供中文警告。
- `Host.combo_skill: SkillBase = null`、`get_combo_skill() -> SkillBase`；槽位规则与已有Socket/注册校验一致，不能与常规/终结共享实例或skill_id，普通选技和站位范围只读常规槽。
- `SkillCommandRequest.create(request_id: int, round_id: int, caster: Node3D, skill: SkillBase, scene_scope: Node, wait_timeout_seconds: float, release_authorizer: Callable) -> SkillCommandRequest`：非法身份/引用/有限正等待返回null。只存caster/skill WeakRef和scope数字ID，不保存世界节点。
- Request只读身份`request_id/round_id/caster_instance_id/skill_id/scene_scope_id`；`get_caster() -> Node3D`、`get_skill() -> SkillBase`、`authorize_release() -> bool`。无效Callable失败关闭，授权只检查，不收费；回调只bind数字ID和世代。
- Request状态方法`has_released()/has_failed()/has_action_started()/has_action_finished()/has_wait_expired() -> bool`；`tick_wait(delta: float) -> void`累计有限非负秒数，动作开始后停止。Task 1同时实现Task 6列明的状态标记、token与一次终态通知纯数据接口；Task 6再将它们接入实际根/子交付。均内部API而非Inspector配置。

- [x] 写`test_combo_slot_is_independent`、`test_slot_conflicts_fail_closed`、`test_cost_component_contract`、`test_context_request_identity_and_weak_owners`、`test_request_state_and_tokens_are_idempotent`。覆盖空/重复/跨Host/未注册槽、缺/多费用组件、NaN/INF/负数、普通AI不选择combo，查询不修改原上下文；Request单独验证动作结束但token未结束不通知、重复终结只通知一次、动作开始后等待不累积。

```gdscript
assert(host.get_combo_skill() != host.get_regular_skill(0))
assert(not host.get_equipped_regular_skills().has(host.get_combo_skill()))
assert(copy.command_request == original.command_request)
assert(copy.damage_context != original.damage_context)
assert(cost.base_focus_cost == 20.0 and cost.repeat_focus_cost == 10.0)
```

- [x] 运行新测试证明受控RED；运行既有SkillSlotContractTest/SkillSlotRoutingTest记录普通基线。
- [x] 通过MCP实现上述最小类型、槽位及组件发现；固定DeliveryRunner/RuntimeEffects和普通字段不改变。
- [x] 运行新测试及两项旧测试，均PASS；删除caster/skill后Request getter为null，Request不保活节点。
- [x] Review身份分配仍复用CombatDamageContext.allocate_id，7项配置预算未被额外内部exports侵占。

## Task 2：交付接受边界与追踪并发

**Files:** Create `SkillSystem/02-Delivery/TrackingProjectileDeliverySession.gd`；Modify `SkillSystem/02-Delivery/SkillDeliveryRunner.gd`、`SkillSystem/01-Core/SkillBase.gd`；Test `SkillSystem/05-Tests/TrackingProjectileConcurrencyTest.gd`；Migrate必要的SingleSceneDeliveryRunnerTest断言。

**Interfaces:**

- Session `start(config: TrackingProjectileDeliveryConfig, context: SkillContext, launch_transform: Transform3D, effects: Array[SkillEffectBase]) -> bool`、`cancel(reason: StringName = &"cancelled") -> void`；完成/失败信号签名同ArcProjectileDeliverySession，终结后解除自身监听并释放节点。
- Runner原execute签名不变，true严格表示已接受交付；其delivery_started先于任何被接受交付的效果，delivery_finished/failed各终结一次。cancel继续取消本Runner全部在途会话，is_busy表示仍有交付，不再作为下一次Tracking的入口阻挡。
- `SkillBase.delivery_failed(context: SkillContext, reason: StringName)`独立于当前SkillState；Task 3/6按身份使用。delivery_started由Runner接受回调恰好一次转发，不在execute返回后再次发。
- Instant目标/Effects预检后接受再应用；Tracking launch true后接受、缓冲同步命中；Arc复用已有缓冲会话；GroundArea验证落点/类型/launch及容器就位后接受再launch。接受后最终失败仍返回true。

- [x] 写`test_two_tracking_deliveries_keep_original_contexts`、`test_synchronous_launch_acceptance_order`、`test_unaccepted_launch_never_applies_buffered_hit`、`test_instant_and_ground_area_accept_before_effect`、`test_terminal_signal_does_not_depend_on_current_skill_state`、`test_sessions_disconnect_on_cancel`。使用真实Runner、PackedScene投射物契约，补一组现有Firebolt真实投射物，不仅用替身。

```gdscript
assert(runner.execute(config, first, origin, effects))
assert(runner.execute(config, second, origin, effects))
assert(first.damage_context.request_id != second.damage_context.request_id)
assert(events == [&"accepted", &"effect", &"failed"])
assert(accepted_result) # Effect或区域launch在接受后失败仍为true
```

- [x] 运行新测试得到RED；预检失败断言无accepted/无效果，启动同步报告命中但返回false也不能施加缓冲效果。
- [x] 将旧Tracking运行字段与回调移入Session，Runner维护会话集合/信号转发。保留原投射物8参数契约、碰撞、目标和Effects，不复制新伤害规则。
- [x] 调整Base释放实现：保存本次context局部引用，在接受回调置本次已释放；同步完成/失败不能让后续返回分支重复清理、重发接受或错误refund。普通SkillCostBase支付规则保留，接受后的效果失败不触发未释放退款。
- [x] 运行新测试、SingleSceneDeliveryRunnerTest、SingleSceneFireboltTest、ArcProjectileDeliveryTest、MultiShotArcDeliveryTest、MarkedTargetVolleyTest，均PASS；核对迁移仅涉及接受与最终结果区别。
- [x] Review所有接受边界，确认旧失败即使Base READY或另一次CASTING仍携带旧context；Session集合在退出后归零。

## Task 3：Host等待、用途与带标识动作

**Files:** Modify `SkillSystem/01-Core/SkillBase.gd`、`SkillHostComponent.gd`、`UnitSystem/Components/Combat/AI/AIAttackController.gd`、`AICombatSystem.gd`；Test `SkillSystem/05-Tests/SkillCommandActivationTest.gd`。

**Interfaces:**

- `SkillBase.prepare_request(context: SkillContext) -> SkillContext`：复用原_prepare_context及首选目标解析，查询不占动作、不支付、不刷新冷却；不以当前技能忙碌阻挡下一条缓存预检。activate/can_request按purpose区分冷却，普通默认不变。
- Host `prepare_command_context(preferred_target: UnitBase = null) -> SkillContext`：复用本Host候选/技能预检返回新CHAIN显式角色动作context，空表示配置/目标/软硬条件不合法；用于受理与执行，共用而非两份目标算法，范围不足仍允许接近。
- Host `enqueue_command(request: SkillCommandRequest) -> bool`、`has_pending_command() -> bool`、`has_command_action_lock() -> bool`、`advance_pending_command(preferred_target: UnitBase, delta: float) -> bool`、`cancel_command(request_id: int, reason: StringName) -> void`。enqueue只缓存，advance true表示本帧由连携等待/动作/接近分支拥有。
- Host `get_pending_command_id()/get_active_command_id() -> int`、`get_command_phase() -> StringName`供只读状态。phase取`idle/waiting/approaching/casting/released`，故障原因另传，不制造CD阶段。
- Host新增`command_failed(request_id: int, reason: StringName)`、`command_state_changed()`通知；Host报告事实、Controller在Task 5统一记根失败和退款，不双支付。
- Host既有`confirm_active_action_started(cast_transform: Transform3D, expected_request_id: int = 0) -> bool`、`release_active_action(launch_transform: Transform3D, expected_request_id: int = 0) -> bool`、`finish_active_action(expected_request_id: int = 0) -> void`追加标识；0兼容旧普通调用，新连携回调必须正ID并匹配。取消连携统一cancel_command，不凭当前READY判断动作结束。
- AIAttackController和AICombatSystem `is_action_in_progress() -> bool`覆盖普攻与外部动作；`request_external_action(effective_cast_time: float, target: UnitBase = null, action_payload: Dictionary = {}, request_id: int = 0) -> bool`；`external_action_lifecycle(request_id: int, event: StringName)`事件为`release/finish/cancel`。保留旧三无参数信号，行为层仅接新通知。

- [x] 写`test_chain_bypasses_only_timing_gates`、`test_one_pending_until_action_confirmed`、`test_lock_survives_release_and_ready`、`test_expected_id_rejects_old_events`、`test_conditions_keep_existing_scope`。普通实例CD>0仍拒绝普通调用，同样计时下CHAIN可用但真实动作锁拒绝并发；ALL_REQUESTS拒绝、AUTOMATIC_ONLY不约束显式连携。

```gdscript
assert(host.enqueue_command(first_request))
assert(not host.enqueue_command(second_request)) # 第一条尚未开始，含接近
assert(host.confirm_active_action_started(origin, first_id))
assert(host.enqueue_command(second_request)) # 开始动作后才腾出pending
assert(not host.release_active_action(origin, old_id))
assert(host.has_command_action_lock()) # 接受交付后仍未finish
```

- [x] 行为RED通过后实现用途门禁与Host状态；Host物理帧不得私自重试chain QUEUED，推进权只归行为层，普通重试保持。
- [x] 请求动画成功后才确认动作开始/移pending到active；确认失败取消本次实际动作，不残留锁。带ID通知先捕获旧ID再复位，不用已清空的新当前值。
- [x] 外部动作保持合法release标记、有限且非循环资产检查及animation_finished兜底；内部故障截止取实际动作时长加内部余量1秒，不export，不作为正常动作提前结束点。
- [x] 运行新测试、SingleSceneSkillBaseTest、SkillConditionScopeTest、AIAttackControllerTest、AICombatSystemTest、AISkillActionAnimationTest、RepeatedSkillCastingLifecycleTest，全部PASS。
- [x] Review：CHAIN不启动/延长Host或BSM普通GCD，不清零普通技能CD；旧0标识普通通知不得误命中新连携。

## Task 4：行为优先级、接近与执行时目标

**Files:** Modify `UnitSystem/Components/Behavior/AllyBehaviorStateMachine.gd`、`SkillSystem/01-Core/SkillHostComponent.gd`、`SkillBase.gd`；Tests `UnitSystem/Tests/AllyChainCommandPriorityTest.gd`、`ChainCommandTargetSelectionTest.gd`。

**Interfaces:** 使用Task 3 Host推进/真实动作查询/带ID接口。当前玩家目标使用已有`PlayerBase.get_locked_target() -> UnitBase`读取；preferred_target仅合法敌方锁定意图。SkillBase按自身target_relations验证后优先，否则沿用已有TargetResolver；AITargeting失效目标走原refresh_target/Policy，不写入玩家目标。

- [x] 写`test_started_normal_action_finishes_before_chain`、`test_unstarted_approach_yields_without_new_normal_action`、`test_protection_and_disengage_cannot_steal_chain`、`test_chain_does_not_extend_normal_gcd`；以真实Guardian/Caster的AnimationPlayer与动作控制器验证开始/释放/结束顺序，不仅伪造Host。
- [x] 写`test_current_lock_wins_only_for_hostile_skill`、`test_heal_uses_friendly_selection`、`test_pending_refresh_and_started_target_freeze`、`test_dead_target_reselects_before_start`、`test_switching_locks_does_not_reset_deadline`。两合法敌人A/B：pending时A→B执行B，动作开始后B→A仍执行B；友方治疗不攻击锁定敌人。

```gdscript
assert(released_target == enemy_b)
assert(ai_target_after == ai_target_before) # 合法旧AI锁定未被玩家意图覆盖
assert(is_equal_approx(gcd_after, maxf(gcd_before - elapsed, 0.0)))
assert(timeout_request.has_wait_expired()) # 连续换锁累计8秒仍到期
```

- [x] 两新测试行为RED后，将physics_tick顺序调整为先普通计时、连携资格/动作分支，再保护/脱战/阵型/普通选技；等待旧动作只维持其原移动与朝向，不能趁等待又启动普通攻击。
- [x] 普通未开始接近/排队让位；chain接近复用现有locomotion和1.5秒无进展检查，刷新当前锁定但不重置请求总等待。无目标、封锁、死亡、超时走本ID失败，动作开始后的合法取消仍按原规则。
- [x] BSM迁移到单一带ID动作通知；普通释放仍起普通GCD，CHAIN释放不改该计时。已释放但未finish的chain动作继续拥有本帧。
- [x] 运行两新测试、AllyBehaviorStateMachineTest、AllySkillCombatPolicyTest、SkillApproachRecoveryTest、ProtectAlliesPolicyTest、AllyTargetingIntegrationTest，全部PASS；确认没有新控制效果或连携专属选目标参数。
- [x] 组2 review：空闲最早衔接、不抢断、不饥饿、换锁/目标死亡/保护/脱战边界逐项验证。

## Task 5：队伍控制器、预留与重复计价

**Files:** Create `UnitSystem/Components/Combat/Squad/SquadChainCommandController.gd`；Modify同目录`SquadFocusComponent.gd`、`ComboCostLedger.gd`；Test `UnitSystem/Tests/SquadChainCommandTransactionsTest.gd`。

**Interfaces:**

- Focus `get_bound_scope() -> Node`、`is_party_member(unit: UnitBase) -> bool`、`scope_changed(scope_root: Node)`。解绑先使绑定失效、通知null，再清空/重置资源，回调仍可归还旧预留；相同重复绑定不重置。原事件水位、收益、事务接口不改。
- Ledger `preview_reservation_quote(round_id: int, caster_id: int, skill_id: StringName, base_cost: float, repeat_cost: float) -> float`：纯读，包含同轮同伙伴同技能潜在前序，未知开放轮次从0计，关闭/非法-1，不注册记录。
- Controller仅exports `companions: Array[AllyBase] = [null, null, null, null]`、`focus_source: SquadFocusComponent = null`、`command_wait_timeout_seconds: float = 8.0`。数组必须4且不压缩，重复/跨scope/不同队/不在Focus名单的槽不可用；同scope唯一玩家提供当前锁定和输入资格。
- `submit_slot(slot_index: int) -> bool`、`get_slot_status(slot_index: int) -> Dictionary`、`set_input_enabled(enabled: bool) -> void`、`set_round_source(peek_current: Callable, acquire_for_request: Callable) -> void`、`close_round(round_id: int) -> void`。两Callable无参数返回int，peek可0但不可分配，acquire须正单调ID；无来源失败关闭。
- 状态字典含`can_submit: bool, reason: StringName, phase: StringName, actor_name: String, skill_name: String, icon: Texture2D, estimated_cost: float, active_request_id: int, pending_request_id: int`；无效费用-1，不泄漏可修改记录。UI查询不调用目标解析、不新增轮次；动态目标/条件在submit及执行重新验证。
- 信号`command_accepted(request: SkillCommandRequest)`、`command_rejected(slot_index: int, reason: StringName)`、`command_released(request_id: int, final_cost: float)`、`command_lifetime_finished(request_id: int, round_id: int)`、`request_activity_changed(round_id: int, live_requests: int)`、`slot_status_changed(slot_index: int)`。
- 授权回调只验证当前世代、未释放记录、原预留与最终报价可提交；root accepted时ledger.mark_released→Focus.commit→Request.mark_released，先于伤害效果。失败仅mark_failed/refund一次；成功后失败不逆转。

- [x] 写`test_four_actor_reservations_are_bounded`、`test_failed_predecessor_releases_quote_surplus`、`test_released_miss_still_costs_and_repeats`、`test_no_round_source_fails_closed`、`test_acquired_but_rejected_round_reports_zero_live_requests`、`test_synchronous_accepted_failure_stays_charged`、`test_status_peek_is_non_mutating`。

```gdscript
assert(focus.get_reserved_focus() == 50.0) # 前序20、后序上界30
assert(second_final_cost == 20.0) # 前序释放前失败
assert(focus.get_current_focus() == 80.0 and focus.get_reserved_focus() == 0.0)
assert(instant_events == [&"accepted", &"charged", &"damage", &"delivery_failed"])
assert(empty_batch_notifications == [[round_id, 0]])
assert(records_after_repeated_ui_peek == records_before)
```

- [x] 运行新测试行为RED；同时运行SquadFocusComponentTest、ComboCostLedgerTest、SquadFocusSceneBindingTest保存旧契约。
- [x] 实现绑定及只读预览接口；Controller按预检→acquire→登记/上界→reserve→enqueue→accepted顺序，任一失败统一回滚。受理后等待动画下一帧，禁止同步execute越过记录建立。
- [x] 费用在受理取快照，派生CHAIN damage_context使用根request_id/round_id/skill_id及收益0。同伙伴串行释放符合Ledger先后约束，跨伙伴独立；close_round关闭账本新受理但不取消旧请求。
- [x] acquired后失败即使活请求0也通知；已受理活请求计数包含动作和所有交付，不等同未扣费数量。不根据该数关闭伤害窗口。
- [x] 运行新测试和三项旧契约，全部PASS；校验Instant/GroundArea最终失败不退款、Tracking启动false退款、重复/迟到通知不二次扣费。
- [x] Review顺序与每条失败路径；缺绑定、长度错误、重复伙伴、非法timeout/费用、Focus余额恰好足够及不足均失败关闭且保留其他有效槽。

## Task 6：根动作、子交付与退出清理

**Files:** Modify `SkillSystem/01-Core/SkillCommandRequest.gd`、`SkillBase.gd`、`SkillHostComponent.gd`、`SkillSystem/03-Extensions/TriggerSkillEffect.gd`、`SquadChainCommandController.gd`（完整路径见清单）；Test `UnitSystem/Tests/SquadChainCommandLifecycleTest.gd`。

**Interfaces:**

- Request `retain_delivery(token_id: int) -> bool`、`finish_delivery(token_id: int) -> void`、`mark_action_started() -> void`、`mark_action_finished() -> void`、`mark_released() -> void`、`mark_failed(reason: StringName) -> void`；`lifetime_finished(request_id: int, round_id: int)`仅一次。token正单调身份，同一token重复登记拒绝、重复终结幂等。
- 终结条件：根已释放或失败，且动作结束或失败从未开始，且全部token结束。成功根不能被mark_failed变成可退款；Request不得提前终结后再接受新token。
- Host只记动作状态；Controller只记根释放/失败及终态账务。Base在execute前retain，未接受/最终完成/最终失败均恰好一次finish；开始失败的根必须完成动作清理后通知终态。
- Trigger子context共享request、复制damage_context来源，但purpose REGULAR、execution DIRECT_TRIGGER、preferred_target空、新delivery_token0；新建自己的交付token。子技能自身CD/普通Cost仍遵循已有配置，不再次进入队伍登记/授权/收费。

- [x] 写`test_actor_and_projectile_complete_independently`、`test_child_keeps_root_lifetime_without_extra_fee`、`test_zero_cd_child_failure_releases_instance`、`test_old_action_and_delivery_cannot_clear_new_request`、`test_scope_unbind_refunds_only_unreleased`、`test_reload_has_no_callbacks_or_records`。

```gdscript
assert(not lifetime_finished_after_root_hit) # 动作/子弹仍在运行
assert(child_context.command_request == root_context.command_request)
assert(child_context.purpose == SkillContext.Purpose.REGULAR)
assert(child_context.damage_context.focus_yield_multiplier == 0.0)
assert(charged_root_count == 1 and charged_child_count == 0)
assert(lifetime_signal_count == 1 and remaining_tokens == 0)
```

- [x] 行为RED后将Task 1纯数据token和根状态接入真实执行路径，迟到delivery_failed即使装备技能已READY仍结束原token，不取消新active。
- [x] Trigger子实例同时监听独立delivery_failed和启动/取消，任一终态幂等queue_free；旧0CD失败不能因SkillBase当前状态漏清理。Effects中创建子token发生在父token终结前。
- [x] 场景解绑先停止输入、取消未释放、退款，再清记录/监听/Callable；已释放不退款。取消本请求不得使用Runner.cancel误杀同装备技能其他已释放的在途请求；只有世界/Runner整体退出使用全量cancel。
- [x] 用弱引用验证10次场景重载：预留0、Host pending/active0、旧Request/技能/世界WeakRef null、旧池回调0，预热后孤儿节点不增长；再做1000次失败/接受终态事务验证记录回收，旧轮closed水位不可重开。
- [x] 运行新测试、TriggerSkillEffectTest、TriggeredSkillActivationTest、ExplosiveArrowChainIntegrationTest、ExplosiveArrowStressTest、SkillDamageProvenanceTest，全部PASS。确认无Request自身bind产生循环；已释放来源删除沿原规则处理。
- [x] 组3 review：账务与实际生命周期相互独立、全部失败分支有终态、未开窗空批次通知及旧世代隔离齐备。

## Task 7：InputMap、四技能、只读反馈与独立预览

**Files:** Create控制器/UI/预览三个tscn、UI/预览两个gd、四个Combo_技能场景（清单路径）；Modify四伙伴源场景、project.godot和Controller输入处理；Test `UnitSystem/Tests/SquadChainInputDisplayTest.gd`；Create `SkillSystem/04-Docs/SquadChainCommandConfigurationGuide.md`。

**Interfaces:**

- InputMap `squad_chain_1`—`squad_chain_4`默认物理键1—4；MCP set_input_action设置，脚本只识别动作名。Controller _unhandled_input仅新pressed、不echo，成功受理后消费本事件；暂停、输入禁用、玩家结果流程禁用、解绑时均拒绝新请求，不因此取消已有请求。
- Display唯一export `command_source: SquadChainCommandController`；CanvasLayer根及原生Control四卡固定索引，所有卡mouse_filter IGNORE、focus_mode NONE，监听只读状态通知和Focus变化。施放中pending空仍可请求，不画伪CD/评分/伤害间隔条。
- Preview继承`res://Scenes/TestCombatRoom.tscn`，复用现有17单位；静态加Controller和Display，companions依次Guardian/Priest/Caster/Archer，focus_source引用继承组件，仅覆盖预览initial_focus=100。
- Preview脚本注入peek/acquire的单个开发批次，ID由通用分配器取得，场景重开生命周期清理；显示“阶段二指令验证；非正式连携窗口”。不添加重置键、固定总时长、自动窗口或GameRun变更。
- 四源场景将独立Combo实例放`SkillHost/SkillSocket`、combo_skill强类型引用。Guardian近战hit窗口不得早于释放接受；普通动画/参数不修改，发现不合格资产先诊断，不以免费伤害迁就。

- [x] 写`test_input_map_and_echo_gate`、`test_fixed_slots_and_missing_references`、`test_display_never_mutates_quotes`、`test_ui_does_not_capture_focus_or_mouse`、`test_preview_assembly_and_scene_uids`。测试InputEventAction新按、echo物理事件、释放、暂停/禁用均正确，不用硬编码键值调用生产逻辑。

```gdscript
assert(InputMap.has_action(&"squad_chain_1"))
assert(accepted_after_press == 1 and accepted_after_echo == 1)
assert(cards.size() == 4 and cards[0].focus_mode == Control.FOCUS_NONE)
assert(cards[0].mouse_filter == Control.MOUSE_FILTER_IGNORE)
assert(ResourceLoader.get_resource_uid(scene_path) != ResourceUID.INVALID_ID)
```

- [x] 运行新测试行为RED后，使用MCP保存InputMap、场景与槽位，不手写project.godot。独立技能不共享原实例、不更改现有资源值，复用Effects而非复制脚本。
- [x] 指南记录7项配置、四引用稳定顺序、SkillSocket位置、开发批次非正式含义、如何换现有技能/VFX、常规与连携区别；特别说明先按1观察实际释放再按2才形成有意顺序。
- [x] 运行新测试、CharacterSkillSlotAssemblyTest、SkillSystemFinalLayoutTest、ResourceUidAuditTest、GreaterHealSkillTest、RapidShotIntegrationTest、GuardianSkillAssemblyProbe及前六任务新测试，全部PASS。
- [x] 用MCP运行Preview，观察1—4、忙碌缓存/缓存满、等待接近、换锁、同一技能重放及费用20→30、治疗不受自动40%软条件限制、真实技能VFX。保存逐笔accepted/released/failed/refund与来源统计，不在正式房间添加测试单位。
- [x] 检查正式房间未挂Controller时仍只释放原常规技能；7新场景经Godot保存，UID/类型/引用有效，Inspector新增字段仅预算7种，无内部状态参数。

## Task 8：完整回归、稳定性与阶段交付

**Files:** Create `Docs/Superpowers/Plans/2026-10-13-burst-combo-stage-2-validation.md`；Update本计划、四阶段路线、配置指南与详细设计状态。测试修复只限本阶段范围。

**Interfaces:** 使用现有`Tools/CombatSimulation/RunSquadFocusSceneAudit.gd`；完整入口以实际`extends SceneTree`扫描发现，不以预期数量代替扫描，预计118旧+8新=126。独立RefCounted `RangedAttackPipelineTest.collect_failures()`仍须检查。

- [x] 执行126个预期SceneTree入口及RangedAttackPipeline契约，逐项退出0、PASS、无非预期ERROR；原有预期配置警告逐条列明，不笼统忽略stderr。
- [x] 运行正式Focus审计（3轮各20秒、10次额外重载），确认原自动战斗来源与专注公式一致、CHAIN收益0、无旧监听/预留/孤儿增长；不要求随机战斗与旧报告伤害总数完全相同。
- [x] 独立Preview运行数据审计覆盖四伙伴并发和重复请求，成功收费总数等于实际根accepted、每失败释放前退款一次、保留旧在途归属。每次重开均有新开发ID，旧回调不能消耗新池。
- [x] 使用requesting-code-review进行整阶段独立审查，提供基线SHA、设计/计划、实际测试输出与Review Focus；修正阻塞项并重跑受影响测试，重大时序修正后再做全回归。
- [x] 检查`git diff --check`、新增/修改文件清单、场景UID和Inspector说明，确认正式场景阵容/参数未改；验收文档记录实际数量、测试命令与输出、review修正、可见验证路径及未实现的阶段三/四。
- [x] 向用户交付预览入口、1—4对应技能、费用/等待观察方式与阶段边界；本地提交/GitHub上传仅在另获授权后进行。

## 计划自检

- 设计1—5/14—15的范围、7项配置、独立内容与文件数由Task 1/7落实；设计6—9的请求/动作/冷却/目标由Task 1/3/4落实。
- 设计10的接受/收费与失败矩阵由Task 2/5落实；11的根子生命周期和退出由Task 3/6落实；12的轮次边界及空批次通知由Task 5/7落实；13输入/UI及17验收由Task 7/8落实。
- Review Focus五项均有明确测试名与所属任务；共享接口参数类型、标识单位和真假返回语义已冻结，不让实现者自行猜测。
- Host.prepare_command_context与command_failed/state_changed是本计划补齐的内部协作接口，不增加配置、第二套目标策略或第二支付所有者。
- 纯Request状态/token接口在Task 1交付，Host动作与队伍账务分别在Task 3/5接入，Task 6落实子交付与退出清理；没有要求早期任务调用尚未实现的Request方法。
- 2026-10-13本阶段已按实际结果标记完成，完整126/126通过、正式审计PASS；详细数据见阶段二验收记录，不将阶段二完成等同于整个爆发系统完成。
