# 当前系统使用指南

更新日期：2026-10-23（本次补充玩家技能与被动位移；其他历史段落保留）

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

### 动画工作台

制作／编辑动作的完整七步流程与 AI 交付检查见 [动画工作台操作指南](AnimationWorkbenchWorkflow.md)。入口为 `res://UnitSystem/Visuals/Workbench/HeroAnimationWorkbench.tscn`；武器库位于 `res://Item/Weapon/<武器类别>/`，当前使用 `*AnimationLibrary.res`。

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

头顶状态栏沿用血条左上方、向右排列的小圆点：橙红色表示灼烧，紫色圆点表示降防。降防直接读取实际防御负向修正，刷新不增加圆点，全部降防效果到期／移除后消失；带有可见状态时，即使满血也保持血条显示。

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

## 12. 玩家 Dash 逐层恢复与 HUD 监控

- 玩家最大连续 Dash 次数由 `PlayerBase.maximum_consecutive_dashes` 配置，默认 2。
- 任意一层被消耗后立即按 `dash_cooldown_duration` 开始当前层冷却；每完成一个完整冷却只恢复一层，未满时自动开始下一层，恢复满层后停止计时。
- 恢复期间再次 Dash 只扣除一个完整次数，当前层的恢复进度不会重置或丢失。
- 单帧间隔很大（低帧率或调试暂停）时，系统按真实经过时间连续结算多个已完成的层并保留余量。
- `dash_cooldown_duration <= 0` 表示无冷却：消耗后立即恢复满层，不进入循环计时。
- 玩家死亡时恢复计时冻结，复活后从冻结处继续；房间结算只禁用输入时恢复计时照常运行。
- 玩家生命条正下方的淡黄色细条（`PlayerDashStatusBar`）显示“完整次数 + 当前恢复层进度”的连续值；满层为整条，消耗一层立即缩短总长度的 `1/n`。
- 该 HUD 是严格只读监控：只读取 `PlayerBase.get_dash_charge_capacity()` 与 `get_dash_charge_progress()`，不计算冷却、不推进时间，删除或隐藏它不影响 Dash。
- 伙伴框与顶部目标框不显示 Dash 条；只有阵营为 `Player` 的 `PlayerBase` 单位会驱动该条。

## 13. 运行测试与排错

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


## 终结技特写遮挡隐藏（2026-10-20）

在终结技能根的 Camera Effect Profile 中展开 SkillCinematicCameraProfile → Closeup Occlusion：Hide Closeup Occluders 默认开启，Occlusion Corridor Width M 为完整通道宽度（米），默认1.6；长度由该资源的最终正面镜头位置至角色观察点自动得到。现有Caster、Guardian、Archer预设沿用相同默认，无需另挂节点、资源或动画方法帧。

进入特写前隐藏通道内其他单位的Visual（含武器）及WorldUIRoot，以及独立环境GeometryInstance3D。按世界包围盒而非仅按对象中心判定；保留施放者整棵子树及由通用表现管线标记归属的世界锚点特效，不隐藏单位物理根、碰撞、地面和世界根，不改AI/伤害/材质。脚下可行走支撑体通过向下射线识别（排除单位碰撞），命中点所属的支撑几何不隐藏，支持坡道；无碰撞的平面保留顶部不高于脚下+0.05米的后备判断。合并复杂地图应拆分独立遮挡模型，不把整片环境作为单个可隐藏模型。自定义Custom AABB及Extra Cull Margin也参与实际范围判定。

在release_action请求开始退出特写时立即恢复，早于镜头到战斗视角及投射物释放；不是等命中或整场演出结束。取消、替换、施放者死亡/卸载、CameraRig或Camera3D离树均恢复本次实际隐藏过且仍存在的节点；原本隐藏的节点不纳入恢复，子节点自身的隐藏状态不被覆盖。特写内新生成和移动进通道的对象会追加隐藏，已隐藏对象保持至切出以避免闪烁。

实现入口：CameraFollowController接管镜头生命周期；同目录CinematicOcclusionFilter.gd内部负责筛选和恢复，不作为策划组件装配。SquadFinisherExecutionController传入本次caster；旧四参数begin_cinematic调用仍兼容，但未传施放者时不启用隐藏。验证脚本：UnitSystem/Tests/FinisherCinematicOcclusionTest.gd。

