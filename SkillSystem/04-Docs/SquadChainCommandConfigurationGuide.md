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

测试入口：`UnitSystem/Tests/SquadChainInputDisplayTest.gd`及阶段二新增7个执行/事务/生命周期测试。验收数据见`Docs/Superpowers/Plans/2026-10-13-burst-combo-stage-2-validation.md`。
