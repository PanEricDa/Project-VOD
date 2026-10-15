# 爆发连携阶段三：轮次、伤害窗口、评分与反馈实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** 将现有伙伴指令的真实伤害组织为可连续、多轮运行、可结算与可观察的连携，交付独立可试玩预览。

**Architecture:** 新增一个关卡级 SquadChainRoundController；指令控制器继续负责执行和费用，原 CombatDamageEvent 提供伤害事实，原伙伴 UI 展示评价。轮次关闭不等待或取消交付，终结系统留至阶段四。

**Tech Stack:** Godot 4.7、GDScript、原生 Control/Theme、SceneTree 契约与集成测试、Godot MCP Pro。

**Spec:** [已确认的阶段三设计](../Specs/2026-10-15-burst-combo-stage-3-evaluation-design.md)；同时阅读[完整玩法](../../Vestiges%20of%20the%20divine/爆发连携系统设计-2026-10-11.md)和[四阶段路线](2026-10-12-burst-combo-four-stage-roadmap.md)。

日期：2026-10-16。状态：用户已确认并选当前会话逐项实施；阶段三运行功能、回归及独立审查已交付，两项非阻断改进延后，见验收记录。文档基线 3f77e9b，运行代码基线 1942f0a。此前134项活跃测试通过属于历史证据，不代表本阶段已经测试。

## Global Constraints

- 遵循根 AGENTS.md；所有编辑优先 Godot MCP Pro，适用操作不存在或失败才回退并记录原因；Git使用原生工具，不以编辑器接口替代。
- 沿用当前已打开的 G:/Godot/ProjectVOD，不擅自建立不含用户现场改动的隔离工作树。执行前检查差异，保留用户编辑。
- 运行内容只新增1个.gd、2个.tscn、0个.tres；新增3个测试.gd及Godot生成的4个.gd.uid。不建立评分基类、全局事件总线、终结导演空壳。
- 不修改普通AI、SkillBase、SkillHost、Delivery、伤害公式、技能参数、InputMap、角色源场景或正式关卡。不向 Scenes/TestScene.tscn 添加或修改单位实例。
- 沿用原四伙伴独立执行、每伙伴单条缓存、动作锁、目标、专注预留/提交/退款和重复计价；闭窗不取消、不等待已受理请求。
- 第一次有效正伤害计入后开窗；后续有效伤害刷新间隔；没有整轮总时限；截止时刻相等可接续，严格超过才关闭。
- 旧请求保持原round_id；旧伤害正常扣血但不计分、不续窗、不回充专注。新轮重复加价从0起，旧缓存仍按旧轮收费。
- 公式固定 S = 100 × (H / H0 + D / D0)，浮点计算；H为真实命中，D为实际生命损失。后台不封顶，UI只夹紧显示比例。
- 只在ACTIVE闭窗通知终结资格；无终结库存、弹窗、暂停或演出。PENDING空批次、解绑不通知资格。
- 新组件4项导出：command_source=null、damage_interval_seconds=2.0秒、hit_score_scale=20、damage_score_scale=500.0；原UI仅增加round_source=null。每技能新增配置0项。
- 每个export、公开方法/信号及跨模块参数紧邻简体中文说明；原生场景/Theme承载布局颜色，常规配置不依赖代码。
- 不创建正式外部资源；如经额外批准确需新增，必须Godot保存、验证有效UID、脚本类型及Inspector Quick Load，不接受仅文本可load。
- 每个检查点先提供证据与review结果，再进入下一组；本计划不是一次执行全部任务的授权。

## Review Focus

1. 超时收尾尚未发生时输入/伤害到达：仍须先判严格过期，报价不串轮；Task 2 的 deadline/admission/order 测试锁定。
2. 第一笔瞬发伤害后请求立即回收、角色死亡或目标致死退出：不能因延迟查询/节点失效漏记已经发生的命中；Task 3、4 的 synchronous/fatal/posthumous 测试锁定。
3. close_round/round_finished同步回调重入或卸载世界：不能重开旧轮、重复资格或误清新提供者；Task 1、3、7 的 ownership/reentry 测试锁定。
4. 重复伤害事件与一击多效果混合：不重复加D/续窗，同hit可以累加D但H只一次；Task 3 的 dedup/split-hit 测试锁定。
5. UI绑错世界、旧预览无评价源、反复重载：不能展示其他战场、篡改报价/专注或累积监听；Task 5、6、7 的 compatibility/reload 测试锁定。

---

## 1. 文件与装配范围

以下路径均相对于项目根；不得把计划列出的“新增”误当作已交付。

