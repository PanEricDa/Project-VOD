# 当前系统使用指南

更新日期：2026-07-31

本指南只描述当前活动框架。历史实现位于 `res://Archive`，不要从 Archive 装载场景、脚本或资源。

## 1. 创建基础单位

按用途选择继承场景：

- 玩家角色：继承 `res://UnitSystem/Player/PlayerBase.tscn`
- 友方 AI：继承 `res://UnitSystem/AI/Ally/AllyBase2.tscn`
- 敌方 AI：继承 `res://UnitSystem/AI/Enemy/EnemyBase2.tscn`

玩家当前只有一个正式实例：`res://UnitSystem/Player/Hero/Hero.tscn`。

新单位可以安全修改根节点名称。固定功能节点由父场景和组件内部路径维护，不应让单位名称参与节点查找。

## 2. 配置 Visual

当前视觉场景统一位于 `res://UnitSystem/Visuals/`。新角色应继承或装载 `Base/UnitVisualBase.tscn`，具体模型放在 `CharacterRoot/ModelRoot` 下。不要再创建 `00-UnitBaseVisual` 或 `AllyBaseVisual` 作为中间包装层。

单位根节点的 `Visual` 是视觉插槽。把独立视觉 PackedScene 实例化为 `Visual` 的直接子节点。

视觉场景至少应提供当前系统使用的端点：

```text
CharacterRoot
└── WeaponSocket
```

需要播放动作时，视觉场景还应提供一个挂载 `CharacterAnimationEventPlayer` 脚本的 `AnimationPlayer` 节点（通常命名为 `CharacterAnimationPlayer`）。武器 Visual 只负责模型，不保存战斗算法。

替换 Visual 后检查：

- `WeaponSocket` 仍位于 `CharacterRoot` 下。
- 动画轨道路径与新视觉节点一致。
- 武器预览能挂到 WeaponSocket。
- AICombatSystem 或 PlayerAttackController 能找到动画端点。

## 3. 配置阵营与生命

在单位根节点 Inspector 配置：

- `Maximum Health`
- `Starting Health Percent`
- `Faction Id`
- `Team Id`
- `Targetable`
- `Attack Power`
- `Defense`

`Faction Id` 用于单位类别和展示语义；`Team Id` 用于友好、敌对关系判定。技能目标关系也以单位公开的队伍关系接口为准。

`Attack Power` 是普通攻击、伤害技能和治疗技能可读取的单位基础强度。`Defense` 只减少伤害，不减少治疗。

## 4. 配置头顶血条

`UnitBase` 已默认装配：

```text
WorldUIRoot
└── WorldHealthBar
```

`WorldHealthBar` 是独立组件，单向订阅 UnitBase 的生命信号。UnitBase 不调用 UI；
删除 `WorldHealthBar` 不会影响生命、移动、战斗、索敌或技能。

默认表现：

- 平时隐藏，受到有效伤害后立即显示。
- 绿色条立即显示当前生命。
- 红色条短暂停留在受伤前的位置，再向绿色条平滑收缩。
- 最后一次受伤经过 `Visible Duration` 后淡出隐藏。
- 治疗和复活会刷新数值，但不会主动显示已经隐藏的血条。
- 隐藏期间停止该血条的 SubViewport 更新。

常用 Inspector 参数位于 `WorldHealthBar` 根节点：

- `Local Offset`：相对单位根节点的头顶位置。
- `Visible Duration`：最后一次受伤后保持显示的时间，默认 2.5 秒。
- `Fade Duration`：自动隐藏的淡出时间。
- `Damage Hold Duration`：红色损血条开始消退前的停留时间。
- `Damage Decay Duration`：红色损血条的收缩时间。
- `Bar Pixel Size`、`Border Width`、`Corner Radius`：尺寸与圆角边框。
- `Health Color`、`Damage Color`、`Empty Color`、`Border Color`：统一配色。

不同身高的角色优先在其继承场景中覆盖
`WorldUIRoot/WorldHealthBar.Local Offset`。未来正式模型也可以把 `WorldUIRoot` 对齐到
头部挂点。`BarSprite.pixel_size` 控制血条在世界中的实际大小。

## 5. 配置 AI 索敌与阵型

友方 AI 已包含 `AITargetingComponent` 和 `AllyBehaviorStateMachine`。

在单位根节点配置：

- `Targeting Radius`：单位独立的感知半径。
- `Formation Position`：从 `UnitSystem/AI/Ally/Formation/Positions` 选择一个 `FormationPositionData`。

阵型资源保存位置、游荡和跟随相关数据，不处理战斗状态。进入战斗后，状态机只使用目标、武器攻击距离和战斗游荡参数。

索敌 Debug 圈由 `AITargetingComponent` 的调试开关控制，不要把 Debug 视觉写入正式 Visual。

## 6. 挂载近战或远程 CombatSystem

AI 战斗部件需要手动装载到具体单位源场景：

- 近战：`res://UnitSystem/Components/Combat/AI/AIMeleeCombatSystem.tscn`
- 远程：`res://UnitSystem/Components/Combat/AI/AIRangedCombatSystem.tscn`

实例节点统一命名为 `CombatSystem`，作为单位根节点的直接子节点。

没有 CombatSystem 时，单位仍可移动、索敌和使用阵型，但不会执行普通攻击。魔法职业可以只装技能；如果其策略要求“技能禁用时回退普攻”，则仍需装载适合的 CombatSystem 和兜底武器。

