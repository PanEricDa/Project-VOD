# 玩家技能阶段二验证记录

日期：2026-10-21。范围：Q聚拢、通用外力位移及独立测试场景；E仍是探针。实施、最终完整回归及独立review已完成，等待用户体验验收，未推进第三阶段。

## 1. 实际交付与配置入口

新增4个.gd、2个.tscn（另有Godot生成的.gd.uid），无外部.tres/.res：

- UnitSystem/Components/Movement/ForcedMovementComponent.gd/.tscn：零export的接收器，明确挂在AI单位根下，名称保持ForcedMovementComponent。
- SkillSystem/03-Extensions/PullTargetSkillEffect.gd：通用Effect，只有身前距离1.5米、期望聚集半径0.6米、持续0.35战斗秒三个Inspector参数。
- SkillSystem/00-Skills/Player_Gather/GatherSkill.tscn：原生继承SkillBase.tscn，Self启动；Delivery为场景内InstantTarget / CASTER_RADIUS / WORLD_SCOPE / HOSTILE；Effect Radius=5米。
- UnitSystem/Tests/ForcedMovementComponentTest.gd：物理、碰撞、时钟、生命周期和身份测试。
- SkillSystem/05-Tests/PullTargetSkillEffectTest.gd：快照、适用性、混合目标及技能内容测试。

Gather根配置：0.2秒施法，允许移动/转向，不自动施放，源冷却10秒；Action Animation为空，沿用Sword/basic_cast_1。PlayerSkillsTest中Q/E实例各覆盖为2秒，便于重复测试。E继续使用PlayerSkillProbe及已有Animation资源，不实现临时仇恨。

未新增专用PlayerGather根脚本、Delivery类别、聚怪状态、仇恨规则、动画、特效或全局管理器。UI观察器改为订阅通用施法/交付/动作事实，不再要求每个技能都有ProbeEffect。

## 2. 执行链路和边界

Q输入 -> PlayerSkillController -> SkillHost -> SkillBase动作/释放 -> 冻结释放位置与稳定Visual朝向 -> 现有Delivery收集 -> PullTargetSkillEffect -> 目标ForcedMovementComponent -> AIUnitBase唯一物理移动。
- 不直接写角色位置或Y，不补偿穿墙，不停掉整套AI/动画。外力覆盖水平导航、攻击、冲刺与自身动画位移的旧推进。
- 世界暂停不推进；5%慢放只用物理delta，不二次乘倍率；受击移动锁期间不消费外力时间。
- 后接受请求替换旧请求；取消/回报按token隔离；终态先清理再发信号，回调中产生的新请求不会被旧清理删除。
- 玩家释放后移动/转身不改变整批落点。
- 缺接收器只跳过当前Pull，不影响同目标其他Effect；零个适用Effect在宣布交付接受前拒绝。真实apply=false仍按instant_effect_failed失败。
- affected_targets表示至少一个Effect成功/请求被接受，不代表物理抵达。接受后目标死亡/离树/释放，安全跳过；SINGLE明确允许尸体的技能保留require_alive=false契约。
- 当前Pull临时忽略单位身体碰撞，允许重叠进入0.6米期望圆盘；世界墙体仍可截断。结束后恢复碰撞，交回原有AI/物理移动，不另行推开或瞬移。

## 3. RED -> GREEN与核心覆盖

1. 接收器不存在时ForcedMovementComponentTest明确RED；实现后实际物理体0.35秒移动3米，误差小于0.08米，停止后无残余水平速度。
2. 墙体/单位身体截断，障碍移除无追补；来源死亡/离树、目标死亡/离树正常结束。
3. 无效新请求保留旧请求；合法替换、旧取消、终态回调重入及替换通知重入均不删除新请求。
4. 暂停无推进、5%时间只推进对应距离、受击锁解开不积压跳步；被覆盖动画/冲刺步长不在结束后恢复。
5. 从Y=4米拉向目标Y=99米时，只执行XZ；重力仍使目标下降，不发生垂直吸附或终态Y修正。
6. 快照接口缺失、复制丢字段、逐目标重读位置在RED中被捕获；实现后CharacterRoot/WeaponSocket姿态旋转不改变聚拢方向，Visual转向才改变方向。
7. 普通角色动作在真实释放帧捕获位置；DIRECT_TRIGGER每次重新捕获；交付回调移动/转向施法者不改同批落点。
8. RED复现交付通知删除首目标后的失效访问；修复后后续目标仍执行。公开release_started通知删除施法者或取消并重入新动作，也由独立RED/GREEN验证。
9. 5米范围混合接收器、5.1米外对照、已在圆盘内无需移动、无伤害/无专注事件；空范围/全不适用拒绝不启动成功冷却。
10. PlayerSkillTestSceneTest先因Q仍为探针RED；原生组装后，真实InputMap输入Q/E、两槽独立2秒冷却、重复Q、局部训练配置、未装正式Hero、AI重新启用后恢复攻击均通过。

