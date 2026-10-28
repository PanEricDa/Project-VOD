# 玩家技能阶段一：测试基座与施法入口 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans 按任务逐项实施；同一 Godot 编辑器只保留一个写入方。步骤使用复选框记录真实进度。

**Goal:** 在独立测试场景中，通过 Q/E、现有 SkillHost、玩家动作与正式释放帧，完成两个探针技能的施放闭环；暂不实现聚拢或临时仇恨。

**Architecture:** Input 只发槽号，Controller 适配 Host 与玩家动作。SkillBase 仍负责合法性、交付和冷却；PlayerAttackController 仍是玩家唯一的动画执行者。场景中的技能、输入和适配器显式装配，测试 HUD 只读真实事实。

**Tech Stack:** Godot 4.7、GDScript、InputMap、AnimationLibrary、现有 SkillBase/SkillHost/Delivery、SceneTree 契约测试、Godot MCP Pro。

**Spec:** [总体设计](../Specs/2026-10-21-player-gather-threat-skills-design.md)；[五阶段路线](2026-10-21-player-skills-staged-roadmap.md)。

状态：2026-10-21 用户确认后进入实施；阶段一已实现并完成最终全量回归与独立审查修正，等待用户体验验收。测试场景和Q/E探针已创建；不进入后续阶段。

## Global Constraints

- 所有创建、修改、保存优先 Godot MCP Pro；不支持、不可用或失败时才说明原因并回退。
- 沿用 AGENTS.md 的人类可管理、中文参数说明、正式 Resource 原生保存及有效 UID 要求。
- 不修改 Scenes/TestScene.tscn 中的单位；仅在新 PlayerSkillsTest 场景内局部装配。
- 不将玩家技能或控制组件装入正式 Hero/EnemyBase 源场景，不修改主场景装配。
- 不实现动态装备、热换槽、插拔事务或专项压力测试；只留必要接口和信号。
- 不新增伤害、专注消耗、连携计分、仇恨权级或聚怪状态；Q/E 此阶段只是探针。
- 保留既有移动、攻击、锁定、冷却与输入许可语义；没有新控制器时行为不变。
- 不覆盖已有未提交工作，不修改 MCP 插件，不自动提交 Git 或上传 GitHub。
- 动画制作遵守 Docs/AnimationWorkbenchWorkflow.md；不得用没有事件帧的普通攻击冒充施法动作。
- 完成阶段一后停止，不自动进入阶段二。

## Review Focus

1. 空槽、冷却、动作忙碌及 Q/E 同帧输入：拒绝不能排队、支付费用或产生额外释放；任务2/3测试。
2. 普通请求 request_id=0 不唯一、旧动作通知及同步回调重入：不能释放或清理新动作；任务1/2测试。
3. 动画缺失、循环、事件缺失/重复、零施法时间与事件顺序错误：明确拒绝，不永久占用；任务1测试。
4. 禁止新输入与死亡不是同一件事：前者不擅自取消已开始动作，后者必须清理；任务2/3测试。
5. 场景看似可运行但槽引用、动画 UID、导航或输入实际无效：检验原生资源及真实运行，不只比较文本；任务4测试。

## 1. 已核对的现状与改动边界

- UnitBase 已有 SkillHost、SkillSocket 和两个 Regular Skills 槽；get_regular_skill、request_skill、动作开始/释放/完成及取消入口已经存在。本阶段不重写 Host。
- PlayerAttackController 目前只处理普通攻击，没有 request_external_action，也未接收 action_release_requested / action_finish_requested。不能仅挂技能就认为玩家可以施法。
- CharacterAnimationEventPlayer 已有 release_action / finish_action，方法回调为立即模式；沿用该桥接，不增加技能专用 AnimationPlayer。
- SkillBase 目前专用 Animation 来自终结技 cinematic_profile；普通技能主要依赖默认动作或 MeleeSkillAction。本阶段增加可选普通动作资产，不给玩家探针挂终结镜头配置。
- Godot 原生只读检查确认 SwordAnimationLibrary.res 仅有 RESET 和 basic_attack_1/2/3，没有合法施法片段。
- CameraFollowController 是脚本，不存在可直接复用的 CameraRig.tscn；测试场景按 TestCombatRoom 的 CameraRig + Camera3D 结构装配，不复制整个战斗房间。

## 2. 配置入口与文件交付

