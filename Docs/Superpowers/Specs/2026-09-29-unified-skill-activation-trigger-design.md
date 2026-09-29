# 统一技能激活与触发连锁设计

状态：设计稿，待用户审阅；不授权代码实施。

本文承接《2026-09-29-reusable-projectile-chain-design.md》，以本次讨论确认的“子技能仍是 `SkillBase` 实例”为准。旧稿中的独立碎片命中 Profile、专用生成碎片效果和“子碎片不是技能”等结论不再作为实施依据；其既有投射物调查与实际伤害结果分析仍可参考。

## 1. 目标与不变约束

- 一个技能 `.tscn` 始终是同一种 `SkillBase` 场景定义。放入角色常规槽、或由另一个技能的 `TriggerSkillEffect` 引用时，实例不同；不在技能场景上配置“主动／触发”类型。
- 请求入口决定本次执行方式：常规施放需要角色动作及动画 Release；命中后触发无需角色再播放一次动作，但走同一个技能目标验证、数值交付和效果系统。
- 技能实例各自维护已有的冷却、消耗、条件和 Delivery。触发内容将冷却与资源消耗配置为 0，不增加“父技能支付”“触发技能免冷却”等例外规则。若把非零消耗技能配置为子技能，它按自身配置尝试支付；失败则本次触发失败。每次触发都新建实例，因此该实例的非零冷却即使正常开始，也不能限制下一次新实例；这正是触发内容应配置为 0 冷却的原因。
- 不改普通攻击、移动或闪避体系；不改 `Scenes/TestScene.tscn` 中任何单位实例；不为弓手技能写专用的分裂算法。

## 2. 现状与方案取舍

目前 AI 通过 `AllyBehaviorStateMachine` 请求 `SkillHost.request_best_skill()`；Host 选已装备技能并直接调用 `SkillBase.request_skill(context)`。技能发出的 `action_requested` 是向动作层提出施法动作；动画 Release 最终回调 `SkillBase.release_action()`，再由 `SkillDeliveryRunner.execute()` 交付。信号是事件与协调，不是所有来源共用的激活入口。Host 的显式 `request_skill()` 只接受常规槽技能。行为层目前还会查找技能的 `MeleeAction` 子节点，属于需要收紧的具体组件耦合。

比较过的方案：

| 方案 | 收益 | 问题 | 结论 |
| --- | --- | --- | --- |
| 独立 TriggeredSkillBase／碎片 Profile 管线 | 主流程改动少 | 重复技能属性、效果和交付配置，策划要维护两套对象 | 不采用 |
| 把所有 AI、玩家输入、Host 与动画链一次性重写为消息总线 | 入口形式统一 | 影响范围过大，现有可用 AI 链和测试回归风险高 | 不采用 |
| 保留 Host 与角色动作链，在 `SkillBase` 补共用激活契约与共用交付核心 | 同一个 `.tscn` 可复用，改动集中 | 需要明确触发来源、投射物命中结果和实例生命周期 | 采用 |

## 3. 职责与接口

### 3.1 `SkillHost` 和角色动作层

`SkillHost` 继续管理角色装备槽、AI 自动选技、常规请求资格、全局冷却与当前角色动作。AI 行为层仍只决定“何时尝试施放”，不识别爆裂箭或碎片。普通请求从 Host 进入 `SkillBase`；已有面向动作层的 `action_requested`、接近、取消、完成信号保持其职责。

为去掉行为层反查 `MeleeAction` 的特例，技能动作请求应携带动作系统必需的只读 payload，或通过技能公开的通用动作数据接口提供；行为层不再根据子节点名称认识技能类型。此项仅收紧现有边界，不重写 AI 决策与动画系统。

### 3.2 `SkillBase` 的统一激活契约

使用 `SkillContext` 承载一次请求，增加最少的运行时数据：执行方式（角色动作／直接触发）与本次世界发射变换。执行方式不是技能类型，也不是 Inspector 常驻开关。普通请求仍由 Host 构造上下文，按现有目标、软条件、成本预检进入排队和动作流程；动画 Release 再完成交付。触发 Effect 为每个选中的目标新建同一技能场景的独立实例，配置原施法者与世界交付父节点，再向该实例提交直接触发请求。