## 4. 初版原生运行数据（单位互撞旧规则，保留作历史）

通过Godot MCP Pro启动场景，以simulate_action输入Q/E和移动，不直接调用Effect或位移接收器：

- 初始Hero=(0,0,4)，释放朝向=(0,0,-1)，冻结聚集中心=(0,0,2.5)。
- Q受理/开始/释放/完成均1次，取消0次，受影响3个目标。
- TrainingMelee：(-2,0,1) -> (0.200243,0.000986,2.397933)。
- TrainingRanged：(-3,0,2) -> (-0.032824,0.000986,3.073666)。两者最终相互碰撞停止，未穿透。
- WallBlocked：(3.7,0,1.4) -> (2.851473,0.000872,1.729023)，没有穿过墙体。
- OutsideRadius=(-5.4,0,4)、Unsupported=(-1,0,0)均不动。
- E受理/开始/释放/完成均1次，受影响1（自身探针）。
- 所有生命值不变，仇恨快照仍为空，damage_resolved总计0次。
- 玩家通过真实右移输入到(6.093338,0.000871,4)后，前述敌人位置不变，不持续拖拽。
- 最终新运行会话Q/E各受理、开始、释放、完成1次；点击Reset Test Scene后计数和冷却归零，近战恢复(-2,0,1)。重置后Debugger/error查询仍为0。调试工具执行中发生的脚本类型尚未导入/临时脚本推断错误已修正，不修改MCP插件。

实际圆盘采样依实例身份，位置可略有差异；多个实体汇聚可能比此轮数据更早互相挡住，不能以全部进入0.6米作为多人碰撞验收。

## 5. Review与资源

独立只读review核对阶段二基线到当前差异，不把旧未提交工作计入本轮。两项Important已通过新增失败测试确认并修正：

- 全部Effect不适用时需拒绝，不伪报成功/冷却。
- 通用生命周期检查必须保留显式尸体技能的合法性。
Minor提出不同高度/重力覆盖，已补真实物理测试。最终只读复核确认两项Important均关闭，无剩余Important/Critical。Reviewer做源码复核，实际Godot测试由主执行者运行。

两个新场景由Godot原生保存并验证UID有效：

- ForcedMovementComponent.tscn：8227926744958048061。
- GatherSkill.tscn：6349462069037904036；重新加载验证保留SkillBase继承链。
本阶段无新增强类型外部Resource资产，不产生额外Quick Load配置负担；原探针Animation的有效UID断言继续保留。

## 6. 全量回归

最终完整复测与此前一轮结果一致：175项SceneTree测试，173通过、2项既有失败（没有新增失败）：

- UnitSystem/Tests/CameraFollowControllerTest.gd：旧房间NavigationMesh未烘焙。
- SkillSystem/05-Tests/SingleSceneFireboltTest.gd：旧测试要求6米，用户现有技能配置5米。
RefCounted的RangedAttackPipelineTest另行调用collect_failures，返回空数组。
没有擅改这些旧场景/玩法参数来消除失败。全量结束后补强E重复输入断言，并重跑本阶段两项测试及阶段一三项核心测试；测试逻辑补强未改变生产实现。本轮修改文件的git diff --check通过，未清理既有MCP插件文件的旧格式差异。

## 7. F6验收步骤与停止点

1. 打开Scenes/Tests/PlayerSkills/PlayerSkillsTest.tscn，F6；当前仅显示青蓝色GatherRangeDebug，读取Q的Delivery：半径2米、沿玩家稳定朝向前移0.8米；随移动/转向实时更新。E范围预览关闭，E仍是探针。
2. 原地按Q：左侧近战/远程向玩家身前汇聚，墙右目标被挡，最左范围外与无接收器对照不动。读取Release与Affected，不把Affected理解为到达数。
3. 移动或转身后再按Q；每次使用新释放位置，上一发落点不跟随玩家。2秒后可再次释放。
4. 按E仍只验证探针动作/冷却，不会让怪追玩家；Reset Test Scene重置各对照。
5. 本轮没有正式技能栏/专属特效，也没有把组件/技能装入正式Hero、EnemyBase、CombatRoom；Scenes/TestScene.tscn单位未改动。

