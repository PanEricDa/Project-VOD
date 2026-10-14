# 爆发连携阶段二：实时指令与 AI 行动接入详细设计

> 日期：2026-10-13。
> 状态：用户确认设计/计划后，阶段二已实施并通过后台验收。最终126/126通过，独立审查问题均修复；操作手感待用户确认。详见[实施计划](../Plans/2026-10-13-burst-combo-stage-2-command-plan.md)与[验收记录](../Plans/2026-10-13-burst-combo-stage-2-validation.md)，未进入阶段三。
> 基线：`0a2b21edbb1dc5de18b5692c0f9feffa985ca172`，阶段一已通过用户验收并上传 GitHub。
> 上位规则：[完整玩法设计](../../Vestiges%20of%20the%20divine/爆发连携系统设计-2026-10-11.md)；边界：[四阶段路线](../Plans/2026-10-12-burst-combo-four-stage-roadmap.md)。

## 1. 简单说明与本阶段成功标准

阶段一建立“专注从哪里来、能够承诺多少、何时扣费/归还”的账务。阶段二将这些接口连接到实际的伙伴指挥：

玩家按1—4 → 请求对应伙伴 → 预留专注 → 等待该伙伴最早合法行动机会 → 使用当前目标意图施放 → 成功释放扣费，释放前失败归还。

这时可以验证“按键能不能可靠地让 AI 出手”，以及等待、重复使用和扣费反馈是否顺畅。仍然没有伤害间隔倒数、评分、终结资格或终结演出；不能以阶段二预览宣称整个爆发系统已经完成。

已有四阶段与实时操作规则不重新定案。本文新增的是如何接入当前代码、配置与测试；等待时长和费用仅使用开发占位值。

## 2. 范围和不做的内容

交付连携槽、InputMap路由、单伙伴一条等待请求、动作衔接、执行时目标解析、资源事务、重复费用、只读指令显示和独立预览。四个验证技能复用已有技能内容/动画/VFX，但使用独立实例。

不实现阶段三的轮次开闭算法、伤害计时和评分，不实现阶段四的暂停/终结。玩家Q/E、自由地板瞄准、完整控制debuff、职业/招募/技能获取规则、连锁减免和最终职业连携技能均不扩展。

不改变普通技能数值、普通AI选技优先级、现有仇恨或两个常规槽。不增加每职业的连携执行器，不使用DIRECT_TRIGGER代替角色施法。

## 3. 已读取的实际代码与缺口

| 已有内容 | 当前真实行为 | 阶段二需要的扩展 |
| --- | --- | --- |
| SkillHostComponent | 常规槽和终结槽；`_can_start_request`同时要求公共冷却好、无活动技能 | 一个连携槽；等待请求；区分公共冷却与真实动作占用 |
| SkillBase | 激活只接受READY；释放后进入犹豫/冷却；成功释放后清空当前context | 请求用途；连携不受冷却/犹豫限制；按请求身份保留动作生命周期 |
| AllyBehaviorStateMachine | 普通技能、普攻、保护、接近与脱战均能改变本帧行为 | 连携优先分支覆盖所有普通决策入口，而非只调整ai_priority |
| AIAttackController / AICombatSystem | 控制器可区分普攻与外部动作；旧外部动作信号不带请求标识 | 公开真实动作占用查询与带标识通知，保留旧信号兼容 |
| SkillDeliveryRunner | Arc已有独立会话；Tracking仍使用单一`_busy`、context、projectile | 追踪交付也按请求创建独立会话，旧飞行不能挡住下一次施放 |
| SkillBase / Runner信号 | 瞬发可在execute内完成；失败通知部分依赖技能当前状态 | 统一“交付已接受”与“交付最终完成/失败”，避免迟到回调误清新请求 |
| SkillConditionBase | AUTOMATIC_ONLY默认；ALL_REQUESTS才约束显式指令 | 原样复用；连携是EXPLICIT，不把AI软条件变成指挥门槛 |
| SquadFocusComponent / ComboCostLedger | 已有预留、实际提交、退款、重复计价；提交后refund不会加回余额 | 只在真正成功释放提交；失败保留统一预留归还路径 |
| TriggerSkillEffect | 子技能独立实例，继承伤害来源；无根请求交付生命周期跟踪 | 子技能共享根请求生命周期，不再次收费，不按当前根技能状态清理 |

项目目前有技能禁用与cast_blocked接口，但命名状态本身不会自动实现沉默/眩晕。阶段二接入已有资格接口，并测试外部封锁/禁用；不宣称已经制作完整控制效果。

