# 单场景技能系统使用指南

## 1. 核心概念

每个技能只维护一个场景。技能的名称、索敌关系、施法距离、施法时间、冷却、
AI 使用参数、表现和交付方式都在该场景的 `SkillBase` 根节点配置。

角色只负责：

- 通过 `SkillHostComponent` 装载与请求技能；
- 播放角色施法动画；
- 在动画关键帧调用 `release_action()` 和 `finish_action()`。

技能负责验证目标、交付表现和启动技能冷却。投射物负责自己的飞行、碰撞、
范围、命中和命中特效。

## 2. 文件位置

```text
SkillSystem/
├── 00-Skills/       具体技能场景
├── 01-Core/         SkillBase、SkillHost、Context
├── 02-Delivery/     交付配置与执行器
├── 03-Extensions/   可选条件、消耗、效果
├── 04-Docs/         使用说明
└── 05-Tests/        自动测试
```

同一 `SkillBase` 场景经命中触发子技能的装配方式见
[`TriggeredSkillConfigurationGuide.md`](TriggeredSkillConfigurationGuide.md)。

技能本身的美术特效继续放在 `Effects/Skills`，投射物继续放在
`Item/Projectiles`，角色施法动画由对应角色 Visual 维护。

## 3. 新建技能的标准流程

1. 在 `00-Skills` 下创建技能文件夹。
2. 继承 `01-Core/SkillBase.tscn`。
3. 保存为唯一需要人工维护的 `SkillNameSkill.tscn`。
4. 在根节点 Inspector 依次配置：
   - `Identity`：ID、显示名、图标、AI 优先级；
   - `Targeting`：目标来源、关系、施法距离、释放时复验；
   - `Casting`：角色动作名、基础施法时间、移动和转向许可；
   - `Cooldown`：技能独立冷却；
   - `AI Usage`：自动施法与随机决策延迟；
   - `Presentation`：施法、释放、取消特效；
   - `Delivery`：内嵌交付配置。
5. 在 `Delivery` 字段选择合适类型：
   - `TrackingProjectileDeliveryConfig`：生成并追踪目标的投射物；
   - `ArcProjectileDeliveryConfig`：复用两参数 `launch(target, start_position)` 的弧线投射物；
   - `InstantTargetDeliveryConfig`：立即交付 Effect。默认 `SINGLE` 只影响已解析目标；
     `CASTER_RADIUS` 以施法者为中心，从本次候选快照筛选指定关系和水平半径内的多个
     目标（含 0.05 米容差，按实例去重），并对每个目标复用同一组 Effect；
   - `GroundAreaDeliveryConfig`：在目标位置生成地面区域。
6. 只有技能确实需要特殊规则时，才在根节点下添加
   `SkillConditionBase`、`SkillCostBase` 或 `SkillEffectBase` 子组件。
7. 将技能场景实例拖入单位的 `SkillHost/SkillSocket`。
8. 在该角色的 `CharacterAnimationPlayer` 中制作与
   `action_animation_name` 同名的动画：
   - 唯一一个 `release_action()`：实际交付技能；
   - 一个 `finish_action()`：结束角色动作占用。
9. 运行对应装配测试与运行测试。

## 4. 施法时间与动画

`base_cast_time` 是技能数据，角色还可以通过公开接口提供施法速度倍率。
系统读取动画中的唯一 `release_action()` 时间点，并自动缩放播放速度，使该
关键帧对齐有效施法时间。`base_cast_time = 0` 时，释放关键帧也必须位于 `0`。

动画方法轨道应指向 `CharacterAnimationPlayer`。动画只操作角色 Visual 内部
节点，不应直接移动 Unit 根节点或投射物世界坐标。

## 5. 两个初始示例

### Firebolt

`00-Skills/Firebolt/FireboltSkill.tscn`

- 敌方指定目标；
- `character/firebolt_cast`；
- 0.75 秒基础施法时间；
- 内嵌追踪投射物配置；
- 复用 `Item/Projectiles/FireBall.tscn`；
- 投射物自行管理飞行、碰撞、爆炸和命中。

### HolyLight

`00-Skills/HolyLight/HolyLightSkill.tscn`

- 自动选择候选列表中生命比例最低的友方；
- 内嵌目标瞬发配置；
- `HealthChangeSkillEffect` 直接子节点恢复 25 点生命；
- 释放表现使用金白色 HolyLight 特效。

### GuardianTaunt（施法者中心范围组合示例）

`00-Skills/GuardianTaunt/GuardianTauntSkill.tscn`

- 同样继承 `RangedSkillTemplate`：模板只提供"动画驱动的外部动作入口"骨架，
  并不限定技能必须远程；近战触发、范围效果或纯增益技能都可以使用它；
- 触发目标保持 Guardian 的 0.8 米近战施法距离（`cast_range` 只约束触发目标，
  不会把范围效果半径或 AI 站位拉远）；
- 内嵌 `InstantTargetDeliveryConfig` 且 `target_collection_mode = CASTER_RADIUS`、
  `effect_radius = 5.0`、`affected_relations = HOSTILE`：以 Guardian 自身为圆心，
  从本次候选快照收集水平 5 米内的全部有效敌方单位；
