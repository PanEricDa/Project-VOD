# 爆发连携阶段一：伤害来源与专注基础详细设计

> 日期：2026-10-12。状态：2026-10-13 阶段一实现、回归与独立审查完成，用户验收并授权记录版本；不包含阶段二以后。\
> 上位设计：[爆发连携系统完整设计](../../Vestiges%20of%20the%20divine/爆发连携系统设计-2026-10-11.md)。\
> 阶段边界：[四阶段实施路线](../Plans/2026-10-12-burst-combo-four-stage-roadmap.md)。

## 1. 本阶段交付与明确排除

建立真实伤害到队伍专注的最小闭环：常规有效伤害 → 来源明确的结算事件 → 场景级专注池 → 只读调试显示。同时交付供阶段二使用的资源事务与重复费用接口。

不实现 1—4 输入、连携槽、缓存/优先级策略、冷却绕过、实际评分窗口、终结暂停、玩家 Q/E 或正式连携技能。阶段一的数据模型允许测试指定连携/终结来源，但不改变现有技能自动行为。

现有未提交工作作为分析基线。实现时不得从旧提交覆盖当前 Firebolt、Archer、Caster、特效或镜头改动。

## 2. 项目结构与实际链路审查

### 2.1 根级职责

| 目录 | 本阶段关系 |
| --- | --- |
| UnitSystem | 单位扣血、阵营、仇恨、玩家/AI 命中、状态与生命周期，是主要接入层 |
| SkillSystem | 单次请求上下文、Delivery、Effects、近战外部动作、触发子技能，是来源传播层 |
| Item | 武器数值与投射物运动；本阶段不改模型或弹道 |
| GameFlow | 现有 GameRunController 自动加载 HUD 和绑定队伍；不把专注挂到玩家生命节点上 |
| Scenes | TestCombatRoom、TestScene2 等现有验证场景；不批量改场景或单位 |
| Effects | 已有技能特效与 preview，本阶段不制作新战斗特效 |
| Tools/CombatSimulation | 统计模型与真实战斗 soak 工具，不作为伤害事件权威来源 |
| Prototypes / Archive / addons | 原型、历史实现与工具插件，不纳入本轮生产代码改动 |

审查采用生产脚本调用链、场景装配和契约测试，不声称逐一审核所有素材或历史文件。

### 2.2 当前生产伤害路径

| 路径 | 已有入口 | 数据传播要求 |
| --- | --- | --- |
| 玩家普攻 | PlayerAttackController → CombatValueResolver → UnitBase/EnemyBase | Resolver 创建常规来源，不从玩家当前技能推断 |
| AI 近战/远程普攻 | AICombatSystem 的普攻命中 → Resolver | 即使角色正在其他技能流程，已发出普攻仍是常规来源 |
| 通用技能伤害 | HealthChangeSkillEffect → Resolver | 使用本次 SkillContext 中的来源快照 |
| 外部近战技能 | SkillBase.get_action_payload → AICombatSystem._apply_resolved_hit_damage → Resolver | 必须在动作 payload 携带来源，不只改 HealthChangeSkillEffect |
| 瞬发/跟踪投射物技能 | SkillDeliveryRunner 创建 SkillHitOutcome → Effects | 每目标一次物理命中身份保持稳定 |
| 弧线/连射/炎爆 | ArcProjectileDeliverySession 的逐目标/逐发结果 → Effects | 每一实际命中有独立身份，同次效果复用身份 |
| 爆裂箭碎片链 | TriggerSkillEffect 新建 SkillContext → 子 SkillBase | 子上下文继承来源、根请求与轮次，不恢复为默认常规来源 |

UnitBase 负责实际扣血与原生命信号，EnemyBase 覆盖 apply_damage 提交伤害仇恨，PlayerBase 覆盖它处理已有 Dash 免伤。新增参数必须同步三者，不能旁路 EnemyBase 或破坏 PlayerBase 的拒伤分支。

### 2.3 已有基础与缺口

- CombatValueResolver 返回实际扣血，已有测试覆盖防御、治疗与过量伤害。
- UnitBase.damaged 只有 `(amount, source)`；无法区分同角色的普攻、技能、连携与终结，也没有请求和命中身份。
- SkillContext 会被复制；TriggerSkillEffect 会从零创建子上下文。仅给原始实例加属性不足以传播来源。
- SkillHitOutcome.actual_damage 已按目标累计，有命中前状态快照；可以复用，而不是重新写命中结果类。
- burning 当前只是带剩余时长的命名状态，没有跳伤逻辑。禁止连携持续伤害不等于禁止其携带状态标记。
- GameRunController 是现有唯一流程 Autoload；队伍 HUD 已在场景切换后重新绑定。本阶段不增加全局伤害或专注单例。
- 敌群 EncounterController 有 Pack 生命周期，但当前测试场景与临时 dummy 不一定属于 Pack；专注不能只订阅已登记 Pack。
- 旧 health_changed、damaged、died 被 HUD、房间、仇恨与测试使用，签名与相对顺序必须保留。

