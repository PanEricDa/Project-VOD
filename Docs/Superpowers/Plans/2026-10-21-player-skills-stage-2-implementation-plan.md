# 玩家技能阶段二：Q 聚拢 Implementation Plan

> 2026-10-21用户已验收Q；以当前保存值为准：Delivery半径3.5米、圆心前移3米、拉动0.12秒、落点身前1.5米/散布0.6米、施法0.2秒；源冷却10秒、测试局部2秒。下文旧实施步骤的5米/2米/0.8米/0.35秒为历史记录，不据此回写当前资源。Q范围圈仍直接读取Delivery。阶段三细化计划另文保存，E尚未实施。

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans 按任务顺序执行；保持当前项目目录，只允许一个 Godot 编辑器写入方。用户确认本详细计划后才开始功能代码。

**Goal:** 在既有 PlayerSkillsTest 场景，把 Q 探针替换为真正的聚拢技能：释放时将附近敌人拉向玩家身前，遵守物理碰撞；E 保持探针。

**Architecture:** SkillBase 捕获释放快照，现有 Caster Radius Delivery 收集目标，通用 PullTargetSkillEffect 向目标的 ForcedMovementComponent 提交位移。AIUnitBase 在自己的物理循环消费请求；组件不直接移动单位，不新增技能执行体系或聚怪状态。

**Tech Stack:** Godot 4.7、GDScript、SkillBase/SkillContext、InstantTargetDeliveryConfig、CharacterBody3D、既有 AI 导航与动作管线、Godot MCP Pro。

**Spec:** [已确认的总体设计](../Specs/2026-10-21-player-gather-threat-skills-design.md)；[五阶段路线](2026-10-21-player-skills-staged-roadmap.md)；[阶段一实现与验证](2026-10-21-player-skills-stage-1-implementation-plan.md)。

状态：第二阶段已实现并完成自动验证、原生运行与独立review，用户已验收Q并允许推进；阶段三已另行细化计划，功能尚未实施。Q/E测试实例均保留2秒，不把调试值强加到正式内容基线。完整结果见[阶段二验证记录](2026-10-21-player-skills-stage-2-validation.md)。

## Global Constraints

- 优先 Godot MCP Pro 修改和原生保存；回退必须先说明工具不支持/不可用/失败的具体原因。
- 遵循 AGENTS.md：中文参数及接口说明、清晰目录与 Inspector、原生资源保存/UID/强类型索引验证。
- 不改 Scenes/TestScene.tscn 的单位，不给正式 Hero/EnemyBase/CombatRoom 装配本阶段组件。
- 不实现 E 临时仇恨、专注费用、连携评分、额外聚怪状态或仇恨层级；Q不直接打断技能，不修改怪物攻击距离。
- 不创建装备/拆卸事务，不做热换槽或专项压力测试；保留必要信号、身份隔离及正常死亡/离树清理。
- 不改旧未提交工作与 MCP 插件；不擅自提交 Git/上传 GitHub；阶段完成后停止等待体验验收。
- 本阶段不新做角色动画或专属特效，复用已验证的 Sword/basic_cast_1；后续表现阶段再补。
- 测试 Q/E 冷却都为2秒。Gather源技能保留已确认的10秒基线，测试场景局部覆盖；E暂用现有探针，未来正式12秒基线也不因本轮调试被改掉。

## Review Focus

1. 一帧内同一单位只有一次最终 move_and_slide，外力不能同时叠加导航、攻击位移或动画位移；Task1。
2. 最后一帧、墙体/身体阻挡及不同高度：不瞬移补偿、不穿墙、不直接改Y或停止重力；Task1/4。
3. 同步回调、请求替换、旧取消及来源失效：旧身份不能清理新请求；Task1。
4. 无接收器目标与可移动目标混合、逐Effect跳过、目标在回调中失效：只跳过不适用项，真实apply失败仍fail-fast；Task3。
5. 玩家释放后移动/转向、当前动作或同批其他Effect修改玩家位置：整批仍使用同一份已冻结中心和朝向；Task2/3/4。

## 1. 对照现状后的关键结论

