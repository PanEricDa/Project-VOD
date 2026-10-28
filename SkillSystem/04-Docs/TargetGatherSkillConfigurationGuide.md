# 目标聚拢：配置、组装与验证

日期：2026-10-23。用户已确认新增独立技能，保留旧身前聚拢并只从玩家卸下。未Git提交/推送。

## 1. 文件与组装

新技能：`res://SkillSystem/00-Skills/Player_TargetGather/TargetGatherSkill.tscn`，继承SkillBase.tscn。
新预览：`res://Effects/Skills/TargetGather/TargetGatherEffectPreview.tscn`，复用通用GatherEffectPreview脚本，Skill Scene选择新技能。

旧技能：Player_Gather/GatherSkill.tscn，源文件保持不变，旧GatherEffectPreview.tscn继续可用。没有为新技能增加专有.gd执行类。

实际职责：
- SkillBase根：目标资格、施法距离、动作、冷却、释放复核与统一表现。
- Delivery属性内嵌InstantTargetDeliveryConfig：仅决定效果目标集合；TARGET_RADIUS以技能目标位置为中心，WORLD_SCOPE从本次世界收集单位。
- PullTargetSkillEffect子节点：仅决定拉向哪里、聚拢盘大小和持续时间，通过UnitBase接口提交被动位移。
- UnitBase：被动位移物理/碰撞/回收，原墙地与根许可开关保持。
- RuntimeEffects/独立效果资产：仅消费释放快照，不选敌、不移动单位、不读取其他技能实例。范围世界圆心与拉拽目标位置分别冻结，支持TARGET_RADIUS+CASTER_FRONT或CASTER_RADIUS+TARGET_POSITION交叉组装，不强制配对。
- 玩家Controller：按技能已有目标配置传入自身或当前锁定；不通过技能ID、按键或具体场景路径判断玩法。

Hero源中的槽节点仍名Gather以保留既有路径与测试覆盖，但实例来源为TargetGatherSkill.tscn，Regular Skills[0]引用此节点；E槽未改变。没有热换槽/装备系统或运行时偷偷装配。

## 2. Inspector参数

| 入口 | 当前配置 | 含义 |
|---|---|---|
| 技能根 Target Relations | Hostile | 输入只提交当前敌方锁定 |
| 技能根 Cast Range | 5m（继承默认） | 施法者到锁定目标的距离，不是效果半径 |
| 技能根 Base Cast Time / Skill Cooldown | 0.2s / 10s | 独立测试场景仅把CD覆盖为2s |
| Delivery / Target Collection Mode | TARGET_RADIUS | 围绕技能目标，不使用玩家朝向 |
| Delivery / Candidate Source | WORLD_SCOPE | 范围目标不局限于施法者感知或请求候选 |
| Delivery / Effect Radius | 5m | 水平效果范围，沿既有统一边界容差 |
| Delivery / Affected Relations | Hostile | 只收集敌人 |
| Pull / Center Mode | TARGET_POSITION | 本次技能已冻结目标位置 |
| Pull / Gather Radius M | 0 | 聚到同一水平点，允许重叠 |
| Pull / Duration Seconds | 0.12s | 沿原战斗时钟，不新增计时器 |
| 根 Release Effect Anchor | TARGET_POSITION | 收束视觉与同次目标位置一致 |

新加的通用策划字段只有Pull.Center Mode；范围模式沿已有Target Collection Mode增加TARGET_RADIUS选项。旧中心前移参数只影响旧身前模式，目标模式忽略，不用为其手动填0。新预览的Skill Scene可切技能；不是正式玩法参数。

## 3. 请求与释放规则

1. 没有锁定，Q显示不可用；按Q返回target_missing，不启动动作或技能CD，也不自动选附近敌人。
2. 按Q受理时绑定原锁定目标；施法中玩家切换锁定不会把本次技能换成另一个目标。
3. 释放时沿原SkillBase验证关系、死亡和距离，然后冻结该目标当时的位置。
4. 同次Delivery围绕该位置筛5m内敌人；Pull将可受外力目标拉到同一中心，目标自身位于中心因此无需额外位移。
5. 释放后目标或玩家移动不改变落点和视觉。完成后恢复单位碰撞，普通AI自然散开。
6. 原根外力开关、墙地阻挡、死亡/取消等通用规则继续生效，不新增聚怪状态或特殊优先级。
7. E仍为Self启动，不需要锁定，原5m/临时仇恨/持续/冷却不变。