等待用户体验确认；下一阶段才细化与实现E临时仇恨。没有Git提交/上传。

## 后续调试显示与拉拽诊断

- 按用户要求，将原固定出生点参考圈改为ThreatRangeDebug橙圈，跟随Hero脚下，半径读E的InstantTargetDeliveryConfig.effect_radius。无新增脚本、资源文件或Inspector参数；E仍保持SINGLE探针，不实现阶段三。
- 新增场景行为断言：玩家移动时圈跟随，E范围临时改为3米时圈半径同步变为3米，随后恢复；测试确认预览不改变E的交付类型。
- 使用systematic-debugging定位：运行中所有训练敌人NavigationAgent3D.avoidance_enabled=false，索敌关闭；外力分支覆盖主动导航水平输出，因此不是导航避障的速度混合。
- 本次实测：TrainingRanged期望落点(-0.370512,0,2.772208)，实际停在(-1.255668,0.000667,2.522485)，约232ms触碰TrainingMelee后blocked；TrainingMelee约349ms抵达(0.032487,0.000871,2.689065)；墙后目标约82ms碰墙后blocked。
- 根因是AIUnitBase将is_on_wall()直接回报为blocked，ForcedMovementComponent收到后立即终止，不区分墙体与单位侧碰，也不等待通路重新开放。0.6米圆盘内按实例身份稳定散布落点，则是视觉随机性的另一来源。同实例同中心偏移相同，重开后身份变化可产生不同偏移。
- 本次仅新增范围显示并诊断，没有改变落点采样、物理碰撞或受阻结束规则。修改遵循MCP优先；新增显示测试由RED转GREEN，原生运行Debugger错误0。本轮完整回归175项：173通过，CameraFollowControllerTest旧导航未烘焙、SingleSceneFireboltTest旧6米断言两项既有失败不变，无新增失败；RefCounted攻击管线检查返回空失败列表。

## 用户更新：拉拽期间允许单位重叠

- 已实现：request_move新增运行时参数ignore_unit_collisions=false；Pull固定请求true，不新增Inspector参数、不新建文件、不改变圆盘半径或落点算法。UnitBase内置迁移继续留到最终优化。
- 仅对同一物理世界的UnitBase身体临时添加碰撞例外；不改碰撞层/掩码、Collider、技能命中Area，也不忽略静态墙地。通用默认请求仍保持原身体阻挡行为。
- 受理时扫描一次，监听新单位/单位离树，不逐帧扫描整棵树。弱引用登记自身新增例外，保留已有例外。所有终态先恢复碰撞后通知；被忽略单位删除前移除对应RID，修复测试中发现的Jolt空body日志。
- RED/GREEN：先验证缺少请求选项导致失败；实现后真实物理测试确认可抵达已被单位占用的位置，途中刷出的单位也不阻挡。另补中途删除单位的RED，清理离树例外后GREEN；抵达、手动取消、替换、来源死亡/离树、目标死亡/离树、重入回调均验证恢复。
- 测试场景Q实际调用也验证两个开放目标终态为arrived，落点均在0.6米圆盘内，所有临时碰撞例外清空；墙后目标仍blocked；启用正常敌方AI后继续追击/攻击。
- 原生运行：TrainingMelee抵达(0.032487,0.000871,2.689065)，TrainingRanged抵达(-0.370512,0.000871,2.772208)，两者中心相距约0.41米，小于0.7米身体直径，证明允许重叠；后续原有物理恢复分离至(0.279282,0.000983,2.638149)和(-0.617307,0.000983,2.823124)。没有额外散开算法。
- WallBlocked仍在墙前(2.850913,0.000679,1.729611)终止；范围外/无接收器对照不动。所有单位最终collision_mask仍5、碰撞例外数0、生命不变。原生Debugger错误0。
- 首轮全量175项中173通过、两项既有失败不变。独立review额外指出“接收器离树终态回调重入”可重建碰撞例外，已用独立RED测试复现；修复为离树通知前关闭请求入口，重新入树才开启。修复后核心三项测试通过，独立review复核已关闭Important，无剩余Important/Critical；最终完整回归175项中173通过，仅CameraFollowControllerTest旧导航未烘焙、SingleSceneFireboltTest旧6米断言两项既有失败，无新增失败；RefCounted攻击管线失败列表为空。E仍为探针，正式源场景及受保护TestScene未装配，未做Git提交。


