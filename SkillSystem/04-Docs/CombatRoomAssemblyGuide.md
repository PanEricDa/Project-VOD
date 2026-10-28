# 2026-10-23 当前玩家Q更新

正式Hero的Q槽已改装Player_TargetGather/TargetGatherSkill.tscn，原身前Gather技能只卸下、保留源与预览。F/鼠标中键锁定敌人后按Q，以目标释放位置为中心聚拢5m内敌人，实际完成拉拽者减速90%持续3秒；无锁定拒绝，释放后位置固定。Q默认射程5m/CD10秒，E及其他正式数值不变；专项测试CD仍2秒。以下2026-10-22及更早内容为阶段历史，当前Q配置以本节和[目标聚拢指南](TargetGatherSkillConfigurationGuide.md)为准。

# 完整战斗房间组装与操作

日期：2026-10-22（玩家Q/E正式接入更新；历史阶段记录保留）。

## 正式运行入口

直接 F5，启动 `res://Scenes/CombatRoom.tscn`；也可打开此场景按 F6。它继承 `res://Scenes/TestCombatRoom.tscn`，不复制地图、单位或技能。基础房间及旧阶段预览保留原用途。

本次仅组装已确认的系统，没有新增技能、改动伤害/费用/角色布局，没有向 TestScene 添加或修改单位。正式入口不挂预览脚本、不关闭普通AI；初始专注由Inspector配置，不由预览脚本额外赠送。

## 玩家技能正式接入（2026-10-22）

F5已直接继承Hero源的Gather/ThreatMark和唯一Input/Controller：Q聚拢，E施加2000点限时仇恨（8秒），源CD分别10/12秒，不消耗专注、不造成伤害/连携评分。Q范围半径3.5米、圆心前移3米，聚拢盘前移1.5米/半径0.6米/0.12战斗秒。范围、效果及表现都沿技能源场景维护。

单位根Forced Movement / Forced Movement Enabled默认开启；不挂接收器，关闭即可拒绝外力并立即回收活动请求。正式HUD只新增根PlayerSkillBar，Skill Source指向Hero/PlayerSkillController，Panel局部偏移350,-420,574,-304放在生命列表右上。无测试Harness、范围圈或Unsupported靶。

独立测试场景继承同一Hero装配，仅覆盖2秒CD。当前正式参数重新读取为initial_focus=100、focus_gain_difficulty=2、score_difficulty=2、H0=15、D0=1000.01，本轮未改动。下文较早的参数/阶段描述作为历史记录，以本节与Inspector为准。

完整Q/E→普通真实伤害→专注→连携评分→B终结及输入/死亡/重建测试见阶段五验证文档；导航烘焙和旧Firebolt距离断言不在本轮修改范围。

## 操作闭环

1. 普通攻击及普通技能造成真实伤害，按原公式获取专注；初始余额由Inspector配置，无自然恢复。
2. 1/2/3/4依次指令Guardian/Priest/Caster/Archer的连携技能，仍由角色原动作流程执行。F最近锁定和鼠标中键精准锁定不变。
3. 首次有效连携伤害开窗，每次有效连携伤害刷新当前分数对应的间隔：不超过100分保持基础2.5秒，100到150分指数缩短，150分起0.8秒；窗口结束后按原评分曲线结算。
4. 结算达到100分才弹出3秒终结选择，世界5%慢放。当前Guardian、Caster与Archer已装备终结技，合法时分别按1、3、4选择，Priest灰显。Archer当前为逻辑首版，暂用普通箭与弓动作占位。未操作超时自动关闭。
5. Caster初始施法距离6米，释放复核额外容差2米；死亡、硬失能、非法目标或超距仍可能取消。
6. B演出：进镜真暂停 → 到位后动画正常播放/世界5% → 释放帧真暂停退镜 → 到位后原管线发射 → 五颗火球及主要爆炸结束 → 正常世界速度、镜头归还玩家。

连携技能和终结技仍是不同的SkillBase实例；终结伤害不回专注、不计入连携分数。没有新增A/B模式选择UI；历史比较预览继续保留，不作为正式入口。

## 场景中的可见装配

在CombatRoom根节点下查看/修改Inspector：

| 节点 | 职责与配置入口 |
| --- | --- |
| PlayerSkillBar | 只读本地Hero/PlayerSkillController；槽位、名称、按键、冷却不复制配置 |
| SquadFocusComponent（继承） | 专注容量、初始值、获取难度及伤害换算 |
| SquadChainCommandController | 固定四伙伴引用及原专注源；等待超时 |
| SquadChainCommandDisplay | 四卡、等待/施放反馈和专注信息；只引用Command |
| SquadChainRoundDisplay | 右上方独立COMBO数字、评分槽、连击窗口倒数；只引用Round |
| ChainSkillPresentationController | 连携镜头与释放表现；引用原CameraRig，子节点PauseCoordinator是唯一暂停协调器 |
| SquadChainRoundController | 评分难度、基础/最短伤害间隔、最短间隔评分、H0/D0 |
| SquadFinisherSelectionController | 选择3秒、5%速度；引用Round及同一PauseCoordinator |
| SquadFinisherSelectionDisplay | 限时十字选择显示 |
| SquadFinisherExecutionController | 选择到实际施放的接线；引用Selection和同一CameraRig |