本功能验收：新增遮挡测试、真实Caster/Archer特效归属、目标锚点、局部裁剪容差随缩放、坡道、替换/取消/卸载均通过；编辑器截图与数据确认保留施放者和地面，切出立即恢复。全量164项：163通过，唯一既有CameraFollowControllerTest未烘焙导航失败，泄漏日志0；真实按键4终结流程另测通过，独立复核无遗留问题。


## 技能成功释放后切换自身攻击目标

- Guardian 的连携技能已装配 `AdoptSkillTarget` 子组件，成功开始交付时，将本次技能实际解析的目标设为 Guardian 的攻击目标；输入或开始施法时不切换，释放前取消/失败也不切换。
- 配置入口：打开 `SkillSystem/00-Skills/Combo_GuardianBash/ComboGuardianBashSkill.tscn`，直接查看根节点下的 `AdoptSkillTarget`。组件没有额外数值参数，挂载即启用、移除即关闭。
- 复用：将 `SkillSystem/03-Extensions/SkillAdoptTargetComponent.tscn` 实例化到其他 SkillBase 技能的直接子节点；施法者需提供 `get_targeting_component()` 并使用 AITargetingComponent。不读取玩家后续锁定，也不逐个采用范围命中目标。
- 切换通过索敌组件的公开 `adopt_target(target)` 接口验证：感知可用、存活可选、当前策略及保留距离合法。成功后解除旧保护目标持有，但不建立新的强制持有。之后死亡、超距、Guardian 原有保护扫描等仍按既有规则执行；没有新仇恨、优先级或持续时间规则。


## Priest终结技：圣辉祝福

Priest现已配置终结槽，终结窗口按2施放。释放时8米内存活友方（含玩家及自己）伤害提高30%，持续15秒，重复刷新不叠加、不影响治疗。动作是举杖、头顶水平转两圈、定格、杵地释放；特写保留到1.15秒杵地帧，之后沿原B导演返回战斗视角并结算。

技能入口：`SkillSystem/00-Skills/Finisher_HolyBlessing/HolyBlessingFinisherSkill.tscn`。数值在DamageBlessingEffect配置，半径和释放时场景收集在Delivery配置。独立视觉、Cast/Release/Buff/Sequence预览在`Effects/Skills/HolyBlessing/`。完整编辑与复用说明见`SkillSystem/04-Docs/HolyBlessingFinisherConfigurationGuide.md`。工作台现为StaffVisual+StaffAnimationLibrary，新增finish_cast_1，保留原三段基础动画。


### 伙伴游荡到达距离

四名伙伴的标准减速距离（Slowing Distance）为0.2米、到达停止距离（Arrival Distance）为0.15米，均在角色根节点的运动配置中查看，Caster/Priest恢复继承标准减速距离。编队游荡和战斗游荡共用水平到达判定：刷新范围取减速距离与到达距离中较大者，且仍等待原游荡间隔。以后单独调整减速距离，也不会出现角色已停止、游荡却始终认为未到达的永久等待；没有新增配置项。


## 玩家Q/E正式接入与被动位移（2026-10-22）

F5启动Scenes/CombatRoom.tscn即可使用Q聚拢、E临时仇恨。Hero源场景的SkillHost/SkillSocket下有Gather、ThreatMark，Regular Skills引用它们；根下已有InputMap输入组件及PlayerSkillController。正式CD10/12秒；独立PlayerSkillsTest场景仅覆盖为2秒，并保留三模式、范围圈与观察器，不把这些调试内容带入正式入口。

Q/E技能参数仍在SkillSystem/00-Skills/Player_Gather、Player_ThreatMark各自技能场景维护；范围由Delivery配置，落盘由PullTargetSkillEffect配置，E临时仇恨/持续由ThreatChangeSkillEffect配置。本轮没有改动既有数值或表现资产。

UnitBase根Inspector新增Forced Movement / Forced Movement Enabled，默认开启。不再挂ForcedMovementComponent；关闭时立即终结当前外力并恢复其临时碰撞例外，重开不恢复。通用请求与终态信号直接在UnitBase；Player/AI原物理循环消费同一delta，保留唯一移动执行。聚拢仍忽略单位身体、保留墙地及重力；结束交回正常AI，不新增散开规则。

