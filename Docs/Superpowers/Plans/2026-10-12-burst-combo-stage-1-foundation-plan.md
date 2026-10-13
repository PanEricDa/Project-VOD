# 爆发连携阶段一 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** 建立有来源归属的真实伤害事件、队伍专注资源与事务、重复费用接口和可见基础预览，不实施连携指令或终结。

**Architecture:** 在 UnitBase 实际扣血处发布新事件，保留原生命信号与仇恨链。SkillContext/命中结果/外部近战 payload 传递来源；场景级 Focus 订阅局部单位并处理收益和账目，纯数据 Ledger 计算重复费用。没有新全局 Autoload。

**Tech Stack:** Godot 4.7、GDScript、PackedScene、SceneTree headless 测试、Godot MCP Pro。

**Spec:** [阶段一详细设计](../Specs/2026-10-12-burst-combo-stage-1-foundation-design.md)，上位[完整玩法设计](../../Vestiges%20of%20the%20divine/爆发连携系统设计-2026-10-11.md)。

> 日期：2026-10-12。状态：2026-10-13 实现、回归与独立审查完成；用户验收后授权本地提交并推送 GitHub。仅实施本计划，不自动进入下一阶段。下列代码片段是接口规格示例；实际交付与验证结果见[阶段一验收记录](2026-10-12-burst-combo-stage-1-validation.md)。

## Global Constraints

- 编辑优先 Godot MCP Pro；Markdown 不受适用编辑工具支持时用 apply_patch 并说明原因。
- 不自动添加或修改 TestScene 单位，不修改现有单位装配、正式技能参数或镜头。
- 当前未提交的代码/场景包含既有工作；执行前记录差异，不能用整文件回退或全目录暂存混入。
- 旧 apply_damage 前三个参数、Resolver 前七个参数、原生命信号签名与相对顺序保持兼容。
- 不实施冷却绕过、缓存优先级、1—4 输入、评分窗口、终结暂停、玩家 Q/E。
- 所有新公开方法、信号、传入字段与 @export 有邻近简体中文职责、单位、默认及约束说明。
- 三个新 tscn 通过 Godot 保存并检查引用；本阶段不新增正式 .tres/.res。若实际新增，必须 ResourceSaver 保存、UID 有效与强类型索引验证。
- 数值 100/0/0.1 及测试费用 20/10 是开发验证参数，不是正式玩法平衡定案。

## Review Focus

1. 同次命中有多个伤害 Effect：event_id 各异、hit_id 相同，实际伤害不能重复消费；Task 1/3 测试。
2. 致命回调释放目标/来源：新事件快照可用且收益仅一次，旧死亡/仇恨顺序不坏；Task 2 测试。
3. 连射/碎片期间角色改用其他技能：来源与根身份不变，不能按 active_skill 重建；Task 3 测试。
4. 前序请求失败而后序已预留加价：按实际成功次数扣款并释放余量；Task 4/5 测试。
5. 动态节点、重绑或退出后旧回调：旧数据不回充新场景、不留预留；Task 6 测试。

## 文件与交付冻结

新增 6 个运行/预览 gd、3 个 tscn、8 个测试 gd、1 个配置指南；不新增外部 Resource，不创建独立伤害管理器或每技能专用脚本。完整清单在详细设计第 8/9 节，以下每个任务引用具体文件。

验证入口统一为 Godot MCP Pro `run_headless_script(script_path, timeout_sec)`。等效 PowerShell 命令：

```powershell
& 'G:/Godot/Godot_v4.7-stable_win64.exe/Godot_v4.7-stable_win64.exe' --headless --path 'G:/Godot/ProjectVOD' --script 'res://UnitSystem/Tests/CombatDamageContractTest.gd'
```

新测试统一 extends SceneTree，最终输出自身 `TestName: PASS` 并 quit(0)，失败 quit(1)。红阶段先通过路径检查/dynamic load 验证缺少接口，不把 class_name 尚未导入的解析错误当作有效行为测试。

## Task 1：来源快照与实际事件契约