- AIUnitBase 已统一处理 AI意图、受击移动锁、动画位移、普通位移、重力及碰撞。本次插入外力分支，不另建物理循环。
- SkillMotionComponent是施法者自身随动画运动；拉拽他人不借用其动画时间和Host动作身份。
- 现有瞬发范围交付已支持 World Scope，范围唯一参数仍为 Delivery.effect_radius，不另做场景搜索器。
- 当前 SkillDeliveryRunner 对任意Effect.apply=false终止整次交付；必须先增加默认兼容的适用性检查，不能把预期“不支持拉动”伪装为内部失败。
- 当前训练敌人 Process Mode=Disabled，必须改为继承处理，才能执行物理。静态训练用现有 detection_enabled=false + idle_behavior=STATIONARY，不通过停掉单位根节点保持静止。
- EnemyBase当前没有显式collision_mask，Godot默认只碰世界层，不能据此保证敌人相互挤靠。仅在新测试场景的训练实例设置World|Enemy（当前编号1|4=5）；正式敌人源场景不改。末阶段迁移时需带上通过验证的碰撞设置。
- 阶段一Harness硬依赖ProbeEffect，不能照搬到正式Q。改为订阅通用施法、交付和动作事实；不在Gather中保留假探针组件。

## 2. 交付与装配

新建生产能力：
- UnitSystem/Components/Movement/ForcedMovementComponent.gd
- UnitSystem/Components/Movement/ForcedMovementComponent.tscn
- SkillSystem/03-Extensions/PullTargetSkillEffect.gd
- SkillSystem/00-Skills/Player_Gather/GatherSkill.tscn

新建测试：
- UnitSystem/Tests/ForcedMovementComponentTest.gd
- SkillSystem/05-Tests/PullTargetSkillEffectTest.gd

新增合计4个.gd、2个.tscn、0个外部.tres；其中2个.gd为测试。Gather继承现有SkillBase.tscn，Delivery为技能场景内的强类型子资源，不为三个Effect参数再拆配置文件。

修改：
- UnitSystem/Base/AIUnitBase.gd：物理消费与取消旧水平意图。
- UnitSystem/Base/00_UnitBase.gd：稳定水平朝向查询。
- SkillSystem/01-Core/SkillContext.gd、SkillBase.gd：释放快照及复制。
- SkillSystem/03-Extensions/SkillEffectBase.gd、SkillSystem/02-Delivery/SkillDeliveryRunner.gd：Effect适用性。
- Scenes/Tests/PlayerSkills/PlayerSkillsTest.tscn、PlayerSkillsTestHarness.gd：Q替换、训练配置与通用计数。
- UnitSystem/Tests/PlayerSkillTestSceneTest.gd：更新Q装配和真实聚拢断言，保留E独立性。

明确不新增：PlayerGatherSkill专用根脚本、另一套Delivery、终结镜头资源、位移曲线.tres、技能副本池、聚怪标签或全局管理器。

## 3. Inspector 配置

GatherSkill根：
- Skill Id=player_gather；Display Name=Gather；弱化/干扰显示分类。
- Self关系启动，Controller仍明确传玩家自身；不依赖锁定敌人。
- Base Cast Time=0.2秒；允许移动与转向；Automatic Cast=false；技能源CD=10秒。
- Action Animation留空，沿用Sword/basic_cast_1。没有专属施法、释放、镜头资产也能生效。
- Delivery=InstantTarget / CASTER_RADIUS / WORLD_SCOPE；Hostile；当前Effect Radius=2米、Center Forward Offset M=0.8米（后续体验调参，非原5米玩家圆心）。
- 子节点PullTargetSkillEffect只暴露3个参数：front_distance_m=1.5米、gather_radius_m=0.6米、duration_seconds=0.35战斗秒。

目标根节点挂ForcedMovementComponent.tscn：零策划参数；来源、目标点、进度、token、碰撞结果都是内部运行时信息。
测试场景Hero/SkillHost/SkillSocket/Q改用GatherSkill，Regular Skills[0]引用新实例，CD局部覆盖2秒；E仍是ProbeE，CD2秒。

## 4. 释放快照与聚拢算法

UnitBase.get_facing_direction()->Vector3：
读取单位直接Visual节点的世界-Z轴，投影到XZ并归一化；不读CharacterRoot或WeaponSocket动画。缺少/退化Visual时回退单位根-Z，仍退化则Vector3.FORWARD。不新增朝向Inspector字段。

SkillContext增加两个内部字段：
- release_caster_position:Vector3=Vector3.INF：实际释放时施法者脚下世界位置。
- release_facing_direction:Vector3=Vector3.ZERO：本次稳定水平朝向。
duplicate_context复制两者；额外复制内部require_alive_on_delivery，用于瞬发检查保留技能require_alive=false的原有配置契约，不新增Inspector字段。SkillBase在真实交付前统一写入一次；每个新释放重新捕获，Effect不能每目标重读玩家当前位置。触发管线也采用本次释放快照；非UnitBase的Node3D施法者按其根朝向投影回退。

