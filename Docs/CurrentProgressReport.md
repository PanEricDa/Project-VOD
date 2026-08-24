# 当前项目进度报告

更新日期：2026-07-31

## 当前运行入口

- 项目主场景：`res://Scenes/TestScene2.tscn`
- 玩家实例：`res://UnitSystem/Player/Hero/Hero.tscn`
- 当前 Godot 版本：4.7
- 当前活动框架：`UnitSystem`、`SkillSystem`、`Item`、`Effects`

旧 Hero、旧 Ally/Enemy、旧 AI AttackModule、旧 SkillModule 及其历史文档已经移入 `res://Archive`，不再属于活动运行路径。

## UnitSystem

当前单位继承链：

```text
UnitBase
├── PlayerBase
│   └── Hero
└── AIUnitBase
    ├── AllyBase2
    │   ├── Archer
    │   ├── Caster
    │   ├── Guardian
    │   ├── Priest
    │   └── Saber
    └── EnemyBase2
```

`UnitBase` 统一提供：

- `CharacterBody3D` 单位根节点
- 生命上限和初始生命百分比
- `faction_id`、`team_id`、`targetable`
- `SkillHost/SkillSocket`
- `Visual` 插槽
- `WorldUIRoot/WorldHealthBar`：独立头顶血条组件
- 基础碰撞体
- `attack_power` 与 `defense`：负值在公开 getter 中收敛为 0

`CombatValueResolver` 统一结算：伤害为非负基础值加攻击力比例后，再按目标防御和连击倍率计算；治疗同样读取基础值和攻击力比例，但不受目标防御影响。空、失效或死亡目标不会进入实际生命值变更。

`PlayerBase` 负责玩家移动、冲刺、锁敌与玩家普通攻击。`AIUnitBase` 负责导航、移动、冲刺、朝向和武器装配接口。

`WorldHealthBar` 使用 SubViewport、Control 与 Sprite3D Billboard 显示白色圆角边框、
半透明黑色底槽、绿色实时生命和红色延迟损血。组件默认隐藏，只由有效伤害唤醒；
最后一次受伤后的可见时间、淡出时间和红条动画均可在 Inspector 调整。隐藏期间
SubViewport 停止更新。UnitBase 脚本不持有该 UI 的引用。

本轮同时把 PlayerBase 与 AIUnitBase 复活回调中会遮蔽 UnitBase 字段的
`_current_health` 参数统一重命名为 `_revived_health_value`。

## AI 与状态机

友方 AI 当前使用：

- `AITargetingComponent`：球形感知、持续刷新和敌方锁定。
- `TargetSelectionPolicy`：集中定义当前最近敌方策略。
- `AllyBehaviorStateMachine`：统一处理阵型游荡、追击、攻击、技能接近、脱战和归队。
- `FormationPositionData`：把阵型位置参数保存为可复用的强类型 `.tres`。

战斗状态下，AI 使用武器攻击距离接近目标，并可在攻击距离附近低速随机横向游荡。玩家离战场过远时，AI 退出战斗并复用原阵型跟随逻辑归队。

## 玩家战斗

玩家普通攻击由以下内容协作：

- `PlayerAttackController`
- 角色 Visual 内的 `AnimationPlayer`
- `WeaponData.animation_library`
- `MeleeHitboxComponent`
- `HitFeedbackBridge`

当前支持：

- 鼠标左键攻击
- 输入缓存
- 连击重置窗口
- 按住自动连击
- 冲刺取消当前动作但保留下一段连击
- 武器数据驱动的真实攻击前移
- 近战盒体判定
- 局部卡刀与摄像机震动
- `IronSwordData.tres` 保留既有 UID `uid://bu388bdhai45r`，并配置三段倍率 `0.9`、`1.0`、`1.25`

## AI 普通攻击

AI CombatSystem 分为：

- `AICombatSystem`：共同的武器装配、攻击控制和公共冷却。
- `AIMeleeCombatSystem`：近战命中盒交付。
- `AIRangedCombatSystem`：动画方法轨道释放投射物。

当前 AI 普通攻击公共冷却默认由单位战斗流程控制。近战和远程动作都读取武器 AnimationLibrary；AI 攻击不执行玩家武器数据中的真实前移。

## SkillSystem

当前是单场景技能架构。一个具体技能只维护一个继承自 `SkillBase.tscn` 的技能场景。

已经接入：

- `FireboltSkill.tscn`
- `HolyLightSkill.tscn`
- `SkillHostComponent`
- 投射物、目标瞬发和地面区域 DeliveryConfig 基类
- 统一目标关系与目标选择算法
- AI 自动技能延迟、低概率额外犹豫、技能冷却和共享动作冷却
- 动画驱动的 `release_action()` 与 `finish_action()`

AI 敌方锁定目标和一次技能解析出的临时目标拥有不同生命周期；治疗友方不会覆盖当前敌方战斗锁定。

`HealthChangeSkillEffect` 已统一用于 Firebolt 伤害和 HolyLight 治疗。Tracking projectile 先在投射物生命周期内确认目标，再由 DeliveryRunner 交付 Effect；重复施法测试覆盖同步 launch 生命周期保护。

玩家近战、AI 近战与 AI 远程普通攻击均已进入真实伤害结算，而不是只播放命中表现。

## 死亡与复活

死亡单位不可再被选中、移动、攻击或施法，但保留重力和碰撞；复活只恢复新的行动资格，不恢复旧动作状态。

## Item 与投射物

武器位于 `res://Item/Weapon`，当前包含：

- Bow
- MagicGlobe
- Shield
- Staff
- Sword