## 4. 方案选择

推荐：队伍控制器管理意图和账务，Host管理本伙伴的等待与技能激活，行为层管理实际动作/移动，交付层管理在途效果。

另外两种方案不采用：

- 队伍控制器直接接管移动、动画和技能：能够集中编写，但会复制AI和Skill的已有职责，制造第二套执行逻辑。
- 新建ComboSkillBase及专用交付/效果系统：用途清晰但重复现有能力，技能复用与人类维护成本过高。

推荐方案也不意味着零改动。动作/冷却混合门禁、追踪交付单实例状态与释放信号顺序是本阶段必须解决的真实接入点，不用特例掩盖。

## 5. 人类看到的配置

### 5.1 伙伴配置：只加一个槽

伙伴场景 → SkillHost根节点 → Skill Slots → `combo_skill: SkillBase`，默认空。

技能仍实例化在固定SkillSocket下，再引用到该槽。常规两个槽、连携槽、终结槽不能引用同一个实例；重复skill_id、跨Host引用、未注册引用给中文编辑器警告并失败关闭。

连携槽不参加request_best_skill和普通站位范围推导。用途由槽位与请求入口决定，不由文件名前缀、ai_priority或automatic_cast_enabled偷偷决定。

### 5.2 技能配置：费用组件，而非普通技能多两个无用字段

连携技能场景根下挂一个`ComboFocusCost`节点，只有：

| 字段 | 开发默认 | 约束与影响 |
| --- | ---: | --- |
| base_focus_cost | 20 | 有限非负专注点；根请求基础费用 |
| repeat_focus_cost | 10 | 有限非负专注点；同轮同伙伴同技能此前成功释放一次的附加费用 |

`ComboFocusCost.gd`是Node配置组件，不是支付管理器，不继承SkillCostBase。它只提供费用参数，事务全部由队伍控制器统一维护。

这样选择的原因：SkillCostBase.commit发生在Delivery.execute之前，而阶段一Focus.commit是不可重复退款的成功扣费。本需求还必须在排队前预留。强行用一个普通Cost.commit完成全部支付，会在交付启动失败时错误扣费或要求新增“提交后加回余额”机制。这里分清“费用配置”和“队伍账务”，不重写原SkillCostBase，也不挂两套会重复扣钱的Cost。

SkillBase提供`get_combo_focus_cost() -> ComboFocusCost`，只接受一个直接子节点。普通技能无需挂；连携槽缺失/多挂/参数非法则灰显并警告。Delivery、Effects、条件、动画与其他已有成本照常配置；既有SkillCostBase仍处理其自己的非专注资源，不管理队伍专注。

### 5.3 队伍控制器：三项

`SquadChainCommandController.tscn`根节点：

| 字段 | 默认 | 含义 |
| --- | --- | --- |
| companions: Array[AllyBase] | 四个空引用 | 索引0—3对应按键1—4；不压缩空槽，长度必须4 |
| focus_source: SquadFocusComponent | 空 | 当前世界的唯一专注池 |
| command_wait_timeout_seconds | 8秒 | 从受理到动作真正开始的最长等待；有限正数，包含等待旧动作和接近 |

四个伙伴必须属于Focus绑定世界、与唯一玩家同队，不能重复。无效项灰显；数组长度错误明确诊断，不静默截断或压缩。玩家和PlayerTargeting从同一绑定世界发现，不额外填写第二份玩家引用。

该8秒是开发默认，不是伤害连携窗口。正式施法开始后，不因它到期而截断技能；接近时仍保留现有“无进展失败”的更早判定。

### 5.4 UI：只引用控制器

`SquadChainCommandDisplay.tscn`根节点新增一个强类型`command_source`引用。外观编辑Control/Theme节点，不增加重复容量、费用或业务规则参数。显示开关使用CanvasLayer原生可见性，不新增脚本开关。

新增配置类型总计7项：Host1、费用组件2、控制器3、UI1。四伙伴装配时，费用与槽位分别按各技能实例填写；控制器伙伴数组展开为四个引用。没有请求ID、轮次ID、暂停状态、动作阶段或运行记录的export。

## 6. 请求数据与职责边界

新增`SkillSystem/01-Core/SkillCommandRequest.gd`，RefCounted，不是.tres，不挂节点、不要求策划配置。

保存根request_id、round_id、caster_instance_id、skill_id、scene_scope_id、技能WeakRef、等待秒数快照、资源授权Callable和只读请求状态。目标不在受理时冻结；节点引用不保活旧场景。

