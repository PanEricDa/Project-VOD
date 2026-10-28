# 玩家技能阶段五：被动位移收口与正式装配设计

日期：2026-10-22。状态：阶段四已获用户认可并要求继续；本文件及先内置位移再正式装配的顺序已于2026-10-22获用户确认。详细计划已获用户批准并执行，三批实现已落地；完整验证和review见阶段五validation。未提交Git。

依据：[既有玩家技能设计](2026-10-21-player-gather-threat-skills-design.md)第5.1节、[分阶段路线](../Plans/2026-10-21-player-skills-staged-roadmap.md)及[阶段四验证](../Plans/2026-10-22-player-skills-stage-4-validation.md)。

## 1. 用户目标与现状证据

目标是正式启动即可使用玩家Q/E，并与已有四伙伴、普通AI、连携、终结技共存。
保持技能可装配、接口开放、Inspector易读；不增加装备/热换槽系统，不重调已验收数值。

实施前实际依赖（历史基线，当前入口见阶段五validation）：
- Hero源场景尚未装配PlayerSkillInputComponent、PlayerSkillController及Q/E；测试场景为局部装配。
- 正式EnemyBase继承AIUnitBase，没有ForcedMovementComponent。
- PullTargetSkillEffect当前只接受AIUnitBase且要求唯一标准接收器子节点；缺组件时跳过。
- AIUnitBase的物理循环和死亡处理仍按节点名读取接收器；PlayerBase尚未消费这种外力。
- 因而直接把Q挂到Hero不会使正式敌人可拉拽，不能把“能按Q/有光效”当作正式聚怪完成。
- 上一轮全量181项179通过、2项既有失败；已有工作区存在多项未提交修改，均需保留。

用户此前已经确定最终方向：被动位移内置UnitBase、默认开启、Inspector开关，不逐敌挂组件。本次建议将这项最终优化作为正式装配的前置，而不是先在EnemyBase挂临时组件、以后再迁一次。这个推进顺序已随本设计获用户确认。

## 2. 取舍与范围

推荐：先迁移通用被动位移，再上移Hero装配，最后主场景联合验证。
另一做法是先仅正式接入E/HUD、继续延后Q；它会产生“技能栏存在但Q不能拉”的半成品入口，不作为本次推荐。
不采用给每个正式敌人补外挂接收器的路径，因为它违背已确认的最终配置方式。

本轮不包含：
- 玩家新技能、新特效/动画、职业/技能获取或热插拔。
- 改变仇恨、受击锁、技能打断、AI射程、连携评分、专注或镜头规则。
- 解决正式房间导航未烘焙与Firebolt旧距离断言；如它们确实阻碍验收，单独报告，不默改。
- 阶段四P3显示问题及旧HUD低分辨率重叠；不会将其静默混入迁移。
- 向Scenes/TestScene.tscn添加或修改单位实例。
- Git提交/上传、覆盖用户未保存的编辑器资源。

## 3. UnitBase内置被动位移

### 3.1 配置入口

在UnitBase根Inspector新增一个职责分组和一个字段：
- Forced Movement / forced_movement_enabled：允许被动位移，默认true。

旁置简体中文说明，明确这是接收外力请求的许可，不控制自身移动或技能动画位移。
关闭时拒绝新请求，并立即结束当前外力请求、恢复本请求增加的单位碰撞例外；重新开启不恢复旧请求。
不暴露来源、计时、token、目的地、碰撞记录等内部状态。

### 3.2 外部接口

接口直接归UnitBase，不要求策划添加子节点，不由运行时偷偷补节点：
- request_forced_movement(source, destination, duration_seconds, ignore_unit_collisions=false) -> int
- is_forced_movement_active() -> bool
- get_forced_movement_token() -> int
- cancel_forced_movement(token) -> void
- forced_movement_started(token)、forced_movement_finished(token, reason)信号。

