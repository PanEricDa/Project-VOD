# 技能动画位移组件 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** 为Archer终结技增加与后翻动画同步、带碰撞且保持朝向的0.8米后退，并形成可复用的技能组件。

**Architecture:** 动画方法帧定义区间，当前动作驱动输出实际动画游标，SkillHost把样本交给当前技能组件计算位移。单位在原有唯一物理循环中消费本帧水平位移；不另设时间倍率、秒数计时器或移动循环。

**Tech Stack:** Godot 4.7、GDScript、Node组件、AnimationPlayer方法轨道、CharacterBody3D；Godot MCP Pro优先编辑。

**Spec:** `res://SkillSystem/04-Docs/SkillMotionComponentDesign.md`，用户已确认。

日期：2026-10-20。状态：四任务已完成，独立复核与运行验收通过；全量163项，162通过、1项既有导航失败。建议在当前已连接的项目目录顺序执行，末尾独立只读复核；不擅自创建工作树、提交或推送Git。

## Global Constraints

- “不得硬编码5%/20倍补偿，不维护独立的0.45秒倒计时，不复制动画播放速度参数。”
- “组件仅配置方向与距离，无速度和时长字段。”
- “本轮只支持单个组件、单个位移区间，不引入编号映射。”
- Archer方向为后退、距离0.8米；方向取稳定水平朝向，不取翻转中的CharacterRoot。
- 唯一时间依据为当前实际动作游标及begin/end方法帧；继续使用当前SkillExecutionClock，不创建另一套时钟。
- 每物理帧仍只执行原有一次move_and_slide；不直接写角色global_position，不增加真实腾空或无敌。
- 保留用户当前姿态、伤害、射程、容差和特效参数；不自动向Scenes/TestScene.tscn添加单位。
- 新export、公开接口、信号及跨模块输入均须紧邻简体中文说明，注明单位、身份与生命周期约束。
- 每任务先写行为测试并确认预期失败，再实现、重测；生产编辑优先MCP，失败/不支持才说明原因后回退。
- 原生保存新场景，验证有效UID；外部动画资源保留原UID并显式同步缓存。没有计划新增tres/res。
- 本文中的新接口是待实施契约，不表示现有代码已具备；代码行号以函数名定位，避免脏工作区行号漂移。

## Review Focus

1. end与自然动作完成落在同一物理帧：最后一段位移必须先提交，之后才收尾，不能因RESET丢失末段。任务1、2、3测试覆盖。
2. 普通技能request_id为0且连续重复施放：旧请求事件不能接管或清理新位移。任务1、3使用内部action_serial覆盖。
3. 区间中途5%恢复1倍、镜头冻结或动画加速：相同动画进度对应相同距离，不因进程先后或重复时钟换算漂移。任务1、3、4覆盖。
4. 碰撞截短后不得累积“欠的距离”以便之后瞬移补偿；AI导航不能在同帧叠加移动。任务2、3覆盖。
5. 未挂组件、纯触发无动画、工作台预览或无效方法帧：旧内容不变，配置错误可见且不残留动作占用。任务1、3、4覆盖。

## 文件与职责

新增正式内容仅2个文件：
- SkillSystem/03-Extensions/SkillMotionComponent.gd：技能级位移配置、进度消费、请求隔离；extends Node，@tool支持必要配置提示。
- SkillSystem/03-Extensions/SkillMotionComponent.tscn：Node根、上述脚本、Direction与Distance M两个Inspector内容参数。

新增4个测试脚本（及Godot生成的.uid）：
- UnitSystem/Tests/SkillMotionActionBridgeTest.gd。
- SkillSystem/05-Tests/SkillMotionComponentTest.gd。
- UnitSystem/Tests/SkillMotionCollisionTest.gd。
- UnitSystem/Tests/SkillMotionIntegrationTest.gd。

修改既有接线：
- UnitSystem/Components/Animation/CharacterAnimationEventPlayer.gd。
- UnitSystem/Components/Combat/AI/AIAttackController.gd。
- UnitSystem/Components/Combat/AI/AICombatSystem.gd。
- UnitSystem/Components/Behavior/AllyBehaviorStateMachine.gd。
- UnitSystem/Base/AIUnitBase.gd。
- SkillSystem/01-Core/SkillBase.gd。
- SkillSystem/01-Core/SkillHostComponent.gd。

内容与验收修改：BowAnimationLibrary.res、ArcherPowerShotAction.tres、ArcherPowerShotCinematic.tres、ArcherPowerShotFinisherSkill.tscn、ArcherPowerShotFinisherTest.gd及现有配置/Workbench说明。不重构其他模块，不新建运行时数据Resource、编辑器插件或新角色场景。

## 固定内部协议