聚集中心 C = release_caster_position + release_facing_direction × front_distance_m。
- 批内每个目标用同一C；玩家之后移动、转向不改变该次落点。
- 默认在半径R=0.6的圆盘分配期望点，目标实例身份生成稳定u/v，r=R×sqrt(u)、angle=TAU×v。内部算法，不暴露seed、角度或逐怪槽位。
- 目标已在C的R范围内，作为合法无需移动的成功，不强迫其换位；R=0时用C。
- 只提交XZ水平位移，保持目标原有重力和地形碰撞；不做垂直吸附、跨层导航或悬崖保护的新规则。
- 0.6米是期望聚集区；按用户更新规则，Pull期间忽略单位身体碰撞，允许重叠抵达，墙体仍可能使其提前停下；结束后恢复碰撞，交回原AI/物理移动散开。
- 不改HP、仇恨表、锁定目标、射程或技能动作；也不保证墙后敌人会自动绕墙到达。

## 5. 通用强制位移接口与物理时序

ForcedMovementComponent：
- request_move(source:UnitBase,destination:Vector3,duration_seconds:float,ignore_unit_collisions:bool=false)->int：有限数据、正时长、有效存活来源/目标，返回正token；不支持的父节点或无效配置返回0，不扰动旧请求。当前消费端仅接AIUnitBase，不宣称已支持拉动玩家。
- is_active()->bool、get_active_token()->int：只读当前身份。
- validate_request()->void：AI每物理帧检查来源死亡/离树及目标有效性；不推进计时。
- consume_step(delta:float)->Vector3：返回本帧水平期望位移；只在选中外力分支时推进一次计时，不移动角色。
- report_motion_result(token:int,actual_displacement:Vector3,blocked:bool)->void：move_and_slide后回报；到期/阻挡收束，不补位置。
- cancel_move(token:int)->void：仅取消匹配身份，幂等；旧token不影响新请求。
- signal move_started(token:int)、move_finished(token:int,reason:StringName)：原因arrived/elapsed/blocked/replaced/cancelled/source_invalid/owner_invalid；通知前先提交本次终态，回调后不再清理另一项新请求。

ignore_unit_collisions默认false兼容通用位移；Pull固定传true，只针对UnitBase物理身体临时添加碰撞例外。不关闭碰撞形状、不改层/掩码、不忽略墙地或技能命中Area。启动时扫描一次，期间监听单位加入/移除；删除单位前清掉对应物理例外。所有终态先恢复本次新建例外再通知；替换及回调重入按原token隔离。此策略暂在验证版组件中实现，最终仍按总体设计5.1节迁入UnitBase。

内部只维护一个请求，后接受者替换前者。来源采用弱引用；不持有技能节点/旧Context。验证失败不先取消旧请求。参数不有限、delta≤0时不产生非法速度。

位移算法：从受理时目标位置线性推进到冻结目的地，时长0.35秒。consume_step返回下一期望点与当前实际位置的XZ差；最后一段可缩短，但不在结束后set_global_position。撞墙/身体阻挡立即结束，不在障碍消失后追补。

AIUnitBase顺序：
1. 死亡清理外力；重力和碰撞沿原路径。
2. 校验外力来源；受击移动锁仍沿既有逻辑冻结水平。该期间不消费外力时间，不积累待执行步长。
3. 正常运行_update_ai_movement和既有战斗逻辑；有外力时只覆盖本帧水平运动输出，不冻结整套AI/动画。
4. 外力优先于主动导航、攻击推进和自身动画位移；消费时取消旧水平推进意图，丢弃被覆盖的动画位移片段，终态片段正常清理，不积压成之后的突然位移。不要调用Host取消技能或播放动作。
5. 保留重力；唯一最终move_and_slide；用局部“本帧使用外力”标记回报原token，末帧即使组件随后结束也不走普通攻击/冲刺的位移扣账。
6. 外力结束清掉残余水平速度，下一物理帧由现有AI重新提交意图；不恢复已过期的旧位移片段。

无组件的单位完全沿原分支。暂停不推进；5%慢放通过现有physics delta自然变慢，不另乘时间倍率、不加第二个Timer。

## 6. Effect 适用性与既有行为兼容