实际锁定范围仍由PlayerTargetingComponent管理；修改技能Cast Range不会同时扩大玩家锁定距离。玩家不自动接近：锁定合法但超出技能射程时，Controller消费Host原approach_requested通知并立即取消本次请求，反馈out_of_range，不隐藏排队、不占住Q/E、不在后来走近时自动补放；AI原有接近施法不变。

## 4. 后续复用

- 目标周围范围治疗、降防或伤害：复用TARGET_RADIUS并更换Affected Relations及Effects；不必调用Pull。
- 向目标点聚拢但散布在小盘内：仅修改Pull.Gather Radius M。
- 改回身前聚拢：直接装备保留的旧Gather，或在另一份内容中组合CASTER_RADIUS与CASTER_FRONT。
- 技能提供的目标来自AI还是玩家，不影响Delivery/Effect的执行；范围组件不读取玩家锁定，输入适配只负责把意图传进统一SkillBase。

## 5. 初版4米版本实施与验证（历史记录）

先写TargetGatherSkillTest并观察缺少独立新技能的预定FAIL，再实现：
无锁定零受理/零释放/零CD、E无锁定正常、真实锁定、面向无关、施法中原目标移动与换锁定、释放位置冻结、4m内含施法者5m之外目标、范围外/友方/关闭外力目标排除、目标自身不位移、无伤害、碰撞回收、目标死亡取消、同点视觉及独立预览。

旧GatherPresentationTest和PullTargetSkillEffectTest继续验证旧身前算法/视觉。原测试场景、联合流程、正式装配及CombatRoomFinisherFlowTest已更新为真实锁定Q；正式普通伤害→专注→连携→B终结5发5落地通过。

原生F6：无目标Q受理/释放均0且CD0；F选TrainingMelee后范围圈位于(-2,0.025,1)，实际Q受理/开始/释放各1、affected2，邻近TrainingRanged终点(-2,约0,1)，目标未收到外力请求，Debugger errors0。新预览已截图检查目标圆心与4m范围。运行夹具/暂停仅用于观察，不保存。

MCP创建新继承场景缺少适用接口，原生pack最初会展开根节点；仅该新场景回退最小文本继承定义，随后ResourceLoader重读确认base_scene=SkillBase.tscn、编辑器原生保存及UID验证。其余编辑使用Godot MCP Pro。没有新增正式.tres/.res、没有修改TestScene单位或动画。

最终全量与独立审查结果见第6节。运行日志/快照位于.godot/target_gather_2026_10_23；这不是正式内容目录。

补充回归：范围圆心/拉拽落点交叉组合先RED后修正快照/表现再GREEN；短射程仍可锁定时的隐藏排队问题先RED再复用Host.approach_requested在玩家端拒绝后GREEN；友方排除增加原位置及未收到外力终态断言，避免把错误拉动完成后的inactive当成排除。

## 6. 最终结果与审查处理

最终全量183项，181通过，仅2项既有失败：UnitSystem/Tests/CameraFollowControllerTest.gd（房间导航未烘焙）、SkillSystem/05-Tests/SingleSceneFireboltTest.gd（旧6m断言，当前用户源5m）。逐项检查退出码及错误/泄漏/invalid UID；新增SCRIPT ERROR、ObjectDB/资源泄漏与无效UID均0。本次差异格式检查0问题。

独立只读审查覆盖本次快照差异及最终独立圆心表现：
- P2：短技能射程+较远合法锁定产生隐藏队列，占住Q/E。已实跑预定失败，再使用玩家Controller原Host.approach_requested信号即时取消；不复制距离公式或修改AI接近管线。TargetGather/PlayerSkillControl/Bar及正式CombatRoomFinisherFlow均通过。
- P3：友方排除只查inactive可能是假阳性。已增加原位置不变与无外力终态记录断言，完整测试通过。
- 最终圆心/落点交叉组合表现静态复核未见新增重要问题。审查者不运行引擎，最终测试/UID/原生运行证据由主会话提供；不将只读审查冒充二次运行审计。

修正后正式F5原生验证：加载TargetGatherSkill，正式CD10/射程5；仅运行夹具把射程临时设1，锁定合法敌人后按Q，受理0、Host无活动技能、CD0；恢复射程5再按Q，受理1且进入正常冷却。Debugger errors0，运行夹具未保存，结束已停游戏。