CombatRoom根下PlayerSkillBar仅将Skill Source指向本地Hero/PlayerSkillController，显示真实槽与冷却，不管理另一套技能/CD。F6专项验证仍打开Scenes/Tests/PlayerSkills/PlayerSkillsTest.tscn；Unsupported通过根开关关闭外力。详细入口与操作见[玩家技能配置指南](../SkillSystem/04-Docs/PlayerSkillsConfigurationGuide.md)，验证记录见[阶段五验收](Superpowers/Plans/2026-10-22-player-skills-stage-5-validation.md)。


## 当前玩家Q：目标聚拢独立技能（2026-10-23）

本节更新前文阶段五的Q内容入口：玩家Q已改装SkillSystem/00-Skills/Player_TargetGather/TargetGatherSkill.tscn。先F或鼠标中键锁定敌人，再按Q；无锁定不施放、不进冷却。以原锁定目标释放时的位置为中心，选5米水平范围敌人并拉到该位置，允许重叠；实际拉拽完成后附加90%减速、持续3秒，同组件重复刷新。目标自身不另行移动，释放后落点固定。E与既有数值不变；Q默认射程5m、CD10秒、施法0.2秒、拉动0.12秒；独立测试局部CD2秒。

原Player_Gather/GatherSkill.tscn仅从玩家槽卸下，身前聚拢参数和Effects/Skills/Gather/GatherEffectPreview.tscn保持可用。两者共用通用范围、拉拽和表现组件。当前Hero子节点仍名Gather以保留槽/场景引用，实例来源已换为TargetGatherSkill，Inspector可直接确认。新的目标聚拢预览位于Effects/Skills/TargetGather/TargetGatherEffectPreview.tscn。

配置与复用方式见[目标聚拢指南](../SkillSystem/04-Docs/TargetGatherSkillConfigurationGuide.md)。

## 玩家技能插入普攻（2026-10-23）

按住普攻时可直接按Q/E，合法技能立即打断普攻。技能动作结束后若仍按住普攻，续接被打断段的下一段；末段后从第一段开始。若松开，则按原0.3秒续段窗口等待再次输入，不强制攻击。无效技能请求不打断普攻。取消/死亡/卸装或换武器清除旧段数，新武器从第一段开始；不改变武器动画或技能自身效果配置。完整规则见SkillSystem/04-Docs/PlayerSkillsConfigurationGuide.md末节。


## 普攻命中自动锁定（2026-10-23）

配置入口：打开 UnitSystem/Player/Hero/Hero.tscn，选择 TargetingSystem，在 Target Lock 分组设置 Auto Lock On Hit Enabled。组件默认关闭，当前 Hero 已开启，主场景及复用此 Hero 的测试场景均继承；关闭此开关即可对比旧体验，不会解除已有锁定。

只在没有有效锁定时，玩家普攻结算后的第一个合法存活敌人成为目标；一击多目标沿命中事件顺序，只接受第一个合法目标。已有手动或自动锁定均不被后续命中抢走；目标死亡、失效或主动解除后，下次合法命中可重新锁定。已被本次攻击击杀、友方、超出锁定距离或非候选分组的单位会跳过。F/鼠标中键继续沿原操作规则，不额外给技能、AI伤害或持续伤害增加自动锁定。

实现沿 PlayerAttackController.attack_hit → PlayerTargetingComponent 原 request_lock 入口，复用原合法性、正式锁定特效、朝向与UI广播；切换武器不影响。配置更换持有者、配置失败和组件离树时解除旧监听。验证：UnitSystem/Tests/PlayerAutoLockOnHitTest.gd；实际主场景剑普攻与物理命中验证截图位于.godot/player_auto_lock_on_hit_2026_10_23/first-hit-lock.png。

