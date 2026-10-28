# 玩家技能五阶段实施路线

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans or superpowers:subagent-driven-development to implement an approved stage plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. 本文是分阶段路线，禁止作为一次性大任务执行。

**Goal:** 在独立玩家测试场景中逐步验证Q聚拢、E临时仇恨的可用性、实际效果与玩法，保留开放接口和信号，全部通过后接入正式主场景。

**Architecture:** 输入、角色动作、SkillHost、Delivery/Effects、状态/仇恨、物理执行与HUD分工。第一阶段提供共同底座，第二/三阶段分别交付两个独立Gameplay能力，第四阶段联合玩法与反馈验证，第五阶段只做正式装配迁移。

**Tech Stack:** Godot 4.7、GDScript、InputMap、CharacterBody3D、NavigationAgent3D、SceneTree契约测试、Godot MCP Pro。

**Spec:** [玩家技能设计](../Specs/2026-10-21-player-gather-threat-skills-design.md)。

状态：2026-10-22更新；阶段1—3及Q/E特效已获用户验收。阶段四已实现两槽HUD、三模式完整队伍与暂停/终结输入隔离，完整181项179通过、2项既有失败；独立review无阻断问题、1项P3显示问题已记录；用户已同意继续阶段五准备。阶段五已实施UnitBase被动位移内置、Hero正式装配及CombatRoom HUD；联合验证和阶段末review见阶段五validation；Git操作另行授权。

## Global Constraints

- 遵循项目根AGENTS.md：优先Godot MCP Pro编辑，Inspector中文参数说明，人类可读可管理。
- 不向res://Scenes/TestScene.tscn自动添加或修改单位实例。
- 不覆盖未提交的既有工作，不为测试擅自更改已确认技能参数，不修改MCP插件。
- 正式外部资源必须Godot保存并验证有效UID与强类型Quick Load。
- 不新增仇恨权级、专用聚怪状态、自由地板选点、玩家技能专注费用或职业获取体系。
- 同一时间源只维护一份计时，同一数值只保留一个配置来源。
- 插拔仅保留开放接口、信号和依赖边界；不新增热装卸/换槽事务，不开展插拔组合及专项压力测试。
- 前四阶段不把新组件/技能装配到正式Hero/EnemyBase源场景；共享脚本的扩展必须无组件时兼容旧行为。
- 每阶段完成后停止，交付变更、验证结果、配置入口和已知问题；不自动进入下一阶段。
- Git提交和GitHub上传另行授权，不随阶段验收自动执行。

## Review Focus

1. 空槽、冷却或动作忙碌时输入：明确拒绝，不播放效果或重复释放；阶段1覆盖。
2. 旧动画marker或取消回调迟到：不能释放/终止另一项新动作；阶段1覆盖。
3. 多敌碰撞、墙体、不同高度与失效目标：不瞬移穿墙，不因一个不适用目标中止整群；阶段2覆盖。
4. 临时仇恨刷新、自然衰减、普通仇恨新增、到期与清表交错：只撤销对应贡献且状态一致；阶段3覆盖。
5. 测试装配提升到正式源场景：不得双重输入、重复技能/回调，暂停与终结窗口不穿透；阶段4与5覆盖。

## 依赖与推进规则

```text
阶段1：测试基座 + 玩家施法入口
  ├─ 阶段2：强制位移 + Q聚拢
  └─ 阶段3：临时仇恨 + E状态
           ↓
阶段4：界面 + 联合玩法与反馈
           ↓
阶段5：正式源场景装配 + CombatRoom验收
```

阶段2和3的Gameplay实现互不依赖，但为控制review范围顺序执行：先Q，后E。后续若某阶段返工，仅复查受影响接口及下游，不重写已经通过的独立能力。

## 阶段1：独立测试场景与玩家施法闭环

详细计划：[阶段一实施计划与细节设计](2026-10-21-player-skills-stage-1-implementation-plan.md)。2026-10-21阶段一已实现，新增三项测试通过；全量171/173通过，两项既有失败保留，详见实施计划。用户已确认推进阶段二；阶段一记录保留为历史基线。