## 2026-10-21 拉拽选取范围前移与缩小

- 用户要求：Q选取圆心在释放瞬间玩家身前0.8米，水平半径2米；不修改聚集落点（身前1.5米、0.6米圆盘）与用户当前位移时长0.2秒。上文5米Q配置/旧运行数据为历史记录；E橙色调试圈仍为5米预览。
- 在现有InstantTargetDeliveryConfig新增center_forward_offset_m，默认0保留其他技能配置；复用Runner的候选/关系/存活筛选，沿稳定水平朝向偏移，优先释放快照。保留原0.05米范围边界容差。
- 正式GatherSkill.tscn经Godot原生保存；Inspector配置入口：根节点Delivery > Effect Radius=2、Center Forward Offset M=0.8。无新增资源文件、接收器或专用Delivery。
- RED：新增真实交付测试先因偏移未实现/旧配置出现5项预期失败；GREEN：PullTargetSkillEffectTest和PlayerSkillTestSceneTest通过，无引擎错误。验证前方2.7米目标被选中、后方1.5米排除、圆心随朝向转动、施法者移动不污染快照、零偏移兼容和正式Gather配置。
- 独立测试场景单位摆放不变；集成测试只在运行实例中将玩家移到(-1,0,2.8)靠近现有训练靶，验证两只可拉目标和范围外对照。墙体碰撞测试仍由通用位移测试覆盖。
- 最终全量回归：175个SceneTree测试，173通过、2个既有失败，无新增失败：CameraFollowControllerTest（正式房间导航未烘焙）；SingleSceneFireboltTest（旧测试期望6米、现有技能5米）。本次不修改这些既有内容。编辑器原生读取半径2、偏移0.8，配置校验issues=[]；未执行Git提交或上传。


## 2026-10-21 仅显示Q拉拽作用范围

- 依据用户补充要求，复用原示意圈并重命名为GatherRangeDebug，关闭E范围预览；没有增加第二个圈或额外配置资源。E技能行为不变。
- 圈为青蓝色，初始位置(0,0.025,3.2)、半径2米；测试观察器逐帧读取Q Delivery.effect_radius和center_forward_offset_m，使用UnitBase.get_facing_direction，不受武器动作旋转影响，不修改实际技能效果。
- RED：PlayerSkillTestSceneTest先报告E圈未关闭、Q圈不存在；GREEN：完整输入/动作/聚拢集成测试通过。额外验证初始2米/0.8米、移动/转向、Q半径与偏移动态变更、E参数不干扰Q，以及无效半径隐藏。
- 原生运行截图确认画面只显示一个青蓝圈；数据读取visible=true、radius约2、center=(0,0.025,3.2)、forward_offset=0.8、e_circle_exists=false。单位摆放未改动；仅专用测试场景/观察器/测试与此记录变更。
- 本轮全量回归175项：173通过，仍只有CameraFollowControllerTest（正式房间导航未烘焙）与SingleSceneFireboltTest（旧测试6米、现配置5米）两项既有失败，无新增失败；未提交Git或上传。


## 2026-10-21 用户验收与当前参数基准

- 用户确认Q调试通过，要求后续以其配置为基准。Godot原生读取Gather源场景：effect_radius=3.5、center_forward_offset_m=3、duration_seconds=0.12、front_distance_m=1.5、gather_radius_m=0.6、base_cast_time=0.2、skill_cooldown=10；测试实例局部冷却2秒。没有重写任何Q技能参数。
- 旧圈测试固定断言2米/0.8米，当前数据下先明确出现两项失败；仅更新该测试读取当前保存值，保留独立半径3米/偏移1.2米/转向的行为断言。PlayerSkillTestSceneTest和PullTargetSkillEffectTest均PASS。
- 阶段二体验已验收；阶段三细化计划已编写，E Gameplay尚未实现；后续仍只显示Q示意圈。
- 本轮全量基线回归175项，173通过，仍只有CameraFollowControllerTest（正式房间导航未烘焙）与SingleSceneFireboltTest（旧断言6米/现配置5米）两项既有失败。没有新增失败，没有Git提交/上传。
