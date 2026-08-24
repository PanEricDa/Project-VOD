# SkillSystem 单场景配置重构设计

日期：2026-07-28

## 1. 设计目标

本次重构面向整个 `SkillBase` 框架，而不是只修正 Firebolt。

核心目标：

- 每个技能只维护一个权威资产：一个继承自 `SkillBase.tscn` 的技能场景。
- 设计师打开技能场景、选中根节点后，可以在同一个 Inspector 中完成绝大部分配置。
- 不再要求同时维护 `Skill.tscn`、`SkillDefinition.tres` 和 `SkillDelivery.tscn`。
- 合并只表达默认行为的 Policy，减少空实现、占位资源和重复参数。
- 保留目标选择、施法条件、技能消耗、Delivery 和最终效果的开放接口。
- 技能逻辑不直接依赖 `AllyBase`、具体 AI、玩家控制器或某个角色节点层级。
- 角色施法动画和技能交付继续解耦，并通过统一动作事件连接。
- 先并行验证新实现，再迁移现有 Firebolt 和 HolyLight，避免破坏当前可运行内容。

本次设计不改变以下核心规则：

- 公共冷却与技能冷却独立计时。
- 技能冷却只在技能成功释放、Delivery 成功启动后开始。
- 目标可以在释放时进行最终复验。
- 投射物负责自身飞行、碰撞、命中范围、Gameplay Payload 与命中特效。
- 技能系统负责施放请求、施法状态和启动 Delivery，不替代投射物的命中逻辑。

## 2. 当前架构的问题

当前一个技能通常被拆分为：

```text
Skill.tscn
├─ SkillDefinition.tres
│  ├─ Condition
│  ├─ TargetSelector
│  ├─ DecisionPolicy
│  ├─ Cost
│  └─ CastPresentation
└─ SkillDelivery.tscn
   ├─ Trajectory
   ├─ CollisionPolicy
   ├─ ImpactSelector
   ├─ Payloads
   └─ Delivery Presentations
```

主要问题：

- 一个技能存在多个需要人工维护的入口。
- 目标关系、距离和选择器之间存在跨资源配置。
- `AlwaysCondition`、`NoSkillCost` 等资源只表示“没有额外限制”，却成为必填概念。
- Delivery 被拆成多层策略，配置复杂度超过当前项目实际需要。
- Skill 自己维护 AnimationPlayer 和施法计时，同时角色也有动画系统，职责重复。
- 单独的 CastOrigin 和 DeliverySocket 容易脱离角色世界变换，已经产生过从世界原点发射的问题。
- UI、AI 和运行逻辑读取同一技能时，需要在 Scene 与 Definition 之间来回查找。

## 3. 单一权威资产

每个具体技能只维护一个场景：

```text
FireboltSkill.tscn
HolyLightSkill.tscn
```

场景根节点保存技能的身份、目标、施法、冷却、AI 提示、表现和 Delivery 配置。

不再为每个技能创建：

```text
FireboltSkillDefinition.tres
FireboltDelivery.tscn
HolyLightSkillDefinition.tres
HolyLightDelivery.tscn
```

Godot 的 `.tscn` 本身是 `PackedScene` Resource，可以被 UI、技能栏、装备系统和未来的技能目录引用，因此不需要复制一份 `.tres` 才能被资源系统读取。

第一版 UI 只从 SkillHost 中已经装载的技能实例读取信息，不在本轮重构中新增全技能 Catalog。未来需要展示尚未装载的完整技能列表时，可以生成 `skill_id → PackedScene` 的派生索引；该索引不得保存第二份名称、图标、冷却或参数数据。

## 4. SkillBase 场景结构

```text
SkillBase
├─ DeliveryRunner
└─ RuntimeEffects
```

### SkillBase

负责：

- 保存设计师常用配置。
- 接收和验证技能请求。
- 保存本次施法上下文。
- 请求角色动作系统播放施法动画。
- 响应角色动画发出的释放与结束事件。
- 管理技能自身冷却。
- 收集同场景内的可选 Condition、Cost 和 Effect 组件。

### DeliveryRunner

负责：

- 接收 SkillBase 传入的 `SkillContext` 和 `SkillDeliveryConfig`。
- 根据 Delivery 类型执行瞬时交付、投射物交付或地面区域交付。
- 报告 Delivery 是否成功启动、完成或失败。

它不保存某个具体技能的参数，不要求设计师填写 NodePath。

### RuntimeEffects

负责挂载施法、释放和取消阶段产生的临时表现实例。

角色动作动画不放在这里；角色动画仍由角色 Visual 中的 AnimationPlayer 播放。

### 固定内部引用

`DeliveryRunner` 和 `RuntimeEffects` 是 SkillBase 的固定内部节点。SkillBase 通过固定节点名直接取得它们，不向 Inspector 暴露以下路径：