所有引用已静态保存在场景，可直接在Inspector查看。不需要额外脚本在运行时拼装系统。

正式入口的试验配置以Inspector为准；截至本轮用户已调整为初始专注100、获取难度5，评分难度2、H0=15、D0=1000.01。本次未修改这些数值。评分/专注调整只改上述字段，不修改技能与界面代码；旧预览可能使用不同配置，启动节奏可不同。

## 技能与特写配置

Caster源场景 → SkillHost → Finisher Skill，引用其SkillSocket内的FlameBarrageFinisherSkill。

技能源场景：`res://SkillSystem/00-Skills/Finisher_FlameBarrage/FlameBarrageFinisherSkill.tscn`。伤害、射程、投射物、Effects与视觉仍在此维护，没有在CombatRoom复制覆盖。

镜头资源：`res://Effects/Camera/Presets/FlameBarrageCinematicCamera.tres`，三个过渡时间均0.2秒。动作资源仍为同技能文件夹下FlameBarrageAction.tres，只用原release_action、finish_action方法帧。详细说明见FlameBarrageFinisherConfigurationGuide.md。

更换地图/摆放仍在TestCombatRoom处理，CombatRoom继承更新。后续关卡可沿相同八个组件接线，无需复制技能执行代码；不建议继承旧阶段预览作为正式关卡，以免带入初始资源或测试行为。

## 测试与边界

- CombatRoomAssemblyTest：正式启动入口、继承关系、有效UID、唯一组件、同域引用、四槽顺序和保留数值。
- CombatRoomFinisherFlowTest：普通AI真实伤害产生专注，实际InputMap输入进入连携，真实伤害结算达分，按3选择，完整B演出五发五落地、主要视觉归零、恢复时间及卸载清理。
- 端到端夹具只在内存里提高敌人耐久、安排近距离站位、降低专注/评分难度并缩短闭窗等待，避免测试依赖随机战斗平衡；不修改正式场景或资源，不伪造伤害/资格信号。手工SceneTree装载时显式调用现有Host.configure_owner，与真实F5已核对的世界绑定一致。
- 本次未调整基础房间既有未烘焙的导航网格；该问题仍由CameraFollowControllerTest单独报告，不属于连携接线失败。

## 2026-10-19 达标后的自适应伤害间隔

2026-10-19版本沿用原评分公式和100分资格线，仅缩短收尾等待；2026-10-25已追加按Effect独立开关控制的终结评分威力加成，见文末更新。

配置入口：CombatRoom根节点的SquadChainRoundController → Evaluation。保留Damage Interval Seconds（基础间隔，默认2.5秒），新增Minimum Damage Interval Seconds（默认0.8秒）和Minimum Interval Score（默认150分）；指数形状内部固定，不增加资源、组件或技能配置。

设B为本轮基础间隔，L=min(最短间隔,B)，S为当前综合评分，C为最短间隔评分：

- S≤100：T=B。
- 100<S<C：x=(S−100)/(C−100)，T=L+(B−L)×[exp(−3x)−exp(−3)]/[1−exp(−3)]。
- S≥C：T=L。

默认B=2.5/L=0.8/C=150时：

| 分数 | 本次伤害后的间隔 |
| --- | --- |
| ≤100 | 2.50秒 |
| 110 | 1.69秒 |
| 120 | 1.25秒 |
| 125 | 1.11秒 |
| 130 | 1.01秒 |
| 140 | 0.87秒 |
| ≥150 | 0.80秒 |

每笔有效伤害先更新评分，再从该笔伤害刷新对应时长；不是总连携时限，也不是让无伤害的倒数自行加速。达到100分仍不立即弹窗，只有超过当前伤害间隔后才闭窗并按原规则发出终结资格。继续命中仍会续窗；严格到期边界、暂停冻结、去重、晚到伤害不追加评分和上一轮结果保留均不变。

三个窗口配置和原评分配置一样，在本轮受理时捕获；Inspector编辑从下一轮生效。最短间隔高于基础间隔时按基础值处理，避免开发测试的0.1/0.5秒短间隔被意外延长；最短间隔必须有限且正，终点分数必须有限且大于100，非法配置拒绝建立新轮。

UI沿原interval_seconds/remaining_seconds显示实际缩短后的倒数，无需复制曲线或更改场景装配。测试SquadChainAdaptiveWindowTest使用真实请求与伤害覆盖曲线样本、精确边界、重复事件、暂停、快照、短基础间隔和非法参数；原UI测试同步验证0.8秒窗口中的半程显示。

