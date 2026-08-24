# SipSip 当前实现概要

> 更新日期：2026-07-16  
> 目标版本：Godot 4.7（Forward Plus，Jolt Physics）

本文用于快速了解项目目前已经完成的原型系统、主要文件和后续维护边界，不记录逐行代码细节。

## 1. 项目基础配置

- 主场景：`res://Scenes/TestScene.tscn`
- 游戏分辨率：2560 × 1440（2K）
- 物理层：`World`、`Friendly`、`Enemy`
- 已安装并启用 Godot MCP Pro，Codex 可通过 MCP 检查和操作 Godot 编辑器。
- `AGENTS.md` 规定：任何单位实例都必须由用户手动添加到 `TestScene`；Codex 只能提供添加指引，并可修改单位源场景或脚本。

## 2. 玩家 Hero

主要文件：

- `res://Scenes/ObjectScenes/Hero.tscn`
- `res://Scripts/HeroController.gd`
- `res://Scripts/CameraFollowController.gd`

当前功能：

- 传统 3D Top Down 移动，角色朝向平滑旋转。
- 重力、可配置移动速度与加速度。
- 冲刺具有距离、速度、最大连续次数和冷却参数；默认连续两次、冷却 2 秒。
- 鼠标点击选择敌方目标；点击地面或目标超过默认 5 米时解除锁定。
- `F` 键自动锁定距离玩家最近的敌人。
- 锁定时玩家持续面向目标；伙伴编队以玩家实际正面朝向为参照。
- 玩家锁定范围以圆环显示：通常为绿色，锁定目标后变为红色。
- 玩家与友方不设置实体碰撞，可相互穿过。

### InputMap

所有玩家操作均通过 Godot InputMap：

| Action | 默认输入 | 用途 |
|---|---|---|
| `player_move_forward/backward/left/right` | WASD / 方向键 | 移动 |
| `player_dash` | 已配置键盘按键 | 冲刺 |
| `player_target_select` | 鼠标中键 | 鼠标目标选择 |
| `player_target_nearest` | F | 最近目标锁定 |
| `player_attack` | 鼠标左键 | 三连击 |

## 3. 摄像机与环境

- 固定方向的 Top Down Camera，不允许玩家旋转或缩放。
- 当前镜头角度约 50°，角色位于画面中心轻微偏下。
- 使用平滑跟随、移动方向前瞻、最大跟随距离和过远瞬移复位。
- 摄像机位置、跟随平滑度、前瞻距离等参数均通过 `CameraFollowController.gd` 导出到 Inspector。
- `TestScene` 已配置基础地面、灯光和视觉环境。

## 4. 友方伙伴架构

主要文件：

- `res://Scenes/ObjectScenes/AllyBase.tscn`
- `res://Scripts/AI/AllyBase.gd`
- `Guardian.tscn`、`Warrior.tscn`、`Ranger.tscn`、`Healer.tscn`、`Mage.tscn`
- `res://Scripts/AI/MageAlly.gd`

`AllyBase` 负责共通逻辑：

- 读取玩家实际正面并计算编队中心。
- 在指定编队区域内平滑移动和随机游荡。
- 玩家转向、距离过远或持续移动且伙伴掉队时进行追赶冲刺。
- 重力、平滑转向、到达减速和冲刺冷却。
- 在圆形感知范围内定期搜索最近敌人；发现目标后始终面向敌人。
- 感知圈无敌人时显示浅灰色，有敌人时显示橙红色。
- 默认待机游荡刷新间隔为 1.5～3 秒。

各职业目前只定义原型外观和编队差异：

- `Guardian`：玩家前方区域，装备可拆装的 `ShieldAttack` 盾击模块。
- `Warrior`：沿用 Guardian 的近战调度，装备可拆装的 `SwordAttack` 长剑模块，攻击距离略长。
- `Ranger`：玩家后方一侧，装备可拆装的 `CrossbowAttack` 十字弓模块，发射快速追踪抛物线 Arrow。
- `Healer`：位于队伍中后方，携带简易法杖。
- `Mage`：与 Ranger 类似但距离更远；`MageAlly.gd` 与 Ranger 共享分侧维护逻辑，优先选择相反一侧，减少重叠和反复横跳。