| 类型 | 精确路径 | 职责 |
| --- | --- | --- |
| 新运行脚本 | UnitSystem/Components/Combat/Squad/SquadChainRoundController.gd | 正式轮次、伤害监听、战斗时钟、评分与只读结果 |
| 新组件场景 | UnitSystem/Components/Combat/Squad/SquadChainRoundController.tscn | 可实例化的唯一评价节点 |
| 新继承预览 | Scenes/Previews/SquadChainRoundPreview.tscn | 继承ChainSkillPresentationPreview，不添加单位 |
| 修改脚本 | UnitSystem/Components/Combat/Squad/SquadChainCommandController.gd | 只读释放身份查询、按回调身份安全撤销提供者 |
| 修改UI | UnitSystem/Components/UI/SquadChainCommandDisplay.gd | 可空评价引用、Focus与评价读取、短暂结果显示 |
| 修改UI场景 | UnitSystem/Components/UI/SquadChainCommandDisplay.tscn | 在原四卡上方添加信息区，不改四卡路径 |
| 新测试 | UnitSystem/Tests/SquadChainRoundWindowTest.gd | 轮次、时间、过滤、去重与数学 |
| 新测试 | UnitSystem/Tests/SquadChainRoundIntegrationTest.gd | 真实指令、交付、费用、并发与清理 |
| 新测试 | UnitSystem/Tests/SquadChainRoundDisplayTest.gd | 旧UI兼容、只读绑定、预览与显示 |
| 修改说明 | SkillSystem/04-Docs/SquadChainCommandConfigurationGuide.md | 配置入口、装配、试玩、复用 |
| 修改索引 | Docs/Superpowers/Plans/2026-10-12-burst-combo-four-stage-roadmap.md | 阶段三状态与验收链接 |
| 修改进度 | Docs/CurrentProgressReport.md | 实际完成范围，不把未来任务写成完成 |
| 新验收记录 | Docs/Superpowers/Plans/2026-10-16-burst-combo-stage-3-validation.md | RED/GREEN、回归、实跑、review及限制 |

后四项运行文档在Task 7同步。本计划编写时仅更新设计/进度索引中的“已确认、计划待审”状态，不创建验收成功记录。

配置关系：

```text
预览根（继承现有表现预览；本层script=null）
├─ 原SquadFocusComponent → 原SquadChainCommandController
├─ SquadChainRoundController.command_source → 原指令控制器
└─ 原SquadChainCommandDisplay
   ├─ command_source → 原指令控制器
   └─ round_source → 新评价组件
```

## 2. 冻结接口与数据契约

### 2.1 评价组件

```gdscript
enum Phase { IDLE, PENDING, ACTIVE }
signal round_state_changed(snapshot: Dictionary)
signal round_finished(result: Dictionary)
signal finisher_qualified(result: Dictionary)

func peek_current_round() -> int
func acquire_round() -> int
func get_round_status() -> Dictionary
```

- peek无副作用；未绑定、无当前轮或已经严格过期返回0；当前轮沿用已捕获的合法配置。不得分配/闭窗/通知/改账本。
- acquire仅由原真实受理流程调用；先关闭严格过期轮，再捕获配置并分配全局单调正身份；不可用返回0。使用现有CombatDamageContext.allocate_id，不新增静态身份池。
- get_round_status返回深复制纯值；可以读取时钟计算剩余量，不能因此关闭或创建轮次。
- 四项导出按Assembly / Evaluation分组，浮点项须有限且正，H0至少1；非法配置清晰告警并拒绝建立新轮，不影响已受理请求，当前轮已捕获的配置保持不变。
- 各次信号分别发送纯值深复制，监听者按只读契约消费，不复用内部字典；get_round_status的返回副本可被调用方修改而不污染内部结果。

快照固定字段：

| 字段 | 类型/值 | 约定 |
| --- | --- | --- |
| bound | bool | 成功独占装配且世界有效；不是ACTIVE开关 |
| phase | int / Phase | IDLE、PENDING或ACTIVE |
| round_id | int | 当前身份；IDLE为0 |
| hit_count | int | H |
| total_damage | float | D |
| score | float | S，可大于100 |
| progress_ratio | float | clamp(S/100,0,1) |
| interval_seconds | float | 当前捕获间隔；无当前轮为0 |
| remaining_seconds | float | ACTIVE业务剩余量；其他为0 |
| finisher_ready | bool | ACTIVE且S>=100 |
| last_result | Dictionary | 最近结果深复制；没有则空字典 |

result固定字段：round_id:int、scene_scope_id:int、hit_count:int、total_damage:float、score:float、qualified:bool、close_reason:StringName。正常结算原因固定 &"damage_gap"。退出/解绑/空批次仅清理，不伪造round_finished；不存在对应“失败资格”。

### 2.2 指令源最小扩展

```gdscript
func is_released_request(request_id: int, round_id: int, caster_instance_id: int, scene_scope_id: int) -> bool
func clear_round_source(peek_current: Callable, acquire_for_request: Callable) -> void
```