```text
delivery_runner_path
runtime_effects_path
cast_origin_path
delivery_socket_path
animation_player_path
```

技能发射点由角色动作上下文提供，不能由 Skill 场景内的本地 Marker3D 推断世界位置。

## 5. 根节点 Inspector

### 5.1 Identity

```text
skill_id: StringName
display_name: String
icon: Texture2D
ai_priority: int
```

`skill_id` 是存档、技能目录和运行时识别技能的稳定标识。

### 5.2 Targeting

```text
target_source: TargetSource
target_relation: TargetRelation
cast_range: float
require_targetable: bool
validate_target_on_release: bool
```

`TargetSource` 第一版支持：

```text
PROVIDED
SELF
AUTO_NEAREST
```

通用目标规则直接由 SkillBase 处理，不再为每个技能创建 `ProvidedTargetSelector` 或 `NearestValidTargetSelector` Resource。

距离容差使用 SkillSystem 的统一内部默认值。只有确实需要特殊容差的技能，才通过 Advanced 覆盖，不作为普通技能的常用字段。

复杂的目标评分、扇形筛选或特殊队友优先级属于未来可选 Targeting 组件，不加入第一版根节点字段。

### 5.3 Casting

```text
action_animation_name: StringName
base_cast_time: float
can_move_while_casting: bool
can_turn_while_casting: bool
cancel_when_target_invalid: bool
```

`base_cast_time` 表示从动作开始到 `release_action()` 的游戏规则时间，不表示整个动画长度。

角色动作系统通过施法者公开接口读取施法速度倍率：

```gdscript
get_cast_speed_multiplier() -> float
```

施法者未实现该接口时统一回退为 `1.0`。非法、非有限或小于等于零的返回值视为配置错误，不开始施法。

### 5.4 Cooldown

```text
skill_cooldown: float
cooldown_on_failed_release: bool
```

技能冷却在 Delivery 成功启动后开始。

公共冷却继续由角色动作调度层或 SkillHost 管理，不移动到 SkillBase 内，也不与技能冷却合并。

### 5.5 AI Usage

```text
automatic_cast_enabled: bool
decision_delay_min: float
decision_delay_max: float
extra_hesitation_chance: float
extra_hesitation_min: float
extra_hesitation_max: float
```

这些字段只是技能向 AI 提供的使用提示。

多个技能之间如何选择、何时退回普通攻击、公共冷却和状态优先级仍由 AI 行为状态机管理。`DecisionPolicy` 不再作为每个技能的独立 Resource。

### 5.6 Presentation

```text
cast_effect_scene: PackedScene
release_effect_scene: PackedScene
cancel_effect_scene: PackedScene
```

这些表现由 SkillBase 在角色动作系统提供的世界发射变换上生成。

动作确认开始时传入一次当前世界发射变换，用于 Cast 表现；`release_action()` 时重新读取并传入最新世界发射变换，用于 Release 表现和 Delivery。SkillBase 不缓存角色节点路径，也不从自身场景变换推导发射位置。

投射物的飞行表现和命中特效由投射物场景维护，不在 SkillBase 中重复配置。

### 5.7 Delivery

```text
delivery: SkillDeliveryConfig
```

`delivery` 是强类型内嵌 Resource，默认保存为技能 `.tscn` 中的 SubResource，不要求创建额外 `.tres`。

## 6. Delivery 设计

### 6.1 必要的类型拆分

Delivery 不再按技能创建独立场景，但不同交付算法仍保留少量强类型配置：

```text
SkillDeliveryConfig
├─ TrackingProjectileDeliveryConfig
├─ InstantTargetDeliveryConfig
└─ GroundAreaDeliveryConfig
```

这种拆分用于避免一个大型 Resource 同时显示投射物、瞬发和地面区域的所有无关参数。

每个具体技能只配置一个内嵌 Delivery Resource。

### 6.2 Tracking Projectile

第一版参数：

```text
projectile_scene: PackedScene
projectile_speed: float
turn_speed_degrees: float
maximum_lifetime: float
aim_height: float
impact_radius: float
```

DeliveryRunner 只负责：

- 使用动作上下文提供的发射变换。
- 实例化投射物。
- 传入施法者、目标和发射参数。
- 监听投射物的完成或失败信号。

投射物负责：

- 飞行和追踪。
- 物理碰撞或算法命中。
- 单体或范围目标选择。
- 伤害、治疗、Buff 或其他 Payload。
- 飞行和命中特效。

### 6.3 Instant Target

直接将当前有效目标交给同场景内的 Skill Effect 组件。

适用于 HolyLight 等无需飞行过程的技能。

### 6.4 Ground Area