- `ThreatChangeSkillEffect` 直接子节点对每个目标提交固定 200 点
  `ThreatEvent.Kind.SKILL_BONUS` 仇恨：固定值不是强制目标，敌人是否切换目标
  仍完全由既有仇恨值、当前目标保持和挑战者接管倍率决定；
- 动画使用盾牌库的 `basic_cast_1`（无 Hitbox、无攻击位移的通用施法动画）。

## 6. 注意事项

### 角色技能槽配置

在角色源场景中打开 `SkillHost`。先将技能 `.tscn` 实例化为其 `SkillSocket`
的直接子节点，再在 `Skill Slots` 分组中把该技能节点拖入 `Regular Skills`
数组。默认有两个常规槽，可留空或扩充；数组下标就是技能栏槽号。`Finisher
Skill` 是独立的可空终结技槽，当前角色尚未配置终结技，也没有爆发执行器。

Host 自动注册 `SkillSocket` 下的技能；注册表示技能被 Host 管理，只有装入
有效常规槽才会被普通 AI 选择或通过 `request_skill()` 明确请求。普通 AI
继续根据技能自己的 `automatic_cast_enabled`、Condition、冷却和 `ai_priority`
决定何时释放；相同优先级仍按技能注册顺序选择。未装备技能和终结技不会
影响日常站位距离。正在施放的技能仍以自身距离为准。

`request_finisher()` 仅请求已装备的终结技，继续遵守原有目标、条件、动作
占用及冷却合法性。本阶段只提供入口，不执行连击评分或冷却豁免。策划
无需为普通爆发另建技能实例：未来同一常规技能可在连击中重复选择，仍
共用其运行时状态和冷却。

空槽合法。重复引用同一技能时，前面的常规槽生效；终结槽与常规槽冲突
时常规槽生效。跨角色引用、非 `SkillSocket` 子节点、未注册引用均无效。
Inspector 的配置警告会指出需修复的槽位。本阶段只支持编辑器装配，
不提供战斗中换装。

### 条件适用范围

条件组件作为技能根节点的直接子节点挂载。每个 `SkillConditionBase` 的 Inspector
提供“仅自动施放”（默认）和“所有施放”两种适用范围。
前者只限制 AI 自主请求；后者同时约束玩家、队伍指令和脚本的显式请求。
多个适用于当前请求的条件必须全部通过；跳过软条件不会跳过目标、冷却或消耗检查。

`SkillHost.request_best_skill()` 自动标记 `AI_AUTOMATIC`；`request_skill()` 默认
标记 `EXPLICIT`。直接构造 `SkillContext` 的自主决策调用方也必须设置
`request_source = SkillContext.RequestSource.AI_AUTOMATIC`。
请求来源与 `explicit_target_requested` 独立，后者只控制目标解析方式。
只有 `AI_AUTOMATIC` 请求会在成功释放后结算 AI 犹豫时间；`EXPLICIT`
请求直接开始技能自身冷却，避免玩家或队伍指令被 AI 决策节奏延迟。

可复用组件 `res://SkillSystem/03-Extensions/Conditions/TargetHealthCondition.tscn`
检查已选中技能目标的生命比例。拖入技能根节点下后，在其 Inspector 设置
`Health Threshold Percent`（百分比，0～100）：目标生命必须严格低于该值才通过。
HolyLight 已挂载此组件，默认 100%，表示受伤才自动治疗；默认适用范围为“仅自动施放”。
例如设为 70 时，生命等于或高于 70% 不通过。该组件不更换现有选中的目标。

`GuardianTauntNeededCondition.tscn` 是 Guardian 群体嘲讽的专用自动施放条件，
没有额外 Inspector 参数。它直接复用父技能 `CASTER_RADIUS` Delivery 的作用半径；
范围内至少一个敌人锁定了 Guardian 之外的有效友方时通过。玩家与 AI 友方等价，
敌人已经锁定 Guardian、没有锁定目标、锁定目标已死亡或敌人在范围外时均不通过。

Guardian 嘲讽继续复用盾牌武器的通用 `basic_cast_1` 动作，并在动作的
`release_action` 标记处生成 `GuardianTauntReleaseEffect.tscn`。特效锚定施法者脚下，
以0.5秒橙红冲击环、中心爆发和一次性粒子表达瞬时5米范围；视觉消失不代表仇恨被移除。

- 不再为每个技能维护独立 Definition `.tres` 和 Delivery `.tscn`。
- `DeliveryConfig` 应保存在技能场景内部，不要另存为第二份人工配置资产。
- 投射物发射必须使用动作控制器提供的最新世界 `Transform3D`，不得从技能
  本地坐标推导，否则会再次出现从世界原点发射的问题。
- 技能冷却只在成功交付后启动；配置错误、目标失效或效果接口缺失默认不进入冷却。
- AI 的普通攻击与技能共用角色层共享动作冷却；技能自身冷却独立计时。
- 正式 `.tres`、`.res` 必须通过 Godot `ResourceSaver` 保存并验证有效 UID。
- 添加单位到 `TestScene.tscn` 必须由使用者手动完成。