Guardian 盾击、Warrior 长剑和 Ranger 十字弓普通攻击已经实现；Mage 已实现自动调度的 Fireball 技能。Healer 的治疗/保护、Mage 的其他职业技能及所有实际伤害结算仍未实现。

## 5. 敌方架构

主要文件：

- `res://Scenes/EnemyScenes/EnemyBase.tscn`
- `res://Scripts/AI/EnemyBase.gd`
- `res://Scenes/EnemyScenes/Dummy.tscn`

- `EnemyBase` 提供敌方身份、基础物理与重力，使其能被玩家和伙伴检测。
- `Dummy` 是继承自 EnemyBase 的测试靶子，使用八边形圆柱体和简易木刀外观。
- 当前敌人只作为可感知、可锁定、可命中的靶子，没有生命值、受伤或战斗 AI。

## 6. 可拆装三连击模块

主要文件：

- `res://Scenes/Components/MeleeAttackModule.tscn`
- `res://Scripts/Combat/MeleeAttackModule.gd`

模块实例位于 `Hero/Visual/AttackSpinPivot` 下，与 `HeroController.gd` 完全解耦。删除模块后，玩家移动、冲刺、重力和锁定仍可正常工作。

当前攻击流程：

- 三段临时方块剑动画，支持 0.15 秒输入缓存和 0.7 秒连击续接。
- 每段攻击具有独立的轻微前移，默认距离为 0.20 / 0.25 / 0.35 米。
- 第三击先逆时针转 90°蓄力，暂停后再顺时针旋转一圈并恢复正向。
- 第三击蓄力暂停通过 `third_attack_spin_windup_pause` 调整，当前默认 0.2 秒。
- 第三击的蓄力与暂停阶段不进行命中检测，正式顺时针攻击阶段才开启判定。
- 模块提供连击、攻击开始/结束、判定窗口、命中、前移和旋转等公共信号，方便未来替换正式动画。

## 7. 临时近战命中检测

主要文件：

- `res://Scripts/Combat/MeleeHitDetector.gd`
- `res://Docs/TemporaryMeleeHitDetection.md`

由于当前剑动画只是占位表现，命中不依赖剑刃实际位置，而是在玩家稳定正前方执行三段不同尺寸的盒形空间查询。

- 只检测 `Enemy` 物理层。
- 每个敌人每一段攻击最多命中一次，下一段可再次命中。
- 检测盒尺寸、前向偏移、高度、最大查询数量和调试颜色均可在 Inspector 调整。
- 调试盒在有效窗口内显示，命中后由黄色切换为红色。
- 对外统一使用 `attack_hit(target, hit_position, hit_direction, combo_index)` 信号。
- 正式动画接入后，应替换为基于 `BladeBase` / `BladeTip` 的剑刃扫掠，但尽量保留现有公共信号接口。

## 8. 命中反馈系统

主要文件：

- `res://Effects/Combat/HitFeedbackBridge.tscn`
- `res://Effects/Combat/HitFeedbackBridge.gd`
- `res://Effects/Combat/HitFeedbackProfile.gd`
- `res://Effects/Combat/DefaultMeleeHitFeedback.tres`

命中反馈通过效果桥监听 `MeleeAttackModule.attack_hit`：

- 局部卡刀只暂停攻击动画、攻击前移、第三击旋转和命中查询，不暂停游戏世界或玩家控制。
- Camera3D 使用局部 X/Y 随机位移产生衰减震动，结束后精确复位。
- 同一帧多目标命中会合并视觉反馈，防止重复暂停叠加。
- 三段反馈倍率保存在 `combo_intensity_multipliers` 数组中，当前配置为 `0.425 / 0.5 / 1.3`。
- 默认资源中的基础卡刀时间当前为 0.225 秒；实际卡刀时间为基础值乘以对应连击倍率。
- 删除 `HitFeedbackBridge` 不会影响攻击和命中检测本身。

### AI 普通攻击命中停顿

- AI 攻击父场景同样复用 `res://Effects/Combat/HitFeedbackBridge.tscn`，无需为每种武器复制反馈脚本。
- AI 专用配置为 `res://Effects/Combat/DefaultAIHitFeedback.tres`：默认停顿 `0.12s`、
  最小反馈间隔 `0.03s`、摄像机震动关闭。`0.06s` 在角色持续环绕时辨识度不足，
  因此提高为仍然短促但能看清的 0.12 秒。