- 身份查询仅查现有_records；四项一致、released且未failed才为true，不暴露记录，不要求角色当前节点存活。
- clear_round_source是set_round_source的对称安全撤销：只有两个Callable均等于当前安装值才清空，否则完全无操作；不取消旧请求/退款。指令源不引用评价类。
- 评价以指令源metadata的WeakRef认领唯一所有者，键固定 &"_chain_round_owner"；拒绝第二组件，不覆盖原回调。退出只撤销自己的认领/Callable。
- 继续消费现有scope_changed(scope_root)、request_activity_changed(round_id,live_requests)、command_accepted(request)、command_lifetime_finished(request_id,round_id)。
- 为核对来源队伍，受理时从request.get_caster()捕获request_id→source_team_id纯值；请求结束即移除，解绑清空。不是第二套请求/费用账本，不持有Request或角色强引用。伤害收到时查释放身份并比较此快照，不能按“角色现在的技能/队伍”猜归属。

### 2.3 内部时间与清理边界

仅作为实现/测试定位，不导出，不增加测试专用公开入口：

```gdscript
func _physics_process(delta: float) -> void
func _finish_frame(frame_id: int, generation: int) -> void
func _on_damage_resolved(event: CombatDamageEvent, generation: int) -> void
```

- 节点PROCESS_MODE_PAUSABLE，内部process_physics_priority=-1000，早于当前单位默认优先级；本帧先推进唯一战斗时钟，事件共用该时间戳。若发现已有更早伤害处理者，先记录并统一调度，不让策划手配优先级。
- _clock_usec:int、_clock_fraction:float保存微秒和未取整残差；只接受有限非负delta。_clock_frame:int每次有效物理推进递增，_generation:int在解绑/重绑时递增。
- 每帧只排一个_finish_frame(frame_id,generation)延迟收尾；只处理当前世代/目标帧，过时重复回调无操作。不是等待所有交付。
- 输入acquire与伤害入口同样先判now>deadline；等于接收。正常UI读取不触发收尾。
- 去重采用当前轮event_id集合与(request_id,hit_id,target_instance_id)集合；当前轮关闭即清空。单个last_result和单调_closed_round_id水位，不保留整局闭轮列表。
- 伤害验证/累计在信号同步入口完成；帧末只做超时收尾，不能把请求合法性留到帧末查询。
- 关闭顺序固定：捕获result→清除当前入口/记录水位→原close_round→round_finished→同世代且达分才finisher_qualified。各外部调用后复核会话；新轮重入不允许旧轮收尾擦除新数据。

## 3. 测试执行约定

所有新增测试extends SceneTree，统一failure数组、失败push_error、成功打印“文件名: PASS”、quit(0/1)，沿用现有测试惯例。每个任务先增加本任务用例，跑RED后才写实现；不可只以故意的解析错误作为整个行为的RED证据。

固定调用命令（通过Godot MCP Pro；参数完整，可逐项执行）：

```javascript
await tools.mcp__godot_mcp_pro__run_headless_script({
  script_path: "res://UnitSystem/Tests/SquadChainRoundWindowTest.gd", timeout_sec: 90
});
await tools.mcp__godot_mcp_pro__run_headless_script({
  script_path: "res://UnitSystem/Tests/SquadChainRoundIntegrationTest.gd", timeout_sec: 180
});
await tools.mcp__godot_mcp_pro__run_headless_script({
  script_path: "res://UnitSystem/Tests/SquadChainRoundDisplayTest.gd", timeout_sec: 90
});
```

下文W/I/U分别指上面对应的完整调用。新类首次缺失可先记录加载RED；类可加载后还须看到新增行为断言失败。GREEN必须同时满足退出0、有该文件PASS、无SCRIPT ERROR/ERROR/超时，预期拒绝装配WARNING单列记录。

测试夹具与驱动：

- Task 1在WindowTest定义static make_fixture(parent: Node) -> Dictionary，供I/U复用。内部复用AllyChainCommandPriorityTest.make_fixture(parent, "res://UnitSystem/AI/Ally/Units/Caster.tscn", false)，增加真实Focus、Commander和Round；关闭单位自主物理/AI，保留真实Host/动画与伤害入口。
- 夹具保留world/player/actor/enemy/host/combo/animation/requests，新增focus/commander/round；requests通过command_accepted捕获实际请求，不自行标记released。Focus initial_focus=100，原ComboFocusCost测试值base=20、repeat=10。
- 自动物理关闭的Round可由测试直接call("_physics_process",delta)，再call("_finish_frame",其_clock_frame,其_generation)。这是测试访问内部实现，不为正式组件提供advance_time等公开方法。
- 请求由commander.submit_slot(0)受理；actor.get_behavior_state_machine().physics_tick(0.01)、animation.release_action()、animation.finish_action()推进真实动作，保持delivery token至用例结束。
- 精确边界/数学用真实已释放请求的CombatDamageContext.create(...CHAIN,request_id,round_id,...).for_hit(...)调用enemy.apply_damage(amount,actor,1.0,context)。集成用例必须另外走真实Delivery/投射物/碎片，不用上述精确驱动替代集成证据。
- 捕获damage_resolved得到原event重复emit测试去重；非法来源用例才构造/篡改测试快照，明确标为对抗测试。禁止修改生产伤害事件以便测试通过。

