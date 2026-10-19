# 阶段二：伙伴连携指令配置与验证

状态：2026-10-13 已实现并通过后台验收（126/126），操作手感待人工确认。阶段二只提供实时指令、动作衔接、目标意图和专注收费；尚无正式伤害间隔窗口、评分或终结技。

## 直接运行

在 Godot 打开 `res://Scenes/Previews/SquadChainCommandPreview.tscn`，按 F6。它继承正式 `TestCombatRoom`，没有复制或添加战斗单位；仅预览把初始专注改为100，并装上控制器和只读卡片。

| 按键 | 伙伴 | 独立验证技能 | 复用内容 |
| --- | --- | --- | --- |
| 1 | Guardian | 连携·盾击 | GuardianShield近战动作、效果和特效 |
| 2 | Priest | 连携·强效治疗 | GreaterHeal目标治疗及特效 |
| 3 | Caster | 连携·火球 | Firebolt追踪火球、范围伤害和8秒灼烧标记 |
| 4 | Archer | 连携·连射 | RapidShot单次动作、连续投射物 |

先接近敌人，使用现有F/鼠标中键锁定，按3观察实际释放，再按4。输入受理不等于技能已经释放；同时按下四键不是保证按键顺序的序列编排。

观察卡片的等待空闲、接近目标、施放中、动作收尾和已缓存，以及左上专注总量/预留/可用值。灰显表示当前不能受理，不代表技能在冷却；技能正在施放而缓存空时仍可再请求一次。等待槽满拒绝，不覆盖先前请求。

同一角色同一技能在开发批次中第一次20点、第二次30点、第三次40点，以此递增。等待时预留上界；释放前失败退还预留，成功交付后即收费，之后未命中不退。若前序未释放，后序实际收费会低于重复上界。重开预览得到新批次、100初始专注；不提供临时重置按键。

治疗按自己的友方目标策略选取，不把敌方锁定当治疗目标；显式指令跳过仅限自动AI的40%血量条件，但保留底层合法性和ALL_REQUESTS条件。治疗没有伤害，不因此产生连击得分。本阶段没有实现评分。

## Inspector实际配置入口

新增配置共7种字段，不是每个技能都要填写7项。

| 位置 | 新字段 | 默认/用途 |
| --- | --- | --- |
| 角色 `SkillHost` → Skill Slots | `combo_skill` | 引用自己的 `SkillSocket` 中独立技能实例；不可重复引用普通/终结槽 |
| 技能根的 `ComboFocusCost` 子节点 | `base_focus_cost` | 20，首次成功根释放的专注费用 |
| 同上 | `repeat_focus_cost` | 10，同一角色技能每次成功重复增加的费用 |
| 关卡 `SquadChainCommandController` | `companions` | 四个固定槽，0—3对应1—4，空槽留空，不压缩顺序 |
| 同上 | `focus_source` | 当前关卡的SquadFocusComponent |
| 同上 | `command_wait_timeout_seconds` | 8秒，含旧动作等待和接近；换锁定不重置，动作开始后停止计时 |
| `SquadChainCommandDisplay` | `command_source` | 本关卡控制器；UI只读，不支付、不选目标 |

InputMap使用`squad_chain_1`—`squad_chain_4`物理数字键，可在项目设置重新绑定。键盘事件设备设为所有设备，避免工具写入指定设备编号导致真实键盘不匹配。生产脚本不直接检查物理数字键值。

## FileSystem与装配

- 通用请求：`SkillSystem/01-Core/SkillCommandRequest.gd`。内部身份、用途、生命周期不暴露Inspector。
- 费用组件：`SkillSystem/03-Extensions/ComboFocusCost.gd`，直接挂技能根一次，不继承普通SkillCostBase，避免重复收费。
- 追踪交付会话：`SkillSystem/02-Delivery/TrackingProjectileDeliverySession.gd`，Runner内部创建，无需策划装配。
- 控制器：`UnitSystem/Components/Combat/Squad/SquadChainCommandController.tscn`，置于关卡根，与Focus同一世界。
- 显示：`UnitSystem/Components/UI/SquadChainCommandDisplay.tscn`，原生Control四卡，不捕获鼠标与键盘焦点。
- 技能：`SkillSystem/00-Skills/Combo_GuardianBash/`、`Combo_GreaterHeal/`、`Combo_Firebolt/`、`Combo_RapidShot/`。复用现有模板、Delivery、Effects、动作和VFX，不新增专有技能脚本或外部资源。
- 四个角色源场景：`UnitSystem/AI/Ally/Units/{Guardian,Priest,Caster,Archer}.tscn`，各自 `SkillHost/SkillSocket/Combo…Skill`，原两个普通槽不变。
- 预览：`Scenes/Previews/SquadChainCommandPreview.gd/.tscn`，静态装配以上控制器与显示。正式房间本身没有新增指令组件。