所有路径相对于项目根；下表是计划交付，不表示文件已存在。

| 分类 | 文件 | 责任 |
|---|---|---|
| 新建通用组件 | UnitSystem/Components/Combat/PlayerSkillInputComponent.gd/.tscn | InputMap 动作到槽号 |
| 新建通用组件 | UnitSystem/Components/Combat/PlayerSkillController.gd/.tscn | 玩家请求及 Host/动作适配 |
| 新建测试内容 | Scenes/Tests/PlayerSkills/PlayerSkillProbe.tscn | 继承 SkillBase.tscn 的无伤害探针 |
| 新建测试内容 | 同目录 PlayerSkillProbeEffect.gd | 继承 SkillEffectBase，只上报真实 apply |
| 新建测试内容 | 同目录 PlayerSkillProbeAction.tres | 从 Sword 工作台施法片段保存的 Animation |
| 新建测试场景 | 同目录 PlayerSkillsTest.tscn、PlayerSkillsTestHarness.gd | F6 场地与只读调试 |
| 新建测试 | UnitSystem/Tests/PlayerSkillActionAnimationTest.gd | 动作资产、时序及 payload |
| 新建测试 | UnitSystem/Tests/PlayerSkillControlTest.gd | Controller、输入与清理 |
| 新建测试 | UnitSystem/Tests/PlayerSkillTestSceneTest.gd | 场景装配、导航及真实闭环 |
| 修改通用脚本 | SkillSystem/01-Core/SkillBase.gd | 普通动作 Animation 可选字段 |
| 修改通用脚本 | UnitSystem/Components/Combat/PlayerAttackController.gd | 同一动画执行者增加外部技能动作 |
| 修改通用脚本 | UnitSystem/Player/PlayerBase.gd | 技能动作移动/转向许可的最小接入 |
| 修改动画资产 | Item/Weapon/Sword/SwordAnimationLibrary.res | 新增 basic_cast_1，旧片段不变 |
| 修改工作台 | UnitSystem/Visuals/Workbench/HeroAnimationWorkbench.tscn | 按流程配对 Sword 武器与库 |
| 修改项目配置 | project.godot 的 InputMap | MCP 配置 player_skill_1=Q、player_skill_2=E |

新增合计：7 个 .gd、4 个 .tscn、1 个 .tres；Godot 自动生成的脚本 .uid 不另算业务资产。生产组件只有 Input 与 Controller，其余新建项均为测试内容/测试脚本。SkillHost 原则上只复用；如实施中发现必须修改，先指出具体缺口及影响，不能顺带扩展装备系统。

Inspector 入口：
- Input 仅导出两个 StringName：skill_1_action、skill_2_action，默认对应上述 InputMap；不写 KEY_Q/KEY_E 的运行时判定。
- Controller 不导出技能 ID、重复槽位或内部节点路径；自动解析同一 PlayerBase 下已有 SkillHost/AttackController，保留显式绑定方法。
- Host 仍配置 Regular Skills[0/1]，指向 SkillSocket 中两个不同探针实例。
- SkillBase 的普通动作分组仅新增 action_animation: Animation，可空；空值保持既有默认动作规则。
- 技能时间、冷却仍在技能根；探针 Q=0.2秒/10秒、E=0.15秒/12秒，不在输入/Controller/HUD重复配置。
- Harness 不暴露运行时计数、速度、动作身份等内部参数。

## 3. 动作资产与时间规则

通过 Workbench 配对 IronSwordVisual 和 SwordAnimationLibrary，在正确库内制作简单 basic_cast_1：轻微抬剑/身体前倾，再收回；不做复杂特效、额外位移或镜头。
- 首版片长0.40秒；release_action 在0.20秒，finish_action 在0.38秒；非循环，片尾留0.02秒。
- 姿态仅 CharacterRoot / WeaponSocket；无普通攻击 hit window、attack motion 或 projectile 方法帧。
- 将同一完成片段原生保存为测试目录中的 PlayerSkillProbeAction.tres，两探针共用；它是独立快照，后续编辑需按工作台流程同步，而非维护第二套手写关键帧。
- 播放倍率 = 动画 release 帧时间 / SkillBase.get_effective_cast_time()。Q倍率1，E倍率约1.333；施法速度修正仍只由 SkillBase 计算一次。
- 有效施法时间为0时只接受 release 位于0帧的兼容动画，不能除以0，也不把正前摇悄悄跳过。
- Controller 确认 Host 已开始后才能推进零帧方法，防止效果早于 CASTING。
- 正常结束以 finish_action 为准；动画自然结束但没有合法完成时取消，不能补发 release。内部看门狗上限为按倍率计算的片长+1秒，不在 Inspector 暴露。
- 退出动作必须恢复播放倍率及临时库；不能让下一次普通攻击继承施法速度，不能在死亡后播放 RESET 覆盖死亡表现。