**Files:**
- Create: `UnitSystem/Combat/CombatDamageContext.gd`、`UnitSystem/Combat/CombatDamageEvent.gd`。
- Test: `UnitSystem/Tests/CombatDamageContractTest.gd`。

**Interfaces:**
- Context.create(source: Node, scene_scope: Node, origin: Origin = NORMAL, request_id: int = 0, round_id: int = 0, skill_id: StringName = &"") → CombatDamageContext。
- Context.duplicate_context()、for_hit(hit_id: int) → CombatDamageContext；allocate_id() → int。
- Event.create(context: CombatDamageContext, target: Node, health_before: float, health_after: float) → CombatDamageEvent：实际差值正且有限才成功，非法输入返回 null。
- Event.claim(consumer_key: StringName) → bool；所有业务字段发布后只读。

- [x] 写 `test_origin_defaults_and_copy`、`test_unique_ids_and_hit_identity`、`test_snapshot_and_consumer_claim`。断言 NORMAL 收益 1，CHAIN/FINISHER/UNATTRIBUTED 为 0；复制后改派生命中身份不改父；相同消费者第二次 claim false，另一消费者 true。

```gdscript
var child = parent.for_hit(CombatDamageContext.allocate_id())
assert(child.request_id == parent.request_id and child.round_id == parent.round_id)
assert(child.hit_id != parent.hit_id)
assert(event.claim(&"focus") and not event.claim(&"focus"))
assert(event.claim(&"score"))
```

- [x] 运行 CombatDamageContractTest，确认缺类/接口的受控 FAIL。
- [x] 实现两数据类，使用值快照与进程内正身份；不引入 Node 单例或 Resource 预设。
- [x] 运行测试，确认 PASS；验证 source/target 删除后快照身份和数值仍可读，非法 NaN/Inf 不创建收益事件。
- [x] 记录 Task 1 review 快照；检查参数说明与无循环类加载依赖。提交仅在用户明确选择版本记录时进行，不全目录暂存。

## Task 2：权威扣血事件与旧入口兼容

**Files:**
- Modify: `UnitSystem/Base/00_UnitBase.gd:109`、`UnitSystem/AI/Enemy/EnemyBase.gd:99`、`UnitSystem/Player/PlayerBase.gd:184`、`UnitSystem/Combat/CombatValueResolver.gd:24`。
- Test: `UnitSystem/Tests/DamageAttributionIntegrationTest.gd`。

**Interfaces:**
- UnitBase.apply_damage(amount: float, source: Node = null, threat_multiplier: float = 1.0, damage_context: CombatDamageContext = null) → float；保留既有第三参数职责。
- signal damage_resolved(event: CombatDamageEvent)。
- Resolver.apply_damage 的既有 7 个参数后追加 damage_context: CombatDamageContext = null，仍返回实际扣血。
- Resolver 未传 context 时创建 NORMAL，scene_scope 取 source 的当前场景；headless 测试显式提供 scope。直接 UnitBase 兼容调用无 context 时使用 UNATTRIBUTED。

- [x] 写 `test_actual_damage_and_legacy_signal_order`、`test_player_rejected_damage_has_no_event`、`test_enemy_threat_preserved`、`test_lethal_snapshot_before_disposal`。目标剩 7 点、输入 200，事件 actual_damage 必须为 7；免伤/零伤/死亡重复为零事件。

```gdscript
assert(is_equal_approx(applied, 7.0))
assert(events.size() == 1 and is_equal_approx(events[0].actual_damage, 7.0))
assert(legacy_order == [&"health_changed", &"damaged", &"died"])
```

- [x] 红阶段运行新测试；既有 CombatValueResolverTest 先作为不变基线。
- [x] 在实际扣血成功处创建并发布事件，然后保留旧生命信号序列；同步覆盖签名，不让 Resolver 绕开 EnemyBase/PlayerBase。
- [x] 对非有限伤害失败关闭；事件在致命回调之前发布，快照不依赖死亡后访问目标。
- [x] 运行新测试、CombatValueResolverTest、EnemyThreatIntegrationTest、UnitDeathLifecycleTest、PlayerDashComboContinuityTest，全部 PASS 才结束此任务。
- [x] Review：核对旧调用位置参数、仇恨仅提交一次、玩家拒伤分支无事件、新事件没有重复发布点。