同一对象还跟踪这个请求的动作是否结束、根是否成功释放、仍在运行的交付token。它只保存身份/生命周期并发出通知，不计算费用、评分、目标或移动。

| 所有者 | 负责 | 不负责 |
| --- | --- | --- |
| SquadChainCommandController | 输入、稳定伙伴映射、账务、计价、绑定清理 | 动画、导航、评分计时 |
| SkillHostComponent | 一个等待请求、本伙伴活动请求、技能激活和身份核对 | 专注算法、直接播放动画 |
| AllyBehaviorStateMachine | 最早合法动作机会、接近、朝向、动作锁 | 定义技能伤害/复制选技权重 |
| SkillBase / Delivery | 合法性、真实释放、独立交付、Effects和信号 | 玩家按键、队伍费用记录 |
| SkillCommandRequest | 本根请求及子交付的生命周期 | 新技能执行体系或持久存档 |
| UI | 只读状态；键盘请求由控制器接收 | 计算/提交费用，控制暂停 |

SkillContext新增内部字段：`purpose`（REGULAR/CHAIN）、`preferred_target`、`command_request`、`delivery_token_id`。默认行为与当前普通调用一致。复制时来源快照独立复制，command_request共享同一个生命周期对象；其他目标引用沿用已有失效检查。

用途、EXPLICIT/AI_AUTOMATIC和CHARACTER_ACTION/DIRECT_TRIGGER是三个不同维度。连携根是CHAIN + EXPLICIT + CHARACTER_ACTION；触发子技能仍走自身DIRECT_TRIGGER规则，不复制根的冷却豁免用途。

## 7. 受理、等待和动作锁

### 7.1 一次输入

1. 检查输入启用、暂停、绑定范围、伙伴存活/施法许可、槽位与配置、缓存容量。
2. 对当前目标做一次普通技能预检；无合法目标不预留。预检结果丢弃，不作为缓存目标。
3. 获取根轮次，登记账本，读取预留上界；可用专注不足则撤销临时登记，不留下记录。
4. 预留成功后，把请求放入Host。任何后续受理失败都统一mark_failed、refund和清理。
5. Host.enqueue只缓存，下一物理帧由行为层尝试执行；先建立全部记录、发受理反馈，再允许动画/同步瞬发回调。

同一请求只受理一次。不同伙伴互相独立，按1再按2不保证1先出手；希望顺序稳定时，由玩家观察1实际释放后再按2。

### 7.2 单伙伴一条尚未执行的请求

等待旧动作、转向/接近但尚未确认动画开始，都占用同一个pending位置。开始动作后移为active，此时可缓存下一条。

因此最多是“一条已经开始的技能动作 + 一条待执行请求”。不能在接近阶段再堆第二条未执行请求；缓存满时拒绝新输入，不替换、不再预留。

输入受理后的8秒计时不会因换锁定、刷新接近目标或重复上报同一目标而重置。

### 7.3 哪些可以让位

已开始的普攻、普通施法等待自然结束；普通跟随、战斗游荡、普通技能尚未开始的接近/排队可以让位。等待连携时不启动新的自动技能、普攻、保护抢占或威胁犹豫来拖延指令。

行为层先推进普通公共冷却计时，再处理连携资格和动作分支；不清零普通冷却。必须同时覆盖physics_tick前部的保护、脱战、目标失效和普通接近入口，不是只在request_best_skill中加判断。

普通动作仍在进行时只维持该动作所需的原移动/面向规则；一旦空闲，即尝试等待指令。不同伙伴没有全队冻结。

### 7.4 连携开始后的锁

从动画成功开始到当前动作完成，普通AI、换锁定和新请求均不能覆盖。不能因为SkillBase已经释放、进入READY而提前放开动作锁。

死亡、施法封锁、目标在释放前失效、动作驱动失败、场景退出等走技术失败/取消路径。已成功释放不回滚伤害或退款。没有新做沉默/眩晕技能；已有set_cast_blocked和技能禁用接口需要确实传到正在施法的动作，不只灰显UI。

控制器保留原有animation_finished兜底；资产必须有限、具备合法release标记。故障兜底使用实际动作时长与内部余量，不增加策划配置“卡死时限”。

## 8. 冷却与交付重叠

普通请求继续使用自身冷却、AI犹豫和公共行动冷却。连携根请求忽略这些计时门槛，但不跳过动作占用、存活、封锁、目标、ALL_REQUESTS条件或其他已有资源成本。

