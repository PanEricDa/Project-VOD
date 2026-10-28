# 玩家技能阶段四：技能栏与联合玩法验证 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking. 沿用当前目录、本人实施、阶段末一次独立review；共享Godot仅一个写入方。用户已于2026-10-22确认；阶段四实现/验证/review已完成，待用户体验验收，不自动进入阶段五。

**Goal:** 在现有PlayerSkillsTest中显示真实Q/E技能栏，并验证E引怪、Q聚拢、四伙伴输出及连携/终结共存，不新增战斗机制。

**Architecture:** PlayerSkillController补只读槽状态接口，HUD只读该接口及现有受理/拒绝信号。测试场景保留原Training/Threat Combat，增加明确隔离的Squad Combat模式，复用既有队伍、评分、暂停、镜头和终结组件。正式Hero/EnemyBase/CombatRoom仍不装配。

**Tech Stack:** Godot4.7、GDScript、原生Control/CanvasLayer、InputMap、SceneTree行为测试、Godot MCP Pro。

**Spec:** [已确认玩家技能设计](../Specs/2026-10-21-player-gather-threat-skills-design.md)，[五阶段路线](2026-10-21-player-skills-staged-roadmap.md)。

## Global Constraints

- 所有创建、编辑和保存优先Godot MCP Pro；工具不支持、不可用或失败时说明原因再回退。
- 不向Scenes/TestScene.tscn自动添加或修改单位；本次仅装配已获授权的Scenes/Tests/PlayerSkills/PlayerSkillsTest.tscn。
- 不改变用户已调好的Q/E数值、怪物射程、普通仇恨、衰减、伙伴技能与连携评分算法。
- 正式Q：半径3.5m、圆心前移3m；身前1.5m/半径0.6m聚拢盘；位移0.12战斗秒，施法0.2秒，冷却10秒。
- 正式E：半径5m、2000临时仇恨、8战斗秒、施法0.15秒、冷却12秒。独立测试Q/E冷却都保留2秒。
- 不新增仇恨权级、聚怪状态、强制Guardian接管、地板瞄准、玩家技能专注费用或自然回复。
- UI不维护自己的技能/冷却/范围配置，不执行Effect，不自行复现技能合法性，不添加隐藏输入队列。
- 图标未配置时显示占位，不为了技能栏增加技能专用配置资源或批量制作图标。
- 不制作新角色动画或音效，不重做已验收Q/E特效；缺少表现资产不阻止Gameplay。
- 不进行热装卸、换槽事务、反复50次重载压力测试；保留公开绑定/解绑接口及正常清理。
- 不实施UnitBase被动位移迁移，不提前接入正式主场景。Git提交/上传另行授权。

## Review Focus

1. UI显示可用但控制器拒绝：UI只能说明当前可尝试输入，不承诺目标/费用后续一定通过；Task1覆盖只读查询与实际请求一致性。
2. 启动/模式切换时队伍组件提前绑定或抢输入：部分现有组件_ready会设PROCESS_MODE_ALWAYS，不能只靠禁用父节点隔离；Task2覆盖非Squad模式从进入树前移除联测组件。
3. 终结选择/镜头交接的完全暂停与5%慢放不同：禁止输入不能靠Engine.time_scale猜测；Task3通过原输入许可和真实窗口/演出断言。
4. 无伤害Q/E引发普通战斗不等于Q/E产生专注/评分：Task2分别隔离无伤害阶段与恢复AI后的真实伤害来源验证。
5. 正常死亡/重开留下旧绑定、动作占用、相机或时间令牌：Task3覆盖一次完整退出/重建，不用旧对象身份操作新场景。

## 0. 2026-10-22现状与本次设计决定

阶段1—3的技能、动作、仇恨和位移已完成；Q/E特效已由用户验收：

- GatherCastEffect / GatherReleaseEffect / GatherEffectPreview已经接入Q。
- ThreatMarkReleaseEffect / ThreatMarkStatusEffect / ThreatMarkEffectPreview已经接入E。
- E头顶感叹号及血条状态点由真实状态管理，刷新复用、到期回收，已测试多来源/回滚及渲染插值。
- 最新全量179项：177通过；CameraFollowControllerTest的正式关卡导航未烘焙、SingleSceneFireboltTest的旧6m断言与用户5m配置不符为既有失败。
- 当前只有测试计数面板，没有正式PlayerSkillBar。独立测试场景有Training与Threat Combat以及一个验证Guardian，尚未装完整连携/终结链。