**目标：** 玩家按Q/E能够通过正式SkillHost启动、释放、完成测试技能。先证明请求与动作链路，不实现聚拢和临时仇恨。

### 文件职责

创建：
- Scenes/Tests/PlayerSkills/PlayerSkillsTest.tscn：唯一人工验证场景，直接可F6。
- Scenes/Tests/PlayerSkills/PlayerSkillsTestHarness.gd：仅管理训练模式、重置和只读调试，不实现技能效果。
- Scenes/Tests/PlayerSkills/PlayerSkillProbe.tscn、PlayerSkillProbeEffect.gd：仅记录接受/释放/完成次数的测试技能，禁止装到正式角色。
- UnitSystem/Components/Combat/PlayerSkillInputComponent.gd/.tscn：InputMap动作映射到槽号。
- UnitSystem/Components/Combat/PlayerSkillController.gd/.tscn：Host与玩家动作适配。
- UnitSystem/Tests/PlayerSkillControlTest.gd、PlayerSkillTestSceneTest.gd。

扩展：
- SkillSystem/01-Core/SkillHostComponent.gd：优先复用已有槽位、注册/注销和动作通知；只为本次施法链补必要接口，不新增动态装备事务。
- SkillSystem/01-Core/SkillBase.gd：普通技能可选Animation资产，不借用终结镜头配置。
- UnitSystem/Components/Combat/PlayerAttackController.gd：外部技能动作协议，同一个AnimationPlayer动作互斥。
- UnitSystem/Player/PlayerBase.gd：已有输入许可/移动许可的最小接入，缺少组件保持原行为。
- project.godot的InputMap通过MCP配置player_skill_1=Q、player_skill_2=E，不直接写项目文件。
- 如需新动作资产：遵循Docs/AnimationWorkbenchWorkflow.md，细化阶段计划先核对已有Sword片段，不能把没有方法帧的动画当成合格动作。

### 阶段接口契约

- Input：slot_requested(slot_index:int)，索引0/1；不保存具体skill_id。
- Controller：request_slot(slot_index:int)->bool，true只代表受理，不代表已释放；bind_host(host:SkillHostComponent)->void、unbind_host()->void。
- Host：复用get_regular_skill(slot_index:int)->SkillBase、现有regular_skills配置、注册/注销及相关信号；本轮不实现set_regular_skill原子热换槽入口。
- 玩家动作侧提供request_external_action(effective_cast_time:float,target:UnitBase=null,action_payload:Dictionary={},request_id:int=0)->bool及匹配身份的release/finish/cancel事实；沿用Host.confirm_active_action_started、release_active_action、finish_active_action。
- 动作忙碌明确拒绝，不建立隐藏队列，不默改现有抢占策略。动画数据来自技能，标记仍为release_action与finish_action。

### 工作顺序

- [x] 先写失败测试：空槽不报错、一次输入只受理一次、冷却未好或动作忙碌正确拒绝；两个静态槽位指向不同实例。
- [x] 运行对应SceneTree脚本，确认失败源于接口缺失而非测试夹具错误。
- [x] 创建原生测试场景：Hero、平地、相机、HUD调试区、墙体、边界对照与训练敌人；导航烘焙并验证路径。允许在本新场景自动装配，不触碰旧TestScene。
- [x] 接通InputMap→Controller→Host→角色动作→释放帧→测试Effect→完成帧。Q/E两个槽使用不同实例，Inspector直接可见。
- [x] 验证动作身份、死亡、输入禁止、正常取消与旧marker防重入；被拒绝请求不进入冷却、不播放效果，不开展运行时卸载/重装专项。
- [x] 玩家槽/动作核心测试通过，并检查现有移动/攻击未受影响；接口依赖保持独立，但不做删除输入/HUD的专项验收。
- [x] 交付F6操作说明、真实信号计数/冷却记录和本阶段review，等待用户确认。

### 玩家能验证什么

按Q/E能看见对应槽的受理、动作开始、释放一次与冷却；冷却未好、空槽或动作忙碌时有明确拒绝。此时怪物不会被拉动，也不会改变仇恨；运行时换槽/装卸不属于验收内容。