SkillEffectBase.can_apply_to(context:SkillContext,result:SkillDeliveryResult,target:Node3D)->bool默认true。
- 逐Effect检查：一个不适用不阻止同目标的其他Effect。
- Pull仅对有唯一有效接收器的存活AI目标适用；无组件目标跳过，不为其添加失败仇恨或状态。
- apply=false仍为真实执行失败，保留instant_effect_failed及fail-fast；无效Effect节点也仍失败。
- 同步回调中目标离树/死亡，使用既有目标有效性要求安全跳过，不能访问失效实例或让后续合法目标丢失。
- 每目标至少一个Effect实际成功，才加入affected_targets一次；只有全部跳过的目标不虚报。
- affected_targets表示交付受理/效果请求成功，不表示已物理抵达。拉动后的实际位置由接收器报告及物理测试确认。
- 范围内没有合法Effect目标时，保留现有Runner拒绝交付的契约，不新设Gather空放例外；是否CD仍由SkillBase的现有失败规则处理。
- 当前选取使用释放快照：玩家身前0.8米为圆心、水平半径2米；保留现有0.05米边界容差，不新增高度阈值。通用5米测试保留为默认偏移0的兼容性测试。

本轮只接入瞬发Effect路径，不顺便重构投射物命中/区域伤害的执行器。

## 7. 同一测试场景的验证装配

仅局部修改新PlayerSkillsTest：
- 训练敌人Process Mode改INHERIT；detection_enabled=false、idle_behavior=STATIONARY；所有位移仍由生产AIUnitBase处理。
- 保留近战/远程训练实例，增加清晰的墙后、范围外、无接收器对照实例。都在本场景显式可见；不改受保护旧TestScene。
- Hero初始(0,0,4)时，可将近战(-2,0,1)、远程(-3,0,2)放开放侧；墙后(3.7,0,1.4)、范围外(-5.4,0,4)、无接收器(-1,0,0)。前四类可移动敌人挂接收器；无接收器对照不挂。
- 测试敌人mask=World|Enemy，保留原collision_layer；不把玩家也改成互撞，不全关Collider。Pull期间只临时忽略单位身体，允许重叠；结束恢复其原本碰撞关系。
- Harness使用SkillBase.cast_started、delivery_started/delivery_finished、动作lifecycle，去掉对每槽ProbeEffect节点的必需依赖。
- HUD把“Apply”明确改为“Release”，增加实际affected_targets数量；不把“请求了位移”显示为“全部抵达”。E真实ProbeEffect依旧由自动测试单独验证。
- 测试Reset沿既有reload_current_scene，不增加生产reset接口。不加正式玩家技能栏或复杂目标标识系统。

## 8. 分任务实施

### Task 1：接收器与唯一物理消费

**Files:** 新建ForcedMovementComponent.gd/.tscn、ForcedMovementComponentTest.gd；修改AIUnitBase.gd。
**Interfaces:** 实现第5节全部请求/回报协议；后续Effect只提交请求，不直接移动。

- [x] 写test_open_ground_motion：实际物理体在0.35战斗秒接近期望点，误差≤0.08米，不靠直接改position；运行RED确认缺功能。
- [x] 写test_wall_and_body_collision_no_catchup：墙前截断、多人不穿透；墙撤走后无追补。
- [x] 写test_replace_and_old_cancel_identity：无效新请求不影响旧请求，合法新请求替换旧者，旧取消及终态回调重入不删新请求。
- [x] 实现零export接收器与AI物理分支；同一分支一帧只执行一次move_and_slide，不叠加主动/动画水平步长。
- [x] 写test_pause_slow_time_hit_lock：暂停无推进，5%时间0.35战斗秒变慢但总路径不放大；受击锁不追补。
- [x] 写test_source_and_owner_lifecycle：死亡、离树、到期、场景退出清理，无释放技能节点强依赖。
- [x] GREEN：新测试及AIUnitBaseLocomotionMigrationTest、SkillMotionCollisionTest、SkillMotionIntegrationTest通过。

### Task 2：统一释放位置与朝向快照

**Files:** 修改00_UnitBase.gd、SkillContext.gd、SkillBase.gd；在PullTargetSkillEffectTest.gd先添加快照测试。
**Interfaces:** 提供get_facing_direction及两个release快照字段，duplicate_context保持一致；复用Task1。