- 命中时只暂停当前 AI 攻击模块的动画与 Hitbox 查询；伙伴移动、朝向、重力、公共冷却和整个世界继续运行。
- `AIAttackModuleBase.hit_feedback_enabled` 可在具体继承武器的 Inspector 中单独关闭反馈，原始 `attack_hit` 信号仍会继续发送。
- AI 和玩家共用效果桥接口：AI 三参数命中默认按第一段强度处理，玩家原有四参数连击接口保持不变。

## 9. AI 可拆装普通攻击

### Guardian 盾击

- Guardian source: `res://Scenes/ObjectScenes/Guardian.tscn`
- Weapon module: `res://Scenes/Components/AiAttackModules/ShieldAttack.tscn`
- Profile: `res://Resources/Combat/AI/GuardianShieldAttackProfile.tres`
- Attack range: 0.8m；从警戒距离接近后盾击，攻击结束留在近战范围等待公共冷却。
- Shared systems: `AllyBase` 接近/公共冷却/近战保持、继承的 AI Hitbox、继承的 AI hit-stop feedback。

### Warrior 长剑攻击

- Warrior source: `res://Scenes/ObjectScenes/Warrior.tscn`
- Weapon module: `res://Scenes/Components/AiAttackModules/SwordAttack.tscn`
- Profile: `res://Resources/Combat/AI/WarriorSwordAttackProfile.tres`
- Attack range: 1.0m（Guardian is 0.8m）
- Selection: `attack_1/2/3` random bag；每袋各出现一次，袋边界不立即重复。
- Shared systems: `AllyBase` approach/GCD/hold、继承的 AI Hitbox、继承的 AI hit-stop feedback。
- TestScene: 后续新增或调整 Warrior 实例必须由用户手动完成；Warrior 应与 Guardian 放在同一父节点下（当前为 TestScene 根节点），并设置在地面上不会与 Guardian 或其他单位重叠的位置。Codex 不代替用户添加、移动或重建该实例。

### Ranger 十字弓射击

- Ranger source: `res://Scenes/ObjectScenes/Ranger.tscn`
- Weapon module: `res://Scenes/Components/AiAttackModules/CrossbowAttack.tscn`
- Profile: `res://Resources/Combat/AI/RangerCrossbowAttackProfile.tres`
- Projectile: `res://Scenes/Projectiles/Arrow.tscn`
- Attack range: `6.5m ± 0.4m`；当前 Ranger 源场景的单位独立公共冷却为 `2.0s`。
- Projectile flight: 默认 `0.30s` 飞行时长、`0.80m` 弧高、`0.25m` 目标高度偏移；飞行期间持续读取目标最新位置并保证抵达仍有效的目标。
- Post-attack state: `return_to_guard_after_attack=false`，攻击后留在射程附近进入 HOLD 并复用战斗游荡，不返回当前 `5.0m` 警戒距离。
- Delivery: 不启用近战 ShapeCast；Arrow 抵达后由 CrossbowAttack 转发统一 `attack_hit`，当前不产生伤害、阻挡、击退或远程命中停顿。
- 当前 Ranger 源场景中的 `enemy_vision_range=6.5m`、`combat_guard_distance=5.0m` 是用户在实施期间调整的 Inspector 参数，攻击模块装配保留这些值。

### 攻击模块场景装配规则

- 具体武器实例必须直接放在 `VisualRoot/AttackModuleSocket` 下，节点名称只填写模块名称，例如 `ShieldAttack`、`SwordAttack` 或 `CrossbowAttack`。
- `attack_module_path` 必须与实际场景树完全一致，例如 `VisualRoot/AttackModuleSocket/SwordAttack`。
- 不要把完整层级路径填写进节点名称，也不要把武器模块放在角色根节点下。类似 `VisualRoot_AttackModuleSocket#SwordAttack` 的名称表示节点名称和父级关系创建错误，并不是脚本中定义的有效路径。
- 在 Inspector 中修改职业参数并保存后，应再次确认模块仍位于 `AttackModuleSocket` 下；正确装配后，修改其他 Warrior 参数不会导致攻击模块丢失。

## 10. 单体圣光治疗视觉特效

主要文件：

- `res://Effects/Healing/HolyLightHealEffect.tscn`
- `res://Effects/Healing/HolyLightHealEffect.gd`
- `res://Effects/Healing/HolyLightHealEffectPreview.tscn`