---

## 检查点一：正式轮次与伤害窗口

### Task 1：独占装配、正式批次和空批次回收

**Files:** 新建Round.gd/.tscn、WindowTest.gd（完整路径见文件表）；修改SquadChainCommandController.gd。

**Interfaces:**

- Consumes: set_round_source(peek_current:Callable,acquire_for_request:Callable)、get_bound_scope()->Node、request_activity_changed(round_id:int,live_requests:int)。
- Produces: §2的三项Round公开方法/Phase/完整快照、两项Commander方法、组件场景、WindowTest.make_fixture(parent:Node)->Dictionary。
- 本任务快照H/D/S保持0；伤害接收Task 2、评分Task 3补充，不提前实现。

- [x] 写test_pending_is_lazy_and_shared、test_pending_zero_activity_cleans_without_result、test_acquire_rollback_cleans_empty_round、test_provider_ownership_is_compare_and_clear。查询100次不得分配；真实受理才PENDING；最后请求失败自然清理；两个评价竞争/反向销毁不触碰原提供者。关键断言：

```gdscript
assert(round_controller.peek_current_round() == 0)
assert(round_controller.get_round_status().phase == SquadChainRoundController.Phase.IDLE)
# 真实受理后保存first_round，再查询/受理同轮。
assert(first_round > 0)
assert(round_controller.peek_current_round() == first_round)
# 全部请求自然结束且从未伤害。
assert(round_controller.peek_current_round() == 0)
assert(finished_results.is_empty() and qualified_results.is_empty())
```

- [x] 运行W确认RED；查询方法缺失之外，还要记录空批次/独占/错误撤销至少一个行为失败；补测is_released_request释放前false、释放后true、四项身份任一不符或自然回收后false。
- [x] 实现只读身份查询、compare-and-clear与Round弱所有权/世界监听生命周期；无世界或非法配置返回0。PENDING捕获配置；同批次activity=0清理并close_round，无结果通知。Scene通过Godot创建保存；所有新增公开项中文说明。
- [x] 运行W到GREEN；额外按相同MCP调用分别运行UnitSystem/Tests/SquadChainCommandTransactionsTest.gd、SquadChainCommandLifecycleTest.gd、ComboCostLedgerTest.gd，预期各退出0且PASS。
- [x] 检查场景仅4项导出，无新资源、无隐含自动全局查找。记录RED/GREEN；按明确文件清单本地提交，建议消息feat: add owned squad chain round provider；不推送，用户不允许提交时保留差异并注明。

### Task 2：同步伤害开窗与暂停安全的间隔时钟

**Files:** 修改Round.gd、WindowTest.gd；不修改Delivery或UnitBase。

**Interfaces:**

- Consumes: Task 1公开接口、UnitBase.damage_resolved(event:CombatDamageEvent)、is_released_request四参数查询、原request身份。
- Produces: §2.3内部时间入口与PAUSABLE时基，PENDING→ACTIVE→IDLE窗口；此时可以累计H/D但评分与资格Task 3落地。

- [x] 增加test_first_damage_opens_and_counts、test_non_damage_does_not_open、test_deadline_equal_is_accepted、test_strict_expiry_before_sweep、test_read_only_quote_and_admission、test_pause_freezes_clock、test_delta_fraction_and_invalid_delta。默认2秒：到2.000000秒接续，到2.000001秒过期；伤害/受理/收尾换序结果一致。首伤前施法/特效/治疗/打空均PENDING；ACTIVE即使无活动请求也等间隔；连续10秒、每1秒产生有效伤害时不得因总时长关闭。关键断言：

```gdscript
assert(snapshot.phase == SquadChainRoundController.Phase.ACTIVE)
assert(snapshot.hit_count == 1 and is_equal_approx(snapshot.total_damage, 25.0))
assert(is_equal_approx(snapshot.remaining_seconds, 2.0))
# 严格超时但尚未执行收尾；查询不改变状态/账本/通知数量。
assert(round_controller.peek_current_round() == 0)
assert(finished_results.size() == before_query_finished_count)
# 受理才结算旧轮并分配新的身份。
assert(new_round > old_round)
```