## Task 3：技能、近战和碎片来源传播

**Files:**
- Modify: `SkillSystem/01-Core/SkillContext.gd`、`SkillBase.gd`、`SkillHitOutcome.gd`。
- Modify: `SkillSystem/02-Delivery/SkillDeliveryRunner.gd`、`ArcProjectileDeliverySession.gd`。
- Modify: `SkillSystem/03-Extensions/HealthChangeSkillEffect.gd`、`TriggerSkillEffect.gd`。
- Modify: `UnitSystem/Components/Combat/AI/AICombatSystem.gd`。
- Test: `SkillSystem/05-Tests/SkillDamageProvenanceTest.gd`、`UnitSystem/Tests/MeleeSkillDamageProvenanceTest.gd`。

**Interfaces:**
- SkillContext.damage_context: CombatDamageContext；duplicate_context 保留独立副本。
- SkillHitOutcome.hit_id: int，每目标每实际命中正身份；同次 Effects 共享。
- 非空近战 payload 增加 `damage_context` 键，不改变 MeleeSkillAction 静态伤害参数。
- HealthChangeSkillEffect DAMAGE 转发 for_hit；Trigger 子 context 复制根归属，子 hit_id 新建。

- [x] 写 `test_instant_multiple_effects_share_hit`、`test_arc_multi_shot_distinct_hits`、`test_trigger_chain_inherits_origin`、`test_changed_active_skill_cannot_reclassify_hit`、`test_external_melee_metadata_and_empty_payload`。

```gdscript
assert(first.event_id != second.event_id and first.hit_id == second.hit_id)
assert(fragment.request_id == parent.request_id and fragment.round_id == parent.round_id)
assert(fragment.origin == parent.origin and fragment.focus_yield_multiplier == 0.0)
assert(empty_skill.get_action_payload().is_empty())
```

- [x] 运行两个新测试，确认来源或身份未传播的行为 FAIL。
- [x] 先修改 Context 复制、SkillBase 补缺失普通来源与非空近战 payload；显式来源不被 EXPLICIT 或 DIRECT_TRIGGER 覆盖。
- [x] 修改 outcome 创建点和 DAMAGE Effect 转发；不延迟至 delivery_finished 才发布。
- [x] 修改 Trigger 子上下文与 AI 外部近战 payload 消费；普攻继续 NORMAL，不改 Item 投射物。
- [x] 运行两新测试及 SkillHitOutcomeTest、TriggerSkillEffectTest、TriggeredSkillActivationTest、ExplosiveArrowChainIntegrationTest、MultiShotArcDeliveryTest、PyroblastIntegrationTest、BasicAttackDamageIntegrationTest、ShieldSkillFacingContractTest，全部 PASS。
- [x] Review：每目标/每发身份正确；范围多目标不共享错误 hit_id；子技能不自发恢复收益属性；原动作、冷却、弹道和技能数值无变更。

## Task 4：专注收益和资源事务

**Files:**
- Create: `UnitSystem/Components/Combat/Squad/SquadFocusComponent.gd`。
- Test: `UnitSystem/Tests/SquadFocusComponentTest.gd`。

**Interfaces:**
- maximum_focus=100、initial_focus=0、damage_to_focus_ratio=0.1、auto_bind_parent=true；中文 export 文档标明开发占位。
- bind_scope(scope_root: Node, party: Array[UnitBase]) → bool；unbind_scope() → void。
- get_current_focus/get_reserved_focus/get_available_focus → float。
- reserve(request_id: int, amount: float)、commit(request_id: int, final_amount: float)、refund(request_id: int)、release_request(request_id: int) → bool。
- reset_focus() → void；focus_changed(current: float, reserved: float, available: float)。

- [x] 写 `test_normal_damage_gain_and_capacity`、`test_zero_yield_sources`、`test_concurrent_reservations`、`test_commit_refund_idempotency`、`test_invalid_amounts_and_partial_commit`。测试使用 Task 2 真实事件路径，不靠手动增加资源替代来源验证。