替换连携内容：实例化现有技能模板或技能场景，设置独立skill_id、显示名、效果、Delivery和美术，挂一个费用组件，再引用到角色combo_skill。若已有组件能够表达效果，无需新增执行脚本。不要复用普通槽的同一个技能节点。验证内容关闭自动施放、CD和AI犹豫；真正的连携规则由上下文用途决定，不依赖零CD配置实现。

常规/连携共用SkillBase及交付流程；连携跳过自身CD、AI犹豫和公共冷却，但不擦除普通技能已有计时，不打断当前真正执行的普通动作。动作开始前刷新当前玩家敌方锁定；动作开始后目标冻结。角色死亡、施法封锁等按正常规则失败，不另设玩家聚怪状态。

## 轮次接口与阶段边界

控制器通过`set_round_source(peek_current, acquire_for_request)`接入轮次所有者。peek只查询；acquire在真实输入受理时获取正单调身份。没接接口时失败关闭，UI刷新不得创建批次。预览明确只注入单个开发费用批次，不是正式连携窗口。

生命周期回调须注意：Focus正在执行unbind_scope时，scope_changed(null)监听者不能同步重入bind_scope；此时返回false，应待外层解绑结束后重试。请求受理跨同步回调会校验原会话和本笔预留，不能把旧请求迁到新战场。

阶段三再接基于实际伤害间隔的开窗/续窗/关窗和评分；阶段四再做限时终结选择与暂停演出。现在的卡片不会显示不存在的连击倒数、评分或终结资格。

## 连携施放表现（2026-10-15）

新独立预览：`Scenes/Previews/ChainSkillPresentationPreview.tscn`，继承上述阶段二预览，沿用原阵容/脚本/1—4。原四技能增加共享镜头与强调预设，源释放美术不替换；最初仅新预览覆盖共用释放效果（2026-10-19已补到正式连携源场景，见末节）：微蓝银白的周身光线＋脚下圆环向内汇聚，四个连携均在本次实际施法进度50%时播放，以施法者脚下（Caster Feet）为锚点，不修改源技能的治疗/盾击视觉。

正式接入时，另放 `UnitSystem/Components/Combat/Squad/ChainSkillPresentationController.tscn`，Inspector选择原指令源与CameraRig，Pause Source已预填。不要重复装配暂停协调器，也不再配置一份玩家/世界。当前正式房间未自动接入。

受理黄、实际开始绿并移动镜头、成功释放播放资产并强调0.10秒，期间镜头与战场动作定住，释放视觉/音频继续、绿色从成功释放起0.3秒后清除；失败/拒绝短暂红色。颜色编辑原UI场景Theme，两项时长在UI根Inspector。已有绿色时，下一条缓存只确认文字，不抢当前镜头或边框。显式暂停挂起表现，强调暂停允许受理/预留1—4但不执行AI。

镜头使用玩家锚定的距离加权偏移：伙伴距玩家0—10米时，偏移平滑增强；最终位移倍率当前为2.4，相同距离下为上一版2.0的1.2倍；目标上限为玩家深度处视野宽度28.8%，且不超过双方距离108%。基础进入0.30秒、回归0.55秒，叠加最多0.20秒距离缓动后，仅进入阶段整体除以1.5（实际约0.20—0.333秒），返回仍约0.55—0.75秒，连续施法从当前偏移接续，不先回中再折返。普通期间继续跟随玩家；成功释放时在当前构图定住0.10秒，不补冲、不延迟技能，强调结束后再继续回归或衔接。不增加垂直偏移，不改变朝向、FOV或缩放档位。

配置仍在 Effects/Camera/Presets/ChainSkillFocus.tres，仅有原来的进入/返回两个时长；幅度、距离曲线与额外缓动时间内部封装；停留时长在Effects/Combat/Presets/ChainReleaseAccent.tres配置。技能根Camera Effect Profile留空可关闭镜头，不关闭边框、释放特效或强调暂停。

镜头/强调资源可独立留空；缺失不能改变费用或技能结果。既有等待、动作锁、重复费用与目标规则不变。完整验收见 `Docs/Superpowers/Plans/2026-10-14-chain-skill-presentation-validation.md`，不代表评分/终结已实现。

测试入口：`UnitSystem/Tests/SquadChainInputDisplayTest.gd`及阶段二新增7个执行/事务/生命周期测试。验收数据见`Docs/Superpowers/Plans/2026-10-13-burst-combo-stage-2-validation.md`。

