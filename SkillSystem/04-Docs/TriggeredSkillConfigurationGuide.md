# 通用触发技能配置指南

## 这套装配解决什么

技能场景只有一种根类型：`SkillBase`。放在角色 `SkillHost/SkillSocket` 的实例由角色动作和动画释放；放在另一个技能的 `TriggerSkillEffect.child_skill_scene` 中的同一场景定义，会在命中时新建独立实例并直接激活。来源决定执行方式，技能场景本身没有“主动／触发”类别开关。

普通与触发实例都会检查自己的目标、条件、成本、冷却、交付和效果。触发内容应在自身根节点把 `Skill Cooldown` 设为 `0`、不挂消耗组件；父技能不替子技能支付。新建触发实例的非零冷却只会约束该实例，不能约束下一次新实例，所以不要把它当作跨次触发限流。

## 策划从 Inspector 配置一条连锁

1. 在 `SkillSystem/00-Skills` 下继承 `00-Templates/RangedSkillTemplate.tscn`，建立父技能和子技能的 `.tscn`。模板间接继承唯一的 `SkillBase.tscn`；名称中的 Ranged 指动画入口，不限制子技能的 Delivery 类型。
2. 父技能根节点的 `Delivery` 选择交付配置。若使用 `Item/Projectiles/TrackingArcProjectile.gd` 及其 `launch(target, start_position)` / `projectile_hit` 契约，就用内嵌 `ArcProjectileDeliveryConfig` 并引用投射物场景；弹道时长、弧高与视觉仍在投射物场景里调。瞬发末段使用现有 `InstantTargetDeliveryConfig.SINGLE`。
3. 把 `HealthChangeSkillEffect` 作为技能根节点的直接子节点，配置伤害或治疗。后续 Effect 能从本目标的 `SkillDeliveryResult.current_hit` 读取实际扣血、实际治疗和命中前状态快照。
4. 在伤害 Effect **之后**添加 `TriggerSkillEffect` 直接子节点。配置 `Child Skill Scene`、`Radius M`（米）、`Max Targets`、`Relation Flags`、`Exclude Hit Target`；`Require Positive Damage` 默认开启。可选填 `Required Status Id`，空值不检查状态。目标查询发生在命中时，以命中世界位置为中心，与施法者的 AI 索敌半径无关。
5. 子技能自身继续配置 Delivery、Effects 与表现；它可以再挂同一个 `TriggerSkillEffect` 来延长连锁。只在角色常规技能槽装备需要由角色主动施放的技能；子技能只填进父技能的 `Child Skill Scene`，不要为同一连锁额外占槽。

`TriggerSkillEffect` 只在本次命中实际伤害大于零时分裂；若配置了状态 ID，检查的是该目标**本次效果开始前**的状态，同次命中新施加的状态不计入。每个候选目标都创建不同的子技能实例。子技能的条件、消耗或交付失败只跳过该分支，不撤销父技能已经结算的伤害，也不停止其他分支。飞行中的子实例会保留至命中、失败或场景退出。场景自引用和祖先循环会被拦截。

## 已交付样例：爆裂箭

| 内容 | 文件 | 配置要点 |
| --- | --- | --- |
| 主箭 A | `00-Skills/ExplosiveArrow/ExplosiveArrowSkill.tscn` | 装 Archer 常规槽；Arc 主箭、伤害、最多 3 个附近目标触发碎片；冷却 7 秒 |
| 碎片 B | `00-Skills/ExplosiveFragment/ExplosiveFragmentSkill.tscn` | Arc 碎片、较低伤害；实际伤害为正且目标命中前有 `burning` 时，再向附近最多 3 个目标触发末段 |
| 末段 C | `00-Skills/BurningSplash/BurningSplashSkill.tscn` | 瞬发追加伤害，无后续 Trigger；冷却 0 |
| 灼烧来源 | `00-Skills/Firebolt/FireboltSkill.tscn` | 伤害后由通用 `ApplyNamedStatusSkillEffect` 赋予 4 秒 `burning` |

主箭/碎片的投射物场景分别在 `Item/Projectiles/ExplosiveArrow.tscn` 与 `ExplosiveFragment.tscn`，共用既有弧线投射物脚本，只区分颜色、尺寸与飞行参数。Archer 的 `SkillHost` 第一个常规槽装 A，第二槽目前为空；Bow 动画库有一个 `basic_cast_1`，其唯一 `release_action` 标记供普通技能释放，普攻继续用 `basic_attack_1`。

这里的 `3` 是样例 Inspector 参数，不是框架规则；改 `Max Targets` 可得不同扇出。灼烧 ID 也只是本例配置。未来做毒裂箭、治疗弹射或其他同构内容，可复用 `SkillBase`、Arc/Instant Delivery、通用状态、命中结果、附近查询和 Trigger Effect，只需改参数、技能引用、目标关系与表现。全新弹道或全新命中规则才需要新增通用组件，而非复制一套子技能基类。

## 验证与场景边界

运行 `SkillSystem/05-Tests/ExplosiveArrowAssemblyTest.gd`、`ExplosiveArrowChainIntegrationTest.gd` 和 `ExplosiveArrowStressTest.gd`。压力测试打印活跃技能实例数、在途投射物数和测试环境帧间耗时；这些是观察值，不是预设性能预算。新增正式 `.tres` / `.res` 时仍须经 Godot 保存、验证有效 UID 和 Inspector 类型索引。不要由工具自动向 `Scenes/TestScene.tscn` 添加单位；如要手动体验，可在编辑器里由你决定现有关卡单位的摆放与技能槽配置。