在目标位置或指定落点生成区域场景。区域场景负责自身持续时间、范围检测和效果应用。

第一轮实现只建立通用接口，不扩展复杂区域规则。

## 7. Condition、Cost 与 Effect

### Condition

SkillBase 内建以下通用检查：

- 技能是否可用。
- 是否处于技能冷却。
- 是否存在有效目标。
- 目标阵营关系是否正确。
- 目标是否可选中。
- 目标是否处于施法范围。

普通技能不配置 Condition。

目标通过阵营和有效性检查、但仍在施法范围外时，不将技能请求判为失败。SkillBase 保留该请求并进入 `QUEUED`，SkillHost 发出接近请求；角色进入范围后才请求播放施法动画。

血量阈值、状态要求、装备要求等特殊规则才在具体 Skill 场景中添加 Condition 组件。

### Cost

无消耗技能不配置 Cost，也不创建 `NoSkillCost`。

未来需要法力、生命或其他资源消耗时，在技能场景中添加 Cost 组件。Cost 在 `release_action()` 最终验证通过后提交；Delivery 启动失败时最多退款一次。

### Effect

投射物技能通常由投射物负责最终效果，因此 Skill 场景不需要 Skill Effect。

瞬发治疗等技能可以在同一场景中添加：

```text
HolyLightSkill
├─ DeliveryRunner
├─ RuntimeEffects
└─ HealEffect
```

SkillBase 自动发现实现约定接口的直属扩展组件，不使用手写 NodePath。

## 8. 施法动画和 Cast Time

### 8.1 统一动作事件

角色动画播放器提供：

```gdscript
release_action()
finish_action()
```

普通攻击和技能共用相同动作事件：

```text
动作开始
→ 播放角色动画
→ release_action()
→ 执行当前 Action 的攻击 Hitbox 或技能 Delivery
→ finish_action()
→ 结束动作状态
```

角色动画系统不知道具体技能算法；SkillBase 也不直接操作角色 AnimationPlayer。

### 8.2 Cast Time 缩放

角色动作系统读取目标动画中第一个有效 `release_action()` 方法轨道时间。

```text
effective_cast_time =
    base_cast_time ÷ caster_cast_speed_multiplier

animation_speed =
    release_marker_time ÷ effective_cast_time
```

示例：

```text
release_action 原始时间 = 0.6 秒
base_cast_time = 1.2 秒
cast_speed_multiplier = 1.0
animation_speed = 0.5
```

动画以半速播放，使 Release 事件在实际 1.2 秒时发生。

### 8.3 瞬发技能

`base_cast_time = 0` 表示瞬发：

- 动画仍可播放。
- `release_action()` 必须位于动画起点。
- 不进行施法时间缩放。

### 8.4 第一版限制

第一版每个技能动作只支持一个有效 `release_action()`。

持续引导、连续喷射和多阶段释放属于不同 Action 类型，后续按真实需求扩展，不提前加入普通 SkillBase。

## 9. 运行时信号链

```text
玩家或 AI 提出技能请求
→ SkillHost 检查技能许可和公共冷却
→ SkillBase 解析并验证目标
→ 目标在范围外时保持 QUEUED，并请求角色接近
→ 目标进入范围
→ SkillBase 请求角色动作系统播放 action_animation_name
→ 角色动作系统计算动画播放倍率
→ AnimationPlayer 播放角色施法动画
→ 动画方法轨道触发 release_action()
→ 当前 SkillBase 重新验证目标和提交 Cost
→ DeliveryRunner 执行 DeliveryConfig
→ Delivery 成功启动
→ 启动技能冷却和公共冷却
→ 动画方法轨道触发 finish_action()
→ 角色动作状态结束
```

建议的 SkillBase 信号：

```gdscript
signal action_requested(
    skill: SkillBase,
    animation_name: StringName,
    target: Node3D,
    effective_cast_time: float
)

signal cast_range_required(
    context: SkillContext,
    cast_range: float
)
signal release_started(context: SkillContext)
signal delivery_started(context: SkillContext)
signal delivery_finished(context: SkillContext, result: SkillDeliveryResult)
signal skill_failed(reason: StringName)
signal skill_cancelled(reason: StringName)
signal cooldown_started(duration: float)
signal cooldown_finished()
```

SkillSystem 只依赖动作请求与动作事件接口。UnitSystem 负责把该接口接入具体角色的动画播放器和状态机。

## 10. 配置错误处理

开始施法前检查：

- `skill_id` 是否有效。
- DeliveryConfig 是否存在且配置完整。
- 目标规则是否有效。
- 角色动作系统是否存在目标动画。
- 动画是否含有有效 `release_action()`。
- Release 时间与 `base_cast_time` 是否可计算。
- 最终动画播放倍率是否有限且大于零。

失败时：