本次自动锁定最终回归：187项，185通过；仅既有CameraFollowControllerTest（房间导航未烘焙）、SingleSceneFireboltTest（旧6米断言与当前配置不一致）失败。无新增脚本错误、退出泄漏或无效UID。独立只读审查无重要问题；全量记录见.godot/player_auto_lock_on_hit_2026_10_23/full-suite-final.json。所有编辑使用Godot MCP Pro，没有新增运行时组件、武器/技能分支或正式资源文件；没有修改受保护TestScene、提交Git或覆盖已导出的游戏。


## 连携输入节奏试验：看到施法提示再接下一次（2026-10-24）

正式入口仍为 Scenes/CombatRoom.tscn。按一次1/2/3/4后，直到该角色施法闪光出现前，其他连携键和重复按键均不再受理，不排队、不额外预留专注，也不会把原命令边框显示为红色失败。看到闪光后可以再按任意伙伴的一次连携；接收下一条后再次等待它自己的提示。不要提前快速输入1234后等待全部执行。

开放输入后不需要立刻按，不是节拍或精准判定；没有新增按键、评分规则、专注消耗规则或命中等待。提示后的下一位伙伴可以与上一位动作/投射物交叠；同角色重复仍遵守原动作锁和一个待执行槽。请求在提示前被取消、死亡、施法中断、等待超时或世界解绑时，恢复下一次输入。

配置入口：主场景根下 SquadChainCommandController → Commands → Wait For Cast Cue（正式场景开启，通用组件默认关闭）。取消勾选即可比较原来的全阶段预输入。提示时间继续由各技能根节点的 Cast Effect Start Ratio 配合本次有效施法时间决定；现有四个连携技能均为0.5，不增加另一套秒数配置。技能缺失/替换视觉资产不影响输入解锁，实际释放也提供兜底。

实现链路：SkillBase.cast_cue_reached(context) → SkillHostComponent.cast_cue_reached(context) → 原指令组件请求身份门禁。仅发布事实、复用当前战斗时钟，不扫描特效节点、不由视觉脚本控制战斗。测试：UnitSystem/Tests/SquadChainCastCueInputTest.gd。


## 连携按钮预约与施放显示（2026-10-24）

原黄色预约改为绿色描边；接收合法请求立即显示，四边从2px加粗至6px。角色实际开始施法（原command_started）后，显示同色边框与整块绿色底，不等待投射物发出或命中；成功释放仍按原Success Hold Seconds保留约0.3秒。失败/无效请求保留原红框，提示前被忽略的按键不影响显示；新合法预约会立即清除旧失败红框。没有改变输入门禁、技能动作、专注或评分。

配置入口：UnitSystem/Components/UI/SquadChainCommandDisplay.tscn → Panel → Theme，ChainWaiting为预约（绿色边框、透明底），ChainCasting为施放（绿色边框、绿色底），ChainFailed为失败（红色边框），均为可编辑的StyleBoxFlat，不新增脚本配置参数。StateBorder位于各Card的VBox之前，保证底色不会遮住文字和图标；缓存确认文字同步改为绿色。ChainCard样式为文字提供8px内边距，状态样式相应向外扩展8px，不挤压文字，也不改变原节点查询路径。测试扩展于UnitSystem/Tests/SquadChainInputDisplayTest.gd；原输入节奏测试继续保留。

本轮连携按钮显示回归：188项，186通过；仅既有CameraFollowControllerTest导航烘焙断言、SingleSceneFireboltTest旧射程断言失败。没有新增脚本错误、原生退出异常或退出泄漏。实际D3D12截图核对了绿框、绿底、红框与文字层级，记录位于.godot/chain_button_feedback_2026_10_24/。所有编辑通过Godot MCP Pro完成，正式UI场景UID有效，没有改动输入/技能机制或提交Git。


## 终结技按下预选、松开确认（2026-10-25）

长按达标自动释放的试验已撤回。终结窗口沿用原InputMap的squad_chain_1—4：按下合法选项时显示绿色6px边框并放大6%，持续按住只保留选中，不自动确认；松开该键即确认，不区分点按、短按或长按。确认后整块变绿，沿用原约0.12秒绿色反馈后交给既有终结技演出，避免执行者同步关窗吃掉反馈。只触发一次，重复松开不会再放。

