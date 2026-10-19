# 2026-10-18 基础战斗数值试调

> 最新调整：伤害型连携现为对应普通技能的1.2倍，取代首轮高倍率；治疗连携300不变。旧72.24%与实战样本仅作首轮历史记录。

## 范围与定位

本轮是已有配置调校，不新增技能执行体系、被动规则、全局伤害倍率或成长系统。
以当前五人队和现有哥布林为参照；弓手单次命中在上一版建议上降低30%，不增加箭数或分裂次数；炎爆65。
先形成普攻弱、自动技能持续有效、连携更强的档次。下列数值是首轮试玩基线，不是最终平衡，也未证明战力优势精确为50%。

## 配置入口

- 单位：UnitSystem/Player/Hero/Hero.tscn；UnitSystem/AI/Ally/Units/；UnitSystem/AI/Enemy/Units/。根节点Health和Combat Stats。
- 普攻：Item/Weapon/各武器Data.tres的Basic Attack。不要修改投射物模型来配置伤害。
- 常规/连携/触发技能：SkillSystem/00-Skills/的技能场景。DamageEffect/HealEffect配置base_amount和power_ratio。
- 盾击还有MeleeAction伤害：它独立结算命中盒中的目标；单体DamageEffect与此窗口不共享去重，原目标可能吃两笔。不可漏算。
- 专注：TestCombatRoom根下SquadFocusComponent，Focus Gain Difficulty=10，预览继承此值。组件本身默认5不改，其他独立测试/关卡不会被悄悄改变。
- 评分：SquadChainRoundPreview根下SquadChainRoundController，用户最新Score Difficulty=1.5、H0=20保留，D0=2000。Damage Interval Seconds仍2.5秒。

不向Scenes/TestScene.tscn添加或修改单位实例。源场景修改自然影响其未覆盖的实例；TestCombatRoom保留既有摆放与其他行为覆盖。

## 单位基线

| 单位 | 生命 | 攻击 | 防御 |
| --- | ---: | ---: | ---: |
| Hero | 300 | 12 | 源8，TestCombatRoom既有覆盖10保留 |
| Guardian | 650 | 8 | 35 |
| Archer | 240 | 15 | 3 |
| Caster | 220 | 16 | 2 |
| Priest | 260 | 11 | 5 |
| GoblinWarrior | 500 | 6 | 2 |
| GoblinArcher | 350 | 4 | 1 |

Saber源场景不调整；它共用玩家铁剑，因此普攻随武器变弱。现有自动AI策略不改：Caster/Priest在自动技能启用时是技能主导，并非五人都持续普攻。

## 普攻配置与武器隔离

伤害=（base+attack×ratio）×100/(100+目标防御)，此处预算不含武器随机浮动。

| 武器 | base | ratio | 对应角色减伤前单次伤害 |
| --- | ---: | ---: | ---: |
| Sword/IronSwordData.tres | 3 | 0.25 | Hero 6 |
| Shield/IronShieldData.tres | 2 | 0.25 | Guardian 4 |
| Bow/BowData.tres | 1.4 | 0.28 | Archer 5.6 |
| MagicGlobe/MagicGlobeData.tres | 2 | 0.25 | Caster后备普攻6 |
| Staff/StaffData.tres | 2 | 0.25 | Priest后备普攻4.75 |
| Sword/GoblinSwordData.tres | 5 | 1 | GoblinWarrior 11 |
| Bow/GoblinBowData.tres | 3 | 1 | GoblinArcher 7 |

唯一新正式资源是GoblinSwordData.tres：复制原铁剑数据，保留模型/动画/命中配置，只独立保存敌方伤害数据；通过ResourceSaver保存，并验UID/脚本类型/编辑器索引。不是新武器实现脚本。
五份既有友方武器通过MCP资源工具保存，UID保持有效。

## 技能配置

| 场景/节点 | base | ratio | 当前施法者减伤前结果 |
| --- | ---: | ---: | ---: |
| Firebolt/DamageEffect | 24 | 1 | 每目标40 |
| Pyroblast/DamageEffect | 45 | 1.25 | 每目标65 |
| RapidShot/DamageEffect | 6.3 | 0.28 | 每箭10.5，三箭31.5 |
| ExplosiveArrow/DamageEffect | 14 | 0.7 | 主箭24.5 |
| Trig_ExplosiveFragment/DamageEffect | 2.8 | 0.28 | 每片7 |
| Trig_BurningSplash/DamageEffect | 1.4 | 0.14 | 每次3.5 |
| Combo_Firebolt/DamageEffect | 28.8 | 1.2 | 每目标48 |
| Combo_RapidShot/DamageEffect | 7.56 | 0.336 | 每箭12.6，三箭37.8 |
| Combo_GuardianBash/DamageEffect | 14.4 | 1.2 | 原目标24 |
| Combo_GuardianBash/MeleeAction | 19.2 | 1.2 | 盒内每目标28.8；原目标两路命中共52.8 |
| Combo_GreaterHeal/HealEffect | 300 | 0 | 治疗300 |

普通盾击两路24/20保留，普通HolyLight仍38.2、GreaterHeal仍150；普通和连携防御Buff不改，两个不同来源可按已有状态规则同时生效。
GuardianTaunt的ThreatEffect固定仇恨400，仍按既有阈值与衰减，不变成强制锁定。
技能CD、随机等待、AI优先级、范围、箭数、分裂次数、灼烧8秒均不改。普通/连携是独立场景与实例，不自动同步彼此配置。

## 专注与评分