### 共用释放汇聚效果（2026-10-15）

- 资产：`Effects/Skills/Shared/ReleaseAccentFlash.tscn`；保留旧路径/UID，仅替换内容，无新增脚本或外部资源；通用Cast入口新增锚点与开始进度配置。
- 编辑入口：场景内 `VisualRoot/BodyRays` 的8条周身短光线、`VisualRoot/GroundRing` 的脚下环；材质为微蓝银白、无阴影，不创建灯光。动画在 `AnimationPlayer/pulse`，回收在 `CleanupTimer`。
- 光线0—0.08秒向躯干外缘收拢；脚下约1米半径圆环在0.06—0.18秒向内收拢；0.25秒前淡出、0.28秒回收。汇聚效果已移至Cast入口，在本次实际施法进度50%时播放并遵循战斗时钟，取消/失败立即清理，成功释放时一次性效果按原时长自然回收（不截断短施法），蓄力型资产结束；共享释放时停仍为0.10秒，Release通道仍支持原独立时钟。
- 单独查看：运行 `Effects/Skills/Shared/ReleaseAccentFlashPreview.tscn`，点击“播放所选资产”。联动试玩：运行 `Scenes/Previews/ChainSkillPresentationPreview.tscn`，进入战斗后使用1—4。
- 其他技能可在根节点 `Presentation / Cast` 下选择同一 `Cast Effect Scene`，`Cast Effect Anchor` 选 `Caster Feet`，`Cast Effect Start Ratio` 设 `0.5`（0表示开始即播放，默认0以兼容普通技能）；`Release Effect Scene` 另管成功释放视觉，若希望只在所选施法进度出现则不要重复配置；不需要新组件。当前只装配在上述四个连携的预览覆盖中，正式房间和普通技能保持原状。

## 2026-10-16：正式连携轮次与伤害评价（阶段三）

试玩入口：res://Scenes/Previews/SquadChainRoundPreview.tscn，F6运行，沿用1—4与原锁定操作。此预览继承ChainSkillPresentationPreview，根script=null，替代该预览的_development_round；旧预览不变。正式关卡尚未接入。

装配：在关卡根实例化UnitSystem/Components/Combat/Squad/SquadChainRoundController.tscn；command_source选择该关卡原SquadChainCommandController。SquadChainCommandDisplay只连接command_source，显示技能卡片与专注；另实例化UnitSystem/Components/UI/SquadChainRoundDisplay.tscn，将其round_source指向此评价节点，显示右上COMBO、评分槽和倒数槽。不重复填写队伍、Focus或暂停源，不给各技能新增参数。TestScene单位实例仍由用户手动添加，Codex不代放。

评价节点共7项参数（含两个自适应窗口字段）：

| Inspector | 默认 | 用途 |
| --- | --- | --- |
| Assembly / Command Source | 空 | 原伙伴指令源；世界/队伍/请求从此取得 |
| Evaluation / Score Difficulty | 5.0 | 评分难度；越低越容易得分，5为当前曲线标准倍率 |
| Evaluation / Damage Interval Seconds | 2.5秒 | 基础伤害间隔；评分不超过100时保留，达标后缩短，不是总时限 |
| Evaluation / Minimum Damage Interval Seconds | 0.8秒 | 达标后最短间隔；不会延长更短的基础间隔 |
| Evaluation / Minimum Interval Score | 150分 | 达到最短间隔的评分；必须大于100 |
| Evaluation / Hit Score Scale | 10次 | 连击曲线基准H0；达到基准贡献40分（难度5） |
| Evaluation / Damage Score Scale | 100生命点 | 伤害曲线基准D0；达到基准贡献60分（难度5） |

六个数值仅是开发基线，不是最终难度平衡；本轮建立时捕获，编辑只影响下一轮。非法参数明确诊断并拒绝建立新轮，不能静默除零或改变已受理技能。

首笔连携正伤害先计入再开窗；每笔后续有效伤害续窗；普通伤害/施法/治疗/特效不续窗。S=[40×log₂(1+H/H0)+60×(D/D0)^1.1]×(5/score_difficulty)，后台不封顶，显示进度最高100%。H按真实命中去重、D按实际生命损失累计。达分先显示就绪，伤害间隔结束才通知资格；阶段三不会暂停或打开终结菜单。

闭窗不取消或等待旧投射物/碎片/缓存；旧请求仍按原轮执行及支付，迟到伤害不串新轮，也不恢复专注。新轮重复费归零，但不会清空伙伴原缓存槽。单独移除评价只拒绝新请求，不重置专注或取消已释放技能。