这是一个与生命值系统完全解耦的可复用单体治疗视觉组件：

- 默认总时长 `0.5s`，仅使用暖金、象牙白和纯白，不包含绿色元素。
- 视觉由地面金色光环、短暂圣光柱、上升光点、四向白金闪光和局部 OmniLight3D 组成。
- 提供 `play()`、`stop()`、`reset_effect()`、`is_playing()`，并发送 `effect_started` / `effect_finished` 信号。
- 可在 Inspector 调整时长、三组颜色、光环半径、光柱尺寸、粒子数量、灯光能量与范围；灯光峰值会写入每个实例独享的动画资源，不会污染其他实例。
- `auto_free_on_finished` 决定自然播放结束后是否释放实例，便于直接生成或对象池复用。
- 预览场景可独立循环查看效果，不依赖也不修改 TestScene；当前阶段不执行生命值恢复、目标筛选或治疗结算。

验证结果：专用契约测试及现有 9 个战斗测试全部通过，Godot 4.7 Headless Smoke 退出码为 0，MCP 编辑器错误数为 0。TestScene 保持 SHA-256 `179A711803F0C03ECEFC8C91F3807DBC1C5AE64F6F044134E9E9C66AEB643B7E` 不变。

## 11. 通用技能调度与 Mage Fireball

主要文件：

- `res://Scenes/Components/SkillModules/SkillModuleBase.tscn`
- `res://Scripts/Combat/Skills/SkillModuleBase.gd`
- `res://Scripts/Combat/Skills/SkillProfile.gd`
- `res://Scenes/Components/SkillModules/FireballSkill.tscn`
- `res://Scripts/Combat/Skills/FireballSkill.gd`
- `res://Resources/Combat/Skills/MageFireballProfile.tres`
- `res://Scenes/Projectiles/FireBall.tscn`
- `res://Scripts/Combat/Skills/FireballProjectile.gd`
- `res://Scenes/ObjectScenes/Mage.tscn`

`SkillModuleBase` 是不依赖 `AllyBase` 的通用技能组件：

- 内部状态为 `READY / DECISION_WAIT / QUEUED / CASTING / COOLDOWN`。
- 决策等待、额外犹豫、施法时间、距离容差和技能冷却全部来自 Profile。
- 父模块验证通用 `Node3D` owner、目标、可选目标组和水平施法距离，但不搜索目标、不移动角色、不计算命中或治疗。
- 外部宿主在移动、动作占用和公共冷却均允许时调用 `begin_cast()`；施法开始立即发送 `cast_started`。
- 施法结束再次检查目标和距离；具体技能通过覆盖 `deliver_skill()` 实现交付，只有成功交付才启动技能专属冷却。

AllyBase 只作为单向宿主：

- 维护 `VisualRoot/SkillModuleSocket` 直接子节点的通用多技能注册表，并保留 `skill_module_path`、`set/get_skill_module()` 作为主技能兼容入口。
- `SkillModuleBase` 不引用 AllyBase；AllyBase 只连接父模块公共信号。
- 默认在可请求且目标有效的模块中选择最高 `ai_priority`；同优先级随机择一，同一时间只有一个 active skill slot。
- 默认目标解析为 `ENEMY` 使用当前感知敌人、`SELF` 使用自身；`ALLY` 暂时返回 null，留给 Healer 等专用宿主覆盖。
- 自动流程为决策等待、超距独占接近、普通攻击/公共冷却门控、施法移动与朝向控制、交付，以及成功冷却或失败重试/释放。
- 技能正式开始施法时，复用当前单位的 `basic_attack_global_cooldown` 立即启动公共冷却；技能专属冷却仍由模块独立维护。
- 最终距离校验失败会对仍然结构有效的目标重新进入决策等待并保留 active slot；目标失效、取消、重置或卸载会释放移动所有权和 slot。
- 公共冷却和技能冷却独立计时；施法已开始后的取消不会清除已启动的公共冷却。

Mage 现在在源场景的 `VisualRoot/SkillModuleSocket/FireballSkill` 装配功能完整的 FireballSkill，并通过上述通用调度自动选择目标、接近、施法和发射。其他职业未挂载技能模块，现有普通攻击行为保持不变。