SkillBase payload 规则：既有 cinematic_profile 分支不变；普通 action_animation 有配置时合并进已有普通动作 payload，不丢失 MeleeSkillAction 伤害元数据或 skill_motion_enabled。DIRECT_TRIGGER 不新增动画等待。现有 AI 控制器已能接收 Animation 负载，需做兼容回归，不借此重构 AI。

## 4. 接口与数据流

```text
Q/E → Input.slot_requested(0/1)
    → Controller.request_slot
    → Host.get_regular_skill → Host.request_skill
    → Host.action_requested
    → AttackController.request_external_action
    → Host.confirm_active_action_started
    → release_action → Host.release_active_action → ProbeEffect.apply
    → finish_action → Host.finish_active_action → 解锁
```

### 输入与控制

PlayerSkillInputComponent：
- signal slot_requested(slot_index:int)：只输出0或1，不携带技能ID。
- set_input_enabled(enabled:bool)->void：仅控制新输入；默认允许。
- 使用 _unhandled_input 的按下事件，过滤键盘 echo；同一事件只发送一次，GUI已经处理的事件不穿透。

PlayerSkillController：
- bind_host(host:SkillHostComponent)->void / unbind_host()->void：明确连接/断开边界，重复绑定同一 Host 不重复连接；不发展成动态装备功能。
- request_slot(slot_index:int)->bool：true表示本次请求已被受理且未在同步启动中失败，不表示伤害或效果已发生。
- signal slot_accepted(slot_index:int,skill:SkillBase)。
- signal slot_rejected(slot_index:int,reason:StringName)：reason取 invalid_slot / empty_slot / input_disabled / owner_dead / action_busy / skill_unavailable / action_rejected；这些是反馈，不复制底层合法性算法。
- 两个当前探针都是 Self 启动，传玩家自身，不依赖当前敌方锁定。将来其他目标模式需另行接目标输入，不在本阶段假装已支持自由瞄准。
- 调用前检查动作忙碌及玩家许可；冷却、条件、成本等仍交 Host。Host 的 request_skill 返回后检查本次动作是否已同步失败，不能一边 accepted 一边 cancelled。
- Controller 记录本次 skill实例、context实例和动作serial。普通请求继续使用 request_id=0，不能把它误当唯一执行身份。

PlayerAttackController 增加：
- request_external_action(effective_cast_time:float,target:UnitBase=null,action_payload:Dictionary={},request_id:int=0)->bool。
- get_external_action_serial()->int：只读单调递增的本地动作身份。
- is_action_in_progress()->bool：普通攻击实际播放中或外部技能动作中为true；CHAIN_WAIT / ROUND_WAIT 不作为不可打断动作。
- cancel_external_action()->void：幂等，不取消其他身份的新动作，不发成功释放。
- cancel_current_action()->void：Host 动作执行者协议，按当前模式取消；不新增行动类别。
- signal external_action_lifecycle(request_id:int,action_serial:int,event:StringName)，event为 release / finish / cancel。这是玩家端新增信号；相比现有AI信号显式携带serial，不修改AI签名或强行统一旧调用者。
- 获取本次 ProjectileOrigin 世界变换作为 Host 确认和释放参数；端点缺失明确失败，不依赖具体武器/技能ID。

外部动作只能从不忙碌状态进入。进入时清空原普通攻击的等待/缓冲，技能动作期间普通攻击轮询、RESET及原动画结束回调不得抢占。同帧 Q/E 按事件处理顺序受理首个，另一个拒绝，不保留队列。

### 权限、取消与清理

