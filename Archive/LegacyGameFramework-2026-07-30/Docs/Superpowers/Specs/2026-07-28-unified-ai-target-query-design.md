# AI 统一感知与技能临时目标设计

日期：2026-07-28

## 目标

保留现有 `AITargetingComponent` 的自主敌方锁定行为，同时让敌方、友方、自身和中立单位技能复用同一份感知候选数据。

技能设计者只需在技能场景根节点的 Inspector 配置：

- `Target Relations`
- `Target Selection Mode`
- `Require Targetable`
- `Require Alive`
- `Cast Range`

不再配置 `Target Source`，不创建每技能一份的 `TargetSelectionPolicy` Resource，也不扫描全场景分组寻找目标。

本次只统一候选来源、目标过滤和目标选择。技能动画、Delivery、冷却、伤害、治疗数值、武器攻击距离和 `TestScene.tscn` 均不在改动范围内。

## 核心概念

系统允许同时存在两种生命周期不同的目标：

- `locked_target`：由 `AITargetingComponent` 持续维护的敌方战斗目标。
- `resolved_target`：一次技能请求最终选中的临时作用目标。

友方治疗技能可以临时选择友方单位，但不会覆盖、清空或替换敌方 `locked_target`。技能结束、失败或取消后，仅释放本次 `resolved_target`。

## Inspector 配置

### Target Relations

使用位标志复选项，可以同时选择多个关系：

```gdscript
enum TargetRelationFlag {
    SELF = 1,
    FRIENDLY = 2,
    HOSTILE = 4,
    NEUTRAL = 8,
}
```

关系判定以 `team_id` 和 `UnitBase` 的公共能力接口为准：

- `SELF`：目标就是施法者自身。
- `FRIENDLY`：与施法者同队，但不是施法者。
- `HOSTILE`：与施法者敌对。
- `NEUTRAL`：既非同队也非敌对的其他单位。

`faction_id` 只表示阵营类别或展示语义，不直接作为技能关系判定依据。

多选示例：

- 只治疗其他友方：`FRIENDLY`
- 可治疗自己和友方：`SELF | FRIENDLY`
- 对任意非己方单位生效：`HOSTILE | NEUTRAL`

### Target Selection Mode

第一版提供以下枚举：

```gdscript
enum TargetSelectionMode {
    CURRENT_COMBAT_TARGET,
    NEAREST,
    RANDOM,
    LOWEST_HEALTH_RATIO,
}
```

- `CURRENT_COMBAT_TARGET`：优先使用调用方传入的当前战斗锁定目标。
- `NEAREST`：从合格候选中选择水平距离最近的目标。
- `RANDOM`：从合格候选中随机选择一个目标。
- `LOWEST_HEALTH_RATIO`：选择当前生命百分比最低的目标。

不在第一版加入通用的 `LOWEST_ATTRIBUTE + StringName`。未来需要最低法力、最低护盾等规则时，直接增加明确的枚举项和集中算法，避免字符串拼写错误和 Inspector 隐式依赖。

当 `Target Relations` 只包含 `SELF` 时，选择策略不会改变结果，但字段仍保留统一的 Inspector 布局。

### 有效性开关

- `Require Targetable`：目标必须允许被选取。
- `Require Alive`：目标必须存活。

它们与关系、排序各自只有一个明确职责，不重复表达目标来源。

## 组件职责

### AITargetingComponent

继续负责：

- 使用现有 `Area3D` 和球形碰撞维护感知。
- 按 `refresh_interval` 持续更新敌方 `locked_target`。
- 使用现有敌方锁定策略，不改变基础索敌行为。
- 使用 `targeting_radius + 1m` 保持已锁定敌方目标。

新增只读候选接口：

```gdscript
func get_perceived_candidates(
    maximum_distance: float = -1.0
) -> Array[Node3D]
```

规则：

- 默认最大距离为单位自身的 `targeting_radius`，不是锁定保持半径。
- 只返回当前仍与感知 `Area3D` 重叠、仍在场景树中且位于请求距离内的单位。
- 不判断关系、不排序、不修改 `locked_target`。
- 返回通用 `Array[Node3D]`，避免 SkillSystem 依赖具体单位脚本类型。

### TargetResolver

新增一个纯算法工具 `TargetResolver.gd`，集中维护：

- 关系位标志定义与匹配。
- `Require Targetable`、`Require Alive` 过滤。
- 当前目标、最近、随机和最低生命百分比选择。

它不是 Node，也不是可配置 Resource，不会出现在技能场景或 Inspector 中。设计师不需要维护额外文件；开发者未来扩展新的通用选择模式时，只修改该集中算法和枚举。

解析器只依赖目标公开的能力方法，例如：

- `is_targetable()`
- `is_dead()`
- `is_friendly_to()`
- `is_hostile_to()`
- `get_health_ratio()`

缺少所需能力时，该候选对相应规则判定为不合格，而不是产生运行错误。

### SkillBase

技能根节点直接保存唯一一份目标配置：