旧Gather和E技能源SHA256相对本次开始保持一致，新技能/预览/测试UID有效；新技能实际base_scene为SkillBase.tscn。受保护TestScene执行前后均不存在，没有创建或编辑其单位。未更改动画、数值平衡、地图导航、插件、普通AI规则或既有连携/终结机制，未提交Git。

## 7. 当前版本：5米范围与完成后减速（2026-10-23）

新Q仍只修改TargetGatherSkill.tscn，原身前Gather和E源不变。Delivery / Effect Radius现为5米（配置类默认值，Inspector仍可直接修改）；选怪圈、调试圈和释放特效读取同一配置，无需重复调半径。Cast Range仍为5米，两者职责不同。

场景树装配：

```text
TargetGatherSkill
└─ PullTargetSkillEffect
   └─ StatModifierSkillEffect
```

选择StatModifierSkillEffect子节点：Target Mode=DELIVERY_TARGET、Modifier Stat=MOVEMENT_SPEED、Modifier Mode=PERCENT、Amount=-90、Duration Seconds=3、Stacking Rule=REFRESH。数值-90表示降低90%，剩余10%普通移动速度；3为战斗秒，遵循暂停/慢放。组件沿用既有通用属性效果脚本，没有新增减速专用脚本、资源类型或强制敌人装配新接收器。

执行边界：
- 技能根直属Effects仍按原Delivery即时执行；Pull直属SkillEffectBase子节点属于“实际拉拽完成后”执行，不会提前或重复进入技能根效果集合。
- 仅本次token以arrived/elapsed自然结束且实际发生水平位移时执行子效果；选中中心但未移动的原目标、免疫/关闭外力、被墙阻挡、取消、替换、死亡或来源失效不触发。
- 同一目标新的拉拽替换旧请求，旧监听解除，不会在新请求完成时误触发旧效果。组件离树解除所有待完成监听，不额外取消物理拉拽。
- 同一组件再次生效按状态容器原REFRESH规则刷新至3秒，不逐次叠加到100%减速。不同来源依旧遵循状态容器原百分比合并规则。
- AIUnitBase普通移动统一消费现有MOVEMENT_SPEED状态修正，包含行为层明确提交的速度；基础movement_speed不被改写。冲刺、动画位移与被动拉拽不受此普通移速修正影响，玩家移动本次未拓展。
- 子效果可以改装为其他SkillEffectBase（如降防），不是专门的减速回调。解除/删除该子组件即可取消后续减速装配，不改拉拽代码。完成后失败只诊断，不回滚已发生的位移或技能释放。

测试：PullCompletionEffectTest先观察缺少完成后效果/真实AI减速/正式装配/5米范围的预定失败，再实现转绿。覆盖真实物理抵达、默认与显式普通移速、3秒到期、同组件刷新、改配为降防、取消/替换/禁用/死亡、中心原地、移除组件清理和普通根级属性效果仍立即生效；TargetGatherSkillTest额外验证实际Hero输入链路下5米边界、真实抵达目标附加减速且排除对象无状态。初版第5-6节为历史验证，当前回归结果另行记录于本次验证段落。

复用兼容性补充：待完成记录保存每目标独立SkillDeliveryResult包装，冻结该目标的current_hit引用，保留同一次命中的后续伤害累加，避免范围循环把记录覆盖为最后一只怪。TriggerSkillEffect的原自引用/祖先循环保护改为查找最近SkillBase，直接挂根与嵌套完成后使用同样有效；不建立第二套触发入口。两项均先由真实交付/嵌套触发测试观察失败后修正。

当前最终验证：全量184项，182通过，仅既有CameraFollowControllerTest导航未烘焙与SingleSceneFireboltTest旧6米断言失败；本次专项PullCompletionEffectTest、TargetGatherSkillTest、TriggerSkillEffectTest、测试场景/联合流程/正式终结技流程均通过，无新增SCRIPT ERROR、ObjectDB资源泄漏或invalid UID。原生F6实际Q受理/施法/释放/完成各1，affected=3（中心目标加两只周围怪），两只实际拉动目标收到stat=2/amount=-90/remaining=3/pull_active=false，中心目标无减速事件；Debugger errors=0。旧身前Gather和E源SHA256与本次快照一致，SkillBase场景继承保留，新场景及测试UID有效，TestScene未创建。独立只读复核P2命中记录隔离、P3组件移除不取消物理，以及嵌套触发循环保护均已处理，无剩余重要发现。全量日志：.godot/target_gather_slow_2026_10_23/full-suite-final.json。所有编辑使用Godot MCP Pro；无新增正式.tres/.res、无Git提交/推送。