当前UI拆分为两个独立组件：SquadChainCommandDisplay保留四卡和原Focus当前/预留/可用信息，不依赖评价组件；SquadChainRoundDisplay只连接round_source，在右上显示大号数字与英文COMBO、评分槽、伤害间隔倒数槽。评分不显示数字或百分比，100分进度满槽并变金，后台继续累计。数字每次变化快速从小放大后回弹，动画速度内部封装。结算后保留上次数字和评分进度，直到新轮首笔有效伤害替换；不显示终结资格或连携结束文字；新指令/等待命中不清除旧结果。闭窗隐藏倒数槽，暂停冻结动画和倒数，解绑/换源不串世界。布局/字号/样式在独立SquadChainRoundDisplay.tscn的Panel与VBox子节点中编辑；UI不拥有业务时钟或终结资格。

后续同类队伍直接复用此评价节点与两个显示组件；不创建每技能评分资源。阶段四从finisher_qualified(result)消费一次资格事实，不能从UI或last_result当作库存读取。


## 2026-10-16：难度系数调校入口

- 评分：选中当前关卡的SquadChainRoundController节点，在Evaluation / Score Difficulty中调整；源场景为UnitSystem/Components/Combat/Squad/SquadChainRoundController.tscn，逻辑由同名.gd维护。
- 专注：选中当前关卡的SquadFocusComponent节点，在Focus / Focus Gain Difficulty中调整；源场景为UnitSystem/Components/Combat/Squad/SquadFocusComponent.tscn，逻辑由同名.gd维护。
- 两个系数独立，均默认5.0、Inspector最低0.1、支持超过10；5为各自当前模型的标准倍率，2.5为两倍，10为一半。评分曲线已替换旧线性模型，5不表示逐项沿用旧分数。只需调这两个难度系数，原H0/D0与damage_to_focus_ratio维持基线即可。
- 评分乘5/score_difficulty，受理新轮时捕获；本轮中途编辑不重算，下一轮生效。100分资格线、原连击/伤害比例、实际伤害及时间间隔不变。非法评分难度拒绝建立新轮。
- 专注收益为actual_damage × focus_yield_multiplier × damage_to_focus_ratio × (5/focus_gain_difficulty)，下一笔有效常规伤害立即生效；不重算余额、不影响预留/费用/容量，不为零收益连携或终结伤害增加回充，不增加自然恢复。非法专注难度停止新增收益。
- 在SquadChainRoundPreview中，直接选中根下上述两个节点调整即可；所有既有实例自动继承默认5，无需重新装配、改技能或创建.tres。修改源场景是全体未覆盖实例的默认值，修改关卡实例只影响该场景。


## 2026-10-16：连击递减与伤害温和加速曲线

- 仍只由原SquadChainRoundController计算，无新增参数、脚本、场景或资源；专注算法与技能内容不变。
- S=[40×log₂(1+H/H0)+60×(D/D0)^1.1]×(5/评分难度)。H为本轮有效累计命中，D为累计实际生命损失；每次伤害后按累计值重算，不能对单笔伤害分别取幂再累加。
- 首轮试玩默认H0从20校准为10，D0从500校准为100；未覆盖的既有实例继承新默认。玩家自己已填写的场景覆盖值保留，该次调校时SquadChainRoundPreview难度为3；当前配置以最新调校记录为准。40/60与1.1属于内部曲线常量，不增加Inspector项。
- 难度5时，10击/100伤害=100分；20击/20伤害约73.61，40击/40伤害约114.78，3击/150伤害约108.86。高连击与高伤害均可达标，分数没有硬上限。40/60仅表示各自达到基准时的贡献，不代表每轮固定占比。
- 难度系数继续乘5/系数；基准与难度均在本轮受理时捕获，改值不重算旧轮，资格线100、伤害间隔、晚到弹道、计数去重与上一轮显示保留规则不变。
- 默认10/100是首轮试调，不是最终平衡；后续仍在原节点通过H0、D0和难度调校，不为各个技能配置评分规则。


## 2026-10-16：放宽连携衔接窗口

Damage Interval Seconds默认由2.0秒改为2.6秒（增加30%）。从最近一次有效连携伤害开始倒数，每次有效伤害刷新完整2.6秒；不是整轮总时限。评分、专注、技能速度和输入规则不变。仍在SquadChainRoundController的Evaluation中配置，改值下一轮生效。


## 2026-10-18：衔接窗口与镜头幅度微调

Damage Interval Seconds默认由2.6秒调整为2.5秒；仍按有效连携伤害间隔刷新，不是整轮总时限。SkillFocusCameraProfile内部最终位移倍率由2.0调整为2.4（增加20%）；距离曲线、进入速度倍率、返回速度、释放强调停顿均不变，无新增Inspector配置。