```gdscript
# current=50：预留不直接扣除 current。
assert(focus.reserve(101, 30.0))
assert(not focus.reserve(102, 25.0))
assert(focus.commit(101, 20.0))
assert(is_equal_approx(focus.get_current_focus(), 30.0))
assert(is_zero_approx(focus.get_reserved_focus()))
assert(not focus.commit(101, 20.0) and not focus.refund(101))
```

- [x] 红阶段运行新测试，确认缺少组件或事务行为 FAIL。
- [x] 实现线性开发换算、容量和事件 claim；收益过滤使用来源属性、队伍/敌方关系与 scope，不写连携超时特例。
- [x] 实现预留与终态记录；final_amount 不超过预留，重复操作无副作用，release_request 不清理尚有预留的请求。
- [x] 运行测试，验证零收益来源、未知直接扣血、空来源、非队伍来源与非敌方目标不回充；多目标与致命事件正常回充。
- [x] Review：UI 不能写资源，退款不是加钱；事件防重不依赖无限增长全局历史集合。

## Task 5：重复费用账本和预留上界

**Files:**
- Create: `UnitSystem/Components/Combat/Squad/ComboCostLedger.gd`。
- Test: `UnitSystem/Tests/ComboCostLedgerTest.gd`。

**Interfaces:**
- register_request(request_id: int, round_id: int, caster_id: int, skill_id: StringName, base_cost: float, repeat_cost: float) → bool。
- get_final_quote/get_reservation_quote(request_id: int) → float，未知身份返回 -1。
- mark_released(request_id: int) → float，成功前报价并计一次；重复释放回调返回原费用，失败终态返回 -1。
- mark_failed(request_id: int)、close_round(round_id: int)、release_request(request_id: int) → void。

- [x] 写 `test_non_adjacent_repeat_counts_success_only`、`test_pending_predecessor_upper_bound`、`test_failed_predecessor_releases_excess_reservation`、`test_closed_round_retains_old_requests`。closed 禁止新登记，但保留已有请求生命周期。

```gdscript
assert(is_equal_approx(ledger.get_reservation_quote(second_id), 30.0))
ledger.mark_failed(first_id)
assert(is_equal_approx(ledger.get_final_quote(second_id), 20.0))
assert(focus.commit(second_id, ledger.mark_released(second_id)))
assert(is_zero_approx(focus.get_reserved_focus()))
```

- [x] 红阶段确认重复、失败和关闭语义 FAIL。
- [x] 实现按轮次/伙伴/技能记录，缓存上界只包括本请求之前仍可能成功的同键请求；每个请求登记序号固定，同伙伴实际执行串行。
- [x] 接入 Task 4 的组合测试；失败不计次，子碎片不登记，不用技能 CD 控制重复。
- [x] 新轮从零，旧轮已有请求仍按原记录结算；所有引用释放后清理关闭记录。
- [x] Review：不实现窗口时机或游戏重置键，不引入连锁减免，不让身份重复重复计次。

## Task 6：场景绑定与独立只读预览

**Files:**
- Create: `UnitSystem/Components/Combat/Squad/SquadFocusComponent.tscn`。
- Create: `UnitSystem/Components/UI/SquadFocusDebugDisplay.gd`、`.tscn`。
- Create: `Scenes/Previews/SquadFocusFoundationPreview.gd`、`.tscn`。
- Test: `UnitSystem/Tests/SquadFocusSceneBindingTest.gd`、`SquadFocusDebugDisplayTest.gd`。
- Create: `UnitSystem/Components/Combat/Squad/README.md`。

**Interfaces:**
- Display.bind_focus(source: SquadFocusComponent) → void；unbind_focus() → void。
- Display 导出 focus_source: SquadFocusComponent 和 debug_enabled=false，不复制容量或换算参数。
- Focus 从 parent scope 局部发现唯一 Player/同队 Ally，连接该 scope 单位事件及 node_added/tree_exiting 生命周期。