沿用项目既有只读Dictionary动作负载方式，不新增资源文件或隐藏的策划装配：
- SkillBase动作负载增加内部布尔值`skill_motion_enabled`，默认false。
- AIAttackController为每次已接受外部动作递增`action_serial`；不作为Inspector参数。身份由(request_id, action_serial)组成，普通request_id=0也能区分。
- 当前动作内部样本sample只含事实：
  - `interval: Vector2`：动画区间[a,b]，单位为片段秒数。
  - `previous_position: float`与`position: float`：本次推进前后的实际游标。
  - `forward: Vector3`：区间首次进入时从既有_read_visual_forward读取并锁定的水平前向。
  - `terminal: bool`：本帧已跨到/越过结束方法帧。
- 动作控制器和CombatSystem不访问SkillBase/SkillMotionComponent；组件不查找AnimationPlayer节点或调用AI物理函数。

运行时接口：
- CharacterAnimationEventPlayer：`signal skill_motion_marker_requested(begin: bool)`；`begin_skill_motion() -> void`、`end_skill_motion() -> void`。
- AIAttackController、AICombatSystem：`signal external_action_motion_sample(request_id: int, action_serial: int, sample: Dictionary)`。
- 两者提供`get_external_action_serial() -> int`，不改原external_action_lifecycle(request_id, event)两参数接口及现有语义。
- SkillHost：`consume_action_motion_sample(request_id: int, action_serial: int, sample: Dictionary) -> void`。
- SkillHost输出`signal skill_motion_step_requested(request_id: int, action_serial: int, displacement: Vector3, terminal: bool)`及`signal skill_motion_cancel_requested(request_id: int, action_serial: int)`。
- SkillMotionComponent：`validate_configuration() -> PackedStringArray`；`sample_motion(request_id: int, action_serial: int, sample: Dictionary) -> Dictionary`；`cancel_motion(request_id: int, action_serial: int) -> void`。
- sample_motion结果仅含`accepted: bool`、`displacement: Vector3`、`terminal: bool`，不反传物理/动画状态。
- AIUnitBase：`submit_skill_motion_step(source: Node, request_id: int, action_serial: int, displacement: Vector3, terminal: bool) -> bool`；`cancel_skill_motion(source: Node, request_id: int, action_serial: int) -> void`。source使用Host，单位内部只弱引用它。

## Task 1：建立按实际动画游标输出的事件桥

**Files:** 修改CharacterAnimationEventPlayer.gd、AIAttackController.gd；新增SkillMotionActionBridgeTest.gd。
**Consumes:** 当前request_external_action、get_action_delta、AnimationPlayer实际播放速度与游标。
**Produces:** 上述方法、external_action_motion_sample和action_serial契约；不接入真实位移。

- [x] 写失败测试：开启skill_motion_enabled时读取实际播放片段的一对标记。使用[a,b]=[1.0,1.5]，样本游标1.25、区间[1.0,1.5]必须原样输出；不得把世界秒数或归一化值伪装成动画游标。
- [x] 加入边界：0秒开始、重复/倒置/缺失标记、非有限位置、一次推进跨begin/end、end恰在片尾、普通ID0重复两轮serial不同；未开启位移的旧片段不受限制。
- [x] 运行新测试，确认因接口不存在或无样本而失败，不能以解析错误代替RED。
- [x] 增加事件方法与控制器绑定。开始请求时解析实际选中的动作Animation，不读预设的另一份动画；enabled才校验方法帧恰好一对且a<b。
- [x] 有位移的普通角色动作也使用同一手动动作驱动；未挂组件的普通动作保持原播放路径。普通动作如受finish_action提前结束，end不得晚于该有效结束点；专属终结动作沿原片段自然完成门闩。
- [x] 取推进前后游标；方法回调只记录边界，不立即清理位移。推进后统一发样本，跨越两标记也只发一份。若自然完成会立即RESET，先保存终点并提交样本，再执行原收尾通知。
- [x] 驱动位移动作时，将控制器physics优先级由单位当前process_physics_priority派生为其前一级，保存旧值并在收尾恢复；保证先推进/提交意图，后由单位物理循环执行，不更改非位移动作顺序。
- [x] 测试同一动画游标在world scale=1、0.05、0.2及播放速度0.5/1/2时含义一致；动画被hold或真暂停时不输出前进样本。跨真实physics_frame变更流速，不修改时钟私有缓存。
- [x] 重跑新测试及AISkillActionAnimationTest、FlameBarrageRuntimeTest，均PASS。审阅本任务差异；仅在用户另行授权时提交该任务的精确文件，禁止git add全工作区。

## Task 2：组件进度计算与唯一碰撞执行

