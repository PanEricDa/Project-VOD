# Archer 终结技：蓄力重箭（逻辑首版）

## 已实现

一个合法敌方目标、一支追踪弧线箭、一次伤害；没有穿透、溅射、分裂、灼烧联动或持续伤害。
原始伤害暂为 240 + 8 × 有效攻击力；当前 Archer 攻击15，对零防御目标为360，再沿既有防御公式结算。

正式 CombatRoom 的 Archer 源场景已装备独立 Finisher Skill；原两个常规技能和连射连携不变。连携结算达标后，在限时终结窗口按4选择。初始射程以根节点Cast Range当前配置为准（接入特效时保留用户Inspector的9米），释放容差2米（不扩大起手范围）。技能不由普通AI自动释放，没有额外冷却或专注费用，资格由既有终结选择系统管理。

目标遵循现有 SkillHost／SkillBase：合法玩家锁定作为优先意图，否则使用原AI和技能选择逻辑；不会增加地板选点操作。距离、死亡及释放阶段合法性仍按原规则检查；前摇中目标死亡等导致请求失败时释放已有镜头和时间占用。箭发出后沿现有投射物追踪与命中规则，不添加专属重选机制。

沿用B演出：动作开始时暂停推进角色特写；到位后世界5%慢放、动作按请求时钟推进；释放帧暂停回到目标战斗视角，恢复暂停后发出箭，世界仍5%；箭按请求时钟正常飞行，命中结算后恢复世界速度、归还镜头。

## 配置入口

`res://SkillSystem/00-Skills/Finisher_ArcherPowerShot/ArcherPowerShotFinisherSkill.tscn`

- 根节点 Targeting：Cast Range=9（保留用户接入前配置）、Release Range Tolerance M=2。
- DamageEffect：HealthChangeSkillEffect，Damage，Base Amount=240、Power Ratio=8。
- 根节点 Delivery：内嵌 ArcProjectileDeliveryConfig，Destination Mode=Unit Target、Shot Count=1、Target Expansion留空。地面散布／爆炸半径对此模式不生效，也不影响镜头构图。
- Delivery.Projectile Scene：`res://Item/Projectiles/ArcherPowerShotProjectile.tscn`；独立光矢，飞行0.14秒、弧高0，沿既有目标抵达规则单次命中。
- Cinematic Profile：同目录 ArcherPowerShotCinematic.tres，引用 ArcherPowerShotAction.tres。
- Camera Effect Profile：`res://Effects/Camera/Presets/ArcherPowerShotCinematicCamera.tres`，沿用已有三段过渡时间配置，当前各0.2秒。
- Cast Effect Scene：`res://Effects/Skills/ArcherPowerShot/ArcherPowerShotCastEffect.tscn`，开始比例0；Release Effect Scene与音效仍空，光矢出生小光环由Flight视觉维护。

`res://UnitSystem/AI/Ally/Units/Archer.tscn` → SkillHost.Finisher Skill 指向 SkillSocket/ArcherPowerShotFinisherSkill。源技能静态Delivery不在角色中重复覆盖。

## 表现内容与动画状态

正式技能已采用BowAnimationLibrary/finish_attack_1的独立Action快照；最新片长1.7秒，释放帧约0.766667秒，完成帧1.68秒，Base Cast Time同步为约0.766667秒以保持原速。绿色主体／蓝色辅助的蓄力、飞行和命中资产已完成并接入；音效未制作。

后续正式动画通过 Docs/AnimationWorkbenchWorkflow.md 制作，再同步本技能Action并对齐释放帧。后续投射物应另建独立场景、保留既有追踪弧线契约，再在Delivery替换Projectile Scene；不要修改共享Arrow导致普通射击和连射一起改变。特效分别填技能Cast／Release和投射物Flight子场景／Impact接口，不需改伤害算法或另写终结技系统。

## 交付与通用兼容扩展

新增内容：1个技能.tscn、3个正式.tres（动作／演出／镜头）、1个自动测试.gd及Godot生成的.uid、本说明；没有新增专用运行时.gd或投射物／特效场景。

既有通用组件仅补齐两点：单体Arc命中后发送与地面模式相同的 projectile_landed 事实；终结镜头仅在地面散布模式读取散布+爆炸半径，单位目标使用正常战斗距离构图。Caster地面终结和Guardian自身范围行为保持原逻辑。

测试 `res://SkillSystem/05-Tests/ArcherPowerShotFinisherTest.gd`：一箭360实际扣血、仅一个目标、友邻不受影响、初始射程、玩家锁定优先、B慢放与正常投射物时钟、单体镜头构图、前摇死亡取消、时间镜头清理与有效UID。另更新正式场景和角色槽测试中的已有终结技名单。

## 本轮验证记录（2026-10-20）