Fireball Profile 默认值：`display_name="Mage Fireball"`、`target_faction=ENEMY`、`delivery_type=PROJECTILE`、`required_target_group="enemy_targets"`、`ai_priority=0`、`can_move_while_casting=false`、施法距离 `6.0m ± 0.25m`、施法时间 `0.75s`、技能冷却 `5.0s`、决策等待 `0.3–3.0s`，每次请求有 `10%` 概率额外犹豫 `3.0–5.0s`。

Fireball 模块/投射物可调值与语义：

- `FireballSkill.gd` 默认 `cast_origin_path=CastOrigin`、速度 `9.0m/s`、最大转向 `180°/s`、最长生命周期 `3.0s`、爆炸半径 `1.2m`；只有世界所属投射物成功 launch 后才进入技能冷却，缺少 Profile、场景、CastOrigin、当前 gameplay scene、目标或 launch 契约时安全失败且不启动技能冷却。
- `FireBall.tscn` 使用半径 `0.18m` 的球形扫掠，环境+敌方 mask 为 `5`，爆炸只查询敌方 mask `4`，不包含友方层。多个碰撞按飞行方向投影选择最近接触；爆炸半径精确为零时执行点查询。
- 追踪目标失效后保持最后方向直线飞行，直到碰撞或生命周期结束；蓄力、飞行、爆炸分别复用已批准的 `FireballCastChargeEffect.tscn`、`FireballFlightEffect.tscn`、`FireballExplosionEffect.tscn`。
- 模块和投射物只发送/转发信号，不读取或写入生命值，不结算伤害、击退、燃烧/状态或命中反馈。

TestScene 仍由用户管理：如果场景中已有用户放置的 Mage，源场景更新会自动继承；如果没有，用户需在 Godot 编辑器中把 `res://Scenes/ObjectScenes/Mage.tscn` 手动拖到 TestScene 根节点（与其他单位同级），放置在地面上。伙伴行为会自动识别唯一 `faction_id = "Player"` 的玩家单位，不需要维护角色路径或额外玩家标签。用于观察施法的用户放置 Dummy 必须处于 Mage 感知范围及玩家交战限制内。Codex 不添加、移动或重建这些单位实例。

## 12. 当前原型边界与后续重点

以下内容尚未实现或仍属于临时方案：

- 敌我生命值、伤害结算、死亡、击退和硬直。
- Healer 的治疗/保护、Mage 的其他职业技能，以及 Fireball 的实际伤害结算。
- 敌方战斗 AI。
- 正式角色模型、骨骼、武器挂点和攻击动画。
- 基于真实剑刃轨迹的命中检测。
- 音效、粒子、伤害数字等完整战斗反馈。

后续接入正式资产时，应优先保留现有模块边界和公共信号，替换视觉动画与检测器内部实现，避免把战斗逻辑重新混入 `HeroController.gd`。

## 13. 新 UnitSystem 移动继承链

`res://UnitSystem` 已建立一套与旧单位并行存在的新基础结构：

```text
UnitBase
├── PlayerBase
└── AIUnitBase
    ├── AllyBase2
    └── EnemyBase2
```

- `UnitBase` 只维护生命、阵营关系和能否成为目标，并提供通用的 `Visual` 与碰撞体基础节点。
- `PlayerBase` 独立读取现有 InputMap，提供平滑移动、移动朝向、重力、连续两次冲刺和冲刺冷却；尚未迁移目标锁定、攻击或摄像机。
- `AIUnitBase` 直接管理 AI 的导航速度、重力、朝向、冲刺和
  `move_and_slide()`；`MovementSystem` 只保留共享的 `NavigationAgent3D`。
- `AIUnitBase.set_movement_target()` 支持独立控制“是否朝向移动方向”，使战斗单位
  可以横向移动但持续面向敌人。
- `AllyBase2` 根节点装配单一 `BehaviorStateMachine`，统一管理
  `FORMATION_WANDER / FORMATION_REPOSITION / COMBAT_APPROACH /
  COMBAT_HOLD / COMBAT_ATTACK / RETURN / CUSTOM`。
- 伙伴状态机默认自动查找唯一 `faction_id = "Player"` 的单位，因此不再维护容易因
  改名失效的 `player_path` 或额外的玩家身份标签。
- 运行时可在状态机的 Inspector `Debug > Current Follow Target` 中只读查看当前
  实际跟随对象；该字段不参与保存，也不能改变跟随算法。