原选择倒计时和5%慢放保持不变；按住不延长窗口，超时后松开不补放。暂停中松开取消本次选中，暂停期间不执行待确认终结技。此前修复的暂停边界保护继续保留；在松开和派发时复查角色可用性及身份，避免死亡、卸载或换槽误确认。开窗前已按住的键仍需先松开再重新按；多键继续保留首个有效选项，释放其他键不确认。

已移除Hold Confirm Seconds导出参数、hold_progress_ratio状态字段、四个HoldProgress节点和FinisherHoldProgress样式，不保留未使用的长按机制。配置入口仍为UnitSystem/Components/UI/SquadFinisherSelectionDisplay.tscn → Root/Cross → Theme：FinisherSelected为预选绿框，FinisherConfirmed为确认绿底。缩放与确认反馈时长沿既有内部封装，不新增Inspector参数；显示只读pressed_slot/selected_slot，不自行接收输入、计时或执行技能。程序化try_select_slot仍保留原同步确认接口。

测试覆盖四槽真实按下/松开、按住0.6秒不自动释放、确认反馈可见、暂停边界、超时、取消、持键尾部、多键、改键及单次执行。正式CombatRoomFinisherFlowTest与PlayerSkillCombinedFlowTest恢复真实短按/松开输入，不再人为等待0.55秒。备份、截图和验证日志在.godot/finisher_release_restore_2026_10_25/。没有修改技能内容、专注、评分、连携节奏、镜头或终结动作。

本轮松开确认回归：188项，186通过；仅既有CameraFollowControllerTest导航烘焙断言、SingleSceneFireboltTest旧射程断言失败，没有新增脚本错误、退出泄漏或原生退出异常。D3D12真实输入截图显示按住0.6秒仍为预选，松开后进入绿色确认。主场景编辑视图已在确认无未保存标记后刷新，Inspector不再保留长按参数。所有编辑通过Godot MCP Pro完成；本轮没有提交Git或覆盖导出游戏。


## 地形高度跟随与缩放俯角（2026-10-27）

配置入口：各关卡的 `CameraRig`，脚本 `UnitSystem/Components/Camera/CameraFollowController.gd`。无需给 Hero 额外挂载组件。

- **Follow → Lock Vertical Follow**：默认关闭。镜头随目标的世界 Y 高度移动；打开则保留首次绑定高度。**Follow Smoothness** 控制追随速度，**Camera Offset** 设定基础偏移（米）。跨层或传送距离超过 **Snap Distance** 时直接对齐。
- **Zoom → Zoom Distances / Initial Zoom Step / Zoom Smoothness**：沿用现有滚轮 InputMap 和距离档位；距离为相对基础视距的增量（米）。平滑视距同时驱动高度和俯角，连续滚轮输入不会排队。
- **Zoom Pitch → Zoom Pitch Enabled**：默认开启。只有最接近角色的两个档位降低俯角；从第三近档起，所有更远档位保持常规角度，只改变视距。关闭恢复固定角度的原缩放方式。
- **Zoom Closest Pitch Degrees**：最近档下视俯角，默认30°；**Zoom Farthest Pitch Degrees**：第三近及更远档位共用的常规俯角，默认50°，字段名沿用旧配置。默认四档从近到远为30°、45°、50°、50°。角度相对世界水平面，范围1°—85°；常规角度小于最近角度时按最近角度处理。
- **Zoom Focus Height M**：观察点离玩家脚底的高度，默认1米。用于镜头降低后保持躯干构图；不影响技能自身的特写观察点。

空缩放数组保留原始相机姿态；单档使用最近俯角。FOV保持不变，命中反馈统一叠加在变焦姿态上，技能特写结束恢复相同档位的角度和位置。近/远俯角、观察高度、开关可在运行时 Remote Inspector 调整；修改档位数组和初始档位应重新运行场景。

验证：`UnitSystem/Tests/CameraTerrainZoomTest.gd` 覆盖升降跟随、默认30°/40°/50°/50°档位、远档过渡角度不变、更多非等距档位仅最近两档变俯角、平滑高度、运行时角度调整、反馈及特写恢复、旧固定模式、空数组和单档。`CameraSkillFocusTest` 与 `FinisherCinematicOcclusionTest` 回归通过；`CameraFollowControllerTest` 仅保留修改前同样存在的 TestCombatRoom 导航未烘焙断言失败。