- [x] 写 `test_auto_bind_unique_party`、`test_duplicate_bind_and_dynamic_units`、`test_rebind_rejects_old_scope_events`、`test_unbind_clears_reservations`、`test_display_read_only_and_invalid_source`。
- [x] 红阶段运行两测试，确认缺少场景/显示/绑定行为 FAIL。
- [x] Godot MCP Pro 创建并正式保存三 tscn；Focus 与 Display 是正式可复用源场景，预览引用它们，不复制节点脚本。
- [x] 场景绑定先断旧连接再绑新；只订阅后代 UnitBase，不依赖 EnemyBase/Pack，不每帧全场遍历。多玩家不猜测，旧世代回调失败关闭。
- [x] 显示数值与只读条；预览创建普通、连携和终结来源的实际扣血按钮，以及预留/提交/退款验证按钮。保持与正式输入分离。
- [x] 运行两测试，验证场景可加载、正确根类型、引用有效与 UID；销毁 focus 后 Display 安全解绑，无重复信号。
- [x] 编辑器运行独立 preview，检查普通伤害增长、零收益来源不增长、预留与实扣区别、参数中文提示。必要时使用 Computer Use 检查，不把截图当数值测试。
- [x] README 写明文件、6 个导出配置项、开发默认、手动挂载方法与常见灰显/无收益原因。不自动向 TestScene 添加任何单位。
- [x] Review：无全局 Autoload、无正式关卡装配改动、无新增 .tres、无需每个敌人或碎片配置专注。

## Task 7：阶段一回归与 review 交付

**Files:** 上述实际变更；验收记录新增到 `Docs/Superpowers/Plans/2026-10-12-burst-combo-stage-1-validation.md`，仅执行后创建，当前不创建空验收文件。

- [x] 执行前重新读取 AGENTS、详细设计、计划及 git status/diff；记录基线，必要时根据用户选择的工作方式隔离，不能丢失未提交依赖。
- [x] 运行 8 个新测试，以及 Tasks 2/3 的全部既有回归；追加 CharacterSkillSlotAssemblyTest、CasterSkillActionAssemblyTest、CombatHUDBindingIntegrationTest、GameRunResultFlowTest。必要警告分类记录，任何非预期失败先解决，不改原技能参数来迁就测试。
- [x] 通过 MCP 读取编辑器错误，运行资源引用/UID 检查，git diff --check；确认新脚本说明与目录清单一致。
- [x] 独立 review 数据契约、兼容信号、外部近战与碎片传播、费用幂等、动态场景清理、Inspector；记录问题与对应修复/复测。
- [x] 交付实际 .gd/.tscn/.tres 数量、配置方法、全部测试结果和可见演示；新预览只证明阶段一，不宣称已实现连携操作。
- [x] 用户验收阶段一后授权记录本地版本并推送 GitHub；此次授权单独来自用户后续回复，不由实现计划推导。阶段二仍未开始。

## 本次规划基线

2026-10-12 已实际运行 7 个旧测试，全部 PASS：CombatValueResolverTest、EnemyThreatIntegrationTest、BasicAttackDamageIntegrationTest、SkillHitOutcomeTest、ExplosiveArrowChainIntegrationTest、UnitDeathLifecycleTest、CombatHUDBindingIntegrationTest。HUD 双玩家警告是预期分支。没有运行新的阶段一测试，因为这些实现与测试文件尚未创建。

## 自查与执行交接

Task 1/2 冻结数据与事件，Task 3 解决传播，Task 4/5 冻结资源与费用，Task 6 提供场景/人类配置与可见成果，Task 7 验收；每个任务都有独立测试与 review 关注点。阶段一不提前建立评分管理器、输入控制器或终结导演。

2026-10-13 用户已批准，由当前主代理按任务顺序实施，独立 reviewer 审查并复核修复；118项最终回归通过。用户完成真实场景体验并要求后台稳定性验证后，已授权记录当前项目版本并上传 GitHub；阶段二仍需后续决定。接口关联较强，不建议多个实现者同时修改 UnitBase、SkillContext 或同一个战斗链。