两个入口在完成各自必要的动作步骤后，调用同一内部“提交消耗、释放表现、执行 Delivery 与 Effects、按技能配置启动冷却”的交付核心。直接触发不伪造 `ACTION_REQUESTED`／`CASTING` 动画状态，也不向角色动作层申请动作；但不会绕开子技能自己的目标有效性、条件、消耗、Delivery 配置检查。被触发技能的 `request_source` 视为现有的 `EXPLICIT`（脚本明确请求），不冒充父技能的 `AI_AUTOMATIC`；需要约束显式触发的条件应配置为 `ALL_REQUESTS`。

普通技能保持现有“以施法者位置判断施法距离”。触发技能的发射点来自父命中的世界位置，目标距离据该发射点判断，而不是据远处的原施法者位置判断。原施法者身份仍用于阵营、数值和仇恨结算。两种距离原点只由本次请求上下文决定，不复制两套目标算法。

### 3.3 `TriggerSkillEffect` 与附近目标策略

`TriggerSkillEffect` 是技能根节点下可复用的 `SkillEffectBase` 子节点。Inspector 只需配置：引用的子技能 `PackedScene`、触发条件、附近目标半径、最大数量、目标关系和是否排除本次受击者。数量是参数，不写死“三个敌人”。该 Effect 只读取当前命中的结果、在触发时取得候选并选目标、为每个目标创建一个子技能实例，然后提交触发请求；不直接写子技能的伤害、弹道或特效代码。

附近筛选在命中时对命中点进行一次物理空间范围查询，再复用 `TargetResolver` 的关系／存活／可选取校验；筛选以命中点为圆心、按水平距离稳定排序、单次选取去重。不能直接复用 Host 的 `get_perceived_candidates()`：该接口始终按**施法者**的索敌半径过滤，可能漏掉远处命中点附近的敌人。查询不到合法候选时安全不触发，不做全场景逐帧扫描。空间查询的碰撞层与垂直容差须以现有单位碰撞配置为准，并用不同高度的命中测试验证。

同一个父技能可以挂多个 Effect；子技能也可以挂自己的 Effect。连锁终止由内容装配决定：末段技能不再配置触发子技能。配置验证应拒绝直接自引用与可识别的循环引用，以免错误配置造成无限生成；这是防护检查，不是玩法层数规则。

## 4. 爆裂箭实例的数据流

```text
弓手技能槽：爆裂箭技能实例 A
  AI → SkillHost → A 的普通激活 → 角色动画 Release
  → A 的 Arc 投射物抵达目标 → A 的伤害 Effect 结算实际扣血
  → A 的 TriggerSkillEffect：仅实际伤害 > 0 时，选附近最多 3 名敌人
  → 每个目标创建独立的碎片技能实例 B1～B3，并从命中点触发
  → 各 B 发射自己的碎片投射物、结算自己的伤害
  → B 的 TriggerSkillEffect：受击者命中前有灼烧且实际伤害 > 0 时，
     选其附近最多 3 名敌人
  → 每个目标创建独立的末段技能实例 C；C 即时交付额外伤害，不再触发
```

这里 A、B、C 均继承同一个 `SkillBase.tscn`，只因 Delivery、Effects 和表现配置不同而形成不同内容。B、C 不在角色常规槽中，也不参与 AI 自动选技。一个技能场景若同时在槽位与 Trigger Effect 中使用，也分别实例化，运行状态互不覆盖。最多三个 B 和九个 C 是此例 Inspector 数值产生的上限，不是框架硬编码；实际数量可能因目标、状态或伤害结果减少。

## 5. 命中结果、投射物适配与生命周期

当前 `TrackingArcProjectile`／`Arrow.tscn` 使用 `launch(target, start_position)` 和 `projectile_hit`，而现有技能追踪投射物 Delivery 使用另一套八参数 `launch`／`projectile_impacted` 契约。需要为前者在 Skill Delivery 层补通用适配，不改弓箭普攻的既有使用方式。投射物负责飞行和报告命中，技能 Delivery 在命中时依序执行其 Effects。