- 需要临时跟随队长、护送对象或其他 AI 时，可调用
  `BehaviorStateMachine.set_follow_target(target)`；传入 `null` 即恢复自动跟随玩家。
- 原 Formation 编队中心、随机游荡、分侧稳定、掉队追赶和冲刺算法已经迁入状态机；
  旧 `FormationComponent` 与 `LocomotionComponent` 均已删除。
- 未装备武器的 Ally 自主锁定敌人后会接近默认 `2m` 战斗距离，在允许环带中以低速
  轻微游荡并持续面向敌人；装备近战武器后则由武器的攻击距离覆盖此后备距离。
- `COMBAT_HOLD` 与 `COMBAT_ATTACK` 共用同一套低速持距环绕移动；攻击动画播放期间
  不再清空导航目标，但仍不会执行 AI 攻击位移 marker。环绕候选具有大于到达阈值的
  最小切向偏移，避免轻微距离修正被运动层直接判定为“已经到达”而长期站定。
- 玩家与当前敌人距离超过 `12m` 时 Ally 强制脱战并暂停索敌 `1.5s`，随后直接把
  移动控制交回原有 `FORMATION_REPOSITION` 编队跟随流程；距离足够远且冲刺可用时
  会复用既有紧急 dash，否则使用既有普通跟随。暂停结束后直接恢复正常索敌。
- `CUSTOM` 提供一个统一的未来状态入口和进入、更新、退出钩子，可继续扩展休息、
  互动、采集或剧情行为，而不需要预先创建空节点。
- `EnemyBase2` 当前没有敌方行为组件，因此只受通用重力并保持水平停驻，供未来巡逻和追击系统继承。

新系统尚未替换旧 Hero、AllyBase、EnemyBase 或任何职业场景；TestScene 仍完全由用户手动管理。后续应先单独预览和验证这些新基类，再按 Guardian、Warrior、Ranger、Healer、Mage、Dummy 的顺序逐个迁移。

## 14. 新 UnitSystem 通用 AI 近战战斗

新 AI 近战链路已在 `AIUnitBase` 层完成，Ally 与未来 Enemy 可共用同一战斗组件：

```text
AllyBehaviorStateMachine
  -> AICombatSystem（武器装配、普通攻击入口、1 秒公共冷却）
    -> AIAttackController（随机单段动画、动画事件）
      -> 忽略 AI 攻击位移 marker（角色身体不前移）
      -> MeleeHitboxComponent（通用敌我过滤与单窗口去重）
      -> HitFeedbackBridge（AI 局部卡刀，不震动摄像机）
```

主要实现：

- `AIUnitBase` 现在只保留空 `Visual` 插槽；`AllyBase2` 和 `EnemyBase2` 分别装载独立
  蓝色、红色方块视觉场景。两个视觉场景统一提供 `CharacterRoot`、
  `CharacterRoot/WeaponSocket` 和 `CharacterAnimationPlayer`。
- `CombatSystem` 默认挂载在所有 `AIUnitBase` 上，但默认不装备武器；无视觉、无武器
  时安全降级，不影响重力、移动、索敌或编队。
- 玩家和 AI 共用 `WeaponData`、武器视觉、AnimationLibrary、动画事件与 Hitbox 数据。
  玩家可继续消费 `attack_motion_requested` 实现攻击位移；AI 保留该信号的正常发出但
  不订阅执行，因此攻击时 CharacterBody3D 不会产生前移。
- `WeaponData.attack_range` 与 `attack_range_tolerance` 是近战最大可发动距离及容差；
  公共冷却期间单位继续复用原有持距游荡。
- AI 每次请求只从 `basic_attack_1...n` 随机播放一段；洗牌袋确保一轮内不重复，并
  避免相邻两轮边界播放同一动作。
- 普通攻击成功开始时立即启动默认 `1.0s` 公共冷却。目标失效、取消或强制脱战不会
  清除已经开始的冷却，也不能在动画尚未结束时重叠攻击。
- `MeleeHitboxComponent` 已由玩家专用组件泛化为玩家/AI 共用组件；本阶段只发送
  `attack_hit`，不结算伤害、生命值、击退或死亡。
- Amy 是第一例：其继承场景只覆盖 `CombatSystem.starting_weapon` 为
  `res://Item/Weapon/Sword/IronSwordData.tres`，会在自主锁定目标后接近至约
  `1.0m` 并执行剑攻击。