```gdscript
@export_flags("Self", "Friendly", "Hostile", "Neutral")
var target_relations: int = TargetRelationFlag.HOSTILE

@export var target_selection_mode: TargetSelectionMode = \
    TargetSelectionMode.CURRENT_COMBAT_TARGET

@export var require_targetable: bool = true
@export var require_alive: bool = true
@export_range(0.0, 100.0, 0.1) var cast_range: float = 3.0
```

技能不读取 `AITargetingComponent.locked_target`，也不自行扫描场景。它只接收 Host 提供的候选集合和可选的当前战斗目标，然后交给 `TargetResolver`。

解析完成后，只将最终结果写入本次 `SkillContext.resolved_target`。候选集合不作为长期状态保存。

### SkillHostComponent

增加运行时注入接口：

```gdscript
func set_target_candidate_provider(provider: Node) -> void
```

Provider 只需实现：

```gdscript
func get_perceived_candidates(
    maximum_distance: float = -1.0
) -> Array[Node3D]
```

`AllyBase2` 在现有装配阶段自动把自己的 `AITargetingComponent` 注入 `SkillHostComponent`。不增加导出的 NodePath，不要求每个继承单位重复配置。

每轮自动技能决策时，Host 只向 Provider 读取一次候选集合，再复用于本轮所有技能评估。完成迁移后，删除当前 `skill_target_candidates` 全场景分组扫描。

## 请求规则

### 自动 AI 请求

自动请求使用技能自身的 `Target Relations` 和 `Target Selection Mode`：

1. Host 获取当前感知候选。
2. 若允许 `SELF`，将施法者加入候选。
3. Host 将当前敌方 `locked_target` 作为可选的“当前战斗目标”传入。
4. `TargetResolver` 过滤关系、存活和 targetable 条件。
5. 按技能的选择模式选出一个 `resolved_target`。
6. 无合格目标时，该技能不占用 `active_skill`。

### 显式外部请求

剧情、玩家命令和测试可以调用显式接口并传入目标。显式目标是本次请求的指定目标，不再由选择策略替换，但仍必须通过：

- `Target Relations`
- `Require Targetable`
- `Require Alive`
- 技能既有条件和消耗校验

这样既保留外部精确控制，也不会让不合法目标绕过技能定义。

## 数据流

### Firebolt

配置：

```text
Target Relations = Hostile
Target Selection Mode = Current Combat Target
Cast Range = 6m
```

运行：

```text
AITargetingComponent.locked_target
→ SkillHost 自动请求
→ TargetResolver 验证当前战斗目标
→ SkillContext.resolved_target
→ 接近 / 施法 / Delivery
```

### HolyLight

配置：

```text
Target Relations = Friendly
Target Selection Mode = Nearest
Cast Range = 3m
```

运行：

```text
AITargetingComponent.get_perceived_candidates(targeting_radius)
→ TargetResolver 过滤友方并选择最近目标
→ SkillContext.resolved_target
→ 接近 / 施法 / Delivery
```

Priest 当前 `targeting_radius = 6m`，因此只考虑六米感知范围内的友方；目标位于三至六米之间时，复用现有技能接近流程。

如希望治疗包含自身，只需把关系改为 `Self | Friendly`，无需新增脚本或 Resource。

## 目标稳定与失败规则

- 一次技能选中临时目标后，本次请求不自动换人。
- 决策等待或接近期间目标失效时，取消本次请求并回到正常技能决策。
- 接近连续 `1.5s` 无有效距离进展时，沿用现有 `approach_stalled` 终止规则。
- 释放时继续复验目标有效性和 `cast_range`。
- 目标失效、技能取消和动作拒绝均不得覆盖或清空敌方 `locked_target`。
- 不在同一次施法中静默替换目标，避免表现、动画朝向和 Delivery 目标不一致。
- 未注入 Candidate Provider 时，显式请求仍可用；自动候选查询安全返回无目标。

## 配置迁移

### HolyLight

- 删除旧 `target_source` 和独立目标 Policy 配置。
- 设置 `Target Relations = Friendly`。
- 设置 `Target Selection Mode = Nearest`。
- 保持 `Require Targetable = true`。
- 保持 `Require Alive = true`。
- 保持现有 `Cast Range`。

### Firebolt

- 删除旧 `target_source` 和独立目标 Policy 配置。
- 设置 `Target Relations = Hostile`。
- 设置 `Target Selection Mode = Current Combat Target`。
- 保持现有 `Cast Range`、动画、投射物和 Delivery。

### UnitBase

- 完成 Host 候选提供者迁移后，移除只服务于旧技能全局扫描的 `skill_target_candidates` 自动分组注册。
- 生命、队伍、阵营和 targetable 公共接口保持不变。

## 测试