- [x] 运行W确认RED，重点记录“相等截止误关”“超时未收尾仍接纳旧轮”失败，不能只测大致2秒。
- [x] 在Round实现已有单位扫描、动态加入/退出与带世代的弱监听；校验世界、CHAIN、有限正实际伤害、原释放身份、受理队伍及敌对关系。第一笔先记H/D再通知开窗；进入ACTIVE后每笔合法伤害刷新deadline。实现整数微秒+残差、内部早处理优先级、延迟收尾及入口先过期，禁止墙钟/物理帧差计时。
- [x] 增加原生SceneTree暂停用例：真实0.10秒释放强调和显式暂停期间时钟及remaining不变；恢复继续。另将相同1秒分成60/120/1000步，累计时钟误差不超过1微秒；NaN/INF/负delta不推进。
- [x] 运行W到GREEN，并重跑SkillSystem/05-Tests/ReleaseAccentClockTest.gd、UnitSystem/Tests/ChainSkillPresentationControllerTest.gd。预期评价无新增暂停令牌、原强调/VFX继续正常。
- [x] 本地定向提交建议feat: evaluate chains on the pausable damage gap clock；提交前review截止换序、动态监听、PENDING没有第二个超时器。

**检查点一验收：** W及上述旧测试通过；Inspector只有四项。review轮次提供者与账本边界后才进入第二组。

## 检查点二：评分与真实交付隔离

### Task 3：两层去重、H/D评分与一次资格通知

**Files:** 修改Round.gd、WindowTest.gd。

**Interfaces:**

- Consumes: Task 2真实伤害同步接受与时钟。
- Produces: §2固定H/D/S字段、round_finished(result:Dictionary)、finisher_qualified(result:Dictionary)及纯值last_result。

- [x] 增加test_event_and_hit_dedup、test_aoe_and_multihit、test_score_three_paths、test_fractional_score_and_overkill、test_score_configuration_snapshot、test_close_once_and_reentry。用默认H0=20、D0=500校验以下精确值；UI夹紧不得反向修改后台：
```gdscript
# 独立夹具：20次各1实际伤害；1次500；10次各25；1次25。
assert(is_equal_approx(high_hit_result.score, 104.0))
assert(is_equal_approx(high_damage_result.score, 105.0))
assert(is_equal_approx(mixed_result.score, 100.0))
assert(is_equal_approx(single_result.score, 10.0))
# 一次命中分10+15两次扣血：H=1，D=25，S=10。
assert(split_status.hit_count == 1 and is_equal_approx(split_status.total_damage, 25.0))
assert(is_equal_approx(split_status.score, 10.0))
assert(qualified_results.is_empty()) # 达分但尚未闭窗。
```

- [x] 运行W确认RED；重复原event不能改变H/D或deadline。分裂/多段不同hit分别计数，五目标一次命中每目标计1。非法身份、友军、NORMAL/FINISHER、非有限/非正事件不计不续。
- [x] 实现两层去重、浮点评分及0—1显示比例；伤害超过目标剩余HP时仅计算真实扣血。当前轮捕获间隔/H0/D0，运行中修改只影响下一轮；非法新配置不静默换值、不取消旧请求。
- [x] 按§2.3顺序关闭并发出结果。增加同步瞬发后立即lifetime_finished、致命伤后tree_exiting、来源死亡但投射物仍到达的测试；必须同步接受合法伤害。对round_finished监听者触发新轮/解绑/free评价分别验收，并单独修改getter返回字典验证副本隔离：旧轮最多一次、无跨世代资格、last_result不被查询副本篡改。
- [x] 运行W到GREEN；验证空批次/低分/解绑无资格，达分ACTIVE只ready、自然闭窗finished一次→qualified一次。重复收尾不再通知，评分大于100不截断；重新跑SkillSystem/05-Tests/SkillDamageProvenanceTest.gd。
- [x] 定向本地提交建议feat: score chain rounds with deduplicated real damage；提交前检查无资格库存、无终结暂停、无节点/Request混进对外字典。

### Task 4：旧轮交付、新轮费用与真实并发联调

**Files:** 新建IntegrationTest.gd；只有测试证明必要时才在既定Round/Commander范围修复，不扩展技能框架。

**Interfaces:**

- Consumes: WindowTest.make_fixture(parent:Node)->Dictionary、原submit_slot(slot_index:int)->bool、SkillCommandRequest根/子交付生命周期、Task 3全部结果。
- Produces: 真实Host/Delivery/费用跨轮契约；不增加生产接口。

