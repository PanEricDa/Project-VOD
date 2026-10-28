# 动画工作台：AI 制作与编辑流程

更新日期：2026-10-20。依据用户确认的七步工作流，并对照当前场景、动画事件桥和终结技装配整理。
本文是以后 AI 制作角色／武器动作的默认操作指南，不是另一套动画系统。本次只记录，不切换工作台、不修改动画。

## 1. 文件与编辑入口

| 用途 | 当前路径 |
|---|---|
| 工作台 | `res://UnitSystem/Visuals/Workbench/HeroAnimationWorkbench.tscn` |
| 工作台角色视觉 | `HeroVisual` |
| 整体姿态节点 | `HeroVisual/CharacterRoot` |
| 武器动作节点／预览挂点 | `HeroVisual/CharacterRoot/WeaponSocket` |
| 动画编辑节点 | `HeroVisual/CharacterAnimationPlayer` |
| Guardian 盾牌预览 | `res://Item/Weapon/Shield/IronShieldVisual.tscn` |
| Guardian 武器动画库 | `res://Item/Weapon/Shield/ShieldAnimationLibrary.res` |
| 法球预览 | `res://Item/Weapon/MagicGlobe/MagicGlobeVisual.tscn` |
| 法球动画库 | `res://Item/Weapon/MagicGlobe/MagicGlobeAnimationLibrary.res` |

其他武器库同样位于 `res://Item/Weapon/<武器类别>/`：Bow、Sword、Staff 各自目录内的 `*AnimationLibrary.res`。
以目标 WeaponData 的 `visual_scene` 和 `animation_library` 为配对依据，不靠角色名称猜测。
当前正式武器库使用的是 **.res**，不是用户口述示例中的 .tres；沿用现有文件，不为扩展名另建副本。

## 2. 开始前：只读检查

1. 明确本次任务是“创建新片段”“修改已有片段”，还是“制作后接入具体技能”。仅制作动画不等于授权改正式技能装配。
2. 查看 Git 差异、Godot 当前工作台与资源是否有未保存修改；不得直接覆盖用户正在编辑的内容。
3. 记录工作台当前武器、AnimationPlayer 的库列表、目标库的 UID／已有片段。必要时记录相关文件哈希作为保护依据。
4. 核对片段名称是否已存在：新建不得静默覆盖同名片段；如果任务明确要求调整已有片段，才编辑原片段。
5. 优先使用 Godot MCP Pro 的场景／动画／资源操作或编辑器 API；需要可视化操作时可用 Computer Use。仅工具不支持或失败时回退直接编辑，并说明原因。

## 3. 七步标准流程

### 第一步：打开工作台

打开 HeroAnimationWorkbench.tscn，定位 HeroVisual。
这里只制作视觉动作，不修改正式单位的 CharacterBody3D、战斗逻辑或测试关卡单位。

### 第二步：更换武器预览（武器相同则跳过）

在 `HeroVisual/CharacterRoot/WeaponSocket` 下：

- 只删除旧武器的 **Visual 场景实例**，例如 MagicGlobeVisual；不删除其源 .tscn 文件。
- 不删除 WeaponSocket，不删除它的 ProjectileOrigin 等基础端点，也不误删其他非武器节点。
- 实例化目标武器 Visual 为 WeaponSocket 的直接子节点；Guardian 使用 IronShieldVisual.tscn。
- 保留武器 Visual 自带的局部变换；不要为了摆动作去改它的源模型或把预览偏移烘焙进源场景。

通过原生 API 实例化时，保留场景实例关系；只按实际编辑场景设置实例根的 owner，不把所有后代重设 owner 导致实例被摊平。

### 第三步：替换武器 AnimationLibrary

选中 `HeroVisual/CharacterAnimationPlayer`，打开底部 Animation 页签中的动画库管理入口：

1. 移除旧武器库的**挂载关系**，例如 MagicGlobeAnimationLibrary；不是删除磁盘上的库。
2. Load 已有目标库，例如 ShieldAnimationLibrary.res；工作台挂载名可沿用 ShieldAnimationLibrary。
3. 保留 `unit` 基础库和不属于旧武器的其他库；当前工作台还有无名前缀的本地库，不能一并清空。
4. 核对武器模型与库成对匹配。