专注收益=实际普通伤害×0.1×5/10，每2000实际普通伤害回100。连携/终结无专注收益，无自然回复。
保留容量100，正式房间初始0、试玩预览初始100。费用仍20起、同轮同角色同技能成功重复每次再加10。
评分公式不改，仅提高当前评分预览的D0：S=[40log2(1+H/20)+60(D/2000)^1.1]×(5/1.5)。
100分只表示资格；不代表100%怪群生命，也不自动补出尚未完成的终结技系统。

## 验证与复现

- Tools/CombatSimulation/CombatBalanceBaselineTest.gd：真实生命扣除/治疗、新武器隔离与UID、正式场景覆盖、完整输出预算。
- Tools/CombatSimulation/RunCombatBalanceComparison.gd：--mode=auto/basic/chain --seconds=45。只修改运行副本，将现有A+B七敌重排作同时接敌，不保存或改TestScene；用真正SceneTree切换确保技能世界绑定。玩家由既有脚本自动追打，并立即恢复can_die=true，不是无敌测量。
- basic模式关闭自动技能，因而治疗也停用；不能用它的死亡时间直接推导普攻伤害强弱。
- 原CombatNumericalSimulator是历史硬编码模型，没有当前连携体系，不用于本轮平衡验收。

### 理想预算（不是AI实战战果）

5近战+2远程总生命3200；火球→连射→火球→连射共100专注。
两次火球均覆盖七敌、两次连射各选一个不同的近战以避免过量伤害时，实际伤害2311.7065，占72.2408%。
这是当前配置的可验证预算。站位分散、死亡目标、弹道和动作占用会降低实际值。

### 首轮真实AI对照样本

运行副本保留当前AI与导航，自动驱动玩家，非人类游玩胜率：

| 模式 | 结果 |
| --- | --- |
| 自动技能+普攻，无连携 | 约57.75秒清场，普通伤害3200；无人死亡；承伤1487.64、治疗1099.4；Guardian剩331.09、Hero剩237.05 |
| 仅普攻，关闭自动技能与治疗 | 约8.63秒玩家死亡，此前造成395.35伤害；这是无治疗且玩家自动贴脸的压力样本，不是正常队伍生存时间 |
| 自动战斗+四次连携输入 | 20秒时剩585.12血（共削掉81.71%）；连携独立伤害982.35（30.70%），普通伤害1632.52；四次均成功释放，费用20/20/30/30，无人死亡 |

四次连携输入时刻为1.0/1.5/3.0/3.5秒，角色依现有动作/接近规则执行，不按输入瞬时强制命中。该样本未完成理想聚怪，不能声称连携自身已实际达到70-80%。
单次样本不用于宣称稳定优势50%；自动战斗清场时间也高于原30-45秒试调目标。用户先体验本轮，不自动继续放大伤害。

### 回归记录

本轮新增行为测试先按新预算观察失败，再落地配置并通过。
首次全量138项：132通过，五项旧配置断言需迁移（嘲讽、火球、武器、单位生命）；另SquadChainCommandTransactionsTest打印PASS后一次原生进程退出异常0xC0000005，后续四次单项复测exit=0，未复现。未据此猜测或修改生产管线；最终全量结果另附。
嘲讽测试将“高于技能仍不接管”的原目标仇恨从250调整为500，仍真实覆盖默认阈值而非删除该验证。
编辑器已打开的WeaponDataInheritanceTest，修改前确认缓冲区等于磁盘；MCP强制编辑后只在确认差异恰为两条预期断言时同步缓冲区。

最终全量回归：138/138通过（全部exit=0），包含新的CombatBalanceBaselineTest；最初退出异常的事务测试也在此次全量运行中正常退出。未将未复现的原生退出异常表述为已定位或修复。完整首轮/最终结果与实战输出存于.superpowers/archives/2026-10-18-combat-balance/verification.json。

资源验证：六个本轮保存的武器资源UID均有效；新GoblinSwordData加载为MeleeWeaponData，编辑器filesystem_cache10登记为Resource/MeleeWeaponData，支持强类型WeaponData字段索引。已有武器UID保留。Godot保存时去除了与父场景相同的冗余覆盖，未改变这些字段的有效值。所有项目编辑均使用Godot MCP Pro。


## 2026-10-18 后续试玩：伤害型连携下调至普通技能1.2倍

用户实测尚未完成一套连携就已击杀敌人，本次仅调整三个伤害型连携自身配置。基础伤害与攻击力系数都乘普通版的1.2，保证不同攻击力/防御下保持同一伤害比例，不新增通用倍率字段，不跨技能运行时同步参数。火球150→48，连射每箭42→12.6（三箭126→37.8），盾击主目标两路132→52.8、范围72→28.8。普通技能/治疗300/专注费用/范围/箭数/施法/AI机制均不改；评分难度已由用户另调为1.5，本轮保留，H0=20/D0=2000/窗口2.5也不改。

当前满专注理想七敌预算为734.8049实际伤害，约占3200总生命的22.9627%，不再沿用旧70-80%验收目标。旧实战结果不是此次1.2倍版本的测量。基础测试增加0/10/60攻击力与0/35/100防御的真实扣血比例校验，盾击两路分别覆盖；治疗测试每笔独立制造足够缺口，避免降伤后缺血不足造成过量治疗截断。

1.2倍版本最终回归：138/138通过，所有测试exit=0；真实效果扣血比例与盾击动作路径均验证通过。原70-80%预算断言已改为新配置的734.8049伤害预算。验收归档：.superpowers/archives/2026-10-18-chain-damage-1p2/verification.json。