## 3. 方案取舍

选择“单位级权威伤害事件 + 场景级专注组件”，而不是全局信号总线，或让每个 Effect 自己增加专注。

- 事件在实际扣血成功处生成，过量伤害与致命伤害口径一致。
- 不在 Resolver、Effects、投射物多处重复发布同一伤害。
- 组件按场景与队伍绑定，不依赖玩家存活或具体职业。
- 缺少专注组件时旧战斗正常运行；不强制所有关卡立刻装配。
- Inspector 只提供少量资源参数，不要求策划逐个碎片标记“禁止回充”。

## 4. 新增数据契约

### 4.1 CombatDamageContext：伤害发生前的来源快照

文件：`UnitSystem/Combat/CombatDamageContext.gd`，RefCounted，不是外部 Resource，不进入 Inspector Quick Load。

| 字段 | 含义 |
| --- | --- |
| origin | UNATTRIBUTED、NORMAL、CHAIN、FINISHER；用途不是角色类型，也不是执行方式 |
| request_id | 根技能请求身份，0 代表兼容的非技能入口；不作费用自动扣款依据 |
| round_id | 连携批次归属；阶段一只传递，不开窗或决定何时结束 |
| skill_id | 本段具体技能，用于诊断；不用于猜测来源类别 |
| hit_id | 一个目标的一次真实命中；同次命中的多个数值效果共享，子命中另建 |
| scene_scope_id | 发起交付所属场景/测试世界身份，防止重载后的旧数据混入 |
| source_instance_id / source_team_id | 来源单位身份与阵营快照，来源释放后仍能读取 |
| focus_yield_multiplier | 常规来源默认 1，连携/终结默认 0，无归属默认 0；用于收益，不影响伤害 |

创建接口建议：

- `create(source: Node, scene_scope: Node, origin: Origin = NORMAL, request_id: int = 0, round_id: int = 0, skill_id: StringName = &"") -> CombatDamageContext`。
- `duplicate_context() -> CombatDamageContext`：独立值副本，不共享可变运行字段。
- `for_hit(hit_id: int) -> CombatDamageContext`：保留来源与批次，派生某个命中的快照。
- `allocate_id() -> int`：进程内单调正整数身份生成；不使用 ResourceUID，不在场景重绑时复用。

源 Node 不作为必须存活的所有权句柄。普通调用入口自动创建 NORMAL，显式连携/终结请求保留其已提供数据；EXPLICIT 不自动等同 CHAIN，DIRECT_TRIGGER 也不自动等同 NORMAL。

### 4.2 CombatDamageEvent：实际结算后的事件

文件：`UnitSystem/Combat/CombatDamageEvent.gd`，RefCounted。

包含 event_id、上述来源快照、目标实例/阵营快照、实际正伤害、扣血前后生命快照。只对真实正扣血创建事件；零伤害、免伤、死亡后的重复攻击不创建计分事件。

- event_id 区分一次真实扣血，重复监听不得重复收益。
- hit_id 区分一个逻辑命中；同次命中拆分两个数值效果可以有两个扣血事件，但未来评分只增加一次命中数并累计两笔伤害。
- 不把整个 Delivery 的最终汇总量当作每笔事件，不等待 delivery_finished 才发布伤害。
- 发布后业务字段只读。事件可提供 `claim(consumer_key: StringName) -> bool` 维护局部消费防重，不用全局无限增长的已处理事件集合。
- 每个独立消费者使用独立键；专注消费不阻止后续评分消费。只读 UI 不 claim 伤害。
- 来源节点失效不抹除身份、收益和用途；不能反查角色当前状态重建信息。

### 4.3 单一发布点与兼容签名

UnitBase 新增 `damage_resolved(event: CombatDamageEvent)`。apply_damage 追加可选末参数 `damage_context: CombatDamageContext = null`，前三个位置参数保持原样；EnemyBase、PlayerBase 同步签名与 super 转发。

有效扣血后先建立完整快照并发布新事件，再发送原 health_changed → damaged → died/受击处理，保留原信号相对顺序。这样致命事件在死亡回调释放单位前可被消费，监听者不需要存活目标来读取快照。