- `Target Relations` 支持 Self、Friendly、Hostile、Neutral 及多选组合。
- Nearest、Random、Lowest Health Ratio 和 Current Combat Target 均只在合格候选中选择。
- AITargeting 候选接口只返回 `targeting_radius` 内单位，不泄漏保持半径外沿候选。
- 一次友方技能查询不会改变敌方 `locked_target`。
- HolyLight 只选择感知范围内的其他存活友方；启用 Self 后可以选择自身。
- 无合格目标时不占用 `active_skill`。
- Firebolt 继续使用已有敌方锁定目标。
- 友方目标位于 `cast_range` 外但感知范围内时进入现有接近流程。
- 临时目标失效或接近停滞后完整释放请求，敌方锁定保持不变。
- 显式传入目标仍执行关系、存活和 targetable 验证。
- 不存在 Candidate Provider 时，显式技能保持可用，自动查询安全失败。
- 删除全场景候选分组扫描后，Caster、Priest 连续施法回归继续通过。
- Godot 4.7 headless 测试、完整编辑器扫描和 MCP 输出无新增错误。

## 不在本次范围

- 不加入最低法力、最低护盾、威胁值或职业优先级算法。
- 不新增视线遮挡、锥形视觉或听觉感知。
- 不修改玩家指挥锁定。
- 不修改技能伤害、治疗数值、动画、特效、投射物或 Delivery。
- 不向 `TestScene.tscn` 自动添加或修改任何单位实例。

## Implementation Verification

实施日期：2026-07-29

### 最终路径

- 通用临时目标解析器：
  - `res://SkillSystem/01-Core/TargetResolver.gd`
- 技能配置与上下文：
  - `res://SkillSystem/01-Core/SkillBase.gd`
  - `res://SkillSystem/01-Core/SkillContext.gd`
- 候选提供与装配：
  - `res://SkillSystem/01-Core/SkillHostComponent.gd`
  - `res://UnitSystem/Components/Targeting/AI/AITargetingComponent.gd`
  - `res://UnitSystem/AI/Ally/AllyBase2.gd`
- 已迁移技能：
  - `res://SkillSystem/00-Skills/Firebolt/FireboltSkill.tscn`
  - `res://SkillSystem/00-Skills/HolyLight/HolyLightSkill.tscn`

### 最终行为

- `SkillBase` 已移除 `Target Source` 和单选 `Target Relation`。
- 技能 Inspector 使用 `Target Relations` 复选、`Target Selection Mode`、
  `Require Targetable`、`Require Alive` 和 `Cast Range`。
- `SkillHostComponent` 不再扫描 `skill_target_candidates` 全局组。
- `AllyBase2` 自动把现有 `AITargetingComponent` 注入 SkillHost，无额外 NodePath。
- 感知 Area 的物理掩码为 `7`，可以观察 Player、Ally、Enemy 三类单位层；持续锁敌仍由
  原有 `TargetSelectionPolicy` 过滤，因此基础敌方锁定规则未改变。
- Firebolt 使用 `Hostile + Current Combat Target`。
- HolyLight 使用 `Friendly + Nearest`。
- 临时技能目标不修改敌方 `locked_target`。

### 验证结果

以下 16 个直接受影响测试全部通过：

- `TargetResolverTest`
- `UnitRootConfigurationTest`
- `AITargetingComponentTest`
- `TargetSelectionPolicyTest`
- `SingleSceneSkillBaseTest`
- `SingleSceneSkillHostTest`
- `SingleSceneCoreContractsTest`
- `AllyTargetingIntegrationTest`
- `UnitBaseSkillHostAssemblyTest`
- `SingleSceneFireboltTest`
- `SingleSceneHolyLightTest`
- `PriestHolyLightAutomaticRuntimeTest`
- `CasterFireboltRuntimeTest`
- `RepeatedSkillCastingLifecycleTest`
- `SkillApproachRecoveryTest`
- `AllySkillCombatPolicyTest`

Godot 4.7 完整无窗口编辑器扫描退出码为 `0`，没有脚本解析、场景属性或资源加载错误。

项目现有 40 个 SkillSystem/UnitSystem 测试中，29 个通过；其余 11 个属于本次改动前后均
不在目标查询迁移范围内的陈旧断言或当前资产差异，包括：

- 测试仍引用已删除的 `Amy.tscn`。
- `UnitDirectoryLayoutTest` 仍断言旧 TestScene2 单位和坐标。
- 武器攻击距离、弓投射物默认值、盾牌 Workbench 动画库与当前资产不一致。
- Archive 旧技能 Resource 的 UID 审计失败。
- `RangedAttackPipelineTest.gd` 本身不是可直接运行的 SceneTree/MainLoop 测试。
- 旧 AI 战斗/武器视觉测试依赖当前已变化的武器和 Visual 装配。

这些失败没有在本次迁移中通过修改资产或场景进行掩盖。

MCP Pro 已连接。其 `validate_script` 会把已注册 `class_name` 脚本复制到临时
`gdscript://` 后再次编译，因此对 `SkillBase`、`SkillHostComponent`、
`AITargetingComponent` 和 `AllyBase2` 报出 `hides a global script class`；临时上下文
同时无法解析新注册的 `TargetResolver`。这是验证器误报，真实项目编译、完整编辑器扫描和
上述运行测试均通过。

本次没有向 `res://Scenes/TestScene.tscn` 添加、删除或修改任何单位实例。