## 2026-10-18：基础数值试玩基线

普通伤害、连携伤害与敌我生命池已分档，完整配置见Docs/Superpowers/Plans/2026-10-18-combat-balance-baseline.md。TestCombatRoom专注获取难度10，评分预览继承；预览用户评分难度2/H0=20保留，D0=2000，连携间隔仍2.5秒。正式初始专注0，试玩初始100。连携理想全覆盖预算72.24%不代表真实AI战果。无新增正式技能脚本/技能场景；唯一新资源为Item/Weapon/Sword/GoblinSwordData.tres，用于隔离敌方与玩家武器数值。


### 2026-10-18 试玩后：连携降伤

三个伤害型连携现为对应普通技能的1.2倍：火球48、连射每箭12.6、盾击主目标两路52.8（均减伤前）。配置仍在各Combo技能场景的DamageEffect/MeleeAction，普通技能与治疗连携不改。用户最新评分难度1.5保留，未自动补偿评分或专注。首轮72.24%预算已失效，当前理想七敌预算约22.96%；详情见基础数值记录末节。


## 阶段四第一切片：终结选择接口（2026-10-18）

独立预览：res://Scenes/Previews/SquadFinisherSelectionPreview.tscn，继承阶段三预览，不改正式关卡或原数值。

F6运行后按原方式积累专注、锁定敌人并使用1—4连携；停手后按现有伤害间隔结算，达分才弹出。窗口左1=Guardian、上2=Priest、右3=Caster、下4=Archer，实际名称来自原伙伴固定槽，不另配名单。

选择期间战斗为5%速度；倒计时默认3真实秒。按对应InputMap动作显示选中高亮、输出日志后收起；不选则超时关闭。两种路径都恢复此前时间倍率。真正菜单暂停会挂起倒计时；普通释放短停顿不会。

配置入口：SquadFinisherSelectionController仅Round Source、Pause Source、Selection Duration Seconds（真实秒）、Selection Time Scale（绝对速度上限）；显示的Selection Source指向该控制器。预览已连接原SquadChainRoundController和ChainSkillPresentationController/PauseCoordinator。

UI场景：res://UnitSystem/Components/UI/SquadFinisherSelectionDisplay.tscn；十字卡片、样式、字体、颜色和倒计时在节点Inspector中编辑，过渡速度内部封装。

当前仅验证接口：未装备正式终结技能也可选存活且唯一的本世界伙伴。缺失、重复、死亡或跨世界槽无效。按键只输出[FinisherSelection]日志及finisher_selected纯值事件，不执行技能、不花专注、不打断动作。后续接正式终结执行时再接真实技能合法性。

旧按键需释放后重按；弹窗期间及本次按下的收尾事件不进入普通连携，关闭后新按下恢复原用途。控制器缺失时原场景行为不变；UI只读，删除显示不会擅自取消窗口。

本轮不接Scenes/TestScene.tscn或正式关卡。若正式场景需要接入，由后续明确的装配任务处理，不复制伙伴或暂停管理器。

## 2026-10-19 达标后的自适应伤害间隔

当前版沿用原评分公式和100分资格线；只缩短收尾等待，未实现终结伤害加成。

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

## 2026-10-19 正式连携源场景补齐统一闪光
此前银白闪光仅在ChainSkillPresentationPreview的实例覆盖中，正式CombatRoom未继承这些覆盖。本轮将同一资产配置到SkillSystem/00-Skills/下四个Combo_*技能源场景的根节点：Presentation → Cast → Cast Effect Scene=Effects/Skills/Shared/ReleaseAccentFlash.tscn，Cast Effect Anchor=Caster Feet，Cast Effect Start Ratio=0.5。普通角色实例直接引用源场景即可，不依赖预览脚本或运行时装配。

Caster的连携施法视觉由火球蓄力替换为统一银白闪光；其普通Firebolt不改。Guardian和Priest原有成功释放视觉保留；Archer补上此前为空的施法视觉。没有改技能数值、镜头、时停或播放代码，没有新增资源/运行脚本，也没有修改TestScene单位。源场景均通过Godot编辑器原生保存。

回归增加在既有CombatRoomAssemblyTest中检查四技能正式配置，在CombatRoomFinisherFlowTest中观察真实按键连携生成的银白闪光、施法阶段及角色脚下附着；旧配置下两项先失败，补齐源配置后通过。另将终结技旧固定半径/射程测试更新为有效配置及相对当前射程的边界，不回退用户现有散布2.01米、射程7米等参数。