### 0.1 技能栏外观

只做两张紧凑卡片，不增加选择层级：

- 每张显示快捷键、技能图标（无图标用名称首字符占位）、技能名称、剩余冷却。
- 冷却用遮罩/进度与一位小数秒数；读SkillBase真实剩余量与配置时长，不自行倒计时。
- 当前角色技能施放中显示绿边；输入受理作短确认；拒绝作约0.25真实秒红边/简短原因，反馈长度内部封装，不新增Inspector数值。
- 冷却、动作忙、输入受禁、死亡、空槽用灰显区分；“技能就绪”和“角色当前不能操作”是两个维度，不能因自身CD为0就显示可操作。
- 不复制伙伴连携的等待队列/专注费用逻辑，不设置点击释放按钮，不占用鼠标锁定与攻击输入。
- 两卡横排放左下、玩家生命信息上方，与中央四伙伴栏错开；以1280×720及当前编辑器实际窗口检查。卡片最小宽104、高90、间隔8，整体左边距16；最终偏移以不遮挡现有玩家生命、伙伴栏和终结窗口为准，只编辑原生Control布局，不增加布局脚本参数。

### 0.2 唯一配置入口及接口修订

技能栏Inspector只增加一个强类型来源：`skill_source: PlayerSkillController`，拖入玩家已有PlayerSkillController。不再要求同时维护Host、Controller、Input、两个技能和快捷键等重复引用。

阶段路线初稿为PlayerSkillBar.bind_host(host)。目前尚无该UI实现或调用方；本计划将其细化为`bind_source(controller)`，由Controller读取已绑定Host和InputMap。原因是Host无法独自表达玩家动作忙碌、输入禁止和受理/拒绝反馈，直接暴露多引用会转移装配复杂度。不保留一套没有消费者的旧UI入口；Controller已有bind_host不变。此为接口细化，不增加技能执行机制。

PlayerSkillController新增：
`get_slot_status(slot_index: int) -> Dictionary`。0/1为普通槽；查询不请求技能、不改变动作、不支付成本、不发受理/拒绝信号。返回独立纯值数据及共享只读Texture2D：

| 字段 | 含义 |
|---|---|
| slot_index / configured | 槽号、是否有合法静态技能；非法槽安全空数据 |
| skill_name / icon | 从Host当前槽技能取得；不保留另一份技能描述 |
| input_action | 从已绑定PlayerSkillInputComponent取得动作名，UI再按InputMap读键名 |
| phase / can_request / reason | 当前显示阶段、是否可尝试请求、稳定原因；目标/条件/费用仍由原释放管线最终判定 |
| cooldown_remaining / cooldown_duration | 技能自身真实冷却秒数及本技能配置时长 |
| global_cooldown_remaining / global_blocked | Host共享冷却及原外部冷却锁；不伪造为技能自身冷却 |

phase限定为empty/ready/casting/cooldown/blocked；reason复用现有稳定分类，必要的UI细分只作为显示原因，不改变request_slot的历史拒绝分类。Owner死亡/输入禁止、动作忙、Host禁用、共享CD均需要灰显；正处于本槽真实施法时保留casting标识。未知未来Condition仍由Host处理，can_request不是必定释放成功的保证。

PlayerSkillBar新增：
`bind_source(source: PlayerSkillController) -> void`，重复绑定幂等，null等于解绑；
`unbind_source() -> void`，只解除自身监听、清UI反馈，不取消技能或改写Host；
`refresh_immediately() -> void`，只读刷新，用于绑定时和UI契约测试。
只有skill_source一个常用导出参数；尺寸、颜色、字体、对齐在.tscn中编辑。反馈动画常量、连接、缓存均不导出。每个export和公开方法有中文约束说明。

## 1. 文件与职责

### 新建生产内容

- UnitSystem/Components/UI/PlayerSkillBar.gd：两槽只读显示与视觉反馈。
- UnitSystem/Components/UI/PlayerSkillBar.tscn：原生CanvasLayer、两卡、键名/图标占位/名称/冷却遮罩/状态边框。
- SkillSystem/04-Docs/PlayerSkillsConfigurationGuide.md：玩家槽、UI、Q/E效果和测试模式装配说明。