- 新增 ArcherPowerShotFinisherTest 通过：单目标360零防御伤害、邻近敌友不受伤、玩家锁定优先、射程与前摇死亡取消、B演出和时钟清理。
- 基于正式 CombatRoom 的实际输入验证通过：普通AI伤害积攒专注 → 输入3产生真实连携与达分结算 → 终结窗口输入4选择Archer → 一箭发出/命中各1次 → completed，世界时间恢复1且无暂停残留。验证夹具仅在运行实例降低评分/专注难度，不写正式场景。
- 全回归158项：157通过；1项既有CameraFollowControllerTest失败，原因是CombatRoom导航网格未烘焙，与本技能无关。测试日志未发现泄漏报告。
- 三个外部资源均经Godot原生保存并验证有效UID，演出/镜头/动作均在对应强类型Quick Load中可检索。
- 未修改CombatRoom场景、共享Arrow、原Bow库及用户微调的Guardian动作；专属造型、特效和动画仍待后续制作。

## Workbench终结动作制作（2026-10-20，暂未接入）

已在 `res://Item/Weapon/Bow/BowAnimationLibrary.res` 新建 `finish_attack_1`，工作台已替换为BowVisual与BowAnimationLibrary，unit和本地库保留。片长1.48秒，非循环；0–0.20秒高举弩，0.20–0.36秒转向前瞄准，0.36–0.60秒定格，0.60秒release_action，随后后坐并原地后翻一圈，1.17秒落地，缓冲归位，1.46秒finish_action。

本轮只制作动画；正式ArcherPowerShotAction.tres／Cinematic／Base Cast Time未改，正式技能仍使用之前的占位动作，待动画确认后再同步接入。未添加实际后退位移或技能特效。

CharacterRoot旋转使用Godot原生Rotation3D轨道（四元数），以间隔小于180度的中间姿态完成整圈，片尾回到等价零旋转，避免360→0的长距离反向归位。武器和高度使用普通属性轨道；只编辑CharacterRoot与WeaponSocket，不修改单位物理根。

验证：实际AnimationPlayer推进一遍时release/finish各1次，总旋转360度，水平偏移0，结束直立回原点，过渡到unit/RESET的最大旋转跳变0度。原Bow库的RESET、basic_attack_1、basic_cast_1的轨道/关键帧/事件校验均保持不变；库原UID保留。六个关键姿态已渲染预览。

动画回归补充：Guardian动画测试改为在自己的运行夹具显式装载盾牌与盾牌库，不再要求共享工作台永久保持盾牌预览；远程武器迁移测试改为验证基础动作仍存在，允许武器库增加终结片段。两项均重测通过，没有更改Guardian技能或弩的基础动作。

## 正式动画接入（2026-10-20）

以用户在编辑器内最新微调的1.7秒片段为准，保存内存中的Bow库后同步ArcherPowerShotAction.tres，并显式刷新Cinematic Profile引用，保留原UID。只将提前到0.933333秒的finish_action移到归位后的1.68秒，防止后翻被正常AI接管截断；其余姿态、片长、释放帧不改。

正式流程测试通过：一次发射／一次命中、玩家锁定优先、前摇死亡取消、动作完成后无锁残留。实际主场景运行记录确认箭命中后后翻继续（可见高度约0.64米），最终世界速度1、未暂停、角色动作锁释放。没有添加实际后退位移，也没有改正式CombatRoom场景或现有伤害参数。

## 绿色光矢特效（2026-10-20）

视觉顺序：向实际ProjectileOrigin汇聚的绿蓝射线 → 绿芯蓝边的高速直线光矢 → 命中点小核心与蓝色冲击环 → 沿世界入射方向向目标背后窄锥形散射。射线、散射均为独立Mesh与动画，无碰撞、子技能或额外伤害，原伤害240+8×攻击力不变。

### 文件与编辑入口

目录 `res://Effects/Skills/ArcherPowerShot/`：

- ArcherPowerShotCastEffect.tscn：VisualRoot/Focus下编辑核心、聚合环、16条绿蓝射线；AnimationPlayer/effect编辑收束节奏。
- ArcherPowerShotFlightEffect.tscn：VisualRoot下编辑BrightCore、GreenEnvelope、BlueRailLeft/Right与FlashRing的网格、材质和动画。
- ArcherPowerShotImpactEffect.tscn：VisualRoot下编辑HitCore、HitRing与13条ExitRay的动画；局部-Z为穿出方向，不能按敌人朝向摆放。
- 三个独立*EffectPreview.tscn及ArcherPowerShotSequencePreview.tscn，F6运行；Inspector可选预览段、是否自动重复，界面提供重播。预览不调用战斗逻辑，飞行时间读取正式投射物，动作引用正式Action。
- ArcherPowerShotCastEffect.gd、ArcherPowerShotImpactEffect.gd：仅分别补充动态弩口跟随和世界入射方向；生命周期、播放、取消与请求时钟复用既有FlameBarrageEffectPlayer，不复制另一套播放器。
- ArcherPowerShotEffectPreview.gd为共用预览驱动；ArcherPowerShotVisualEffectTest.gd为方向、跟随、回收和纯视觉边界测试。