现有 `HealthChangeSkillEffect` 的伤害路径调用统一 `CombatValueResolver`，但丢弃实际扣血返回值；`apply()` 返回成功并不代表造成正数伤害。增加每目标的运行时命中结果，供后续 Effect 读取实际扣血量及必要的命中前状态快照。主箭与碎片的触发判断只依据本次直接命中结果，不监听全局伤害事件，也不把治疗或零伤害误算为触发。此运行时结果不作为正式 `.tres` 配置资源。

每个触发实例保留至自身 Delivery 完成／失败或投射物结束；不能在“技能发射成功”时立即释放实例，否则在途投射物的 Effect 节点会丢失。退出时断开信号并释放实例；一个子实例失败只结束该分支，不倒退已经释放的父技能或取消其他碎片。根技能当前单个 Runner 的 `_busy` 约束不能阻止其他独立技能实例并行；同一个常规槽技能连续释放时是否需要独立交付会话，按现有重复施放回归测试保证。

## 6. 资源装配和策划配置

```text
SkillSystem/00-Skills/ExplosiveArrow/ExplosiveArrowSkill.tscn
  SkillBase：装入 Archer 常规技能槽；配置常规冷却、目标与 AI 使用
  Delivery：Arc 投射物，引用主箭场景
  DamageEffect：主箭伤害
  TriggerSkillEffect：要求本次实际伤害 > 0；半径、数量 = 3；
    child_skill_scene = ExplosiveFragmentSkill.tscn

SkillSystem/00-Skills/ExplosiveFragment/ExplosiveFragmentSkill.tscn
  SkillBase：冷却 = 0；无资源消耗；不装角色槽
  Delivery：Arc 投射物，引用碎片场景
  DamageEffect：较低的碎片伤害
  TriggerSkillEffect：要求命中前灼烧且本次实际伤害 > 0；
    半径、数量 = 3；child_skill_scene = BurningSplashSkill.tscn

SkillSystem/00-Skills/BurningSplash/BurningSplashSkill.tscn
  SkillBase：冷却 = 0；无资源消耗；不装角色槽
  Delivery：现有瞬时目标交付
  DamageEffect：末段追加伤害；无进一步 TriggerSkillEffect

Item/Projectiles/…：主箭和碎片场景，复用现有弧线投射物脚本；只区分视觉／弹道参数
```

三种内容技能是用于本例的三个 `.tscn`，不是三个新技能父类。`TriggerSkillEffect` 是通用组件，附近筛选和命中结果也是通用能力。以后做毒裂箭、治疗弹射等同构效果时，只需在这套已交付规则范围内改关系、条件、数值、子技能引用与表现；全新弹道或判定类型仍需新增通用规则。正式 `.tres`／`.res` 如有新增，必须经 Godot 保存并验证 UID、强类型与 Inspector Quick Load；不能只写文本文件。

## 7. 性能边界与验证

第一版不做对象池。每条碎片一个技能实例使状态、Runner 和清理边界明确；当前基础 `SkillBase.tscn` 只有根节点、Runner 与 RuntimeEffects 三个节点，是否成为瓶颈需以真实场景测量，不凭实例数量推断。目标筛选仅在命中时发生，数量由配置上限约束，末段使用瞬时交付。实例与投射物各自正确释放，优先防止驻留和重复回调。

测试覆盖：普通 AI 技能现有回归、显式常规请求、触发实例不占角色动作、同一场景的槽位与触发实例互不污染、0／1／3／多于 3 个附近目标、无／有灼烧、零实际伤害、目标飞行中死亡、多个碎片同时命中、子分支失败、连续爆发与场景卸载。另在多轮连锁压力场景记录峰值活跃技能实例数、投射物数、帧耗时及释放后的节点数；只有测出创建／销毁或效果热点时才考虑池化或视觉简化。不得自动向 `Scenes/TestScene.tscn` 添加单位。

本稿获批后再编写实施计划；未实施前，上述触发入口、Arc 技能交付及命中结果均不是现有代码能力。