Resolver.apply_damage 在原参数末尾追加同名可选参数。普通 Resolver 调用建立 NORMAL，未知的直接 UnitBase.apply_damage 调用保持 UNATTRIBUTED；后者照常扣血和仇恨，但不把测试扣血或脚本扣血猜成可回充战斗。

新增字段、费用和发布事件拒绝 NaN/Inf；UnitBase 的伤害入口补有限值检查，有限合法输入的计算、死亡和仇恨行为不变。不要借本阶段重写治疗公式或仇恨系统。

## 5. 传播与命中身份

1. SkillContext 增加 `damage_context`，复制时深拷贝该数据。SkillBase 在首次准备请求时补齐普通来源，已有连携/终结来源不能被覆盖。
2. SkillHitOutcome 增加 hit_id。SkillDeliveryRunner 和 ArcProjectileDeliverySession 在创建每目标/每段 outcome 时分配；同次 Effects 读取该 outcome 身份。
3. HealthChangeSkillEffect 只给 DAMAGE 分支传递 for_hit 快照。HEAL 继续使用旧恢复入口，不创建伤害事件。
4. TriggerSkillEffect 给新子上下文复制来源，继承根 request_id、round_id、scope 与收益；子 SkillBase 可以更新具体 skill_id，不能改根归属。子目标的新 hit_id 不沿用父命中。
5. 外部近战动作只在现有非空 MeleeSkillAction payload 增加 damage_context；不能使原本空 payload 变成非空，否则会误入零伤害近战分支。
6. AICombatSystem 的外部近战分支转发 payload 快照；普攻分支仍由 Resolver 生成 NORMAL。不根据 active_skill 判断命中来源。
7. Item 投射物本阶段不增加专注参数；交付层已经持有请求上下文，那里传递即可。

角色动作取消不撤销已发布事件；Effects 后续失败也不回滚已扣生命。新事件和旧 SkillHitOutcome 记录引用同一笔实际结果，不重复扣血。

## 6. SquadFocusComponent：场景级资源与事务

文件：`UnitSystem/Components/Combat/Squad/SquadFocusComponent.gd` 和同名 tscn。放在房间/测试世界根下，不挂玩家、不改全局 Autoload。

### 6.1 Inspector

| 导出字段 | 开发默认值 | 职责 |
| --- | --- | --- |
| maximum_focus | 100 | 专注容量，有限正数；本组件资源单位 |
| initial_focus | 0 | 初始化量，夹在 0 与容量之间，不每次显示刷新都重置 |
| damage_to_focus_ratio | 0.1 | 每点有效伤害换算倍率，允许 0 关闭收益；仅开发占位，不是正式平衡公式 |
| auto_bind_parent | true | 初始化后绑定父场景，发现唯一玩家与同队伙伴；关闭时显式 bind_scope |

当前值、预留值、可用值、绑定场景、最近事件是只读调试状态，不做可编辑 @export。

本阶段明确采用可替换的线性开发公式：gain = actual_damage × focus_yield_multiplier × damage_to_focus_ratio。后续算法在这个换算边界更换，不改变来源、事务或技能调用。

### 6.2 场景绑定与事件筛选

`bind_scope(scope_root: Node, party: Array[UnitBase]) -> bool` 绑定一处场景和队伍快照；`unbind_scope() -> void` 断开全部连接并清理当前场景预留、事件消费和引用。

- auto 模式要求唯一 Player，伙伴必须同队；多玩家/无合法队伍失败关闭并给一次诊断，不猜测某个主角。
- 遍历该 scope 内 UnitBase，连接 damage_resolved；不要求 EnemyBase 或 Pack 登记，支持 dummy。
- 动态节点加入/退出时更新局部连接，不每帧重扫全场；只处理 scope 后代，临时技能/特效节点不当成单位。
- 只接收来源属于当前队伍、目标是其合法敌方、scope 与绑定一致、实际正伤害的事件；不依赖目标当前存活，因此致命扣血也回充。
- 对收益属性为零的数据自然获得零收益，不另加“迟到/失败连携不可回充”的例外分支。
- 解绑/重载后旧场景、旧回调和旧事件不能改变新资源池。角色死亡不销毁池，战斗中已发出的有效攻击按快照处理。
- reset 明确用于新场景/测试会话初始化；解绑释放旧承诺，不把旧资源带入新场景。本版不做跨关卡专注保存。

### 6.3 公开接口与幂等