- PlayerBase 增加 set_skill_action_permissions(can_move:bool,can_turn:bool)->void，由 Controller 根据本次技能维护；默认true/true，结束/取消恢复。
- Q/E均允许移动/转向。can_move=false只抑制新的水平操作，不关闭重力、碰撞或整个物理处理；can_turn=false时不由锁定/移动朝向覆盖当前视觉。
- 新技能请求不插入正在执行的普通攻击/冲刺；技能动作占用期间不让新的冲刺取消或覆盖它。仅做互斥接入，不改变原普通攻击与冲刺之间已有规则。
- set_player_input_enabled(false)仍只禁止新输入，不擅自取消已开始动作；request_slot直接调用也必须检查该许可，不能绕过。
- 死亡、Host取消、技能执行失败、场景退出会终止相应动作并清理锁；先失效旧serial/引用，再通知外部，防止同步回调清掉新请求。
- release最多一次、finish最多一次；晚到的旧serial忽略。CharacterAnimationEventPlayer保持立即方法回调，停止旧动画不留下延迟方法调用。
- 释放前取消不进入技能冷却；释放后取消不撤销已经提交的效果或冷却。这沿用既有 SkillBase 规则，不另做退款系统。

## 5. 独立测试场景

PlayerSkillsTest.tscn 显式包含：
- 平地、静态墙体、NavigationRegion3D（实际烘焙），基础灯光与环境。
- Hero 实例，在本场景局部增加两个新组件；SkillHost/SkillSocket 下两个探针实例，Regular Skills分别引用。
- CameraRig + Camera3D，使用现有 CameraFollowController。
- EnemyContainer：GoblinWarrior 与 GoblinArcher 的训练实例。阶段一默认 Process Mode=Disabled，仅作为后续可复用目标，不启用真实战斗，也不修改其源场景。
- CanvasLayer/调试面板：Q/E名称、受理/拒绝、当前动作、冷却、开始/释放/完成计数、最近拒绝原因，以及重载本测试场景按钮。
- 地面边界与5米参考标记用于后续阶段；标记不是第二份技能效果半径，后续由正式 Delivery 数据驱动。

探针继承正式 SkillBase.tscn，使用 Self + InstantTarget Delivery，仅对自身调用一次 ProbeEffect.apply。两个实例ID为 player_probe_q / player_probe_e，关闭自动释放、无伤害/费用/评分。
ProbeEffect 仅发出 applied(context:SkillContext,target:Node3D)供 Harness 记录真实效果执行，不把接收按键当成释放计数。
Harness 不直接调用 Effect、写冷却或模拟技能成功；计数来自输入反馈、cast_started、真实apply及动作完成事实。只在已匹配身份时归属当前槽。

## 6. 可审查的实施任务

### Task 1：普通动作资产与玩家动作执行

**Files:** 修改 SkillBase.gd、PlayerAttackController.gd、SwordAnimationLibrary.res、Workbench.tscn；创建 PlayerSkillProbeAction.tres、PlayerSkillActionAnimationTest.gd。
**Interfaces:** 实现第3/4节动作协议与普通 action_animation 字段；不实现 Controller 或输入。

- [x] RED：测试 test_plain_action_payload_preserves_existing_metadata，断言普通Animation原样进入payload、无Cinematic Profile、旧Melee元数据和motion标志保留；空值及DIRECT_TRIGGER行为不变。
- [x] RED：test_action_marker_contract，断言唯一release=0.20、finish=0.38、length=0.40、非循环、Animation及库UID有效；错误事件、循环和不匹配零施法时间拒绝。
- [x] 运行对应测试，确认因功能/资产缺失失败，而非测试夹具无法装载。
- [x] 通过Workbench真正制作并预览动作，原生保存库/快照，保留现有片段与UID；通过Inspector验证Animation强类型Quick Load。
- [x] 实现外部动作及payload；test_effective_cast_time_controls_release分别用0.20/0.15秒验证释放帧时间（容差一个物理帧）、一次release/finish、倍率恢复。
- [x] test_attack_cannot_steal_external_animation：按住普通攻击不覆盖技能；无新组件时原攻击照常。test_duplicate_or_old_serial_ignored：重复release、旧finish不影响新动作；检查0帧握手不抢跑。
- [x] GREEN：新测试及 AISkillActionAnimationTest、AIAttackControllerTest、PlayerDashComboContinuityTest 通过；确认AI终结动作/时钟分支未改变。

### Task 2：槽位请求与Host适配

**Files:** 创建 PlayerSkillController.gd/.tscn、PlayerSkillControlTest.gd；不新增Host装备API。
**Interfaces:** 消费Task1动作协议；提供request_slot、bind_host/unbind_host及受理/拒绝信号。