- [x] 写test_late_projectile_cannot_reopen_or_join、test_old_pending_keeps_old_price、test_new_round_resets_repeat_price、test_rapid_and_fragments_keep_root、test_parallel_reservations_and_failed_release、test_posthumous_projectile_keeps_snapshot。复用真实连射/爆裂箭现有场景，所有修改只限内存夹具。
- [x] 运行I确认RED，至少复现旧_development_round下新轮无法重置费用、无正式归属过滤或迟到伤害入错轮中的一项；若已GREEN则加入反向对照证明测试确实观测到了原round_id而非仅血量。
- [x] 构建具体序列：A首击→留一枚长飞行投射物/同伙伴旧缓存→超过2秒关闭A→另一空闲伙伴受理B→A迟到和B伤害交错。A扣血但不改变B H/D/deadline/Focus收益；A缓存重复费仍30，B同技能首发20。夹具需要额外专注时只改变该夹具容量/初始量，不改正式100容量。
```gdscript
assert(request_b.round_id > request_a.round_id)
assert(is_equal_approx(new_round_base_cost, 20.0))
assert(is_equal_approx(old_round_repeat_cost, 30.0))
assert(after_old_damage.hit_count == before_old_damage.hit_count)
assert(is_equal_approx(after_old_damage.total_damage, before_old_damage.total_damage))
assert(is_equal_approx(focus_after_old_damage, focus_before_old_damage))
```

- [x] 用真实Delivery确认AOE、多发、子碎片继承根请求/轮次、独立命中；实际死亡后投射物仍可命中。两伙伴同帧支付、一个失败一个成功、重复失败回调不重复退款，失败不增加重复次数。保留原缓存占用和锁，不以新轮清空动作。
- [x] 运行I/W到GREEN；重跑SquadChainCommandTransactionsTest、SquadChainCommandLifecycleTest、ComboCostLedgerTest、AllyChainCommandPriorityTest、ChainCommandTargetSelectionTest（路径均UnitSystem/Tests/，后缀.gd）。检查每轮关闭没有调用reset_focus。
- [x] 定向本地提交建议test: cover late chain deliveries and cross-round costs；生产修复与失败复现一起提交，记录实际修复文件，不靠放宽旧断言通过。

**检查点二验收：** H/D三条达分路径、去重与资格时序、真实费用/交付证据齐全；review无复制账本与跨轮串分后进入第三组。

## 检查点三：正式反馈与可试玩预览

### Task 5：在原四伙伴UI整合专注、连击与伤害间隔

**Files:** 修改SquadChainCommandDisplay.gd/.tscn；新建DisplayTest.gd。

**Interfaces:**

- Consumes: get_round_status()->Dictionary、round_state_changed(snapshot:Dictionary)、round_finished(result:Dictionary)、原command_source.focus_source与Focus公开getter/focus_changed。
- Produces: 唯一新增UI导出round_source:SquadChainRoundController=null；无新输入方法、无业务时间计算。

新增节点固定在Panel/VBox下，原Cards/Card1—4及其子路径不变：

```text
Evaluation（VBoxContainer，默认隐藏）
├─ Focus（VBoxContainer）
│  ├─ Values（Label：当前 / 预留 / 可用）
│  └─ Bars（Control：重叠ProgressBar UsedAndReserved / Available）
├─ ChainSummary（Label：连击数字）
├─ ScoreProgress（ProgressBar：0—1）
├─ DamageInterval（ProgressBar：0—1）
└─ Result（Label：就绪/结果）
```

Focus条：UsedAndReserved显示current/maximum的总持有宽度，Available叠加available/maximum；两者差集表达reserved。value内部夹紧0—1、max_value=1，中文数字同时显示原始真实值；这不是重新计算账务。DamageInterval的比例只读remaining_seconds/interval_seconds，无ACTIVE则隐藏。

- [ ] 写test_optional_round_source_keeps_stage_two、test_wrong_source_or_scope_hides_evaluation、test_ui_queries_do_not_allocate_or_charge、test_pending_active_and_summary、test_focus_binding_swaps_cleanly。无round_source保留原四卡；错误绑定只告警/隐藏新增区，不阻断指令。
```gdscript
assert(not display.get_node("Panel/VBox/Evaluation").visible) # 无评价源。
assert(round_before_reads == round_after_reads)
assert(is_equal_approx(focus_before_reads, focus_after_reads))
assert(display.get_node("Panel/VBox/Evaluation/ScoreProgress").value == 1.0) # 后台S>100。
assert(round_controller.get_round_status().score > 100.0)
```

- [x] 运行U确认RED（场景可加载后记录状态/只读断言失败），再实现可空绑定和主动断开旧监听；区分command_source变化、round_source变化与focus_source/世界变化，调整原_refresh_binding的早返回条件，不能只检查command_source而忽略新装配变化。
- [x] 用Godot原生场景编辑添加上述节点、StyleBox/Theme、mouse_filter=IGNORE；底部居中向上自适应，新增区隐藏时原布局不留空。保留现有黄/绿/红、缓存文字和成功0.3秒反馈。
- [x] 增加test_summary_one_second_and_replaced_by_hit、test_ui_pause_matches_business、test_noninteractive_no_extra_input。结算摘要内部1秒，仅表现；新首伤立即替换，PENDING不显示0连击/倒数；显式暂停沿用is_feedback_suspended语义挂起摘要，不用墙钟推进业务窗口。
- [x] 运行U/W/I到GREEN，并跑UnitSystem/Tests/SquadChainInputDisplayTest.gd、SquadFocusDebugDisplayTest.gd、ChainSkillPresentationControllerTest.gd；记录修改前后旧UI兼容结果。
- [x] 定向本地提交建议feat: display focus and chain evaluation in the squad panel；review仅增1项导出、所有新增非交互Control忽略鼠标、不新建1—4输入监听。