工作台的库挂载名不需要改成运行时名称：运行时控制器会按现有规则将武器库挂载为 `weapon`。动画内部轨道不应依赖工作台根名、角色名或某个库前缀。

### 第四步：在目标武器库中创建／选取片段

在已加载的目标武器库内创建新 Animation，例如 `finish_attack_1`，**不是新建到无名库或 unit 库**。
命名沿用现有用途：攻击常见 `basic_attack_N`，施法常见 `basic_cast_1`，终结动作可用 `finish_attack_N`／`finish_cast_N`。
名称本身不会自动把片段装进某个技能，实际使用由现有配置决定。

可以复制适合的片段作为编辑起点，但必须真正按本次动作需求编辑和预览；不得把未经制作的占位副本当作新终结动画交付。
复制后核查并清理不适用的方法帧，避免多一次伤害交付或误开普通攻击判定。

**2026-10-20 核对结果：Shield 库已有 finish_attack_1，MagicGlobe 库已有 finish_cast_1。此信息只是当时快照，以每次实际读取为准。**

### 第五步：在时间轴制作关键帧

默认只编辑以下两个节点的视觉位置／旋转（确有需要时才用缩放）：

- `CharacterRoot`：角色整体倾斜、转身、起伏等姿态。
- `CharacterRoot/WeaponSocket`：武器抬举、挥动、蓄力、收势等动作。

CharacterAnimationPlayer 的 `root_node` 当前为 `..`，即 HeroVisual；因此轨道应使用相对路径：

```text
CharacterRoot:position
CharacterRoot:rotation
CharacterRoot/WeaponSocket:position
CharacterRoot/WeaponSocket:rotation
```

不把动作关键帧写到 HeroAnimationWorkbench、HeroVisual、正式单位根、ModelRoot、武器模型内部节点或 ProjectileOrigin。用户明确要求模型内部动画等例外时，再单独处理。

先确定前摇—释放—后摇节奏，设置初始姿态及关键姿态，再调整过渡和停顿。播放检查时不仅看单帧，还要看完整动作和回到正常姿态。
整圈旋转特别检查角度插值、结尾到 RESET／下一动作的过渡；不能用 360°→0° 的长距离反向插值来“归位”。不得只凭数值等价就断言不会回转。
不要为一个新片段顺带改共享 RESET；若确需改其基准，先检查对其他动作的影响。

### 第六步：按动作用途补充事件与校验

“原则上只编辑两个节点”是指姿态轨道；必要的方法轨道仍使用项目已有动画事件接口。

用于 SkillBase 的施法／终结动作，方法轨道接收节点为 `CharacterAnimationPlayer`，无参数：

- `release_action()`：实际释放点，恰好一次。
- `finish_action()`：结束动作逻辑占用，恰好一次，在 release 之后且不超出片长。

片段非循环。不要在技能动作中无意保留普通攻击的 hit window、release_projectile 或 attack motion 方法帧。
如果任务本身是制作普通攻击，则按现有普通攻击契约保留其必要事件，不能统一替换为技能事件。
片长、释放帧、完成帧需实际校验；避免浮点误差造成完成帧略超出片长，必要时在片尾留小余量。

终结技无需新增 begin_cinematic_closeup 等开场方法：现有导演在动作开始时自动接管；release_action 触发返回战斗镜头的暂停门闩。镜头过渡仍由既有 Camera Profile 的三个时间配置控制，不能通过新增动画方法另建一套时序。

### 第七步：保存并重新读取验证