- [x] RED：test_empty_and_invalid_slot_rejected，断言空槽/索引-1/2不调用动作或Effect；test_two_slots_use_distinct_instances断言0/1分别请求对应实例。
- [x] RED：test_busy_cooldown_and_same_frame_requests，断言忙碌/冷却拒绝，两个同帧请求仅受理一个，被拒绝技能保持READY且无计费。
- [x] 运行RED后实现Controller；复用Host.get_regular_skill/request_skill与三项动作通知，不复制冷却/合法性实现。
- [x] test_start_failure_is_not_accepted：缺端点/不兼容动画同步失败时返回false，不同时发送accepted，Host不残留占用。
- [x] test_cancel_and_death_cleanup及test_reentrant_old_callback_does_not_clear_new_action：释放前取消不CD、释放后取消保留CD，死亡无RESET覆盖，旧通知不能终止同步新请求。
- [x] GREEN：Controller测试通过；SingleSceneSkillHostTest、UnitBaseSkillHostAssemblyTest通过。若需要改Host先记录缺口并review。

### Task 3：InputMap与玩家权限

**Files:** 创建 PlayerSkillInputComponent.gd/.tscn；修改PlayerBase.gd、InputMap；扩充PlayerSkillControlTest.gd。
**Interfaces:** 消费Task2.request_slot；输入输出slot_requested；PlayerBase提供第4节权限接口。

- [x] RED：test_inputmap_dispatch_and_echo，真实InputEventAction只发一次；项目键绑定检查Q/E；echo不重复；重绑定后按新InputMap工作而非硬编码键值。
- [x] RED：test_input_disabled_does_not_cancel_started_action：禁止输入后新请求拒绝，已开始动作仍可完成；暂停不执行技能输入。
- [x] 通过MCP配置两个InputMap动作，实现输入与权限接入；不增加第二套费用、施法或CD计时。
- [x] test_move_turn_permissions_and_legacy_fallback：允许移动的探针可边走边放；测试夹具中关闭移动/转向会生效，重力碰撞仍更新，结束恢复，无组件的Hero旧行为不变。
- [x] GREEN：PlayerSkillControlTest、PlayerTargetingComponentTest、PlayerDashComboContinuityTest、PlayerDashRechargeTest通过。

### Task 4：测试场景、只读反馈与阶段验收

**Files:** 创建 PlayerSkillsTest.tscn、Harness.gd、Probe.tscn、ProbeEffect.gd、PlayerSkillTestSceneTest.gd；更新本计划真实结果。
**Interfaces:** 仅装配Tasks1–3与已有系统，Harness只读正式事实。

- [x] RED：test_scene_assembly_contract，断言只有一个Host/输入/Controller/AnimationPlayer、两槽不同实例、ProbeEffect继承正确、正式Hero源场景未新增技能组件。
- [x] 通过MCP建立第5节场景，保留场景继承与资源外部引用；配置探针数值，原生保存并验证资源UID。
- [x] test_navigation_has_real_path：实际烘焙mesh且同步地图后，两侧可走点路径非空，墙体切割有效；不把只挂NavigationRegion当作通过。
- [x] test_real_input_to_effect_and_finish：真实输入Q/E分别启动、apply一次、完成一次；CD从成功释放开始；冷却拒绝时这些计数不增加。
- [x] test_probe_has_no_gameplay_side_effects：敌人位置、HP、威胁表、专注/连携事件不因探针变化；测试不靠尚未装配的系统伪造成功。
- [x] F6人工观察走动+Q/E、冷却重复按键、空槽配置、动作忙碌、死亡/重开及退出；查看Output/Debugger，记录动作/Effect/冷却数据，不只交付log。
- [x] GREEN：三项新测试及相关回归通过；更新配置入口、F6步骤、具体测试结果与已知失败。停止并交付用户review，不进入阶段二。

## 7. 测试运行与基线区分

SceneTree脚本直接运行，不依赖新增测试插件。PowerShell在项目根执行，例如：

```powershell
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' --headless --path 'G:\Godot\ProjectVOD' --script 'res://UnitSystem/Tests/PlayerSkillActionAnimationTest.gd'
```

另外两项新测试替换为PlayerSkillControlTest.gd、PlayerSkillTestSceneTest.gd。回归同理替换已有脚本路径；每项必须输出对应 TestName: PASS 且退出码0，无新增SCRIPT ERROR、资源泄漏报告或Debugger错误。测试实例应主动释放，不能只忽略退出警告。