本轮验证：SquadChainAdaptiveWindowTest先在旧固定间隔上复现失败，再于新曲线接入后通过。原UI/快照测试按动态间隔更新；正式场景测试不再锁死可编辑的初始专注/难度，端到端夹具显式从零开始验证收益。全量155项中154通过，唯一既有CameraFollowControllerTest导航网格未烘焙失败；ObjectDB/资源泄漏日志0，git diff --check通过。本轮为实现者自审，未进行独立代理评审。未提交或推送Git。

## 2026-10-19 正式连携源场景补齐统一闪光
此前银白闪光仅在ChainSkillPresentationPreview的实例覆盖中，正式CombatRoom未继承这些覆盖。本轮将同一资产配置到SkillSystem/00-Skills/下四个Combo_*技能源场景的根节点：Presentation → Cast → Cast Effect Scene=Effects/Skills/Shared/ReleaseAccentFlash.tscn，Cast Effect Anchor=Caster Feet，Cast Effect Start Ratio=0.5。普通角色实例直接引用源场景即可，不依赖预览脚本或运行时装配。

Caster的连携施法视觉由火球蓄力替换为统一银白闪光；其普通Firebolt不改。Guardian和Priest原有成功释放视觉保留；Archer补上此前为空的施法视觉。没有改技能数值、镜头、时停或播放代码，没有新增资源/运行脚本，也没有修改TestScene单位。源场景均通过Godot编辑器原生保存。

回归增加在既有CombatRoomAssemblyTest中检查四技能正式配置，在CombatRoomFinisherFlowTest中观察真实按键连携生成的银白闪光、施法阶段及角色脚下附着；旧配置下两项先失败，补齐源配置后通过。另将终结技旧固定半径/射程测试更新为有效配置及相对当前射程的边界，不回退用户现有散布2.01米、射程7米等参数。

最终验证：正式入口实机捕获Priest在0.8秒施法的半程后生成ReleaseAccentFlash，实例附着Priest且仍处于CASTING；截图确认银白光线与地环可见。全量155项中154通过，唯一失败为既有CameraFollowControllerTest导航网格未烘焙；无新增脚本错误、ObjectDB或资源泄漏日志，git diff --check通过。未改用户技能数值，未提交或推送Git。

## 2026-10-19 独立COMBO显示

正式CombatRoom与SquadChainRoundPreview（以及继承它的终结预览）根下新增SquadChainRoundDisplay。源场景为UnitSystem/Components/UI/SquadChainRoundDisplay.tscn，同名.gd仅负责只读显示；Inspector仅一个Round Source，指向本关卡原SquadChainRoundController。不重复设置Command/Focus/队伍或评分参数。

右上方由上至下为大号数字与英文COMBO、评分进度槽、较细的伤害间隔倒数槽。评分不显示数字或百分比，100分填满并变为金色，后台分数继续累计。数字变化以0.65倍快速放大至1.12倍再回到正常，动画内部封装；连续伤害只重启同一个跳字状态，不创建堆叠Tween。暂停及原表现暂停时冻结动画，业务倒数只读取原评价快照。

首笔有效伤害前隐藏；闭窗保留上一轮数字和评分槽，倒数槽隐藏；不显示终结资格或连携结束文字；新请求未命中不清旧结果，下一轮首笔伤害替换。切换评价源或卸载世界不串数据。技能栏移除原连击/评分/倒数，保留原四卡和专注信息，专注显示不再依赖评价组件。

布局编辑入口：打开独立源场景，Panel的锚点/偏移控制位置；VBox/ComboRow/Number的主题字号控制大数字；ScoreProgress与DamageInterval维护各自高度和内嵌样式。组件场景内可直接预览示例排版，不需修改脚本；无新增外部.tres资源，无技能/战斗参数变化。

SquadChainRoundDisplayTest覆盖真实伤害驱动的显示、无数字评分、动态间隔、跳字重入、暂停、结果保留、换源与卸载、只读无扣费、正式及预览装配，以及关卡卸载无孤儿UI节点。

本次验证：SquadChainRoundDisplayTest先因独立组件不存在而失败，接入后通过；正式CombatRoom真实连携命中时已截图核对右上布局、两条进度槽及底部技能/专注保留。全量155项中154通过，唯一失败仍为CameraFollowControllerTest的既有导航网格未烘焙检查；顺序运行的终结选择压力测试通过，ObjectDB/资源泄漏日志0，git diff --check通过。本次没有提交或推送Git。


## 2026-10-25 终结评分效果奖励

闭窗最终评分捕获一次1至1.5倍的威力快照，四终结技的主要数值效果已开启。配置入口为各Effect的Finisher Reward → Use Finisher Bonus，默认false；倍率仅增强具体Effect指定的数值，不改变范围/数量/时长。继承、上下文与子技能传递及当前五个开启节点见 FinisherScoreRewardConfigurationGuide.md。