验证连携场景将自身CD设0、自动施放关、AI犹豫关，便于人读；运行契约仍按请求用途区分，不能依赖策划恰好把CD填0来实现功能。普通实例的冷却绝不被清零或重置。

连携也不启动或延长普通共享行动冷却；Host与行为层的skill_released处理按purpose分支。普通计时在连携过程中照常推进，动作结束后普通AI仍按当时真实剩余冷却决策。这不是把公共冷却设0，而是连携请求没有修改普通计时的职责。

动作结束即可重复同一连携，不等待之前投射物/碎片命中。现有Arc会话复用；Tracking抽出`TrackingProjectileDeliverySession.gd`，移入原追踪状态/回调，每次execute建一个会话。Runner只管理会话集合和转发，不重写Effects。

SkillBase保留固定DeliveryRunner与RuntimeEffects节点；不临时克隆整个装备技能，不给每个技能新增Runner配置或“最大并发数”参数。会话结束/场景退出都清理自身连接和引用。

## 9. 目标意图与重新解析

SkillContext.preferred_target是通用的可选首选目标入口，默认空，不新增Inspector目标权重。

- 适用的进攻技能：当前玩家锁定敌人合法时直接优先，不进入AI加权竞争。
- 不适用或无锁定：SkillBase沿用自己的target_selection_mode、关系和候选。
- CURRENT_COMBAT_TARGET的旧AI目标失效时，允许AI感知组件用其已有refresh_target/Policy正常重选；不把玩家目标写入AI锁定，不新增连携专属目标选择算法。
- 治疗/自身技能不接收敌人锁定，仍用最低生命/自身等已有模式。
- 范围、多目标、碎片等由Delivery和Effects继续展开。

执行尝试和接近期间重新读取锁定与候选，直到即将开始动作。锁定改变可更新未开始动作的接近目标，但不重置请求截止时间。动作开始后冻结本次解析结果；不把后来换锁定套到已开始动作或已发出的投射物。

目标在动作开始前死亡：重新按同一规则选合法目标。开始后、释放前失效：沿用技能release验证取消该请求；已发出后的追踪/打空交给原投射物规则。无目标或无法接近时失败，不无限等待。

SkillBase公开prepare_request查询，供Host与控制器复用目标/条件/成本预检但不占动作，不使用“当前技能是否忙碌”拒绝对下一条缓存的预检。UI不循环调用会随机选目标或修改AI锁定的查询。

## 10. 费用与真实释放边界

基础费用、重复费用在受理时取快照，后续Inspector修改不追溯已受理请求。上界包含此前同轮同伙伴同技能仍可能成功的根请求；实际提交只数此前已成功释放。

费用例：第一条20，尚在施法时受理第二条预留30。第一条失败，第二条成功仅扣20并解除10余量；第一条成功则第二条扣30。失败、打空的区别：释放前失败不计重复；释放成功但未命中仍计重复且不退款。

真正支付点是SkillBase.delivery_started / Host.skill_released，不是action_requested、cast_started、release_started或最终命中。

### 10.1 统一“已接受交付”信号

Runner.execute的返回值统一为“是否接受了真实交付”，不是“所有Effects是否最终成功”。

配置/目标/launch启动失败且尚未接受时返回false，不发接受信号。接受后先发delivery_started，再做瞬发Effects或等待投射物；后续失败是delivery_failed，不把execute改回false，也不撤销已产生的伤害。

SkillBase在Runner的接受回调中标记根已释放，并恰好一次转发自身delivery_started；Host转发给队伍控制器，控制器ledger.mark_released后Focus.commit。这样瞬发造成伤害前，收费与释放状态已经确定。

发射前通过SkillCommandRequest的资源授权Callable检查本请求预留和最终报价仍可提交。该授权只检查，不扣款，不给子技能收费，也不作为Inspector接口。普通SkillCostBase保持自己的既有支付流程。

各交付的接受边界明确区分：Tracking在launch返回true后接受，并继续缓冲launch内同步命中；Arc在会话成功启动后接受；Instant在合法目标/Effects预检完成后、执行任何Effect之前接受。GroundArea在落点、场景类型和launch方法预检完成、合法效果容器就位后接受，再调用区域效果执行；此后的launch/effect失败按交付失败处理，而不是退回“未释放”。本阶段不新增地板选择内容，但要给该既有分支补接受/最终失败契约测试，不能留下同步产生效果后被免费退款的漏洞。