**Files:** 新增SkillMotionComponent.gd/.tscn；修改AIUnitBase.gd；新增SkillMotionComponentTest.gd、SkillMotionCollisionTest.gd。
**Consumes:** Task 1样本协议。
**Produces:** sample_motion与submit/cancel_skill_motion_step接口；尚不自动给任何正式技能装配。

- [x] 写组件失败测试，配置后退0.8米、前向Vector3.FORWARD、区间[1.0,1.5]。第一次游标1.25应输出Vector3(0,0,0.4)，到1.5再输出Vector3(0,0,0.4)；重复1.5不得再给距离。另覆盖左/右/前向及非有限/零方向、无效配置与旧serial。
- [x] 写碰撞失败测试：实例化真实AIUnitBase，夹具内放地面与StaticBody3D墙体；无墙累计后退0.8米（容差0.03米），有墙0<=实际后退<0.8米，朝向不反转，随后几帧不得补偿穿墙。不改正式TestScene。
- [x] 运行两项，确认预期失败，再实现组件；定义enum Direction { FORWARD, BACKWARD, LEFT, RIGHT }；Inspector仅导出direction: Direction = Direction.BACKWARD与distance_m: float = 0.8，距离须有限且>0。片段边界由控制器负责，组件不另计时。
- [x] 组件内部根据实际游标计算p，使用上次已消费p防重复；超出end夹到1。锁定方向，末段accepted且terminal；不能用实际碰撞距离反算动画进度。
- [x] AIUnitBase仅增加由Host身份占有的待消费水平位移状态，不新建MotionState或物理回调。物理delta>0时将本帧位移转换成水平velocity，仍在原move_and_slide结算；不额外乘除Engine.time_scale。
- [x] 位移区间覆盖普通导航水平意图并保留初始朝向；锁定期间无新样本则水平速度为0。重力走原流程，不更改Visual/CharacterRoot动画。
- [x] terminal帧必须先消费最后位移，再释放占用；自然结束的后续清理不能抹掉该帧。撞墙后标记本区间受阻，之后样本只推进进度，不追补未完成距离。
- [x] 死亡、动作取消或source离树及时清理；取消只有source+request_id+serial匹配才生效。无效/旧样本不得覆盖更新占用。
- [x] 新场景经Godot正式保存并验证UID；两项测试及AIUnitBaseLocomotionMigrationTest、原攻击位移相关回归PASS。审阅后作为独立检查点，不自动提交。

## Task 3：接通当前技能与动作身份

**Files:** 修改SkillBase.gd、SkillHostComponent.gd、AICombatSystem.gd、AllyBehaviorStateMachine.gd；新增SkillMotionIntegrationTest.gd。
**Consumes:** Task 1控制器事实、Task 2组件/物理接口。
**Produces:** 通过现有技能请求启动并完成的真实动画位移。

- [x] 写失败测试：真实Ally动作、SkillHost及组件；从动作开始到end验证后退0.8米、保持朝向。覆盖普通ID0、连携/终结正ID、同一技能重复请求、没有组件不移动。
- [x] 加入身份与生命周期：已发射后SkillBase不再CASTING但后摇仍可位移；旧动作取消不影响下一动作；区间死亡/取消后不再移动，已发箭矢仍按原规则命中。
- [x] 在SkillBase增加`get_motion_component() -> SkillMotionComponent`，直接子节点按类型查找；重复组件给配置错误。get_action_payload各返回分支统一附加内部enabled事实，不能要求行为层按节点名字查找。
- [x] Host只定位当前动作所持技能及组件，接收动作样本后核对当前request_id和驱动serial，再调用sample_motion；不反查动画，不导入AIUnitBase。组件有效时把结果作为位移意图信号发出。
- [x] AICombatSystem仅转发控制器样本与serial；BehaviorStateMachine沿已有依赖连接样本到Host、Host位移/取消信号到owner。断开/重新配置时成对清理，禁止双重连接造成双倍距离。
- [x] 区分正常terminal与硬取消：terminal的末段意图保持到单位消费；硬取消立即清理。迟到信号只属于原身份，不以当前新动作替代。
- [x] 必测实际physics顺序：位移样本提交时单位尚未执行当帧移动；不要靠调用两次move_and_slide让测试过。用本帧真实角色位移而非信号次数验收。
- [x] 慢放矩阵：在同一动画区间跑1倍、5%、20%，播放速度0.5/1/2；在进度0.5附近从5%恢复1倍，并插入镜头动作hold/真暂停。无障碍时进度0.5累计0.4米，结束0.8米，容差0.03米。
- [x] 工作台或纯视觉预览只发方法信号无Host时应无副作用；无动画的直接触发不自动位移。新测试及现有Host/连携/终结测试PASS，审阅此检查点，不自动提交。