### Task 6：装配继承预览与编辑器可读性验收

**Files:** 新建Scenes/Previews/SquadChainRoundPreview.tscn；修改DisplayTest.gd；必要的布局修正仍限既定UI场景。

**Interfaces:**

- Consumes: Round组件场景、Task 5 round_source、Scenes/Previews/ChainSkillPresentationPreview.tscn继承链。
- Produces: F6可运行预览，节点名SquadChainRoundController；无额外预览脚本。

- [x] 写test_preview_uses_formal_provider、test_preview_preserves_existing_content、test_scene_configuration_counts：新预览必须继承原表现预览，根script=null，只有一个Round/原Commander/原PauseCoordinator，UI两项引用正确，无新增单位/技能副本/外部资源。
- [x] 运行U确认RED（新场景缺失）；随后通过Godot编辑器API建立继承场景，保存并重载检查真实PackedScene继承关系；不能以另存完整展开场景冒充继承。
- [x] 覆盖根script=null，避免根_ready再次安装_development_round；添加唯一评价组件、command_source指向原Commander，UI round_source指向评价。仅本预览关闭原Focus开发显示，保留节点与旧预览；更新标题说明1—4/真实伤害间隔，不加重置轮次快捷键。
- [x] 运行U到GREEN；原SquadChainCommandPreview和ChainSkillPresentationPreview仍用原提供者/表现，普通场景未被迁移。新组件导出4项、UI新增1项均有中文提示、强类型引用Inspector可选择。
- [x] 实际运行新预览：常规伤害充能→1/3/4开窗接续→停手结算→再次调用重复价重置；2治疗不虚开窗；观察原镜头/半程VFX/0.10秒强调与窗口冻结同时成立。记录Debugger新ERROR与既有WARNING，不混为零警告。
- [x] 在1280×720和1920×1080检查四卡/新增条不裁切、PENDING/ACTIVE/结果布局与鼠标穿透；可用Computer Use直接操作，启用前阅读对应技能。截图只用于布局，不用GPU截图读回测毫秒时钟。
- [x] 定向本地提交建议feat: add inherited squad chain round preview；未完成真实试玩则标未验收，不以无头通过替代。

**检查点三验收：** 新预览有完整多轮可见循环，原两预览仍可用；由用户review可读性与反馈。不要接入正式TestScene或制作终结菜单。

## 检查点四：连续运行、完整回归与交付

### Task 7：生命周期压力、独立审查与交付记录

**Files:** 扩充既定3个新测试；按失败证据修复既定运行文件；更新文件表中的配置指南/路线/进度，创建阶段三验收记录。

**Interfaces:**

- Consumes: Task 1—6全部公开契约与原生命周期；不得加入测试专用生产API。
- Produces: 可复现压力结果、全量回归记录、独立review结论、明确的装配与用户验收说明。