新增长期交付的独立`SkillBase.delivery_failed(context, reason)`通知。无论装备技能当前已READY、正在另一次CASTING或COOLDOWN，旧交付都按其context身份通知并清理；旧失败不能取消新动作。既有skill_failed/skill_cancelled语义兼容，但Host必须核对请求身份和是否已释放，不能凭技能当前state清空active。

### 10.2 失败矩阵

| 情况 | 账务/重复次数 | 动作与后续 |
| --- | --- | --- |
| 受理前拒绝、缓存满 | 无账目 | 不替换原请求 |
| 受理后超时、无目标、封锁、启动失败 | 归还预留、不计成功 | 清理本请求，后续缓存按自身资格处理 |
| release标记到了但Delivery未接受 | 归还预留、不计成功 | 统一失败 |
| 交付已接受，Effects后续失败或投射物打空 | 已扣费、计成功、不退款 | 清理交付，不回滚已结算结果 |
| 已释放后死亡/动作中断 | 已扣费、不退款 | 在途效果遵循原规则；后续请求按死亡资格失败 |
| 重复/旧回调 | 不重复扣费/退款/计次 | 不清理不属于它的新动作 |

## 11. 动作、根交付与子交付生命周期

资源终态不能在第一次命中或一次root delivery_finished时立刻销毁：动作可能尚未结束，子碎片也可能还在飞行。

SkillCommandRequest按纯数字token登记本请求全部交付。SkillBase在进入execute前登记自己的token；启动失败或最终完成/失败释放一次。子技能继承command_request，但新建自己的token、命中身份，仍用自身CD/Cost/显式触发规则，不继承根冷却豁免或首选目标。

请求满足“根已成功释放或已失败 + 本根动作结束/从未开始 + 全部交付token结束”才发lifetime_finished。控制器据此释放Focus终态与Ledger请求记录，并通知下一阶段轮次所有者。普通没有command_request的技能不进入这套计数。

不根据caster.active_skill识别旧交付。Token和动作标识均由单调ID生成器分配；不保存全部历史请求，账本关闭记录仍按阶段一水位清理。

AIAttackController的request_external_action追加可选request_id（旧调用默认0），AICombatSystem转发。新增带ID的external_action_lifecycle通知（RELEASE/FINISH/CANCEL），旧无参数信号保留兼容。行为层迁移到带ID通知，不同时双接两套回调；Host的释放、完成和取消方法校验expected_request_id。控制器复位前用本次ID发通知，迟到事件不命中新请求。

场景解绑先停输入、失败未释放请求、归还预留，再清理所有者记录、监听和Callable。已释放请求不退款。RQ不强引用Host、技能或世界，Callable只绑定数字身份与世代，不能bind请求自身形成RefCounted循环。

## 12. 阶段二的轮次边界：不偷做阶段三

生产控制器提供内部轮次来源接口，不自行根据施放/命中/总时间决定开闭：

- `set_round_source(peek_current: Callable, acquire_for_request: Callable)`：前者只读，后者用于一次真实请求取得归属。
- `close_round(round_id: int)`：轮次所有者通知费用记录关闭；已有请求继续，不清空等待技能。
- `command_lifetime_finished(request_id, round_id)`：供轮次所有者清理首发未命中的批次。

缺少轮次来源时明确不可受理，不悄悄建立全关卡永久连携或每次按键重置费用。轮次身份单调分配；UI仅peek，不因刷新界面创建新轮。

资源预检可先读取peek：没有批次时只显示/检查基础费用，有批次时读取非变更上界；真正受理仍须在acquire后重新报价和预留。若取得批次后受理失败，控制器移除临时账目，并发送request_activity_changed(round_id, live_requests)，即使live_requests仍为0也须通知。轮次所有者据此清理“未开窗且没有活请求”的空批次，不能泄漏永远未开启的轮次；已开窗的轮次绝不因此关闭。阶段二开发批次所有者只展示，不把这条通知变成临时评分/计时规则。

阶段二独立预览的脚本显式注入一个开发批次，并标明“阶段二指令验证；非正式连携窗口”。开发批次持续到重开预览，方便验证非相邻重复/失败预算；重开走场景生命周期，没有新游戏重置快捷键、固定整轮时限或施放续窗。

阶段三换成实际的未开窗/开放/关闭轮次来源，复用相同请求和费用接口，不修改技能执行逻辑。本阶段正式场景先保留原玩法，不把单批次预览逻辑写入GameRunController。

## 13. InputMap与反馈

新增四个InputMap动作`squad_chain_1`—`squad_chain_4`，默认物理键1—4。脚本只读动作名称，不写物理键值。手柄后续添加到同一动作，不另写执行路径。