共同数据由 `WeaponData` 提供；近战和远程分别使用 `MeleeWeaponData`、`RangedWeaponData`。

投射物位于 `res://Item/Projectiles`。箭矢和火球的运行脚本已迁移到投射物目录，不再依赖旧 `Scripts` 根目录。

## Effects

- `Effects/Combat`：玩家和 AI 可复用的命中停顿配置，玩家额外使用摄像机震动。
- `Effects/Skills/Fireball`：蓄力、飞行和爆炸表现。
- `Effects/Skills/HolyLight`：金白色单体治疗表现。

## 测试状态

2026-07-31 头顶血条实施后的最终验证实际枚举到 44 个继承 `SceneTree` 的可运行脚本，全部以独立 headless 子进程运行：

- 通过：44
- 失败：0
- 超时：0

新增 `WorldHealthBarTest.gd` 覆盖初始隐藏、自动绑定、绿条实时变化、红条延迟消退、
重复伤害刷新计时、治疗不唤醒、解绑和隐藏时停用 SubViewport。CombatValueResolver、
WeaponDataInheritance、玩家近战、AI 近战与远程、Firebolt、HolyLight、DeliveryRunner、
死亡/复活、重复施法生命周期和 Resource UID 审计等既有测试继续通过。
`ResourceUidAuditTest` 通过 27 个活动 `.tres`。

`ShieldAnimationLibraryTest.gd` 已移除对人工单武器工作台永久挂载的陈旧依赖，`WeaponAttackRangeTest.gd` 已更新为 IronSword 当前的 1.1m，两项均通过。HolyLight 正式场景保留 UID `uid://fd88atot6qs4`，现在使用 `FRIENDLY` 加 `NEAREST`：不把施法者加入治疗候选，确定治疗最近的有效友方。Priest 自动治疗运行时测试以该正式策略连续独立运行 20 次，全部通过。

Godot 4.7 独立 headless 编辑器扫描和主场景 `--quit-after 120` 均以退出码 `0`
完成。Godot MCP Pro 实际运行主场景时确认所有活动单位都继承
`WorldUIRoot/WorldHealthBar`；对 EnemyBase2 施加 20 点测试伤害后，绿条立即到 `0.8`、
红条保持 `1.0`，2.5 秒后隐藏且 SubViewport 更新模式回到 Disabled。
本轮运行 Output 没有新增 error/warning。正式血条场景 UID 为
`uid://c7wet0ko35ola`。

## 尚未完成

- 为当前项目中的陈旧测试建立独立修复任务。
- 继续扩展正式技能、数值、伤害和治疗规则。
- 为更多角色与武器制作正式美术动画。
- 在确认观察期安全后，由用户决定是否永久删除 Archive 中的旧实现。
- 暂缓：暴击、Buff、护盾、威胁、掉落、关卡失败，以及 Focus 数值影响。
## 2026-08-01 视觉场景结构整理

- 新增唯一公共视觉父场景 `res://UnitSystem/Visuals/Base/UnitVisualBase.tscn`。
- Ally、Enemy、Player 视觉场景统一迁移到 `res://UnitSystem/Visuals/`。
- 公共父场景只提供 `CharacterRoot`、`ModelRoot`、`WeaponSocket`、`ProjectileOrigin` 和 `CharacterAnimationPlayer`，不包含具体模型。
- 删除旧的 `00-UnitBaseVisual`、`AllyBaseVisual`、`EnemyBaseVisual` 和旧 HeroVisual 路径。
- 动画工作台迁移至 `res://UnitSystem/Visuals/Workbench/HeroAnimationWorkbench.tscn`。
- 未修改 `TestScene` 中的单位实例。
- 验证：UnitDirectoryLayoutTest、AIVisualContractTest、CasterSkillActionAssemblyTest、ResourceUidAuditTest 全部通过，Godot 4.7 编辑器扫描无错误。
## 2026-08-01 通用基础动画接入

- `BasicAnimationLibrary.res` 已挂载至 `UnitVisualBase/CharacterAnimationPlayer` 的 `unit` 动画库槽位。
- 当前通用动画路径为 `unit/Die` 和 `unit/RESET`。
- `Die` 动画末尾已加入 `finish_death_animation()` 方法轨道。
- `UnitStateComponent` 收到死亡信号后，会在其他死亡清理监听器完成后播放 `unit/Die`；复活时播放 `unit/RESET`。
- 动画播放器通过 `CharacterAnimationEventPlayer` 提供播放、结束通知和复位接口，不新增节点。
- 角色动画库仍使用 `character`，武器动画库仍使用 `weapon`，互不覆盖。
- 验证：UnitDeathAnimationIntegrationTest、UnitDeathLifecycleTest 通过，Godot 4.7 编辑器扫描无新增警告。
## 2026-08-01 UnitStateComponent 参数简化

- `Death Lifecycle` Inspector 分类改为 `Death Response`。
- 动画库和动画名称改为脚本内部协议 `unit/Die`，不再暴露为可输入字段。
- 移除死亡后的自动隐藏逻辑；模型保持可见直到单位销毁或复活。
- 删除重复的 `effect_duration`，外部效果场景自行管理表现时长。
- `death_cleanup_mode` 改为 `death_mode`，选项为 `KEEP_FOR_REVIVE`、`REMOVE_AFTER_DELAY`、`REMOVE_IMMEDIATELY`。
- `destroy_delay` 改为 `remove_after_seconds`，语义为从死亡开始计算的最短保留时间；死亡动画未结束时会自动等待动画完成。
- `visual_path` 改为内部固定路径 `Visual`，不再让设计者重复输入。