source须树内存活UnitBase；destination是有限世界坐标，仅水平XZ；持续时间是有限正的战斗秒。
正token表示受理，0拒绝；无效新请求不破坏有效旧请求。新有效请求替换旧请求，迟到取消/终态不能清除新的请求。
保留既有终态语义arrived/elapsed/blocked/replaced/cancelled/source_invalid/owner_invalid，新增disabled仅解释关闭开关。
外部接口不返回可写内部状态，不建立第二个移动计时器或配置资源。

运行状态、碰撞例外与生命周期代码从现接收器迁入UnitBase自身；不保留另一个必须装备的组件，也不建立第二套被动位移体系。
物理消费/结果回报使用有中文职责约束的继承层内部方法，具体命名在实施计划中固定。

### 3.3 谁负责真正移动

UnitBase保存唯一请求与碰撞管理；PlayerBase和AIUnitBase仍分别使用自己已有的物理循环。
保持一次水平速度选择、重力和唯一move_and_slide，不使用position瞬移，不借普通导航移动到目的地。

物理顺序：
1. 校验外力来源/接收者与许可；死亡清理。
2. 原受击水平停顿继续优先，停顿帧不积压外力进度。
3. 有有效外力时消费本帧delta，覆盖正常水平输出；无外力时完全沿用原移动。
4. 重力、世界碰撞和原朝向规则保留。
5. move_and_slide后用捕获的旧token回报；抵达/撞墙/到时立即收束，旧回调不能终止重入的新请求。

AI沿现有方式丢弃被覆盖的攻击推进、冲刺/导航水平意图，不新增技能打断或仇恨变化。
Player也丢弃被覆盖的水平推进/冲刺剩余，解除其关联瞬时移动状态，不中断已有技能动作、不改共享冷却。
新输入被禁用不等于免疫外力；外力仍走物理执行，暂停/5%慢放遵从同一物理delta，不另乘time_scale。
极简UnitBase只提供请求协议；需要实际运动的单位仍由既有Player/AI或未来明确的移动执行者消费，UnitBase不新增独立物理循环。

### 3.4 碰撞与回收

拉拽请求仍只临时忽略其他UnitBase身体，允许同一聚拢盘重叠；墙地、重力、layer/mask及技能命中Area保留。
仅恢复本请求自行增加的例外，不撤销其他系统的例外；单位动态生成/退树沿已有监听处理，不逐帧全树扫描。
抵达、撞墙、取消、关闭、死亡、来源失效、离树和重建均需回收；恢复例外先于终态信号。
来源与请求身份弱归属；离树过程中关闭受理，防止清理回调重入创建新的外力/碰撞例外。

## 4. Pull与测试内容的迁移

PullTargetSkillEffect改为查询目标UnitBase的内置许可并提交request_forced_movement，不再检查子节点名/个数，也不限定AI类型。
范围仍由Delivery、落点/持续时间仍由Pull Effect、表现仍读同一快照，全部保留当前参数。
不允许接收外力的单位只跳过Pull这一Effect；其他伤害/状态效果继续按各自适用性结算。
原地已在聚拢盘内仍是合法完成结果；不开启被动位移的单位不能因已经在盘内而误报应用。

PlayerSkillsTest移除四个临时接收器子节点；Unsupported保留对照用途，但改为根Inspector关闭forced_movement_enabled。
测试监听由接收器信号改到单位信号。原接收器契约中的碰撞、墙、暂停、慢放、重入和生命周期断言迁移保留；
“不支持非AI父节点”“重复接收器节点”等临时装配断言由“玩家可被动位移/开关拒绝”等最终契约替换，不删掉真实行为覆盖。

所有活动代码、场景、测试引用更新后，再移除旧ForcedMovementComponent.gd/.gd.uid/.tscn；删除前核查精确目标和全项目引用，不清理无关目录。
历史阶段文档保留为历史，当前指南标明最终入口；迁移完成不得留下“有组件才能工作”的活动依赖。

## 5. 正式Hero与HUD装配