- 不进入施法动作。
- 不提交 Cost。
- 不启动公共冷却或技能冷却。
- 输出稳定的失败原因。
- 对静态可检查的问题显示 Inspector 配置警告。

释放时目标失效或离开范围：

- 按 `validate_target_on_release` 和 `cancel_when_target_invalid` 处理。
- 默认取消本次释放。
- 默认不进入技能冷却。
- AI 回到正常技能决策流程。

请求阶段目标仅仅位于范围外时不属于配置错误，也不取消请求；它进入接近流程。只有动作已经开始后，目标在 Release 时仍不满足范围规则，才按最终复验规则取消。

## 11. UI、技能栏和存档

技能 UI 可以直接持有：

```gdscript
@export var skill_scene: PackedScene
```

已装备技能从 SkillHost 中的实例读取：

```text
skill_id
display_name
icon
cooldown
current_cooldown
```

第一版不实现未装载技能的全量 Catalog。未来确实需要技能图鉴、技能商店或完整技能数据库时，再由编辑器工具根据技能场景生成 `skill_id → PackedScene` 派生索引。

派生索引不得人工复制技能参数。存档只保存 `skill_id`，避免保存资源绝对路径。

## 12. 脚本和资源压缩

核心运行脚本目标：

```text
SkillBase.gd
SkillHostComponent.gd
SkillContext.gd
SkillDeliveryResult.gd
SkillDeliveryRunner.gd
SkillDeliveryConfig.gd
```

按真实功能保留少量扩展：

```text
TrackingProjectileDeliveryConfig.gd
InstantTargetDeliveryConfig.gd
GroundAreaDeliveryConfig.gd
SkillConditionBase.gd
SkillCostBase.gd
SkillEffectBase.gd
```

完成迁移后，以下默认或重复结构可归档：

```text
SkillDefinition.gd
每个技能的 SkillDefinition.tres
每个技能的 Delivery.tscn
AlwaysSkillCondition.gd
NoSkillCost.gd
BasicRandomDecisionPolicy.gd
SceneSkillPresentation.gd
ProvidedTargetSelector.gd
NearestValidTargetSelector.gd
BasicDeliveryAgent.tscn
TrackingProjectileDeliveryAgent.tscn
默认 Trajectory / Collision / Impact 多层 Policy
```

删除或归档必须在 Firebolt、HolyLight 和 UnitSystem 接入测试全部通过后进行。

## 13. 安全迁移方案

1. 在不修改现有技能运行链的前提下建立新版精简核心。
2. 创建新版 Firebolt 单场景。
3. 验证目标解析、角色动画、Cast Time 缩放、世界发射点、投射物和冷却。
4. 只把新 UnitSystem 中的 Caster 切换到新版 Firebolt。
5. 验证 Caster 的索敌、接近、施法、禁用技能后普攻回退和公共冷却。
6. 创建并验证新版 HolyLight 单场景。
7. 两个代表性技能通过后归档旧 SkillSystem。
8. 整理最终目录并重写 Inspector 配置指南。

迁移过程中：

- 不修改 `res://Scenes/TestScene.tscn` 中的任何单位实例。
- 不自动向 TestScene 添加单位。
- 旧系统在新版验证完成前保持可运行。
- 新建正式 `.tres` 或 `.res` 时仍须通过 Godot ResourceSaver 或编辑器正式保存并验证有效 UID；本设计优先使用技能场景内嵌 SubResource，减少外部资源数量。

## 14. 第一版验收标准

- 一个具体技能只需维护一个 `.tscn`。
- 打开技能场景并选择根节点，可以完成全部普通技能配置。
- Firebolt 不再依赖独立 Definition 或 Delivery 场景。
- HolyLight 不再依赖独立 Definition 或 Delivery 场景。
- 普通技能不需要配置空 Condition、空 Cost 或默认 Presentation。
- Cast Time 能正确缩放角色动画，使 `release_action()` 在目标时间发生。
- Firebolt 从角色提供的世界发射点生成，不从世界原点或 Skill 场景本地坐标生成。
- 技能释放成功后技能冷却与公共冷却分别正确开始。
- Delivery 启动失败、目标失效或动画配置错误不会错误提交 Cost 或冷却。
- AI 普攻和技能共用动作事件接口，但继续使用各自的交付实现。
- UI 能从技能场景或已装备实例读取显示信息，无需第二份 Definition 数据。

## 15. 暂不实施

- 多阶段释放和一个动画中的多次 `release_action()`。
- 持续引导、蓄力松开和可变蓄力阶段。
- 复杂威胁评分和技能组合规划。
- 自定义 Inspector 插件。
- 自动生成技能图标或描述。
- 复杂法力、怒气和多资源消耗。
- 网络同步和多人技能权威。