控制器使用_unhandled_input；只处理新的pressed，忽略echo、释放和按住重复。暂停/禁用/场景解绑均拒绝新请求，但“不收新输入”本身不取消已有请求。

本阶段UI是纯显示卡片，不加鼠标施放按钮，Control不抢焦点且mouse_filter为IGNORE。现有PlayerAttackController在物理帧轮询Input，单纯GUI接受点击并不能阻止普攻；因此不假称“点击已被GUI消费就不会攻击”，也不顺带重构玩家输入。后续若加入可点击技能/终结窗口，需要另行落实共用输入阻挡与阶段切换防穿透；阶段二先只用已确认的1—4路径。

四张固定入口卡显示键位、伙伴/技能名称或现有图标、预计上界费用、正在施放/正在接近/等待当前动作/待执行反馈。施放中有空pending位置仍可再请求；缓存满、死亡、确定封锁、配置错误、专注不足才灰显。没有伪造CD条，没有评分/连击倒数。

UI读取控制器的只读状态；不登记试算请求，不随机选目标，不提交费用。动态目标/条件仍在请求和执行时权威验证，拒绝显示短原因。预计费用通过Ledger新增的非变更preview_reservation_quote计算，不制造虚假请求和历史记录。

控制器仅三项配置、UI一项来源。费用文本、状态颜色、卡片布局在场景和Theme里维护，不以大量export替代可查看的Control节点。

## 14. 独立验证技能与预览

| 伙伴 | 验证内容 | 模板/内容复用 | 所验证路径 |
| --- | --- | --- | --- |
| Guardian | 连携盾击 | 当前GuardianShield技能内容与Melee模板 | 接近、外部近战、角色动作锁 |
| Priest | 连携强效治疗 | 当前GreaterHeal内容与Ranged模板 | 友方目标、零伤害也成功收费 |
| Caster | 连携火弹 | 当前Firebolt内容与Ranged模板 | 追踪弹重叠、状态附加、伤害归属 |
| Archer | 连携连射 | 当前RapidShot内容与MultiShot模板 | 一次动作、多次交付、连续重复 |

验证技能是独立内容和实例，独立skill_id，默认20/10费用。原动作、伤害/治疗、目标模式与特效保持当前内容，CD/自动使用项按连携验证用途配置。Guardian的近战hit窗口不得早于释放接受标记，避免费用确定前结算近战伤害；资产不满足时给装配诊断，不修改正式普通技能动画去迁就。

不宣称这些就是最终四职业连携设计，不制作新美术、专属动画或每技能脚本。Firebolt的burning是状态标记，没有持续伤害；不新增连携DoT。

独立`SquadChainCommandPreview.tscn`继承用户当前TestCombatRoom，复用已有17个单位和Focus组件，加入控制器/UI。只有预览把初始专注设100，便于直接按键测试；正式Focus仍保持现有参数。测试节点均静态可见，不在运行时偷偷创建伙伴阵容。

四个伙伴源场景在SkillSocket装入独立连携实例，普通技能槽与参数不变；正式房间未挂指挥控制器时，它们仍只用原普通技能。实现前需明确源场景装配变更并按Godot MCP保存。不向TestScene添加或修改单位，也不自动改TestCombatRoom摆放和阵容。

## 15. 建议文件交付与数量

### 15.1 六个运行/预览脚本

| 文件 | 职责 |
| --- | --- |
| SkillSystem/01-Core/SkillCommandRequest.gd | 一次指令身份、等待与交付生命周期 |
| SkillSystem/03-Extensions/ComboFocusCost.gd | 唯一两项专注费用配置，不实际扣费 |
| SkillSystem/02-Delivery/TrackingProjectileDeliverySession.gd | 提取既有通用追踪交付状态，支持同技能多次在途 |
| UnitSystem/Components/Combat/Squad/SquadChainCommandController.gd | 输入、伙伴映射、费用、绑定与记录 |
| UnitSystem/Components/UI/SquadChainCommandDisplay.gd | 只读四伙伴指令反馈 |
| Scenes/Previews/SquadChainCommandPreview.gd | 显式开发批次与重开验证，不作正式评分 |

### 15.2 七个新场景

三个系统/预览场景：`SquadChainCommandController.tscn`、`SquadChainCommandDisplay.tscn`、`SquadChainCommandPreview.tscn`，位置与各自脚本相同。

四个内容场景：