验证结果（2026-07-25）：

- 15 项 `UnitSystem/Tests/*.gd` Godot 4.7 headless 测试全部退出码为 0。
- Godot 4.7 项目文件扫描完成，无脚本错误。
- 当前活动目录中不存在 `res://Scenes/TestScene.tscn`（只有
  `res://Scenes/TestScene2.tscn` 与归档副本）；本次未创建或修改任何测试场景，也未
  删除旧 AI 攻击模块。
- 需要实机观察时，由用户在当前测试场景中手动添加 Amy 和目标单位；Codex 不代为
  添加或修改这些单位实例。

## 15. Ally 阵型位置资源与轻量防重叠

Amy 原本散落在状态机 Inspector 中的阵型中心和游荡范围，已迁移为强类型资源：

```text
res://UnitSystem/AI/Ally/Formation/FormationPositionData.gd
res://UnitSystem/AI/Ally/Formation/Positions/Forward.tres
```

设计师配置流程：

```text
创建或复制 FormationPositionData .tres
→ 在 Inspector 配置 Center Offset、左右/前后游荡范围和 Side Mode
→ 将资源赋给 Ally/BehaviorStateMachine/Formation Position
```

- 当前提供 `Defender / DefensiveMid / LeftWingBack / RightWingBack /
  AttackingMid / Forward` 六份通用位置资源。
- Amy 选择 `Forward.tres`，继续使用迁移前的数值：中心偏移 `(0, 2.5)`、左右半径 `1.1m`、
  前后半径 `0.65m`、允许自由跨越中线。
- 资源缺失时状态机使用相同的内建安全默认值并提供配置警告，不阻断移动或战斗。
- 运行时可以通过 `set_formation_position()` 替换资源；Combat/Custom 状态只保存选择，
  回到 Formation 或 Return 时才应用，避免阵型数据覆盖战斗移动目标。
- 防重叠只在 Formation 原本刷新游荡目标时运行：检查同队 AI 的当前位置和 Formation
  预定目标，最多生成 8 个候选，优先选择至少相隔 `0.65m` 的候选；全部拥挤时使用
  最近占用距离最大的候选。
- 该机制不增加持续分离力、碰撞、推挤、传送、独立计时器或阵型协调器；Combat 完全
  不运行候选占用算法。
- 同时修复了状态机初次配置时自动寻找 Player 会重复初始化两次的问题；初始 Formation
  目标现在只生成一次，运行时调用 `set_follow_target()` 仍会按原设计立即重算。

验证结果（2026-07-26）：

- 17 项 `UnitSystem/Tests/*.gd` Godot 4.7 headless 测试全部退出码为 0。
- Godot 4.7 headless 编辑器完整扫描退出码为 0，无脚本错误或警告。
- `Scenes/TestScene2.tscn` 最后修改时间仍为 2026-07-24 21:42:05，本次没有改写；
  归档场景和旧 `Scenes/Components/AiAttackModules` 目录均保留。

## 16. 外部 Resource UID 审计（2026-07-26）

- 当前项目共检查 37 个正式 `.tres` 资源，全部可以由 `ResourceLoader` 加载。
- 之前发现 UID 缺失的 6 个资源已通过 Godot 4.7 正式保存修复，当前结果为 `37/37` 均具有有效 `uid://`。
- 修复的资源包括 AI 攻击 Profile 与技能 Profile；资源参数未改动，仅补齐 Godot 资源登记信息。
- 新增 `UnitSystem/Tests/ResourceUidAuditTest.gd`，会递归检查所有 `.tres` 的 UID 和加载结果，防止再次产生无 UID 资源。
- Godot 4.7 headless 资源审计和编辑器扫描均退出码为 0；本次未修改任何测试场景单位实例。

## 17. AI Hitbox 调试盒 Transform 修正（2026-07-26）

- 玩家与 AI 继续共用 `MeleeHitboxComponent` 的实际盒形查询和 `attack_hit` 信号，组件不依赖 PlayerBase。
- 调试盒改为 `top_level = true` 的世界空间显示节点；每个物理帧直接使用与查询相同的世界 Transform。
- 结束窗口时清理 `global_transform`，避免上一轮攻击或其他单位的父级 Transform 在下一轮短暂残留。
- 新增回归断言：调试盒必须独立于父级 Transform，并与 AI 持有者的查询位置一致。
- `MeleeHitboxComponentTest` 通过，Godot 4.7 headless 编辑器扫描通过。