| 接口 | 约束 |
| --- | --- |
| get_current_focus() -> float | 当前资源，包含已预留但尚未提交的部分 |
| get_reserved_focus() -> float | 全部 RESERVED 请求之和 |
| get_available_focus() -> float | current − reserved，不为负数 |
| reserve(request_id: int, amount: float) -> bool | 正身份、有限非负金额；同请求同金额重复调用无副作用，金额冲突失败 |
| commit(request_id: int, final_amount: float) -> bool | 必须有预留，最终费用不超过预留；成功扣最终金额并释放余量，仅一次 |
| refund(request_id: int) -> bool | 只释放未提交预留，不增加总资源；终态重复调用无副作用 |
| release_request(request_id: int) -> bool | 仅清理已提交/退款的终态记录；尚有预留时失败，拥有者须先 refund，不隐性丢账 |
| reset_focus() -> void | 清理本会话事务，按 initial_focus 重建，不是玩家按键 |
| focus_changed(current: float, reserved: float, available: float) | 只在数值实际变化后发出，UI 只读 |

已提交/退款记录在请求仍可能回调时保留终态；拥有者显式释放请求后可清理，重复操作找不到记录仍无副作用。不依赖大字典永久保存所有历史请求。

## 7. ComboCostLedger：重复计价纯数据

文件：`UnitSystem/Components/Combat/Squad/ComboCostLedger.gd`，RefCounted。它不播放技能、不产生专注、不决定轮次何时开启。

键为 round_id + caster_instance_id + skill_id。记录根请求，子碎片不独立加价或扣费。

- `register_request(request_id: int, round_id: int, caster_id: int, skill_id: StringName, base_cost: float, repeat_cost: float) -> bool`：费用有限非负，身份合法；重复相同登记幂等。
- `get_final_quote(request_id: int) -> float`：按此前实际成功次数报价；未知请求返回 -1，不伪装免费。
- `get_reservation_quote(request_id: int) -> float`：包含同伙伴同技能在本请求之前仍可能成功的请求，提供足额预留上界。
- `mark_released(request_id: int) -> float`：返回本次实际费用并记录一次成功；重复回调返回同一历史费用，不再增加次数。
- `mark_failed(request_id: int) -> void`：不计成功，终态幂等。
- `close_round(round_id: int) -> void`：禁止新登记，已有请求仍可报价/终结，不丢旧记录。
- `release_request(request_id: int) -> void`：拥有者结束回调生命周期后释放引用；关闭且无人引用的轮次可清理。

例：基础 20、附加 10；第一请求尚未释放，第二请求缓存时足额预留 30。若第一请求失败，第二实际费用为 20；若成功则为 30。执行前确定报价，commit 只扣实际金额，多余预留释放。该例仅验证事务，不定正式数值。

正式轮次由阶段三建立/关闭，阶段一用测试批次验证，无临时整轮计时或游戏重置键。来源子技能继承根身份，但不进入费用账本。

## 8. 可见交付、配置与文件清单

### 8.1 新建运行/预览内容

| 文件 | 类型 | 职责 |
| --- | --- | --- |
| UnitSystem/Combat/CombatDamageContext.gd | 新建数据类 | 来源与归属快照 |
| UnitSystem/Combat/CombatDamageEvent.gd | 新建数据类 | 实际结算与局部消费防重 |
| UnitSystem/Components/Combat/Squad/SquadFocusComponent.gd + .tscn | 新建可挂组件 | 资源和事务、场景绑定 |
| UnitSystem/Components/Combat/Squad/ComboCostLedger.gd | 新建纯数据类 | 重复费用记录，不挂额外节点 |
| UnitSystem/Components/UI/SquadFocusDebugDisplay.gd + .tscn | 新建只读显示 | 数值条与文本，复用既有 UI 组织风格 |
| Scenes/Previews/SquadFocusFoundationPreview.gd + .tscn | 新建开发预览 | 普通/连携/终结来源验证及预留、提交、退款演示 |
| UnitSystem/Components/Combat/Squad/README.md | 新建指南 | 配置入口、装配、默认参数与排错 |

显示组件仅两个导出项：强类型 focus_source 节点引用与 debug_enabled。计算参数只在 Focus 根上维护，不复制到显示节点。

预览引用正式 Focus 与 DebugDisplay 场景，不复制脚本。验证按钮只存在于预览，不接入正式 InputMap；使用实际 UnitBase/Resolver 扣血与测试参数，界面明确标记开发验证。