实施前重新记录基线；此前检查曾有两项既存失败：CameraFollowControllerTest的既有房间导航烘焙断言，以及SingleSceneFireboltTest的6米旧预期/当前5米配置不一致。它们不是本阶段新失败；不得擅改游戏参数抹平。新测试场景自身的导航断言必须独立通过，回归出现新差异必须定位。当前文档不声称已重新运行这些测试。

## 8. 人工验收与阶段门槛

实施完成后用户打开 Scenes/Tests/PlayerSkills/PlayerSkillsTest.tscn，F6：
1. 不锁敌，按Q：看真实施法动作、一次释放/完成及2秒测试CD。
2. 按E：对应另一个实例，施法0.15秒、2秒测试CD。
3. 移动中施法应可用；冷却中/动作忙碌重复按不会排队、额外生效或改写动画。
4. 冷却结束可再次施放；死亡/重载后无永久动作锁或残留回调。
5. 本阶段怪物不会被拉动，也不会因Q/E改变仇恨；这是明确的阶段边界，不是功能缺失。

交付需包含文件清单、Inspector入口、三项新测试和相关回归的实际结果、F6验证记录及已知问题。本阶段不交付正式玩家技能栏、Q/E专属特效或主场景装配。

## 9. 计划自检记录

已逐项核对：总体设计的阶段一请求/动作/冷却边界均有任务；request_id与serial区分明确；输入禁止沿用原语义，不等同死亡取消；动作资产不借用Cinematic Profile；所有Review Focus均落实到命名测试。没有把后续聚拢、临时仇恨、插拔验证或正式装配提前带入。实施进度见第10节；最终验收结果见第10节。


## 10. 实施记录与配置说明（2026-10-21）

当前：阶段一已完成实现、回归与独立审查修正，等待用户体验验收；未进入阶段二。全部文件编辑/资源保存使用Godot MCP Pro，没有修改插件，也未Git提交或上传。

### 实际配置入口

- 测试入口：Scenes/Tests/PlayerSkills/PlayerSkillsTest.tscn，打开后F6。
- Hero/SkillHost：Regular Skills[0] → SkillSocket/ProbeQ；[1] → ProbeE。两个是不同实例，正式Hero源场景未挂它们。
- ProbeQ/ProbeE根节点：Action / Action Animation指向PlayerSkillProbeAction.tres；Casting / Base Cast Time分别0.2、0.15秒；Cooldown / Skill Cooldown在测试场景实例均覆盖为2秒（2026-10-21追加调试调整）；允许移动和转向。
- Hero/PlayerSkillInputComponent：两个InputMap动作名。实际Q/E键在Project Settings → Input Map维护，不在脚本硬编码。
- Hero/PlayerSkillController：不需要策划填写技能ID、重复槽或内部路径。
- HUD/DebugPanel：仅测试观察；Accept/Start/Apply/Finish/Cancel分别读取受理、开始施法、真实Effect、动作完成、取消。拒绝原因与冷却直接读取真实流程。
- Sword工作台新增basic_cast_1，0.40秒/释放0.20秒/完成0.38秒。原RESET和三个普通攻击片段逐轨道/关键帧核对未改；动画库UID保留。
- 新增只读is_external_action_in_progress接口用于技能与冲刺互斥，不阻止原有普通攻击被冲刺取消，不增加Inspector字段。

### 已有验证证据

- 三项新增SceneTree测试已通过，测试先因缺少对应功能失败，再由实际实现转绿。
- 已通过相关回归：AISkillActionAnimationTest、AIAttackControllerTest、SingleSceneSkillHostTest、UnitBaseSkillHostAssemblyTest、PlayerTargetingComponentTest、PlayerDashComboContinuityTest、PlayerDashRechargeTest。
- 新场景导航22个多边形、24个顶点；测试真实可走路径与墙体排除，不依赖正式房间尚未烘焙的导航。
- 新Animation原生保存UID=2139922782214679780；Sword库UID=1154281183483410011。编辑器资源索引分别为Animation/AnimationLibrary，action_animation导出字段为强类型Animation。
- 编辑器内实际运行：Q/E各Accept=1、Start=1、Apply=1、Finish=1、Cancel=0；E施法时按住移动，玩家X由0到约2.03；忙碌请求明确拒绝。运行Output未见游戏脚本错误。
- MCP simulate_key仅发送逻辑键，与项目物理键绑定不匹配；实际运行改用InputMap simulate_action和带physical_keycode的原生InputEvent验证，没有为测试改绑定或修改插件。
- 正常死亡/取消、零施法时间、世界原点发射点、旧serial通知、同帧请求、冷却拒绝及输入禁止后已开始动作继续完成，均由新增自动测试覆盖。
- 完整结果与独立审查结论见下文；既有Firebolt距离与正式房间导航两项失败不通过擅改参数消除。