**阶段门槛：** 两槽施放闭环、动作互斥、正常取消/死亡清理及导航可用；不能只凭一个log就认定动画/冷却流程完成，不以插拔专项作为门槛。

## 阶段2：通用强制位移与Q聚拢

详细计划：[阶段二实施计划与细节设计](2026-10-21-player-skills-stage-2-implementation-plan.md)。Q聚拢已完成实现、验证与review，用户已确认调试通过；测试Q/E冷却继续保留2秒局部覆盖。验证记录见[阶段二验收](2026-10-21-player-skills-stage-2-validation.md)。

**依赖：** 阶段1通过。E仍保留测试技能，不提前实现状态/仇恨改动。

创建：
- UnitSystem/Components/Movement/ForcedMovementComponent.gd/.tscn。
- SkillSystem/03-Extensions/PullTargetSkillEffect.gd。
- SkillSystem/00-Skills/Player_Gather/GatherSkill.tscn。
- SkillSystem/05-Tests/PullTargetSkillEffectTest.gd。
- UnitSystem/Tests/ForcedMovementComponentTest.gd。

扩展：
- UnitSystem/Base/AIUnitBase.gd：在已有物理循环消费位移，不新增第二次move_and_slide。
- UnitSystem/Base/00_UnitBase.gd：稳定水平朝向查询，不读武器动画朝向。
- SkillSystem/01-Core/SkillContext.gd、SkillBase.gd：本次释放的方向快照及复制，整批目标使用同一释放事实。
- SkillSystem/03-Extensions/SkillEffectBase.gd、02-Delivery/SkillDeliveryRunner.gd：默认兼容的逐Effect目标适用性检查。
- 新测试场景局部装配接收器与正式GatherSkill；正式EnemyBase和Hero源场景暂不挂组件。

### 阶段接口契约

- UnitBase.get_facing_direction()->Vector3：稳定、归一化的水平朝向；动画内武器旋转不改变其语义。
- SkillContext.release_facing_direction:Vector3：本次释放时冻结，默认零向量表示尚未捕获；SkillBase统一捕获，复制上下文不丢失。
- ForcedMovementComponent.request_move(source:UnitBase,destination:Vector3,duration_seconds:float)->int：返回正请求token，0为拒绝；只接受有限数据。consume_step(delta:float)->Vector3由单位物理循环消费；is_active()->bool；cancel_move(token:int)->void幂等且身份隔离。
- SkillEffectBase.can_apply_to(context:SkillContext,result:SkillDeliveryResult,target:Node3D)->bool：旧效果默认true；不适用只跳过当前Effect，不跳过同目标的其他适用Effect。apply=false仍为真正执行失败，不扩大吞错。
- PullTargetSkillEffect：front_distance_m=1.5、gather_radius_m=0.6、duration_seconds=0.35；收集范围只读Delivery.effect_radius=5。

### 工作顺序

- [x] 先写失败测试：5米内/外、身前方向、玩家释放后移动不拖着落点走、碰撞阻挡、不可位移目标与合法目标混合。
- [x] 运行RED后实现位移接收与物理消费，验证一个最终move_and_slide、世界暂停/慢放、正常结束/取消及死亡后清理，结束后恢复原AI。
- [x] 实现通用Effect及适用性过滤，验证被跳过目标不虚报affected_targets，旧瞬发效果仍保留fail-fast。
- [x] 配置GatherSkill：Self启动、World Scope、Hostile、5米、0.2秒施法、10秒冷却、无伤害、允许移动与转向。
- [x] 在同一测试场景替换Q探针；加入多人碰撞、墙体和重入位移验证。目标已在聚拢区是合法无须移动结果。
- [x] 运行位移/技能核心回归，检查自然结束、重复施放身份及来源失效清理；不测试动态卸下已释放技能。
- [x] 交付Q独立可玩成果、参数入口及review；用户确认后再进入阶段3。

### 玩家能验证什么

范围内近战和远程怪被拉向玩家释放时的身前区域；墙体仍阻挡，单位身体临时忽略、允许重叠，结束后恢复碰撞与原AI。当前用户基准：作用半径3.5米、圆心前移3米、拉动0.12秒、落点身前1.5米且散布半径0.6米。技能源冷却10秒，测试实例2秒；无须E即可验收Q。此前任务中的5米/0.35秒为历史实施记录，不回写当前参数。