数量：6 个运行/预览 .gd、3 个 .tscn、0 个正式外部 .tres/.res；新增 8 个测试 .gd，合计新增 14 个 .gd。自动生成的 .gd.uid 不手写。没有“每种伤害一套代码”，两个数据类是内存对象，不是策划需要配置的资源。

### 8.2 修改既有运行文件（原计划 12 个，实际 10 个）

`UnitSystem/Base/00_UnitBase.gd`、`UnitSystem/AI/Enemy/EnemyBase.gd`、`UnitSystem/Player/PlayerBase.gd`、`UnitSystem/Combat/CombatValueResolver.gd`、`UnitSystem/Components/Combat/AI/AICombatSystem.gd`；

`SkillSystem/01-Core/SkillContext.gd`、`SkillSystem/01-Core/SkillBase.gd`、`SkillSystem/01-Core/SkillHitOutcome.gd`、`SkillSystem/02-Delivery/SkillDeliveryRunner.gd`、`SkillSystem/02-Delivery/ArcProjectileDeliverySession.gd`、`SkillSystem/03-Extensions/HealthChangeSkillEffect.gd`、`SkillSystem/03-Extensions/TriggerSkillEffect.gd`。

改动只用于事件、可选参数和数据传播，不改变技能动作、既有数值、冷却或目标策略。PlayerAttackController、Item 投射物、GameRunController、EncounterController、CombatHUD、project.godot 和正式单位场景本阶段不修改。

实施调整：命中身份在 `SkillHitOutcome` 实例创建时统一分配，既有 Runner 与 ArcSession 已按每目标/每发创建 outcome，无需再修改这两个交付脚本。上表保留原规划清单用于对照；实际仅其余 10 个运行文件新增来源传播代码。

### 8.3 人工装配说明

独立预览可直接运行。若用户希望在 TestScene 观察：由用户把 SquadFocusComponent.tscn 和 SquadFocusDebugDisplay.tscn 放到房间根下，给显示选择对应 focus_source，并开启 debug_enabled；不需要移动/添加单位或配置每个敌人。若唯一玩家条件不满足，关闭 auto_bind_parent 并通过明确测试装配注入队伍，不能静默猜测。

不自动修改 TestScene 单位，不为本阶段改 TestCombatRoom/TestScene2 参数。场景组件是否成为正式 GameRun 的共享服务，在阶段二/三结合控制器装配时再决定。

## 9. 测试、基线与 review

新增测试：

1. UnitSystem/Tests/CombatDamageContractTest.gd：复制、身份、收益、claim 和快照。
2. UnitSystem/Tests/DamageAttributionIntegrationTest.gd：实际扣血、过量、免伤、致命、旧信号与仇恨。
3. UnitSystem/Tests/SquadFocusComponentTest.gd：收益、容量、事务、非有限值。
4. UnitSystem/Tests/ComboCostLedgerTest.gd：非连续重复、失败、预留上界、终态幂等。
5. UnitSystem/Tests/SquadFocusSceneBindingTest.gd：绑定、重绑、动态单位、失效引用、scope 隔离。
6. UnitSystem/Tests/SquadFocusDebugDisplayTest.gd：只读显示与节点失效。
7. SkillSystem/05-Tests/SkillDamageProvenanceTest.gd：瞬发、投射物、多段、多目标和碎片继承。
8. UnitSystem/Tests/MeleeSkillDamageProvenanceTest.gd：外部近战技能与普攻区分，空 payload 保持空。

2026-10-12 通过 Godot MCP Pro 实际运行的现有基线：CombatValueResolverTest、EnemyThreatIntegrationTest、BasicAttackDamageIntegrationTest、SkillHitOutcomeTest、ExplosiveArrowChainIntegrationTest、UnitDeathLifecycleTest、CombatHUDBindingIntegrationTest，7/7 退出码 0。HUD 测试的双玩家警告是其验证失败关闭的预期分支，不是新失败。此记录不等于全项目全部测试已运行。

实现后还须覆盖近战动画、SkillBase、触发与多段交付、当前 Archer/Caster 装配及 GameRun 结果流程；自动测试之外运行独立预览，检查 Inspector、信号解除和实际资源曲线。

review 首先看新事件是否只发布一次、近战和碎片是否漏传、旧信号是否兼容、预留金额是否超额、场景重绑后是否留引用。然后看文件数量和 Inspector 配置是否符合人类可管理原则。

本阶段通过的定义：真实普通战斗能累积可见专注，测试连携/终结来源不回充，资源事务与归属契约稳定，既有战斗回归通过。没有实际连携输入和评分不算缺漏，因为它们是下一阶段明确交付。