### 新建测试与验收记录

- UnitSystem/Tests/PlayerSkillBarTest.gd：真实Host/Controller与UI契约。
- UnitSystem/Tests/PlayerSkillCombinedFlowTest.gd：真实E/Q、普通AI、专注、连携、终结窗口/演出隔离。
- Docs/Superpowers/Plans/2026-10-22-player-skills-stage-4-validation.md：实施时记录RED/GREEN、原生操作、全量结果与review。

### 修改

- UnitSystem/Components/Combat/PlayerSkillController.gd：只读get_slot_status，不修改已有请求合法性或动作抢占。
- Scenes/Tests/PlayerSkills/PlayerSkillsTest.tscn：挂PlayerSkillBar；静态可见装配联测伙伴、队伍组件及其已有HUD。
- Scenes/Tests/PlayerSkills/PlayerSkillsTestHarness.gd：模式隔离、按钮与原数据观察；不接管技能效果或战斗算法。
- UnitSystem/Tests/PlayerSkillTestSceneTest.gd：保证Training/Threat Combat原用例仍有效，补装配读取断言。
- 本路线文档、当前阶段计划与配置说明按实际交付更新。

不新增主动技能、Delivery、状态类型、正式外部.tres/.res或另一套队伍控制器。已有资源按强类型引用；如实施发现确需新正式外部资源，先说明必要性，原生保存并验证UID/Quick Load。

## 2. Task1：只读槽状态与两槽技能栏

**Interfaces:** 消费Host.get_regular_skill/get_skill_owner/get_active_skill/get_global_cooldown_remaining/is_global_cooldown_ready/is_cast_blocked/is_skill_casting_enabled，SkillBase现有状态/冷却/名称/图标，Controller已持有的PlayerBase/AttackController/Input及slot_accepted/slot_rejected。
产出上文get_slot_status、PlayerSkillBar.bind_source/unbind_source/refresh_immediately。

- [x] **Step1 — 写失败测试。** PlayerSkillBarTest使用真实Hero、正式Q/E、真实Controller/Host，测试辅助夹具只放测试文件。覆盖未绑定、空槽、0/1静态槽、图标为空、技能改名/换图标后只读刷新、冷却、同帧忙碌、输入禁止、死亡、重复bind不重复确认；不测试运行中换槽系统。
- [x] **Step2 — 运行RED。** `--script res://UnitSystem/Tests/PlayerSkillBarTest.gd`；应以缺少get_slot_status/UI资产失败，不以脚本解析错误为RED。
- [x] **Step3 — 实现只读接口与UI。** UI采用PROCESS_MODE_ALWAYS逐渲染帧只读刷新，暂停时仍能灰显，CD仍由战斗时钟控制；短确认/拒绝反馈使用真实秒，事件只驱动短视觉；不保存独立冷却remaining，不读Harness计数，不调用activate或Effect。导出source变化和正常退树清理连接，无源时安全空显示，所有Control使用MOUSE_FILTER_IGNORE。
- [x] **Step4 — 原生保存并接入同一测试场景HUD。** Inspector唯一来源指向Hero/PlayerSkillController，不碰Hero源场景。保持原DebugPanel，默认训练模式仍能直接F6；原Q青蓝范围圈、E圈关闭约定不变。
- [x] **Step5 — 验证GREEN。** 运行PlayerSkillBarTest、PlayerSkillControlTest、PlayerSkillActionAnimationTest、PlayerSkillTestSceneTest。Expected：退出0/PASS，无SCRIPT ERROR、泄漏和UID警告。1280×720及当前窗口实际检查不遮挡、不吞鼠标。
- [x] **Step6 — 记录交付。** 本任务成果是可见的两卡和正确状态，不称组合玩法已完成；按用户规则不自动Git提交。

**关键断言：** 对就绪Q/E读取状态前后，真实受理/拒绝计数不变；实际Q释放一次后UI冷却等于SkillBase.get_cooldown_remaining；不在测试写“模拟CD”。Q正在施法时E不能显示可操作，动作结束且CD就绪后恢复。改InputMap键位后标签使用新键名，而不是固定写Q/E；只改测试进程InputMap，不保存项目配置。

## 3. Task2：同一场景的完整队伍联合模式