## 阶段3：可撤销临时仇恨与E Debuff

详细计划：[阶段三实施计划与细节设计](2026-10-21-player-skills-stage-3-implementation-plan.md)。已实现临时账本、单一状态时钟、E正式技能与独立测试场景接续；验证见[阶段三验收](2026-10-21-player-skills-stage-3-validation.md)。用户已确认E及其头顶特效正常，现进入阶段四细化规划，不直接推进正式装配。

**依赖：** 阶段1；不依赖Q的位移算法。按既定顺序在阶段2验收后推进。

创建：
- SkillSystem/00-Skills/Player_ThreatMark/ThreatMarkSkill.tscn。
- SkillSystem/05-Tests/TemporaryThreatSkillEffectTest.gd。
- UnitSystem/Tests/TemporaryThreatLifecycleTest.gd。

扩展：
- SkillSystem/03-Extensions/ThreatChangeSkillEffect.gd：duration_seconds默认0；不新建玩家专属仇恨Effect。
- UnitSystem/Components/Threat/EnemyThreatComponent.gd：临时贡献账本、同一合计查询与衰减；不增加第二份Debuff计时器。
- UnitSystem/Components/Status/StatusEffectComponent.gd：带来源状态记录及撤销绑定；已有灼烧/属性修正兼容。
- UnitSystem/Components/UI/WorldHealthBar.gd：读取真实temporary_threat状态，显示有区别的小点；先不做复杂图标系统。
- 测试场景：E探针替换为正式技能，配置真实敌人和Guardian验证正常接续；正式源场景仍不装新玩家技能。

### 阶段接口契约

- ThreatChangeSkillEffect新增duration_seconds:float=0.0：0完全保持原普通加仇恨行为，正值绑定限时状态；threat_amount继续是唯一数值入口。
- EnemyThreatComponent.upsert_temporary_threat(source:UnitBase,effect_key:StringName,amount:float)->int：同来源/效果刷新一个正token，不叠加；remove_temporary_threat(token:int)->bool幂等撤销。
- StatusEffectComponent.apply_bound_status(status_id:StringName,source:UnitBase,effect_key:StringName,duration_seconds:float,on_removed:Callable)->bool：状态容器独占持续时间；来源弱归属，撤销回调不得依赖技能节点存活。细化计划需锁定刷新/失败事务顺序。
- 原has_named_status、get_active_status_ids和状态变化信号聚合新旧记录；同名多来源只有最后一笔结束才变为无该状态。
- get_threat_for/get_threat_snapshot/比例/resolve_target的语义一致：正常池+全部有效临时贡献；普通Guardian duration=0、400点不变。

### 工作顺序

- [x] 先写失败测试：普通100+临时2000=2100，存续时新增普通50，到期后只留下正常池按自身衰减后的值，而非总池硬减2000。
- [x] 实现临时贡献及既有衰减共用，默认duration=0仍运行原Guardian契约。
- [x] 补状态容器带来源记录与单一到期撤销，验证重复施放刷新、普通仇恨保留、到期撤销、来源失效及敌人死亡/归位清理；多来源覆盖基本数据正确性，不扩展驱散玩法或组件装卸专项。
- [x] 实现ThreatChangeSkillEffect可选限时分支，测试状态创建失败时不残留贡献、不破坏旧记录。
- [x] 配置ThreatMarkSkill：Self启动、World Scope、Hostile、5米、0.15秒施法、12秒冷却、2000点、8秒、无伤害、允许移动与转向。
- [x] 在同一测试场景启用真实仇恨/AI：验证E起效后玩家通过正常仇恨选敌被追击，8秒后正常池接续；不强制指定Guardian，也不缩短远程怪原射程。
- [x] 对比仇恨调试、头顶状态与后台数值，交付数据记录、review并等待确认。

### 玩家能验证什么

E范围内敌人出现状态点并提高对玩家仇恨，近战会按原逻辑追击、远程仍遵守原射程。到期状态点消失，撤回临时贡献，Guardian按其真实仇恨竞争接怪。可以先不使用Q独立验证E。