## Task 4：Archer装配、动画与最终验收

**Files:** 修改BowAnimationLibrary.res、ArcherPowerShotAction.tres、ArcherPowerShotCinematic.tres、ArcherPowerShotFinisherSkill.tscn、ArcherPowerShotFinisherTest.gd、ArcherPowerShotFinisherConfigurationGuide.md、Docs/AnimationWorkbenchWorkflow.md；扩充SkillMotionIntegrationTest.gd。
**Consumes:** 前三任务完整通路。
**Produces:** 可在正式战斗中观察的Archer后翻后退，并有清晰策划配置入口。

- [x] 先读Workbench规范，核对内存与磁盘最新片段、方法帧、未保存修改及UID；记录用户当前技能/特效/动作基线，不强制沿用旧数值。
- [x] 在正确Bow库现有finish_attack_1上只加begin/end方法帧。若当前姿态仍与已审阅设计相同，使用起跳预备约0.92秒、落地约1.46秒；执行时以实际最新姿态核对，业务代码不得出现这些时间。
- [x] 不改姿态、release_action、finish_action、片长或施法速度。遇到用户新姿态与预定关键帧不符，不擅自重做动画；说明差异再确定新的标记位置。
- [x] 原生保存Bow库，将完整片段同步正式Action并显式重绑Cinematic缓存；保留原UID，比较重读后的方法帧和姿态。SkillCinematicProfile验证须仍通过。
- [x] 技能根下实例化SkillMotionComponent，Direction=BACKWARD、Distance M=0.8；保持场景实例关系，不对角色/投射物根做位移动画。所有新export及接口中文说明齐全。
- [x] 新集成测试在运行时CombatRoom副本使用真实Archer、敌方合法目标与真实碰撞移动；不要沿用旧测试里关闭Archer物理处理的夹具来证明位移。其他单位隔离只限运行夹具。
- [x] 断言单箭单次伤害、后翻期间持续水平后退、落地后无残留速度/锁、撞墙安全、世界时间恢复不漂移；正式技能的动画和组件参数都能由Inspector/时间轴调节。
- [x] 配置指南记录组件与两方法帧是唯一入口，Workbench文档补充可选位移事件；纯视觉特效Preview仍只验证外观，不假装验证CharacterBody碰撞位移。
- [x] 执行四项新测试、ArcherPowerShotFinisherTest、ArcherPowerShotVisualEffectTest、正式输入4流程以及全项目SceneTree测试。报告新增失败、既有失败和泄漏，不把已知CameraFollowControllerTest未烘焙导航问题伪装成全绿。
- [x] Godot运行检查实际后退与原朝向，结束后停止测试实例、不保存运行夹具。git diff --check；核对CombatRoom、共享Arrow及其他用户文件没有意外改动。
- [x] 完成独立只读复核后修正重要问题；向用户交付实测结果和文件入口，不自动Git提交/推送。

## 验证命令

在G:/Godot/ProjectVOD执行，exe沿用当前已配置Godot 4.7；示例：

```powershell
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' --headless --path 'G:\Godot\ProjectVOD' --script 'res://UnitSystem/Tests/SkillMotionActionBridgeTest.gd'
```

依次替换为SkillMotionComponentTest、SkillMotionCollisionTest、SkillMotionIntegrationTest及既有测试路径。每项预期exit0、末尾对应PASS，无新增SCRIPT ERROR/泄漏。不在headless测试运行期间调用Godot MCP运行时工具，避免附着到错误进程。

全量回归沿用当前SceneTree发现方式，给本次结果单独日志目录；先检查现有运行器脚本再运行，不改变工作区或覆盖用户测试配置。

## 计划自检

- [x] 设计中的方向/距离、方法帧、单一时间依据、碰撞与生命周期均有明确任务和测试。
- [x] 四阶段接口名称、sample字段、request_id/action_serial及单位身份一致。
- [x] 两方法帧定义时间，不增加持续时间、速度或慢放倍率配置。
- [x] 零帧/跳帧/同帧自然结束、ID0重复动作、取消/死亡与碰撞截短都有测试归属。
- [x] 每阶段先RED再GREEN；文档、资源保存和实际装配归入需要它们的任务。
- [x] 没有计划修改普通攻击、玩家控制体系、终结资格、伤害算法或世界导演规则。

## 执行交接

请用户审阅本计划并选择执行方式。推荐Native：由当前会话顺序实施四个紧密耦合的任务，统一持有Godot编辑器上下文，末尾独立复核。另一选择为Subagent-driven：每任务由独立执行者/复核者接力，但需串行协调同一Godot编辑器，成本更高。

执行方式：用户已确认Native，当前已连接项目顺序实施，完成独立只读复核；未执行Git提交/推送。