### 明确未交付

怪物聚拢、临时仇恨Debuff、正式玩家技能栏/专属特效、运行中装备/拆卸系统及正式CombatRoom装配均未提前实现。训练敌人处于Disabled模式，不会主动战斗。蓝色5米圈仅为初始出生点参考，不是实时技能判定。

### 独立审查修正

审查者Pauli按本轮备份对照增量，只读审查；发现的两项均已先复现失败，再修正并通过新增测试：

1. Host普通取消在回调同步请求新技能时会误清新动作。只在原cancel_active_skill加入捕获skill/context身份的清理保护，沿用现有终结取消的原则；不增加Host公开API、换槽事务或冷却规则。
2. 玩家动作校验原先统计禁用方法轨道；现在仅统计启用轨道，无有效release/finish时启动前拒绝。

另外修正普通payload局部变量重名的编译警告。审查未覆盖的后续阶段保持延后；UID、资源索引和编辑器内运行由执行方实际验证，旧未提交工作和两项已知基线失败不纳入本轮改动。独立审查没有遗留minor项。

### 最终验收结果

- 阶段一四项任务已完成，停止在本阶段，等待用户体验验收。
- 最终代码完整执行173项SceneTree测试：171通过，2项既有失败：
  - UnitSystem/Tests/CameraFollowControllerTest.gd：既有TestCombatRoom导航网格未烘焙。
  - SkillSystem/05-Tests/SingleSceneFireboltTest.gd：旧测试期望6米，当前用户配置为默认5米。
- 两项失败在实施前已复现，本轮未通过改游戏参数或旧房间内容掩盖。新增三项测试、审查补充的取消重入/禁用轨道用例均通过，无资源泄漏报告。
- RangedAttackPipelineTest为RefCounted契约辅助类，不可用--script启动；额外调用collect_failures结果为空，不计入173项SceneTree数量。
- 全量测试中11个既有测试脚本有warning输出：CameraFollowControllerTest、EncounterControllerTest、ChainSkillPresentationControllerTest、SquadFocusSceneBindingTest、SquadChainRoundWindowTest、SquadChainAdaptiveWindowTest、PlayerTargetingComponentTest、GamePauseCoordinatorTest、CombatHUDBindingIntegrationTest、SkillReleasePresentationTest、TriggerSkillEffectTest。未把warning等同为全部测试失败；新增三项测试无warning。
- 最终编辑器新运行会话：Q/E各真实受理/开始/Apply/完成一次；点击Reset Test Scene成功重载，两槽全部计数归零、输入许可恢复；Debugger查询errors=[]，Output无游戏脚本错误。
- 工作台、测试场景、脚本均已保存；原武器片段未改。正式Hero/EnemyBase/CombatRoom未装配本阶段内容，Scenes/TestScene.tscn未动；没有Git提交或上传GitHub。
- 审查问题修复后未再次派发审查，按计划用失败用例转绿及最终全量回归验证。无遗留minor项。完整配置入口和F6步骤见本节及第8节。

执行裁定：保留当前项目目录及未提交结果，符合用户确认；Host仅补原取消流程的身份防护，不扩展装备/插拔系统。后续阶段、热换槽与旧未提交内容继续遵守原范围，不借阶段一扩大实现。

### 2026-10-21 追加：缩短测试冷却

用户为方便测试要求两技能CD均为2秒，已通过Godot MCP修改PlayerSkillsTest场景中的ProbeQ、ProbeE实例并保存。没有改共享Probe模板或生产技能基线；上述早期10/12秒验证记录保留为历史。PlayerSkillTestSceneTest已改为验证两项实际2秒冷却，先失败再通过。重新运行全量仍为171/173通过，仅既有Camera房间导航与Firebolt距离断言失败。第二阶段继续保留测试2秒覆盖。