- `SkillSystem/00-Skills/Combo_GuardianBash/ComboGuardianBashSkill.tscn`
- `SkillSystem/00-Skills/Combo_GreaterHeal/ComboGreaterHealSkill.tscn`
- `SkillSystem/00-Skills/Combo_Firebolt/ComboFireboltSkill.tscn`
- `SkillSystem/00-Skills/Combo_RapidShot/ComboRapidShotSkill.tscn`

来源均套用当前SkillBase模板/技能内容，不配一套新Effects/Delivery预设。不新增正式外部.tres/.res或新特效场景。Combo_只方便人辨认用途，不改变执行类型。

### 15.3 既有生产文件修改：建议15个

SkillSystem：SkillContext.gd、SkillBase.gd、SkillHostComponent.gd、SkillDeliveryRunner.gd、TriggerSkillEffect.gd。

UnitSystem：AllyBehaviorStateMachine.gd、AICombatSystem.gd、AIAttackController.gd、SquadFocusComponent.gd、ComboCostLedger.gd，以及Guardian/Priest/Caster/Archer四个源场景。

项目配置：project.godot，仅通过MCP InputMap操作增加四动作，不手写配置文件。

Focus仅加公开get_bound_scope、is_party_member与scope_changed通知供装配，原收益/事务数值不改变。Ledger在既有文件增加只读费用预览方法，没有新费用账本。上述数量是详细设计的建议交付，实施计划确认后冻结；必要兼容测试/指南改动另列，不隐藏工作量。

新增八个测试脚本，合计新增14个.gd、7个.tscn、0个.tres/.res；.gd.uid由Godot生成。另交付`SkillSystem/04-Docs/SquadChainCommandConfigurationGuide.md`及执行后的验收记录。

## 16. 关键公开接口契约

以下是设计签名，不是已实现代码。新增接口旁必须写简体中文参数/单位/约束，内部数据不export。

- SkillBase：`prepare_request(context: SkillContext) -> SkillContext`、`get_combo_focus_cost() -> ComboFocusCost`；保留activate/can_request等旧入口及默认普通用途。
- Host：`get_combo_skill() -> SkillBase`、`enqueue_command(request: SkillCommandRequest) -> bool`、`has_pending_command() -> bool`、`has_command_action_lock() -> bool`、`cancel_command(request_id: int, reason: StringName) -> void`。推进由行为层在合法衔接点调用`advance_pending_command(preferred_target: UnitBase, delta: float) -> bool`；true表示本帧由该请求接管动作/接近，不代表已成功释放。
- Host既有confirm/release/finish动作接口追加可选expected_request_id=0；0兼容旧调用，新指令必须传真实正ID。
- Request：`authorize_release() -> bool`、`retain_delivery(token_id: int) -> bool`、`finish_delivery(token_id: int) -> void`、`mark_action_started()`、`mark_action_finished()`、`mark_released()`、`mark_failed(reason: StringName)`；lifetime_finished只通知一次。Host只写动作状态，队伍控制器只写根释放/失败状态；已释放不能被后续失败改成可退款。Root动作从未开始的失败可直接记action_finished；方法幂等。
- Controller：`submit_slot(slot_index: int) -> bool`（0—3，true仅受理）、`get_slot_status(slot_index: int) -> Dictionary`、`set_input_enabled(enabled: bool)`、`set_round_source(peek_current: Callable, acquire_for_request: Callable)`、`close_round(round_id: int)`。
- Controller状态字典固定含：can_submit、reason、phase、actor_name、skill_name、icon、estimated_cost、active_request_id、pending_request_id。不得返回可编辑账目或让UI拿记录直接修改。
- Controller通知command_accepted(request)、command_rejected(slot_index, reason)、command_released(request_id, final_cost)、command_lifetime_finished(request_id, round_id)、request_activity_changed(round_id, live_requests)、slot_status_changed(slot_index)。live_requests统计仍拥有动作或根/子交付生命周期的根记录，不只统计未扣费请求；用于下一阶段的未开窗批次清理，不作为当前伤害窗口结束条件。
- Ledger：`preview_reservation_quote(round_id, caster_id, skill_id, base_cost, repeat_cost) -> float`，未知开放轮次从0成功计，关闭/非法返回-1，不创建记录。
- Focus：`get_bound_scope() -> Node`、`is_party_member(unit: UnitBase) -> bool`、`scope_changed(scope_root: Node)`。解绑通知null并在reset之前允许所有者归还旧预留，旧事件仍按原世代/身份水位拒绝。
- Tracking会话：`start(config, context, launch_transform, effects) -> bool`、`cancel(reason)`，最终通知带原context，启动失败不会留会话。