## 阶段4：技能栏、组合玩法与表现反馈

详细设计/计划：[阶段四实施计划](2026-10-22-player-skills-stage-4-implementation-plan.md)，已获用户确认并实施；证据见[阶段四验收](2026-10-22-player-skills-stage-4-validation.md)。Q/E特效部分已完成，见GatherSkillEffectsGuide与ThreatMarkSkillEffectsGuide；不得重做已验收内容。

**依赖：** 阶段1—3均通过。两个技能在同一测试场景已经独立可用，本阶段不新增战斗机制。

创建：
- UnitSystem/Components/UI/PlayerSkillBar.gd/.tscn。
- UnitSystem/Tests/PlayerSkillCombinedFlowTest.gd。
- SkillSystem/04-Docs/PlayerSkillsConfigurationGuide.md。
- Effects/Skills/Gather/及Effects/Skills/ThreatMark/下独立释放场景和对应*EffectPreview.tscn；必要共用播放器沿用既有Effects/Combat，具体美术仅做清晰的验证级表现。
扩展测试场景/Harness：HUD、重置、组合案例；按需局部装配已有伙伴连携/终结组件，不改其系统。

### 阶段接口契约

- 阶段四接口细化：PlayerSkillBar.bind_source(source:PlayerSkillController)->void、unbind_source()->void、refresh_immediately()->void；Inspector只有一个Controller来源。Controller.get_slot_status(slot_index:int)->Dictionary只读Host槽/冷却及现有动作/输入许可，UI消费其状态与受理/拒绝信号，不另配Host/Input/两个技能。初稿bind_host为尚未实施的UI草案，现由统一来源接口取代；Controller已有bind_host保持不变。
- 未来UI按钮/手柄可以复用阶段1 Controller.request_slot，不另建释放管线；本轮只落实Q/E，不提前新增其他输入方式。
- 表现资源只配置在技能根节点；范围圈读取同一个Delivery半径，无资源时Gameplay保持有效。
- 测试重置仅重建本测试世界或通过正式清理入口操作，不把测试专用reset加到生产类。

### 工作顺序

- [x] 先写核心联合测试：静态Q/E各使用正确技能，图标/名称和冷却一致，普通伤害/仇恨/连携评分不被这两个无伤害技能污染。
- [x] 制作两槽技能栏：Q/E、技能名称/图标占位、冷却与不可用状态；不添加技能选择层级。
- [x] Q/E已加入可辨识表现与独立预览，并通过用户验收；后续不重做。技能动作如需调整须走Workbench，正式外部Animation资源需原生保存/UID验证。
- [x] 运行E拉怪→Q整理→队伍普通战斗/连携的真实流程，确认效果独立、原锁定/仇恨/连携评分不串线。
- [x] 验证暂停、输入禁用、终结选择窗口不穿透Q/E，继续沿用现有游戏输入许可。
- [x] 在实际游玩中验证反复使用Q/E、冷却到期再次施放、正常死亡/重开和退出无残留状态；记录核心结果，不安排50次重载或插拔专项压力测试。
- [x] 完成独立review并交付实现/验证记录；无阻断问题，一项轻微显示问题暂缓。
- [x] 用户同意继续后续工作；正式装配按阶段五书面设计与实施计划门槛推进。

### 玩家能验证什么

看到Q/E技能栏和冷却，可以实际组合拉怪、聚拢与队伍输出，判断玩法是否有效、顺手。正常施放/到期/死亡与重开不残留光效、永久仇恨或移动锁。输入和HUD仍保留开放接口，但不要求现场拆卸验证。

## 阶段5：正式源场景与主场景接入

2026-10-22实施前核对（历史）：正式敌人当时尚无临时接收器，直接挂Q不能实现拉拽。建议将此前确认的UnitBase被动位移内置作为正式装配前置；书面设计见[阶段五接入设计](../Specs/2026-10-22-player-skills-production-integration-design.md)，该设计和推进顺序已获用户确认；[详细实施计划](2026-10-22-player-skills-stage-5-implementation-plan.md)已获用户批准并执行；UnitBase迁移、正式装配及联合流程已落实，结果见[阶段五验证记录](2026-10-22-player-skills-stage-5-validation.md)。