**Interfaces:** 消费Task1技能栏；复用既有SquadFocusComponent.bind_scope、SquadChainCommandController.companions/focus_source、Round.command_source、Selection.round_source/pause_source、Execution.selection_source/camera_source及现有相应HUD。

模式：Training保持静止靶；Threat Combat保持现有敌人+验证Guardian；新增Squad Combat用于四伙伴输出及1—4连携/终结。Reset重建并保留当前模式，模式切换不沿用旧状态/资源。

- [x] **Step1 — 写失败测试。** PlayerSkillCombinedFlowTest验证三模式实际实例/绑定、E使真实仇恨与状态生效、Q实际进入聚集圆盘、同一世界仅一套队伍/暂停系统；无伤害Q/E阶段不产生damage_resolved、不直接增加专注/连击。
- [x] **Step2 — 运行RED。** `--script res://UnitSystem/Tests/PlayerSkillCombinedFlowTest.gd`；Expected缺少Squad模式/装配的行为失败。
- [x] **Step3 — 静态装配已有内容。** 在测试场景ValidationActors保留ValidationGuardian，增加ValidationPriest、ValidationCaster、ValidationArcher，使用现有源场景和技能。初始站位Guardian(-2,0,5.5)、Priest(0,0,7.5)、Caster(-3,0,6.5)、Archer(1,0,6.5)；不移动既有敌人/墙/玩家。
- [x] **Step4 — 装配现有队伍链路。** 根下实例化原SquadFocusComponent、SquadChainCommandController、ChainSkillPresentationController（含原PauseCoordinator）、SquadChainRoundController、SquadFinisherSelectionController、SquadFinisherExecutionController以及三种原HUD。伙伴固定顺序Guardian/Priest/Caster/Archer，与正式场景一致。相机引用本测试CameraRig、世界引用本测试根，不能指向CombatRoom。
- [x] **Step5 — 在进入树前隔离模式。** Harness从TEST_MODE_META读取整数0/1/2（既有bool转int保持训练/仇恨测试调用有效）。_enter_tree移除本模式不用的伙伴/队伍组件，避免它们_ready改为PROCESS_MODE_ALWAYS后仍处理输入或暂停。Training无伙伴；Threat Combat只留Guardian且无连携系统；Squad Combat保留四伙伴及唯一队伍系统。_ready仅启用已有敌人AI、接UI与数据观察，不动态生成技能或伪造绑定。
- [x] **Step6 — 参数与数据。** 新联测组件沿当前CombatRoom有效参数复制一次作为场景显式配置，不反向修改主场景；当前读取基准为initial_focus=100、focus_gain_difficulty=2、score_difficulty=2、hit_score_scale=15、damage_score_scale=1000.01，其余沿既有资源。实施前重读，若用户已改以当时值为准并记录；不因难达分调正式数值。自动测试只在运行夹具将初始专注设0验证真实获取。
- [x] **Step7 — 验证GREEN。** 先隔离伙伴输出记录Q/E无伤害；再启用真实AI，证明普通伤害使专注增加，真实1—4输入发起连携。Q/E不重设伙伴锁定、不强制Guardian交接，远程按原射程；Q落点取释放快照，不能用结束后已移动的玩家位置判断。Expected：该测试及原PlayerSkillTestSceneTest退出0/PASS，老训练/仇恨模式结果保持。
- [x] **Step8 — 原生游玩。** F6，点击Squad Combat，E后走动引怪，Q整理，伙伴正常输出，按1—4使用原连携；观察红标到期与原仇恨接续。不把测试计数面板当正式HUD，不从主场景启动替代本阶段人工入口。

自动夹具可在实例上临时提高敌人耐久、把输入者站位摆到可用范围以避免击杀/随机AI干扰；必须使用真实技能与伤害管线，不写回资源、不伪造专注/命中/资格信号。这不属于新的平衡方案。全部测试辅助函数留在Test.gd，不能加到生产系统。

## 4. Task3：暂停/终结边界、正常生命周期与阶段验收

**Interfaces:** 消费Task2同一场景与既有暂停协调器、玩家输入许可；不新增“正在聚怪/正在爆发”全局变量。