Hero.tscn：
- 在已有SkillHost/SkillSocket中实例化GatherSkill和ThreatMarkSkill。
- regular_skills固定引用[Gather, ThreatMark]，不再创建另一个Host或执行管线。
- 挂已有PlayerSkillInputComponent和PlayerSkillController，沿InputMap的player_skill_1/Q、player_skill_2/E。
- 保留现有武器、攻击、生命、防御、移动、动画、相机和索敌配置。

CombatRoom.tscn：
- 原继承结构不变，只装PlayerSkillBar并将skill_source指向正式Hero/PlayerSkillController。
- 不复制测试世界、调试面板、模式切换、范围圈或Unsupported靶。
- 保留现有队伍、专注、评分、终结与镜头引用；不新增另一套协调器。

PlayerSkillsTest.tscn：
- 继承Hero上移后的装配，去除局部重复输入/控制器/技能节点与引用。
- 只保留测试CD=2秒的必要覆盖、测试地形、三模式、Q范围圈和观察器。
- 保留现有局部HUD布局；如重复来源引用可沿继承读取，不跨文件手工维护同一技能数值。

正式技能源冷却仍是Q10秒/E12秒；测试2秒只为调试，不把测试值写到正式Hero。
其他已验收范围/伤害/仇恨参数保持；实施前重新读取，若用户已调过，以当时配置为准。

## 6. 可验证的小批次

A. 内置位移：独立测试场景验证默认能力、开关、Player/AI唯一物理移动、碰撞/时间/生命周期；先不装正式Hero。
B. 正式装配：Hero源槽与输入、CombatRoom HUD、测试局部去重；验证单次输入只启动一次。
C. 联合验收：F6独立场景与F5正式场景，验证E引怪→Q聚拢→队伍输出→连携/终结、退出/重开。
每批先写真实行为失败测试再实现；如遇改变玩法的必要性，先说明，不以迁移掩盖额外规则。

## 7. 文件范围与验收门槛

预期修改：
UnitSystem/Base/00_UnitBase.gd、AIUnitBase.gd、UnitSystem/Player/PlayerBase.gd；
SkillSystem/03-Extensions/PullTargetSkillEffect.gd；
Hero.tscn、CombatRoom.tscn、PlayerSkillsTest.tscn/Harness及依赖旧接收器的测试；
当前使用指南/装配指南/玩家技能指南和阶段文档。

测试新增/迁移：
UnitForcedMovementTest（由旧接收器契约迁移）、PlayerSkillsCombatRoomAssemblyTest；
原PlayerSkillControl/Action/Bar/TestScene/CombinedFlow、Pull、Q/E表现、临时仇恨、原连携/终结测试继续回归。
最终全量允许仅原两项基线失败，无新增SCRIPT ERROR、泄漏、无效UID或残留暂停。
资源/场景原生保存，新增外部Resource若确有必要须有效UID与强类型Quick Load，本设计不新增正式.tres/.res。

实施计划需列出精确文件清单、继承场景操作顺序、每批RED/GREEN命令、引用迁移检查和本轮变更前快照；
只读独立review对比本轮基线，不把用户原未提交改动算成本轮实现。
完成后交付配置入口与F5/F6操作方式，等待用户验收，不自动Git操作。

## 8. 自查

- 原定“不逐单位挂组件”得以落实，UnitBase只增加一个策划开关。
- 请求与物理执行分离，仍只有原移动循环真正移动，不建立第二套驱动。
- 先处理正式Q的真实前置依赖，再装技能，不以光效/按键日志代替可用性。
- 测试CD与正式CD边界明确，场景去重后仍有独立回归入口。
- protected TestScene实例、不相关平衡与既有已知问题均未扩大到本次修改。
- 本文件及推进顺序已获确认；详见[阶段五实施计划](../Plans/2026-10-22-player-skills-stage-5-implementation-plan.md)，用户已批准实施；以阶段五validation记录实际交付与剩余事项。