**依赖：** 阶段4通过且用户明确确认接入主场景。只迁移已验证的装配，不继续顺手加功能或调数值。

修改：
- UnitSystem/Player/Hero/Hero.tscn：显式装配输入/Controller、SkillSocket两个正式技能、Regular Skills引用。
- 被动位移最终方案已更新：最后统一优化时内置UnitBase，并通过Inspector开关控制，不再以EnemyBase外挂ForcedMovementComponent作为最终装配。已于阶段五完成，见总体设计5.1节。
- Scenes/CombatRoom.tscn：场景HUD挂PlayerSkillBar并绑定正式Hero，不更换场景主体。
- Scenes/Tests/PlayerSkills/PlayerSkillsTest.tscn：移除已上移到源场景的重复组件/技能覆盖，继续继承正式装配；保留测试地形/训练模式/调试。
- UnitSystem/Tests/PlayerSkillsCombatRoomAssemblyTest.gd：正式装配契约。
- Docs/CurrentSystemUserGuide.md、SkillSystem/04-Docs/CombatRoomAssemblyGuide.md、PlayerSkillsConfigurationGuide.md：同步最终配置入口。

### 工作顺序

- [x] 先记录当前主场景单位/装备/数值/相机/输入绑定及未提交差异，测试场景案例全部保持可复验。
- [x] 写失败测试：正式Hero两个槽、敌人位移接收、HUD绑定、单次输入只施放一次。
- [x] 仅把通过验收的装配接入源场景；主场景沿原继承结构保存，不改TestScene单位、不复制整个测试场景。
- [x] 清掉测试局部重复装配，验证测试场景与主场景均只有一套输入、控制器、Skill实例和信号连接。
- [x] F6测试场景与F5正式启动双向验收；验证普通AI、聚怪接续、Guardian嘲讽、连携/终结演出、相机与场景退出。
- [x] 跑全套契约/回归，新增失败逐项定位；已知基线失败单独列明，不通过擅改参数消除。
- [x] 交付最终变更清单、Inspector操作说明、测试结果和review。
- [ ] 用户体验验收待确认；用户另行要求时才Git提交与上传。

### 玩家能验证什么

正式启动直接获得Q/E，并与完整队伍战斗、连携和终结演出共存。独立测试场景仍可F6复现全部案例，没有把调试面板或探针技能带进主场景。

## 最终统一优化（阶段五已实施）

- [x] 将被动位移请求、状态与生命周期从临时ForcedMovementComponent迁入UnitBase，默认具备能力，Inspector开关默认开启。
- [x] 在PlayerBase和AIUnitBase已有物理循环统一接入；技能Effect改调单位接口，保留唯一物理移动，不转成普通AI导航。
- [x] 迁移时清理临时组件装配与引用，同步对应文档和测试；本次已按确认计划完成。

## 统一验证方式

执行SceneTree测试的命令模板（PowerShell；执行前确认本机Godot路径仍有效）：

```powershell
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' --headless --path G:/Godot/ProjectVOD --script res://UnitSystem/Tests/PlayerSkillControlTest.gd
```

按阶段替换为该阶段Test.gd，预期退出码0和对应PASS；同时检查SCRIPT ERROR、ObjectDB泄漏及resources still in use。每个阶段做实际原生运行检查，不把只加载成功当作可玩验证。

人工统一入口：Scenes/Tests/PlayerSkills/PlayerSkillsTest.tscn，F6；最终正式入口：Scenes/CombatRoom.tscn，F5。

## 阶段交付模板与授权

每阶段提供：本阶段实际文件、配置入口、运行操作、核心行为断言与玩法实测结果、失败分类、review结论、剩余事项。阶段验收记录保存为Docs/Superpowers/Plans/2026-10-21-player-skills-stage-N-validation.md。

阶段一开始前先输出其细化设计/实施计划，建议沿用当前会话本人执行、独立review的方式。用户确认前不创建测试场景、不写生产代码；用户只批准某阶段不代表批准剩余阶段全部连做。