- [x] **Step1 — 先补边界失败测试。** 覆盖显式暂停、PlayerBase输入禁止、真实终结选择窗口和B模式镜头交接期间按Q/E：无受理、无新状态/位移/释放特效、无CD消耗。已开始动作按现有规则完成/取消，不能因UI解绑额外取消。
- [x] **Step2 — 演出完整后恢复。** 使用真实伙伴连携伤害产生达分，出现原选择窗口；完成一个现有终结演出再确认Q/E可输入。5%慢放不自动等同“全面禁用”，按原输入许可规则断言，不能只根据Engine.time_scale或UI可见猜测。
- [x] **Step3 — 必要修正。** 若集成暴露漏拦截，只修正已有输入许可传递/消费，不加技能专用终结判断，不重写GamePauseCoordinator或终结流程。每项修正先补能复现的RED测试；若需要改变已确认玩法则暂停说明。
- [x] **Step4 — 正常死亡/重开。** 一次联测流程中让玩家死亡、退出并重建同一测试场景；旧动作、Q外力、E状态/标记、临时仇恨及暂停/镜头令牌须按既有生命周期清理。新场景两个槽和HUD独立，无残留绑定；测试专用重开只在Harness，不增加生产reset。不是热装卸压力测试。
- [x] **Step5 — 核心回归。** 跑PlayerSkillBarTest、PlayerSkillCombinedFlowTest、PlayerSkillControlTest、PlayerSkillActionAnimationTest、PlayerSkillTestSceneTest、ForcedMovementComponentTest、PullTargetSkillEffectTest、TemporaryThreatLifecycleTest、TemporaryThreatSkillEffectTest、GatherPresentationTest、ThreatMarkPresentationTest、CombatRoomFinisherFlowTest。逐项检查真实输出。
- [x] **Step6 — 完整回归与原生检查。** 再跑所有extends SceneTree的*Test.gd；Expected无新增失败，旧两项单独报告，不为绿灯改Gameplay。原生截图、Debugger和退出状态都记录，不把PASS文字当作无报错/无泄漏。
- [x] **Step7 — 文档与独立review。** 更新PlayerSkillsConfigurationGuide、阶段四验收和路线状态；阶段末一次只读review对比本阶段基线，重要发现以RED→GREEN修正后重跑。UI来源、模式隔离、输入不穿透、正常回收是重点。
- [x] **Step8 — 交付并停止。** 用户可在同一F6场景体验两槽技能栏与完整循环；阶段五/UnitBase迁移、主场景/Git操作均不自动开始。

## 5. 验证命令

PowerShell通用模板：

```powershell
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' --headless --path 'G:\Godot\ProjectVOD' --script res://UnitSystem/Tests/PlayerSkillBarTest.gd
```

按上文逐项替换脚本路径。全量沿用最近已执行的rg枚举extends SceneTree脚本方式；最多4个进程并行。运行原生游戏时不并行headless，避免MCP连到错误进程。全部执行记录写阶段四validation，不在未实施时填写PASS。

## 6. 计划自查与实施门槛

- 阶段1—3与Q/E特效成果复用，不重做；本阶段只补HUD和联合验证。
- UI公开接口统一为bind_source，Controller仅补get_slot_status，后续任务消费名称一致。
- 一个Inspector来源，不新增CD/键名/技能描述/技能范围的重复配置。
- 三种测试模式的隔离在进入树前处理，已考虑现有组件在_ready强设ALWAYS；不只设置父节点disabled。
- 无伤害Q/E的直接事件与后续AI造成的事件分开验证。
- 阶段四完成后才讨论正式场景与UnitBase迁移，本次不以缺少正式装配判阶段四失败。
- 不自动提交代码/计划，不删除用户既有未提交内容，不建立新工作树。
- 计划已获用户确认；沿当前会话本人实施，阶段末一次独立review；实际证据见同日stage-4-validation。

## 实施补记

- 在实际终结窗口发现Q/E输入穿透，先RED后补齐既有Command输入持有向PlayerBase通用许可的传递；多来源持有和原基础禁用互不覆盖，不在技能中增加终结特判。
- 本测试原有五人血条占据左下，Q/E以原生Control局部偏移放在其右上，Squad收起长调试读数；不重做正式血条/伙伴栏的低分辨率布局。
- 新增PlayerBase和SquadChainCommandController的小范围输入许可修改在原计划允许的必要修正内；源Hero、EnemyBase及CombatRoom装配未修改。

独立review：无阻断问题，一项已知P3显示问题暂缓，详见[阶段四验收](2026-10-22-player-skills-stage-4-validation.md)。