投射物 `res://Item/Projectiles/ArcherPowerShotProjectile.tscn`：复用TrackingArcProjectile，独立挂载Flight场景并引用Impact场景，不改共享Arrow。其Flight Duration与Arc Height控制飞行；材质、形状和光丝颜色在对应Effect场景编辑，不在技能脚本硬编码。

### 通用接口与时序

TrackingArcProjectile仅增加可选 `configure_impact_direction(world_direction)` 调用：特效实例入树前接收入射方向，不支持该方法的旧资产保持原行为。Impact在ready后转换为正确世界朝向，也支持旋转父节点。伤害仍由SkillEffects单次执行。

Charge通过既有configure_cast接收实际施法时长并跟随真实弩口；取消隐藏并由技能清理。Flight及Impact沿既有set_execution_clock推进，5%世界慢放中保持终结表现速度；主Impact在0.28秒结束后发出effect_finished并自回收，导演再恢复世界速度，后翻继续沿原动作占用完成。

### 配置保护

接入前当前编辑器中的Cast Range已为9米，Release Range Tolerance为2米；本次保留这些手工配置，没有重设回此前文档的12米。动画、伤害、角色槽、CombatRoom以及其他投射物场景未改。没有新增外部tres/res，所有新场景经原生ResourceSaver保存。

### 交付验证结果

- 全回归159项：158通过，仅既有CameraFollowControllerTest因CombatRoom导航网格未烘焙失败；泄漏日志0。
- 追加重测ArcherPowerShotVisualEffectTest、ArcherPowerShotFinisherTest及实际输入4的主场景端到端验证均通过。四个预览可完整结束，改动预览目标后散射会随入射方向更新；Godot实际验证预览武器局部-Z朝向目标，不需要反转。
- 正式技能验证可见蓄力、飞行期间5%世界速度、主命中特效结束前保持慢放、随后恢复时间；一次单体伤害、邻近敌友不受影响、前摇目标死亡正常取消、动作锁正常释放。
- 三段实际运行画面已检查，8个新增场景均有原生保存后的有效UID。共享Arrow、Bow动画库、CombatRoom与伤害配置保持原样；本次未提交Git。

### 特效可读性调整

蓄力、飞行、命中三段视觉线性尺寸统一放大为前版的1.3倍，包括核心、光环、光矢长宽、聚合射线及散射的尺寸/分布。直接调整独立特效场景的网格尺寸、局部位置与位置动画关键帧；不缩放技能或投射物逻辑根，因此蓄力Focus继续精确跟随发射点，不会被锚点更新抵消。颜色、透明度、播放时间、飞行时间、伤害、实际作用范围及镜头参数均不变。


## 动画驱动后退（2026-10-20）

正式技能根节点下实例化通用 SkillMotionComponent.tscn，Inspector仅配置 Direction=BACKWARD、Distance M=0.8米；不配置速度或时长。组件位于 res://SkillSystem/03-Extensions/，不属于伤害Effects。

BowAnimationLibrary.res 的 finish_attack_1 在 CharacterAnimationPlayer 方法轨道上增加 begin_skill_motion（0.92秒）与 end_skill_motion（1.46秒），覆盖起跳预备至落地缓冲；用户姿态、释放帧、完成帧与片长不改。正式 ArcherPowerShotAction.tres 已同步，Cinematic Profile 引用已刷新，原UID保留。修改动画后仍需按Workbench流程同步正式Action。

区间只定义动画时间。当前实际动作游标决定已走距离，沿当前SkillExecutionClock同步播放速度、5%慢放、暂停和恢复正常时间；没有另一份秒数或倍率。角色物理根只水平后退，视觉腾空与整圈后翻仍由CharacterRoot动画负责。保持面向目标、碰撞截短且不补偿穿墙，动作取消/死亡/卸载清理占用；已发箭矢不回滚。主命中特效结束后导演仍按原规则恢复世界，不因后退延长慢放。

复用：其他SkillBase根下实例化同一组件，在实际动作中设置一对begin/end方法帧，再选方向与距离。每技能一组件一区间，纯触发无角色动画时不产生位移；普通动作end不得晚于finish_action，专属终结动作仍自然播完。预览场景验证外观，不代替真实CharacterBody碰撞测试。


### 位移交付验收

四个新增测试通过，覆盖真实物理碰撞、受击移动锁不积压、取消/死亡/组件及动作驱动卸载、同帧末段、旧身份与同步替换动作隔离。9格世界速度/动画速度矩阵、hold/真暂停、区间内恢复正常时间、普通ID0与实际CombatRoom B模式均通过。原生运行测得水平后退约0.800米、面向保持、箭矢命中一次，世界速度恢复1且无移动锁。

全量SceneTree回归163项：162通过，唯一既有CameraFollowControllerTest的room navigation mesh is baked失败（未烘焙导航网格），泄漏日志0。真实输入4端到端另测通过。CombatRoom、共享Arrow和Shield动画库哈希与实施前相同。Godot MCP动态脚本自身的_mcp_error未使用提示未修改；新增代码初始化提示已修正并重测。