- [x] RED：test_release_snapshot_ignores_weapon_animation，旋转CharacterRoot/WeaponSocket不会改变真实身前方向，转动Visual则会改变。
- [x] RED：test_release_snapshot_is_shared_and_frozen，交付通知中移动/转向施法者，各目标仍收到同一释放中心；Context副本保留两字段。
- [x] 实现统一捕获；角色动作与DIRECT_TRIGGER均在各自实际交付时捕获，不因复制上下文沿用上一发。
- [x] GREEN：快照断言、TriggeredSkillActivationTest、AIUnitSkillFacingTest、CasterFeetPresentationFacingTest通过。

### Task 3：适用性、聚拢Effect及技能内容

**Files:** 新建PullTargetSkillEffect.gd、GatherSkill.tscn；修改SkillEffectBase.gd、SkillDeliveryRunner.gd；补齐PullTargetSkillEffectTest.gd。
**Interfaces:** 消费Task1/2；提供通用can_apply_to，保留原apply错误契约。

- [x] RED：test_mixed_receivers_and_multiple_effects，缺组件只跳过Pull，另一个计数/伤害Effect仍能作用，其他合法目标不丢失；真正apply=false仍失败。
- [x] RED：test_radius_and_front_cluster，5米内有效、5.1米外无效，中心为身前1.5米，期望偏移≤0.6米；无关HP/仇恨不变。
- [x] RED：test_already_gathered_no_move与test_target_removed_during_delivery，已在聚集区不重新推挤，失效目标不产生崩溃或虚报。
- [x] 实现适用性及Effect；原生创建继承SkillBase的GatherSkill，用强类型Delivery子资源组装，不新增Delivery脚本或外部.tres。
- [x] GREEN：SingleSceneDeliveryRunnerTest、TriggeredSkillActivationTest及新Effect测试通过，旧默认Effect行为不变。

### Task 4：可玩场景与回归

**Files:** 修改PlayerSkillsTest.tscn、Harness.gd、PlayerSkillTestSceneTest.gd；更新本计划及路线状态。
**Interfaces:** 显式装配Task1–3，不伪造Gameplay；保留阶段一Q/E入口和2秒测试CD。

- [x] RED：场景契约改为Q=player_gather、E=player_probe_e，断言接收器、局部碰撞/训练配置及两槽2秒CD。
- [x] 原生装配实际Q与测试敌人；Harness移除ProbeEffect必需依赖，改通用交付事实及目标计数。
- [x] 实际InputMap施放Q，等待物理完成；开放目标向身前聚拢，墙后被挡、范围外/无组件不动；之后玩家移动不拖拽旧落点。
- [x] 验证E依旧只跑自身探针；两技能均可2秒后重复；Q/E不产生伤害、仇恨或专注/连携伤害事件。
- [x] 用独立测试夹具启用原敌方AI，确认外力结束后正常追击/攻击，无永久移动锁；不在正式房间装配。
- [x] 检查Output/Debugger、取消/死亡/重开、原动画位移兼容；跑新增测试、阶段一三项测试及完整回归。
- [x] 交付F6步骤、实际数据和review，记录既有失败，不修改旧参数掩盖；等待用户体验确认，不开始阶段三。

## 9. 运行命令与验收

项目根PowerShell：
```powershell
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' --headless --path 'G:\Godot\ProjectVOD' --script 'res://UnitSystem/Tests/ForcedMovementComponentTest.gd'
```
第二项替换为res://SkillSystem/05-Tests/PullTargetSkillEffectTest.gd，场景测试替换为res://UnitSystem/Tests/PlayerSkillTestSceneTest.gd。预期各TestName: PASS、退出码0、无新增SCRIPT ERROR/泄漏；必须先看到对应新功能RED再实施。

全量回归按项目全部非Archive/addons的SceneTree测试运行；RefCounted的RangedAttackPipelineTest另外调用collect_failures。阶段一已知Firebolt距离旧断言与正式房间导航失败继续单独报告，不更改其玩法数值消除。

F6最终可见成果：玩家按Q后，附近敌人真实滑向身前，受墙体约束但在拉拽期间允许单位身体重叠；移动或转向不拖着已释放的聚集区走；E仍为探针；2秒CD便于反复测试。允许忽略单位身体而重叠聚集，但不会无视墙体；不把仇恨接管混入本阶段。

## 10. 计划自检

已核对：唯一物理消费、释放快照、Effect默认兼容、训练模式、局部碰撞、Harness去探针耦合、2秒CD及回归均有任务。相比路线仅补足两项必要细节：释放中心快照与move_and_slide后的实际结果回报，不新增策划参数。无TODO/占位接口；实施范围仍限于第二阶段，不推进临时仇恨、专属特效或正式场景装配。