- [x] 增加test_100_rounds_10_scope_reloads、test_dynamic_units_and_listener_cleanup、test_remove_round_preserves_requests、test_reentrant_scope_change_and_replacement_owner。先执行W/I/U，记录新增边界RED；若边界已GREEN，不为制造失败破坏实现，记录现有行为已覆盖，再加针对性反向对照。
- [x] 真实驱动100次根请求分布至少20次自然闭窗、10次世界重载，包含并发成功/失败、旧请求跨轮。动态生成/移除敌人、重复绑定、拒绝第二评价、删除拒绝方、单独移除有效评价、结算回调内换世界/替换提供者。
- [x] 修复实际失败并重跑三项到GREEN；稳定后检查：当前轮0、去重集合0、队伍快照表0、监听回基线、Commander/账本活动记录0、Focus reserved=0、Host锁/缓存清空、原Pause token和镜头回归。旧请求仍执行时不强求账本提前归零；等原交付自然结束后检查。last_result最多1份，未保留Node/Request强引用；节点free后不能再访问它做“零泄漏”断言。
- [x] 通过rg重新枚举所有活跃SceneTree测试，排除Archive/addons和非测试工具；候选命令为`rg -l --glob '*Test.gd' '^extends SceneTree' UnitSystem SkillSystem Item Effects Scenes Tools`。逐文件按§3 MCP运行，timeout_sec=180；历史134+新增3仅预估137，最终以真实枚举数为准。逐项保存退出/PASS/错误/耗时，不能只报总数。
- [x] 额外通过Godot编辑器脚本加载UnitSystem/Tests/RangedAttackPipelineTest.gd，调用.new().collect_failures()，预期[]；RefCounted不调用free。重跑原Focus正式场景审计Tools/CombatSimulation/RunSquadFocusSceneAudit.gd（同MCP，timeout_sec=180），无正式场景编辑。
- [x] 实跑新预览完整一轮/连续多轮、连射、长飞行晚到、治疗穿插、菜单暂停及重复按键；采样实际正常战斗时钟与专注。停止运行后检查Debugger，无本次引入SCRIPT ERROR/ERROR。未实际人工验证的手感项目单列，不声称自动测试证明舒适度。
- [x] 请求独立只读代码review，提供设计、计划、最终差异和原始测试输出。重点检查本计划5类Review Focus及本组泄漏/重入；发现问题先增加失败复现再修复，并重跑受影响与全量测试，不以“审查过”替代测试。
- [x] 更新配置指南：唯一评价节点四项参数、UI可空引用、继承预览入口、无每技能新参数、关闭评价不取消旧请求、阶段四待实现。验收文档逐组记录证据/限制/工具回退；路线与当前进度仅写实得结果。
- [x] 执行`git diff --check`及差异范围核对；检查project.godot、单位源场景、普通技能源场景、TestScene/TestScene2/TestCombatRoom无本次变化。新场景Godot保存后验证UID有效；运行/测试脚本.uid由Godot登记。无新增.tres。
- [x] 定向本地提交建议test: validate squad chain round lifecycle and regressions；最后交付修改文件数、运行入口、如何验证、全部测试结果、review残留问题。GitHub上传需用户明确授权，不在本计划默认执行。

**检查点四验收：** 所有自动测试与实际Debugger检查有证据；独立审查阻断问题闭环；用户可按下节复现。阶段四仍未开始。

## 4. 用户最终能验证什么

1. F6运行Scenes/Previews/SquadChainRoundPreview.tscn，沿用F/鼠标中键锁定和1—4伙伴调用。
2. 第一笔连携正伤害时出现连击、终结进度与2秒间隔条；施法/治疗不会虚开窗。
3. 每笔有效连射/碎片伤害续条；停手后结算，达分显示资格结果，但不暂停/弹终结菜单。
4. 再次请求开始新轮，重复费用重新从基础值计算；旧弹伤害不加入新轮。
5. 释放强调或菜单暂停时伤害间隔不流逝；恢复后继续。
6. 在唯一Round节点修改间隔/H0/D0只影响新轮；不需修改各技能。现有正式场景暂不接入。

## 5. 计划自审与执行门槛

| 设计章节 | 实施归属 |
| --- | --- |
| §1—3范围、复用与职责 | 全局约束、Task 1/4 |
| §4轮次、空批次、旧新并存 | Task 1/2/4 |
| §5同步资格、真实命中与去重 | Task 2/3/4 |
| §6评分、快照与资格 | Task 3 |
| §7同帧、暂停与报价 | Task 2/4 |
| §8接口与所有权 | §2、Task 1/3 |
| §9清理/退出/重载 | Task 1/4/7 |
| §10 Inspector与显示 | Task 5/6 |
| §11文件与预览 | 文件表、Task 6/7 |
| §12—14测试/review/审阅门槛 | 三测试入口、四检查点、Task 7、本节 |

自审锁定：7个任务，4个review检查点；接口/字段按§2统一；正式运行新增1gd/2tscn/0tres；3测试脚本另计。clear_round_source仅是提供者安全撤销，不重写执行体系。没有隐藏终结系统、首击超时、全局串行队列或每技能评分配置。

执行方法需用户选择并授权：推荐当前会话逐项实施（executing-plans），因为7项任务共享轮次/请求/时钟接口，保持同一Godot现场便于连续验证，末尾再独立审查；也可选择每任务独立子代理实施/审查（subagent-driven-development），审查更密集但上下文成本更高。批准计划不等于自动开始代码实施。

## 2026-10-16 实施收尾

[验收记录](2026-10-16-burst-combo-stage-3-validation.md)包含实际交付、137项全量回归、100根/50轮/10世界压力、正式Focus审计和独立审查。Task5首个测试步骤的主体已完成，仅更换Focus源后的旧监听专用断言未补；该步骤保留未勾选，并与早期close_round回调用例补强一起作为非阻断Minor明确延后。另有重复错误装配的告警去重改进延后。未把这些项目写成已覆盖。

按用户选择保持当前Godot目录与分支；已逐任务本地提交，未自动上传或合并。阶段四、正式场景接入及主观手感验收未包含在本次完成声明中。