## 7. 配置 WeaponData 与动画

武器目录：

```text
Item/Weapon/
├── WeaponData.gd
├── MeleeWeaponData.gd
├── RangedWeaponData.gd
└── 具体武器文件夹/
```

共同字段：

- `Display Name`
- `Visual Scene`
- `Animation Library`
- `Attack Range`
- `Attack Range Tolerance`
- `Basic Attack Base Damage`
- `Basic Attack Power Ratio`
- `Combo Damage Multipliers`

`Combo Damage Multipliers` 的索引 0 对应 `basic_attack_1`；缺少对应项时安全回退为 `1.0`。普通攻击仍先由既有 Hitbox 或 Projectile 确认命中，再进入统一数值结算。

近战额外配置：

- 每段 `Attack Forward Distances`
- `Attack Motion Speed`
- 每段 `Hitbox Sizes`
- 每段 `Hitbox Center Offsets`

远程额外配置：

- `Projectile Scene`

动画命名使用：

```text
basic_attack_1
basic_attack_2
basic_attack_3
```

段数按 AnimationLibrary 中连续存在的名称决定。近战动画用方法轨道调用命中窗口事件；远程动画用方法轨道调用投射物释放事件。角色动作可以移动 Visual，但真实 CharacterBody3D 位移必须由单位控制器执行。

将武器 Resource 配置到单位根节点的 `Starting Weapon`。运行时换装使用 CombatSystem 或玩家攻击控制器公开的装备接口。

## 8. 挂载 SkillHost 中的技能

`UnitBase` 已经自带：

```text
SkillHost
└── SkillSocket
```

具体技能场景位于：

```text
res://SkillSystem/00-Skills
```

把技能场景实例化为 `SkillHost/SkillSocket` 的直接子节点即可。`SkillHostComponent` 默认自动发现这些 `SkillBase` 子节点，不需要每个单位新增注册脚本。

## 9. 配置技能场景与动画事件

新技能的最短流程：

1. 继承 `res://SkillSystem/01-Core/SkillBase.tscn`。
2. 在 `SkillSystem/00-Skills/技能名` 中保存唯一的具体技能 `.tscn`。
3. 在技能根节点配置 Identity、Targeting、Casting、Cooldown、AI Usage、Presentation 和 Delivery。
4. 将 Delivery 设为正确的内嵌强类型 Resource：
   - `TrackingProjectileDeliveryConfig`
   - `InstantTargetDeliveryConfig`
   - `GroundAreaDeliveryConfig`
5. 只有确实需要特殊规则时，才增加 Condition、Cost 或 Effect 子组件。

角色接到技能动作请求后播放自己的施法动画。动画方法轨道调用：

- `release_action()`：把当前动作发射点 Transform 传回 SkillHost，并执行技能交付。
- `finish_action()`：结束角色动作占用。

技能不反向查找某个动画名称。施法时间由 `base_cast_time` 提供，动作控制器根据请求数据缩放当前施法动画；回访失败应报告配置错误。

`HealthChangeSkillEffect` 使用 `base_amount` 和 `power_ratio` 结算伤害或治疗。Tracking projectile 由投射物确定 targets，再由 `DeliveryRunner` 执行 Effect；当前 Firebolt 配置为伤害，HolyLight 配置为仅友方（不含自己）治疗，并在有效友方中选择最近目标。

目标配置：

- `Target Relations`：Self、Friendly、Hostile、Neutral，可多选。
- `Target Selection Mode`：当前战斗目标、最近、随机、最低生命百分比。
- `Require Targetable`
- `Require Alive`
- `Cast Range`

## 10. 死亡与复活

单位 HP 到 0 后不可被选中，并停止移动、攻击和施法；死亡仍保留重力与碰撞。`revive` 只恢复新的行动资格，不恢复死亡前的动作。关卡失败、掉落与死亡动画尚未实现。

## 11. 手动把单位加入 TestScene

Codex 不会自动向测试场景添加单位实例。

需要测试新单位时，由使用者在 Godot 编辑器中：

1. 打开 `res://Scenes/TestScene2.tscn`。
2. 将具体单位 `.tscn` 拖到场景根节点。
3. 设置不与现有单位或地面重叠的初始位置。
4. 检查 Starting Weapon、Formation Position、技能实例和 CombatSystem。
5. 保存场景并运行。

## 12. 运行测试与排错

重点测试目录：

- `res://UnitSystem/Tests`
- `res://SkillSystem/05-Tests`

常用命令：

```powershell
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' `
  --headless --path 'G:\Godot\ProjectVOD' `
  --script 'res://UnitSystem/Tests/LegacyFrameworkArchiveContractTest.gd'

& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' `
  --headless --path 'G:\Godot\ProjectVOD' --editor --quit
```

出现配置问题时按顺序检查：

1. Output 中第一个错误。
2. 场景引用是否仍位于活动目录。
3. Resource UID 是否有效。
4. Visual 是否提供 CharacterRoot、WeaponSocket 和动画端点。
5. 动画方法轨道是否只在正确时间调用一次事件。
6. 技能是否位于 `SkillHost/SkillSocket`。
7. AI 是否装载了正确的 CombatSystem。

任何正式 `.tres` 或 `.res` 都必须通过 Godot 编辑器、MCP Resource 工具或 `ResourceSaver` 保存，并验证有效 UID；强类型字段还必须能被 Inspector Quick Load 按正确类型检索。
