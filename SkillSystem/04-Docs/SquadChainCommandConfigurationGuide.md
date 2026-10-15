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

新独立预览：`Scenes/Previews/ChainSkillPresentationPreview.tscn`，继承上述阶段二预览，沿用原阵容/脚本/1—4。原四技能增加共享镜头与强调预设，源释放美术不替换；新预览仅覆盖共用释放效果：微蓝银白的周身光线＋脚下圆环向内汇聚，四个连携均在本次实际施法进度50%时播放，以施法者脚下（Caster Feet）为锚点，不修改源技能的治疗/盾击视觉。

正式接入时，另放 `UnitSystem/Components/Combat/Squad/ChainSkillPresentationController.tscn`，Inspector选择原指令源与CameraRig，Pause Source已预填。不要重复装配暂停协调器，也不再配置一份玩家/世界。当前正式房间未自动接入。

受理黄、实际开始绿并移动镜头、成功释放播放资产并强调0.10秒，期间镜头与战场动作定住，释放视觉/音频继续、绿色从成功释放起0.3秒后清除；失败/拒绝短暂红色。颜色编辑原UI场景Theme，两项时长在UI根Inspector。已有绿色时，下一条缓存只确认文字，不抢当前镜头或边框。显式暂停挂起表现，强调暂停允许受理/预留1—4但不执行AI。

镜头使用玩家锚定的距离加权偏移：伙伴距玩家0—10米时，偏移平滑增强；最终位移倍率当前为2.0，相同距离下为上一版的两倍；目标上限为玩家深度处视野宽度24%，且不超过双方距离90%。基础进入0.30秒、回归0.55秒，叠加最多0.20秒距离缓动后，仅进入阶段整体除以1.5（实际约0.20—0.333秒），返回仍约0.55—0.75秒，连续施法从当前偏移接续，不先回中再折返。普通期间继续跟随玩家；成功释放时在当前构图定住0.10秒，不补冲、不延迟技能，强调结束后再继续回归或衔接。不增加垂直偏移，不改变朝向、FOV或缩放档位。

配置仍在 Effects/Camera/Presets/ChainSkillFocus.tres，仅有原来的进入/返回两个时长；幅度、距离曲线与额外缓动时间内部封装；停留时长在Effects/Combat/Presets/ChainReleaseAccent.tres配置。技能根Camera Effect Profile留空可关闭镜头，不关闭边框、释放特效或强调暂停。

镜头/强调资源可独立留空；缺失不能改变费用或技能结果。既有等待、动作锁、重复费用与目标规则不变。完整验收见 `Docs/Superpowers/Plans/2026-10-14-chain-skill-presentation-validation.md`，不代表评分/终结已实现。

测试入口：`UnitSystem/Tests/SquadChainInputDisplayTest.gd`及阶段二新增7个执行/事务/生命周期测试。验收数据见`Docs/Superpowers/Plans/2026-10-13-burst-combo-stage-2-validation.md`。

### 共用释放汇聚效果（2026-10-15）

- 资产：`Effects/Skills/Shared/ReleaseAccentFlash.tscn`；保留旧路径/UID，仅替换内容，无新增脚本或外部资源；通用Cast入口新增锚点与开始进度配置。
- 编辑入口：场景内 `VisualRoot/BodyRays` 的8条周身短光线、`VisualRoot/GroundRing` 的脚下环；材质为微蓝银白、无阴影，不创建灯光。动画在 `AnimationPlayer/pulse`，回收在 `CleanupTimer`。
- 光线0—0.08秒向躯干外缘收拢；脚下约1米半径圆环在0.06—0.18秒向内收拢；0.25秒前淡出、0.28秒回收。汇聚效果已移至Cast入口，在本次实际施法进度50%时播放并遵循战斗时钟，取消/失败立即清理，成功释放时一次性效果按原时长自然回收（不截断短施法），蓄力型资产结束；共享释放时停仍为0.10秒，Release通道仍支持原独立时钟。
- 单独查看：运行 `Effects/Skills/Shared/ReleaseAccentFlashPreview.tscn`，点击“播放所选资产”。联动试玩：运行 `Scenes/Previews/ChainSkillPresentationPreview.tscn`，进入战斗后使用1—4。
- 其他技能可在根节点 `Presentation / Cast` 下选择同一 `Cast Effect Scene`，`Cast Effect Anchor` 选 `Caster Feet`，`Cast Effect Start Ratio` 设 `0.5`（0表示开始即播放，默认0以兼容普通技能）；`Release Effect Scene` 另管成功释放视觉，若希望只在所选施法进度出现则不要重复配置；不需要新组件。当前只装配在上述四个连携的预览覆盖中，正式房间和普通技能保持原状。