1. 保存 Workbench.tscn 的预览装配。
2. **明确保存被编辑的外部 AnimationLibrary.res**，不能只保存工作台就认为动画库已经落盘。原生 API 用 ResourceSaver 保存回原路径，保留原 UID。
3. 重新读取库，确认新片段在正确库内、关键帧与方法帧持久化、已有片段未被误删。
4. 验证 ResourceLoader.get_resource_uid(path) 不为 INVALID_ID；既有库 UID 不应因编辑变化。如新增外部 Animation 资源，同样必须由 Godot 正式保存并验证 UID。
5. 确认预览姿态没有意外写成工作台的新静态变换；保存预览装配前停止播放并回到正常基准。
6. 除非任务另有要求，工作台保留本次目标武器与库，便于用户继续调整；不自动切回旧武器，也不自动提交 Git。

## 4. 制作完成与正式技能接入是两步

在工作台完成并保存库，只完成“动画制作”。现有终结技读取的是 `SkillCinematicProfile.action_animation`，不按 finish_attack_1 名称自动寻找片段。

如果任务还包含正式技能接入：

1. 将完成的 Animation 保存／更新到对应技能目录的正式 `*Action.tres`，保留已有资产 UID；它是独立快照，不会自动随武器库变化。
2. 在该技能 Cinematic Profile 中引用正式 Animation，调用 validate_configuration() 校验非循环、唯一且合法的方法帧。
3. 按现有动作控制器规则核对技能 Base Cast Time 与 release 帧；以原速播放为目标时应对齐，不擅自固定成所有技能共用的秒数。
4. 在实际技能流程检查：特写不吃动作、释放一次、正常后摇和归位，且没有重复伤害或动作占用残留。

只有制作任务不包含接入时，报告“库内片段已完成，正式技能尚未切换”，不悄悄替换现有占位动画。

## 5. AI 交付检查单

- [ ] 工作台武器 Visual 与动画库匹配，基础端点／unit 库保留。
- [ ] 片段位于目标武器外部库，同名与用户未保存修改得到保护。
- [ ] 姿态轨道原则上仅 CharacterRoot 与 WeaponSocket，路径相对 HeroVisual。
- [ ] 前摇、释放、后摇、停止归位及旋转方向均经过实际预览。
- [ ] 对应动作类型的方法事件正确；技能／终结动作非循环，release 与 finish 唯一且顺序合法。
- [ ] 工作台与外部库都已保存，重新读取正确、UID 有效。
- [ ] 需要接入时，正式 Action／Profile 已同步且实际技能验证通过；不需要接入时明确未切换。
- [ ] 汇报修改文件、动画名称、片长、释放／完成帧，以及正式技能是否已采用。

## 6. 首次实际操作补充（2026-10-20）

Guardian 的 finish_attack_1 在开始时只存在于编辑器内存，磁盘动画库尚无此片段。因此先检查内存与磁盘，再编辑当前已挂载库中的原对象并正式保存；不要重新打开场景丢掉用户预备工作。

同步独立 Action 后，已打开的 Cinematic Profile 可能仍持有旧 Animation 对象。应对照磁盘重载的 Action 与当前 Profile 的片长及方法帧，必要时显式重新引用已保存 Action 并保存 Profile，保持外部引用和原 UID；不能只看到磁盘测试通过，就忽略当前编辑器的旧缓存。

编辑器选中 AnimationPlayer 可能把预览游标重置到0；先选中节点，再 seek 到待检查姿态。预览后恢复基准，不把中途蓄力或下砸姿态保存为工作台静态变换。


## 7. 可选技能位移方法帧

需要真实水平位移时，在技能根下实例化 SkillSystem/03-Extensions/SkillMotionComponent.tscn，仅配置方向与总距离（米）。在CharacterAnimationPlayer方法轨道添加一对无参数 begin_skill_motion() / end_skill_motion()；0≤begin<end≤片长，每技能仅一个区间，普通动作end不晚于finish_action。未挂组件的旧技能不要求此标记。

方法帧提供实际动画秒数区间，动作游标为唯一进度，不另填速度、持续时间或慢放补偿。不要给单位根制作位置轨道来代替碰撞位移。工作台没有战斗Host时只发事件，不会移动预览根。保存武器库后同步正式Action和Cinematic引用，检查原UID与实际动作；Archer当前后退0.8米、区间0.92–1.46秒。