## 18. 单位根节点装备与编辑器预览（2026-07-26）

- `AIUnitBase` 与 `PlayerBase` 根节点现在直接暴露 `starting_weapon`。
- `AllyBase2` 根节点直接暴露 `formation_position`；设计师不需要进入
  `CombatSystem` 或 `BehaviorStateMachine` 子节点重复配置。
- 原有子节点仍保留运行时 setter，但不再向 Inspector 暴露同名字段。
- `EditorWeaponPreview.gd` 仅在编辑器中读取根节点武器数据，并把武器视觉临时生成到
  `CharacterRoot/WeaponSocket`；预览实例不保存、不加载动画、不连接攻击或 Hitbox。
- Hero、Guardian、Warrior 的正式配置已迁移到各自根节点，未修改 TestScene 单位实例。

## 19. AI Hitbox 原点闪现回归修正（2026-07-26）

- 原因：`MeleeHitboxComponent.end_detection()` 将独立世界空间调试盒重置为
  `Transform3D.IDENTITY`，造成下一次窗口打开前短暂位于世界原点。
- 修正：关闭窗口时只隐藏调试盒并清除检测状态，保留最后一次有效世界 Transform；
  下一次窗口仍会在首个物理帧使用新的查询 Transform 覆盖。
- 新增回归断言，验证非原点 AI 持有者的调试盒位置及关闭窗口后的 Transform 保持。

## 20. AI Hitbox 首帧原点显示二次修正（2026-07-26）

- `top_level` 世界节点路径仍可能在首帧提交时显示默认原点，已撤回该显示方式。
- 调试盒现在保持普通子节点，并将实际查询的世界 Transform 转换为相对于
  `MeleeHitboxComponent` 父节点的局部 Transform；玩家与 AI 共用同一套逻辑。
- 物理检测仍使用原始世界 Transform，调试显示只是同一结果的局部表达，不依赖 PlayerBase。
- 非原点持有者回归测试、AI 攻击控制器测试和 Godot 编辑器扫描均通过。

## 21. AI Hitbox 第一次攻击原点闪现根因修正（2026-07-26）

- 根因：`MeleeHitbox` 位于 `AICombatSystem` 这个非 `Node3D` 中间节点下，第一次攻击前
  调试盒没有初始化到持有者位置；后续攻击因为复用了上一轮 Transform 所以不再显现。
- 修正：`configure_owner()` 现在立即通过统一的世界到父节点局部 Transform 转换，
  初始化调试盒位置，并保持隐藏；攻击窗口与后续更新继续复用同一写入函数。
- 新增测试覆盖真实的 `UnitBase -> CombatSystem(Node) -> MeleeHitbox(Node3D)` 层级，
  验证第一次攻击前调试盒已在非原点 AI 持有者位置。
## 22. AI Hitbox 首击固定位置闪现的根因修复（2026-07-26）

- 根因最终确认：`AICombatSystem.tscn` 的根节点虽然承载了 `MeleeHitbox`，但根节点及其脚本原先都是 `Node`，不是 `Node3D`。因此 AI 的 Hitbox 位于没有稳定空间变换链的中间节点下，首个攻击窗口可能先提交该节点的固定/旧 Transform，下一物理帧才同步到单位位置。
- 修复：`AICombatSystem.tscn` 根节点改为 `Node3D`，`AICombatSystem.gd` 同步改为 `extends Node3D`。该节点保持默认恒等局部 Transform，仅用于为通用战斗组件提供稳定的空间父节点。
- `MeleeHitboxComponent` 的检测查询和调试显示仍共用同一个世界 Transform；玩家和 AI 不互相依赖，AI 也不再需要额外的首击补丁。
- `AIAttackControllerTest` 增加了场景契约：AICombatSystem 实例必须是真正的 `Node3D`，防止未来重构再次退回 `Node`。
- `Visual` 容器现在允许包含多个子视觉节点；攻击控制器和编辑器武器预览会按 `CharacterRoot/WeaponSocket` 与 `CharacterAnimationPlayer` 端点自动选择正式角色视觉，不再要求 `Visual` 恰好只有一个子节点。模型类型可以是 `CSGBox3D`、`CSGCylinder3D` 或其他 `Node3D`。