不在这个文档冻结每个私有函数名；详细计划需把上述参数类型、调用顺序、ID校验和测试映射展开，不能实现时另猜一套接口。

## 17. 测试与验收设计

| 新测试文件 | 必须钉住的行为 |
| --- | --- |
| SkillSystem/05-Tests/SkillCommandSlotContractTest.gd | 独立实例、槽位冲突、普通AI不选连携、费用组件缺失/重复/非法 |
| SkillSystem/05-Tests/SkillCommandActivationTest.gd | 普通冷却不变、连携CD/犹豫豁免、不延长普通共享CD、真实动作仍锁、条件适用范围、根与子用途不同 |
| SkillSystem/05-Tests/TrackingProjectileConcurrencyTest.gd | 两次真实追踪交付可重叠、不覆盖context、旧失败不清新动作、各会话解除监听 |
| UnitSystem/Tests/SquadChainCommandTransactionsTest.gd | 四伙伴并发承诺、30上界变20、受理回滚、Instant/GroundArea同步接受后失败不退款、取得批次后拒绝也通知0活请求、重复回调幂等 |
| UnitSystem/Tests/AllyChainCommandPriorityTest.gd | 等普通动作结束、未开始接近让位、保护/脱战不抢占、正常CD不清零、CASTING后锁定 |
| UnitSystem/Tests/ChainCommandTargetSelectionTest.gd | 当前玩家敌人优先、友方技能忽略敌锁、缓存换锁、失效重选、接近截止不反复刷新 |
| UnitSystem/Tests/SquadChainInputDisplayTest.gd | InputMap路由、echo拒绝、固定四槽、费用只读、等待不是CD、显示卡片不抢键盘焦点/不提供重复鼠标施放路径 |
| UnitSystem/Tests/SquadChainCommandLifecycleTest.gd | 释放/动作/根与子交付不同步、旧标识隔离、0CD子技能打空也回收、重载无预留/节点残留 |

实施采用行为红→绿，不能把新class_name未导入的解析错误算有效失败。新场景经Godot保存并验证UID、类型、引用；若实际增加.tres/.res必须满足正式资源规则。

完整回归基线118个SceneTree测试加独立RangedAttackPipeline契约；阶段二新增8个后预计126个入口。既有Delivery返回值/同步时序测试按“已接受/最终结果分开”明确迁移，只改变本设计要求的断言，不用改伤害/目标数值迁就测试。

再次运行正式场景伤害审计，确认没有连携控制器的原战斗与收益不变；独立指令预览补逐笔请求、费用、根/子归属统计和多轮重载。动画与实际出手需人工或MCP运行review，不以纯假Host断言替代真实角色动作测试。

## 18. 建议实施拆分（尚非可执行计划）

1. 共用请求/槽位/费用配置与交付接受契约、追踪会话：先证明普通兼容与重叠交付。
2. Host等待、行为优先级、当前目标和带ID动作回调：先证明不抢断/不饿死/不无限接近。
3. 队伍控制器、专注/重复计价、根与子请求清理：证明费用与生命周期恰好一次。
4. InputMap、只读UI、四个验证内容与预览、完整回归和独立review。

这些是阶段二内部的可审阅小任务，不改变已确认的四阶段大路线。用户已确认设计并要求实施；[详细实施计划](../Plans/2026-10-13-burst-combo-stage-2-command-plan.md)将上述四组展开为八项任务，按书面计划审阅门槛开始执行。不自动提交或推送新文档。

## 19. 自检与取舍

- 无冷却不等于动作并发；READY、已释放、动作结束和全部交付结束分开。
- pending包括接近，开始动画后才允许下一条pending。
- 费用只有一份配置、一个事务所有者；不要求普通技能填无效连携参数。
- 目标意图在执行时读，不改仇恨或用玩家锁定覆盖AI长期锁定。
- 子技能共享归属和生命周期，不继承根CD豁免，不再次登记/收费。
- 释放接受先于同步Effects；已产生效果的请求不能被当免费启动失败。
- 交付失败按context通知，不能因当前state/当前技能变了而遗漏或误取消。
- UI费用预览不注册请求，不随机选目标，不创建轮次。
- 阶段二只用标明的开发批次；真实伤害窗口与重复计数重置仍归阶段三。
- 所有等待、记录、监听和强引用都有清理边界，退出与重绑不串场。

当前文档提出的主要新增审阅点是“费用配置节点”“追踪会话/释放接受契约”和“阶段二开发批次与阶段三轮次接口”。这些属于框架实现选择，不增加玩家操作或新的战斗规则。
