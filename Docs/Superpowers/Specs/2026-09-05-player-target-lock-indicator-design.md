# 玩家目标锁定正式特效：设计与实施计划

> **For agentic workers:** 实施时必须逐任务执行并在每个任务后独立复核；推荐使用
> `superpowers:subagent-driven-development`，或使用 `superpowers:executing-plans` 按检查点执行。
> 本文使用复选框跟踪实施状态，但当前阶段只编写计划，不实施任何游戏代码或资源。

**目标：** 在不改变现有玩家锁定接口和战斗系统行为的前提下，增加与 Debug 范围圆环完全分离、
显示在当前锁定单位脚下的金黄色三状态正式特效。

**架构：** `PlayerTargetingComponent` 继续作为锁定状态的唯一事实来源，并只增加一个可选正式特效
场景的创建和驱动职责。新增的 `TargetLockIndicator` 独立封装进入、维持、退出三种表现；现有
Debug 范围圆环保留为独立开发工具并在正式配置中默认关闭。

**技术范围：** Godot Engine 4.7、GDScript、Node3D、MeshInstance3D、QuadMesh、ShaderMaterial、
SceneTree headless tests、PowerShell。

**规格说明：** 本文件前半部分是完整设计规格，后半部分是该规格对应的详细实施计划，二者不拆分
为不同文档。

日期：2026-09-05

## 目标与范围

本阶段在现有玩家目标锁定功能上增加正式的世界空间反馈：玩家成功锁定敌方单位后，在该单位
脚下显示金黄色锁定圆环。设计必须复用现有锁定接口、合法性判断和生命周期，不重写索敌算法，
不改变相机、移动、AI、仇恨或技能执行规则。

现有 `TargetLockRangeIndicator` 是用于观察最大锁定距离的 Debug 内容。它与正式锁定特效在资源、
配置和生命周期上必须完全分离；不得把 Debug 圆环改名、换色或移动到目标脚下后当作正式表现。

本阶段只实现单位脚下的锁定反馈，不加入顶部目标信息面板，也不为不同职业、装备或敌人体型预制
尚未需要的特效变体。

## 基本原则

- 以 `PlayerTargetingComponent` 为锁定状态的唯一事实来源。
- 保留现有公开锁定接口与 `locked_target_changed` 信号，现有消费者无需迁移。
- Debug 范围显示和正式锁定特效分别启停，任何一方失效都不影响另一方。
- 正式特效只表现锁定结果，不能决定目标是否合法，也不能反向修改锁定状态。
- 不给每个敌方单位预置圆环，不新增全局锁定管理器。
- 正式特效全程只维护一个活动实例，目标切换时复用该实例。
- 第一版只建立已经需要的三种表现状态，不增加确认闪光、切换闪光等额外状态。

## 现有接口边界

`PlayerTargetingComponent` 继续负责：

- 读取鼠标选取与最近目标锁定输入；
- 维护 `locked_target`；
- 验证候选分组、敌对关系、存活、可选取状态和最大三维距离；
- 在主动解除、非法请求、目标失效、超出距离或玩家死亡时清空锁定；
- 通过现有 getter、请求方法和 `locked_target_changed` 信号向外提供锁定结果；
- 向现有玩家朝向及威胁聚焦等系统提供原有数据。

以下既有公开行为不因正式特效改变：

- `request_lock()`、`clear_locked_target()`、`get_locked_target()`、
  `lock_nearest_target()` 等接口的语义；
- 非法显式选择会解除旧锁定；
- 重复选择同一合法目标保持锁定且不重复广播状态变化；
- 最近目标继续按现有三维距离选择，不新增屏幕可见性或墙体视线检查；
- 关闭玩家输入时按现有规则保留已经存在的锁定。

## 架构选择

新增可独立实例化和替换的正式特效场景，建议位于：

```text
UnitSystem/Visuals/Targeting/TargetLockIndicator.tscn
UnitSystem/Visuals/Targeting/TargetLockIndicator.gd
```

`PlayerTargetingComponent.tscn` 为该特效配置默认场景资源。组件在初始化时创建一个实例，并通过
明确的表现接口向它传递目标脚下的世界坐标和状态转换。具体圆环资源不能在锁定算法代码中动态
拼装，以便以后直接替换正式美术资源。

```text
玩家锁定输入
    ↓
PlayerTargetingComponent
    ├─ 现有目标选择、验证和 locked_target
    ├─ 现有 locked_target_changed 输出
    ├─ TargetLockRangeIndicator（独立 Debug 范围显示）
    └─ TargetLockIndicator（独立正式特效实例）
           ├─ 进入
           ├─ 维持
           └─ 退出
```

正式特效实例不保存第二份业务锁定状态，也不持有或管理 `UnitBase`。锁定组件在目标有效期间向它
同步世界坐标；特效仅保存播放退出动画所需的最后有效位置。这样目标即使被直接释放，也不会在
特效中留下失效的单位引用。

如果正式特效场景未配置、无法实例化或缺少所需接口，组件只输出一次明确诊断信息。锁定输入、
目标状态、公开 getter 和信号仍须正常工作。

## Debug 范围显示

现有玩家脚下范围圆环继续表示 `maximum_lock_distance`，只用于开发调试：

- 归入明确的 Debug 配置分类，正式游戏默认关闭；
- 保留以玩家为中心的尺寸、位置和颜色逻辑；
- 不读取正式特效的颜色、尺寸或状态；
- `maximum_lock_distance` 即使不显示 Debug 圆环，仍继续参与锁定合法性判断；
- Debug 节点缺失只影响范围可视化，不影响正式圆环和锁定功能。

正式特效也拥有独立启用配置。关闭正式特效时不得自动打开 Debug 圆环，也不得关闭锁定能力。

## 正式圆环视觉规格

第一版使用无需外部贴图的正式场景资源：水平面片配合专用材质绘制金黄色环形区域。它应明显
区别于用于测量距离的 Debug 几何体，同时避免为首版引入额外图片资产依赖。

- 默认外径约 `1.2m`，适配当前普通单位体型；
- 环宽约为直径的 `5%～7%`；
- 使用金黄色自发光材质，保持在不同光照条件下可读；
- 边缘允许轻微软化，避免明显锯齿；
- 不投射阴影，不参与碰撞和射线选择；
- 保持正常深度遮挡，不穿墙或透过地形显示；
- 维持状态只允许轻微的亮度呼吸或材质流动，不增加独立效果层；
- 圆环场景自身保留基础尺寸与颜色配置，以便将来替换或制作实际需要的变体。

圆环使用目标根节点的世界位置作为脚部基准，并增加约 `0.03m` 的统一高度偏移以减少地面重叠
闪烁。现有 `UnitBase` 根节点已经可作为当前单位的脚部位置，第一版不增加地面射线投射、坡面
贴合、骨骼挂点或单位体型接口。以后确实出现大型单位需求时，可替换特效资源或单独扩展锚点，
不在本次预制抽象。

正式特效使用世界变换，不继承玩家的位移、旋转或缩放。只要锁定有效，每次物理更新都同步到
目标脚下；特效动画不得延迟业务锁定或目标方向计算。

## 三状态表现模型

正式特效只有以下三个表现状态：

### 进入

- 首次锁定合法目标时进入；
- 切换到另一个合法目标时，立即移动到新目标脚下并重新进入；
- 圆环快速淡入，并由略小尺寸恢复到正常尺寸；
- 建议时长为 `0.12～0.20 秒`；
- 进入结束后自动转为维持。

### 维持

- 锁定持续合法时维持完整显示并跟随目标；
- 只保留轻微、连续的亮度呼吸或材质流动；
- 重复选择同一目标时继续维持，不重播进入，也不增加确认效果。

### 退出

- 主动解除、非法显式选择、目标死亡、目标被移除、变为不可选取、超出锁定距离或玩家死亡时
  进入；
- 使用最后一次有效世界位置播放快速淡出，可伴随轻微缩小；
- 建议时长为 `0.10～0.16 秒`；
- 退出结束后隐藏并回到等待状态；隐藏只是无表现的静止状态，不构成第四种特效。

如果退出尚未完成便锁定新目标，立即中断退出，在新目标位置重新播放进入。场景树整体销毁时
直接清理，无须等待退出动画完成。

目标切换不在旧目标位置额外播放退出。这样无需同时维护两个特效实例，也避免视觉表现滞后于
已经生效的锁定状态。

## 事件与表现映射

| 系统事件 | 正式特效行为 |
|---|---|
| 首次锁定目标 | 在目标脚下进入 |
| 切换到新目标 | 立即移动到新目标脚下并重新进入 |
| 重复选择同一目标 | 继续维持 |
| 锁定持续有效 | 维持并同步位置 |
| 主动解除或非法显式选择 | 退出 |
| 目标死亡、移除或不可选取 | 退出 |
| 目标超出最大距离 | 退出 |
| 玩家死亡 | 退出 |
| 组件或场景销毁 | 立即清理 |
| 退出期间获得新目标 | 中断退出并在新位置进入 |

## 与其他系统的关系

锁定目标是可供其他系统读取的可选信息，不成为所有战斗行为的强制前提。本阶段：

- 不强制玩家朝向锁定目标；已经读取锁定方向的现有朝向逻辑保持原样；
- 不接管相机，不增加镜头居中或跟随；
- 不限制移动方向，不改变冲刺；
- 不让所有攻击和技能自动追踪锁定目标；
- 不改变 AI、仇恨值、目标选取和队友行为；
- 不实现顶部中央目标面板。

未来目标型技能可以在执行时通过现有接口即时读取并重新验证锁定目标。自由方向攻击、范围技能
和其他非目标型技能继续使用自己的输入与选区规则；本次不提前修改技能系统。

## 生命周期与失败处理

- 组件初始化时至多创建一个正式特效实例，重复配置持有者不得重复实例化。
- 正式特效初始隐藏，不应在尚未锁定时短暂闪现。
- 目标有效期间，先维持现有锁定验证，再同步正式圆环位置。
- 清空锁定时先完成业务状态更新和既有信号语义，再通知特效退出；表现失败不得阻断信号。
- 目标突然被释放时使用最后有效位置退出，不访问已经失效的对象。
- 组件离开场景树时清空引用并直接释放特效，不向正在销毁的接收者广播无意义事件。
- Debug 圆环、正式特效或其中任意材质缺失时分别降级，各自只影响自身显示。
- 诊断信息不得每帧重复刷屏。

## 开放性边界

开放性集中在可替换的正式特效场景和稳定的既有锁定接口：

- 可以以后替换圆环场景，而无需修改目标选择与合法性算法；
- 特效场景内部可以更换网格、材质或动画，而无需影响 `PlayerBase` 和锁定消费者；
- 正式特效启用、资源、统一高度和基础表现参数可以配置；
- 未来职业或大型目标确有需求时，再增加资源选择或锚点策略。
- 新增或调整的可配置参数、公开方法与信号必须按项目规范在声明附近提供简体中文说明，并同步
  说明单位、默认行为和影响范围。

明确不做：全局特效管理器、为所有敌人预挂圆环、单位体型注册表、地面投射系统、摄像机锁定、
技能自动索敌重构、职业特效路由以及顶部目标 HUD。

## 验证契约

新增针对性自动测试，至少覆盖：

- Debug 范围圆环与正式锁定特效是两个独立节点和独立配置；
- 正式游戏默认关闭 Debug 范围显示；
- 分别关闭 Debug 或正式特效时，锁定逻辑和另一种显示不受影响；
- 锁定合法新目标后只创建一个正式特效实例，并正确进入和跟随；
- 重复锁定同一目标保持维持状态，不重播进入；
- 切换目标时复用实例，在新位置重新进入，不在旧位置创建退出副本；
- 主动解除、非法选择、死亡、移除、不可选取、超距和玩家死亡均触发退出；
- 退出期间重新锁定会中断退出并正确进入；
- 目标被直接释放后不存在失效引用，退出使用最后有效位置；
- 正式特效场景缺失或实例化失败时，现有公开接口和信号仍然正确；
- 圆环不投射阴影、不参与碰撞，并保持正常深度遮挡；
- 既有鼠标选取、最近目标、锁定方向和威胁聚焦相关测试不回归。

验证还应包含 Godot headless 场景加载，以及在实际战斗测试房间内检查圆环尺寸、地面闪烁、遮挡、
移动跟随和快速切换目标时的表现。既有无关失败必须单独记录，不得将其误判为本功能引入的回归。

## 验收结果

关闭 Debug 显示进入战斗后，玩家成功锁定敌人会在该敌人脚下看到独立的金黄色正式圆环。圆环
只有进入、维持和退出三种表现，能够跟随移动并正确响应所有锁定解除原因。删除或关闭正式特效
后，现有锁定、朝向、威胁聚焦和输入逻辑仍保持可用；正式表现与 Debug 范围工具不存在资源或
状态混用。

---

# 详细实施计划

## 全局实施约束

- 正确项目根目录固定为 `G:\Godot\ProjectVOD`；不得使用旧项目 `G:\Godot\SipSip` 或不存在的
  `G:\Godot\ProjSipSip`。
- 本计划只增加玩家锁定目标的正式世界空间圆环，不实现顶部目标 HUD、摄像机锁定、技能自动追踪、
  控制器辅助瞄准或新的目标筛选规则。
- 除原则性错误或严重 Bug 外，不评估或整理现有锁定结构；优先复用公开接口，通过新增资源和最小
  接入完成。
- 不修改 `PlayerBase`、AI、仇恨、技能、物品、攻击、伤害、死亡和房间流程的业务逻辑。
- 不修改 `Scenes/TestScene.tscn`，也不自动向任何测试场景添加玩家、友军或敌人实例。
- 不修改 `project.godot`；现有 `player_target_select` 与 `player_target_nearest` InputMap 保持不变。
- 不把现有 `TargetLockRangeIndicator` 或其运行时 `TorusMesh` 当作正式特效资源。
- Debug 范围圆环与正式特效分别配置、分别降级，不能通过共用颜色、节点、材质或可见性变量形成
  隐式耦合。
- 正式特效不得拥有目标选择权，不得发送锁定信号，也不得修改 `_locked_target`。
- 正式特效全程最多一个实例；目标切换不能在旧目标位置额外生成退出副本。
- 正式特效只允许进入、维持、退出三个表现状态；隐藏是退出完成后的静止结果，不增加第四个动画
  状态。
- 不新建 `.tres` 或 `.res`。正式材质使用 `.gdshader` 和 `.tscn` 内部 `ShaderMaterial`，避免额外
  Resource UID 保存流程。
- Godot 扫描生成的新增 `.gd.uid`、`.gdshader.uid` 等相邻 UID 文件只有确认属于本计划新增资源时
  才能随对应任务提交；不得手工编造 UID。
- 每一个新增或修改的 `@export` 参数都必须紧邻简体中文说明，明确用途、单位、默认行为和影响范围。
- 每一个新增公开方法、信号及外部传入参数都必须在声明附近说明职责和关键约束。
- 实施时保留用户已有工作区内容；当前已存在的 `project.godot` 修改和
  `addons/godot_mcp/commands/headless_commands.gd.uid` 未跟踪文件不得加入任何提交。
- 每个开发任务按“失败测试 → 确认按预期失败 → 最小实现 → 针对性测试 → 相关回归 → 单独提交”
  执行。测试如果没有以预期原因失败，必须先修正测试覆盖，不能直接进入实现。
- 本文中的数值是第一版明确默认值，不在实施阶段重新进行未经确认的视觉设计。

## 当前基线与已知例外

计划编写时使用 Godot `4.7.stable.official.5b4e0cb0f` 在正确项目目录进行了只读基线验证：

- `PlayerThreatFocusControllerTest.gd`：exit code `0`，输出
  `PlayerThreatFocusControllerTest: PASS`。
- `UnitDeathLifecycleTest.gd`：exit code `1`，唯一失败为
  `Saber death releases external action controller occupancy`。

第二项是本功能开始前已经存在、且与玩家锁定正式特效无关的 AI 外部行动控制器死亡态断言问题。
本计划不得顺带修改 `UnitDeathLifecycleTest.gd`、`AIAttackController`、`AICombatSystem` 或 Saber 的
死亡释放流程来消除该失败。

实施开始和结束时都必须单独运行该测试作为基线哨兵：

- 如果开始实施时仍只有上述同一失败，结束时允许保留完全相同的唯一失败；失败数量增加、失败文本
  改变、出现解析错误或玩家死亡锁定断言失败，均视为本功能回归。
- 如果开始实施前该既有问题已经被其他任务修复为 exit code `0`，本功能完成后也必须保持 exit
  code `0`。
- 正式特效新增测试不得依赖或复制 Saber 的 AI 控制器断言。

## 文件结构与责任

### 新建文件

- `UnitSystem/Visuals/Targeting/TargetLockIndicator.gd`
  - 只管理正式锁定特效的三状态、透明度、缩放、世界位置和安全隐藏。
  - 不读取 InputMap，不认识 `UnitBase`，不持有锁定目标，不修改任何业务状态。
- `UnitSystem/Visuals/Targeting/TargetLockIndicator.gdshader`
  - 在水平面片上绘制边缘柔和的金黄色环形区域。
  - 保留正常深度遮挡，不使用穿墙渲染，不包含目标选择或状态逻辑。
- `UnitSystem/Visuals/Targeting/TargetLockIndicator.tscn`
  - 正式特效的独立可替换场景，装配脚本、水平面片和内部 ShaderMaterial。
  - 根节点默认隐藏并使用世界顶层变换，子节点不投射阴影且不包含碰撞。
- `UnitSystem/Tests/TargetLockIndicatorTest.gd`
  - 隔离验证进入、维持、退出、中断、位置更新和场景视觉契约。
- `UnitSystem/Tests/PlayerTargetingComponentTest.gd`
  - 使用真实 `UnitBase` 与真实 `PlayerTargetingComponent` 验证锁定状态和正式特效集成。

### 修改文件

- `UnitSystem/Components/Targeting/PlayerTargetingComponent.gd`
  - 保留现有公开锁定接口和合法性算法。
  - 明确现有范围圆环的 Debug 属性，并把其默认显示改为关闭。
  - 新增正式特效场景配置、单实例创建、事件映射和位置同步。
- `UnitSystem/Components/Targeting/PlayerTargetingComponent.tscn`
  - 保留 `TargetLockRangeIndicator` Debug 节点。
  - 为正式特效配置默认 `PackedScene`，但不把正式圆环直接做成 Debug 节点子资源。

### 只运行回归、不修改

- `UnitSystem/Player/PlayerBase.gd/.tscn`
- `UnitSystem/Components/UI/PlayerThreatFocusController.gd/.tscn`
- `UnitSystem/Tests/PlayerThreatFocusControllerTest.gd`
- `UnitSystem/Tests/UnitDeathLifecycleTest.gd`
- `UnitSystem/Base/00_UnitBase.gd/.tscn`
- `UnitSystem/AI/**`
- `SkillSystem/**`
- `Item/**`
- `GameFlow/**`
- `Scenes/**`
- `project.godot`

## 计划采用的稳定接口

为了让任务之间没有命名歧义，实施时使用以下接口；除测试发现与 Godot 4.7 API 冲突外，不在实现
阶段随意改名。

### `TargetLockIndicator`

- `enum EffectState { ENTER, MAINTAIN, EXIT }`
  - 只表示三种可见表现阶段；隐藏不加入枚举。
- `play_enter(world_position: Vector3) -> void`
  - 显示特效、设置世界位置、重置进入进度，并允许中断正在播放的退出。
- `update_world_position(world_position: Vector3) -> void`
  - 只更新世界位置，不重播进入，也不改变当前业务锁定。
- `play_exit() -> void`
  - 从当前位置开始退出；已经隐藏时为空操作。
- `hide_immediately() -> void`
  - 场景销毁或初始化失败时立即复位，不播放退出。
- `get_effect_state() -> EffectState`
  - 供自动测试和调试读取当前三状态；隐藏后返回最近状态，但可见性必须另行查询。
- `is_effect_visible() -> bool`
  - 返回正式特效是否仍在显示，包括进入、维持和尚未结束的退出。

### `PlayerTargetingComponent` 新增内部边界

- `formal_indicator_enabled: bool = true`
  - 正式特效总开关；关闭只影响显示。
- `formal_indicator_scene: PackedScene`
  - 默认指向 `TargetLockIndicator.tscn`，允许以后替换美术表现。
- `formal_indicator_height: float = 0.03`
  - 在目标根节点世界位置上增加的统一米制高度。
- `_create_formal_indicator() -> void`
  - 初始化期间至多创建一个实例，配置无效时只诊断一次。
- `_enter_formal_indicator(target: UnitBase) -> void`
  - 计算目标脚下位置并触发进入。
- `_update_formal_indicator_position() -> void`
  - 锁定有效时同步位置，不触发新动画。
- `_exit_formal_indicator() -> void`
  - 不读取已被清空或释放的目标，仅让现有实例从最后位置退出。
- `_dispose_formal_indicator() -> void`
  - 组件销毁时立即隐藏并释放实例。

现有 `locked_target_changed(target: UnitBase)`、`configure()`、`request_lock()`、
`clear_locked_target()`、`get_locked_target()`、`lock_nearest_target()`、
`select_target_at_screen_position()`、`get_locked_target_direction()` 和
`is_valid_lock_target()` 保持原签名与既有语义。

---

## Task 1：锁定特效三状态的独立行为契约

**文件：**

- 新建 `UnitSystem/Tests/TargetLockIndicatorTest.gd`
- 新建 `UnitSystem/Visuals/Targeting/TargetLockIndicator.gd`

**产出：** 一个暂时不依赖正式网格与材质、但已经完整实现三状态和位置语义的独立特效控制器。

- [ ] **Step 1：建立 SceneTree 失败测试骨架**

  沿用项目现有 `extends SceneTree`、延迟执行 `_run()`、收集 `_failures`、成功 `quit(0)`、失败
  `quit(1)` 的测试风格。测试直接实例化脚本节点，不需要加载玩家、敌人或测试房间。

- [ ] **Step 2：写入进入状态的失败断言**

  测试一个初始隐藏的实例调用 `play_enter(Vector3(2, 0.03, -3))` 后：立即可见、状态为
  `ENTER`、世界位置与传入值一致、初始透明度低于维持值且初始缩放小于 1。

- [ ] **Step 3：写入进入完成后自动维持的失败断言**

  推进超过默认进入时长的帧数，断言状态自动成为 `MAINTAIN`、缩放恢复为 1、基础透明度达到维持
  值且节点继续可见。测试允许维持呼吸造成小范围透明度变化，但不允许回到进入状态。

- [ ] **Step 4：写入位置更新与重复维持的失败断言**

  在维持状态连续传入两个不同世界位置，断言节点跟随最终位置、状态仍为 `MAINTAIN`。该步骤确保
  位置同步不会被误写成每帧重播进入。

- [ ] **Step 5：写入退出与隐藏的失败断言**

  调用 `play_exit()` 后立即断言状态为 `EXIT` 且仍可见；推进超过退出时长后断言不可见。记录退出
  前世界位置并确认退出过程中位置不改变，保证目标已经释放时不再访问目标对象。

- [ ] **Step 6：写入退出中断的失败断言**

  在退出动画尚未结束时调用 `play_enter()` 并传入新位置，断言退出立即中断、状态回到 `ENTER`、
  节点移动到新位置，随后正常转为 `MAINTAIN`。

- [ ] **Step 7：写入无效重复操作的失败断言**

  初始隐藏时调用 `play_exit()` 应保持隐藏；连续调用 `hide_immediately()` 应保持安全；隐藏后的
  `update_world_position()` 可以更新等待位置但不能自行显示特效或改变状态。

- [ ] **Step 8：运行测试并确认 RED 原因**

  在 PowerShell 运行：

  `& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' --headless --path 'G:\Godot\ProjectVOD' --script 'res://UnitSystem/Tests/TargetLockIndicatorTest.gd'`

  预期 exit code `1`，原因必须是脚本或上述正式接口尚不存在；测试脚本自身不得有解析错误。

- [ ] **Step 9：实现最小三状态控制器**

  创建 `TargetLockIndicator.gd`。根类型使用 `Node3D`，初始隐藏；进入和退出分别使用独立的导出
  时长，默认值限定在设计范围内；内部按帧推进当前状态、透明度和统一缩放。维持状态只保留轻微
  呼吸，不增加其他动画分支。

  透明度应通过统一的内部表现值驱动，不能让业务组件直接操作网格材质。脚本暂时允许没有
  `RingMesh` 子节点，以便本任务单独测试状态逻辑；缺少视觉子节点只影响画面，不得让状态方法报错。

- [ ] **Step 10：补齐邻近中文接口说明**

  为三状态枚举、所有导出参数、公开方法及世界坐标参数写明用途、单位、默认行为和影响范围。
  明确说明该类不接受 `UnitBase`、不拥有锁定目标且不会发送锁定信号。

- [ ] **Step 11：运行针对性测试确认 GREEN**

  重复 Step 8 命令。预期 exit code `0`，输出 `TargetLockIndicatorTest: PASS`，且没有 orphan node、
  无效属性、失效对象或每帧重复警告。

- [ ] **Step 12：提交独立行为契约**

  只暂存本任务的测试脚本、控制器脚本及 Godot 为这两个脚本生成的相邻 UID 文件。提交信息建议：
  `feat: add target lock indicator state controller`。

---

## Task 2：正式圆环场景与材质表现

**文件：**

- 修改 `UnitSystem/Tests/TargetLockIndicatorTest.gd`
- 新建 `UnitSystem/Visuals/Targeting/TargetLockIndicator.gdshader`
- 新建 `UnitSystem/Visuals/Targeting/TargetLockIndicator.tscn`

**依赖：** Task 1 已提供三状态接口和可独立运行的状态控制器。

**产出：** 一个可直接实例化、默认隐藏、有正常遮挡且不包含碰撞的正式金黄色圆环资源。

- [ ] **Step 1：扩展场景资源失败测试**

  测试先验证正式 `.tscn` 与 `.gdshader` 路径存在并可加载，然后实例化场景，确认根节点类型为
  `TargetLockIndicator`、默认隐藏、使用顶层世界变换，并且场景只装配一个正式环形显示层。

- [ ] **Step 2：增加节点和渲染契约失败断言**

  要求稳定节点路径 `RingRoot/RingMesh`：`RingMesh` 必须是 `MeshInstance3D`，使用约 `1.2m × 1.2m`
  的 `QuadMesh`，水平放置，关闭阴影；整个特效子树不得包含 `CollisionObject3D`、`CollisionShape3D`
  或其他参与选取的节点。

- [ ] **Step 3：增加材质契约失败断言**

  断言 `RingMesh` 使用正式 `ShaderMaterial` 和本任务 shader；材质具备金黄色、环形内外半径、边缘
  软化、整体透明度参数。测试确认 shader 文本没有 `disable_depth_test`，以此锁定“不穿墙显示”。

- [ ] **Step 4：增加三状态驱动视觉的失败断言**

  实例化真实场景后调用 Task 1 接口，确认进入、维持、退出时脚本能够把透明度传入材质，且退出
  完成后场景根节点隐藏。测试不比较渲染截图，只验证节点、资源和状态驱动契约。

- [ ] **Step 5：运行扩展测试并确认 RED 原因**

  运行 `TargetLockIndicatorTest.gd`。预期因正式场景、shader 或视觉节点尚不存在而失败，而 Task 1
  已通过的三状态断言必须继续通过。

- [ ] **Step 6：创建正式 shader**

  shader 使用空间透明渲染和无光照模式，根据面片 UV 到中心的距离生成圆环；外半径约占 UV 半径
  的 0.5，内半径根据 `5%～7%` 的可视环宽确定，并使用窄范围平滑边缘。颜色默认金黄色，自发光
  强度保持克制；总透明度由控制脚本设置。不得关闭深度测试，不增加扫描线、图标、箭头或额外闪光。

- [ ] **Step 7：创建正式特效场景**

  根节点挂载 `TargetLockIndicator.gd` 并默认隐藏、启用顶层世界变换。建立 `RingRoot/RingMesh`；将
  QuadMesh 水平旋转，尺寸设为约 1.2 米；关闭阴影，并使用场景内部 ShaderMaterial 引用正式
  shader。不得添加碰撞、灯光、粒子、Decal、Viewport 或额外环层。

- [ ] **Step 8：连接状态控制器与材质参数**

  `TargetLockIndicator.gd` 只定位稳定的 `RingMesh`，在存在有效 ShaderMaterial 时更新整体透明度。
  场景或材质缺失时保留三状态运行并只报告一次诊断，不允许每帧报错，也不允许上抛到锁定组件。

- [ ] **Step 9：运行场景和状态测试确认 GREEN**

  运行 `TargetLockIndicatorTest.gd`，预期 exit code `0`。随后以 Godot headless editor scan 加载工程，
  确认 `.tscn`、`.gdshader`、脚本类和内部资源均可解析。

- [ ] **Step 10：提交正式视觉资源**

  只提交本任务列出的场景、shader、更新后的测试和对应新 UID。提交信息建议：
  `feat: add formal target lock ring effect`。

---

## Task 3：以最小改动接入 PlayerTargetingComponent

**文件：**

- 新建 `UnitSystem/Tests/PlayerTargetingComponentTest.gd`
- 修改 `UnitSystem/Components/Targeting/PlayerTargetingComponent.gd`
- 修改 `UnitSystem/Components/Targeting/PlayerTargetingComponent.tscn`

**依赖：** Task 2 已提供可实例化的 `TargetLockIndicator.tscn` 和稳定三状态接口。

**产出：** 现有锁定成功、维持、切换和解除事件能够驱动唯一正式特效实例，同时所有既有锁定接口
保持不变。

- [ ] **Step 1：建立真实组件集成测试夹具**

  测试加载 `00_UnitBase.tscn` 与 `PlayerTargetingComponent.tscn`，在临时 `Node3D` 世界中创建一名
  team 1 持有者和两名 team 2 目标。两名目标加入现有 `enemy_targets` 分组，位置放在默认 5 米范围
  内；组件作为持有者子节点并调用现有 `configure(owner)`。

- [ ] **Step 2：锁定现有公开接口契约**

  在增加视觉断言前先验证现有 `request_lock()`、`get_locked_target()`、`clear_locked_target()`、
  `get_locked_target_direction()` 和 `locked_target_changed` 行为。成功锁定广播一次；重复锁定同一目标
  不重复广播；主动清空只在状态实际变化时广播一次 `null`。

- [ ] **Step 3：写入 Debug 与正式特效分离的失败断言**

  断言 `TargetLockRangeIndicator` 节点仍存在但默认隐藏；默认正式特效场景已经配置。锁定目标后
  Debug 节点仍隐藏，而正式特效可见。分别关闭 `indicator_enabled` 与
  `formal_indicator_enabled`，确认另一类显示和锁定状态不受影响。

- [ ] **Step 4：写入单实例和首次进入的失败断言**

  成功锁定第一目标后，断言组件子树中正式特效实例数量严格为 1、状态为 `ENTER`，世界位置等于
  目标根位置加 `Vector3.UP * formal_indicator_height`，且 `locked_target_changed` 保持既有次数。

- [ ] **Step 5：写入跟随和重复锁定的失败断言**

  等待进入完成后移动第一目标并推进物理帧，断言正式圆环同步到新脚下位置并保持 `MAINTAIN`。
  再次请求同一目标，断言实例数量和信号次数不增加，特效保持 `MAINTAIN` 而不是重新进入。

- [ ] **Step 6：写入目标切换的失败断言**

  从第一目标切换到第二目标，断言业务锁定立即变为第二目标、既有信号增加一次、仍只有同一个正式
  特效实例；该实例立即移动到第二目标脚下并进入 `ENTER`，旧目标位置没有退出副本。

- [ ] **Step 7：写入清空与退出中断的失败断言**

  主动清空后断言业务目标立即为 `null`、信号只发送一次、正式特效在最后位置进入 `EXIT`；退出完成
  前重新锁定另一目标，断言同一实例中断退出并在新位置进入。

- [ ] **Step 8：写入关闭正式特效和无资源降级的失败断言**

  分别验证 `formal_indicator_enabled = false` 与 `formal_indicator_scene = null`：组件仍可成功配置、
  请求锁定、返回锁定目标、计算方向和发送信号；不得生成正式特效实例。资源缺失警告只出现一次，
  不能在每个物理帧重复输出。

- [ ] **Step 9：运行集成测试并确认 RED 原因**

  运行：

  `& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' --headless --path 'G:\Godot\ProjectVOD' --script 'res://UnitSystem/Tests/PlayerTargetingComponentTest.gd'`

  预期测试因正式特效配置和驱动尚未接入而失败；现有锁定接口断言必须已经通过。

- [ ] **Step 10：明确现有圆环为 Debug 并默认关闭**

  在 `PlayerTargetingComponent.gd` 中保留现有 `indicator_enabled`、`indicator_thickness`、
  `indicator_height`、`indicator_idle_color` 和 `indicator_locked_color` 字段名称，避免无必要的序列化
  迁移；只把分类和邻近说明改成明确 Debug 语义，并将 `indicator_enabled` 默认值改为 `false`。

  `_configure_indicator()` 和 `_update_indicator_color()` 继续只处理 `TargetLockRangeIndicator`，不得
  接受或操作正式圆环实例。

- [ ] **Step 11：加入正式特效配置和单实例初始化**

  增加三项已锁定的正式配置字段，并在 `_ready()` 中独立调用 `_create_formal_indicator()`。创建过程
  必须与 `_configure_indicator()` 分开；正式特效禁用、场景为空、实例类型错误或接口不完整时安全
  降级，不允许提前返回阻断输入动作验证和锁定初始化。

- [ ] **Step 12：映射 request_lock() 的进入事件**

  保持现有合法性检查和信号顺序。只有目标从无到有或从一个目标切换到另一个目标时调用
  `_enter_formal_indicator(target)`；`_locked_target == target` 的现有早返回路径保持不变，因此不会
  重播进入。

- [ ] **Step 13：映射 clear_locked_target() 的退出事件**

  有目标时先保存正式特效已经同步的最后位置，再按现有语义清空 `_locked_target` 并广播一次
  `null`，随后调用 `_exit_formal_indicator()`。无目标时调用清空仍不广播，也不反复重启退出动画。

- [ ] **Step 14：在现有物理验证后同步位置**

  `_physics_process()` 先沿用现有 `is_valid_lock_target()` 判断：失效则调用统一清空路径；仍有效才
  调用 `_update_formal_indicator_position()`。不得新增第二套距离、阵营、死亡或可选取判断，也不得
  让特效位置更新决定业务目标是否清空。

- [ ] **Step 15：处理组件销毁**

  `_exit_tree()` 继续不广播状态变化。在释放 `_locked_target` 和 `_owner_unit` 前后调用
  `_dispose_formal_indicator()`，立即隐藏并释放正式实例，不等待退出动画，不访问目标对象。

- [ ] **Step 16：在组件场景配置默认正式资源**

  `PlayerTargetingComponent.tscn` 继续保留唯一 Debug 子节点 `TargetLockRangeIndicator`；为
  `formal_indicator_scene` 指定 Task 2 的正式 PackedScene。正式特效由运行时按配置实例化，不能把
  `RingMesh` 直接复制到组件场景中。

- [ ] **Step 17：运行组件测试确认 GREEN**

  重复 Step 9 命令，预期 exit code `0`，输出 `PlayerTargetingComponentTest: PASS`。同时重新运行
  `TargetLockIndicatorTest.gd`，确认接入没有破坏独立三状态契约。

- [ ] **Step 18：提交最小锁定接入**

  仅暂存本任务列出的组件、场景、测试及对应新增 UID。提交信息建议：
  `feat: show formal effect for player target lock`。

---

## Task 4：完整失效生命周期与边界测试

**文件：**

- 修改 `UnitSystem/Tests/PlayerTargetingComponentTest.gd`

**依赖：** Task 3 已完成正式特效的基础锁定、切换、跟随和主动解除。

**产出：** 所有现有解除原因都统一映射到退出状态，目标突然释放时不存在失效引用。

- [ ] **Step 1：增加非法显式选择测试**

  在已有合法锁定后分别请求友方单位、未加入候选分组的单位和范围外敌人，确认请求返回 false、旧
  锁定按现有语义清空、信号只广播一次 `null`、正式特效进入 `EXIT`。

- [ ] **Step 2：增加目标死亡测试**

  锁定合法敌人后通过现有伤害入口使其死亡，推进一个物理帧，确认目标因现有合法性检查被清空、
  正式特效从死亡前最后脚下位置退出；不得给 `UnitBase` 新增专用特效回调。

- [ ] **Step 3：增加不可选取测试**

  锁定后通过现有目标可选取配置使目标不再合法，推进物理帧，确认使用同一清空路径和退出状态，
  不新增第二套监听器。

- [ ] **Step 4：增加超距测试**

  锁定后把目标移动到 `maximum_lock_distance` 之外，推进物理帧，确认业务锁定清空且圆环退出；把
  目标放回范围内不能自动恢复旧锁定或重新显示圆环。

- [ ] **Step 5：增加目标直接释放测试**

  锁定目标并至少完成一次位置同步后调用目标的正常树移除/释放流程，推进物理帧，确认无
  `previously freed instance` 错误、锁定变为 `null`、正式特效使用最后有效位置完成退出。

- [ ] **Step 6：增加持有者死亡与无效测试**

  使用真实持有者的现有死亡入口，确认 `_has_valid_owner()` 失效后锁定被清空并进入退出；持有者
  复活不会恢复旧目标或自动播放进入。组件被直接移出场景树时应立即清理而不是等待退出。

- [ ] **Step 7：增加退出幂等性测试**

  同一清空原因连续触发、清空后再次清空、目标死亡同时超距等情况下，`locked_target_changed(null)`
  只发生一次，正式特效不会反复从头播放退出，也不会创建新实例。

- [ ] **Step 8：运行生命周期测试确认 GREEN**

  运行 `PlayerTargetingComponentTest.gd`，预期 exit code `0` 且没有失效引用、孤儿节点或重复警告。
  然后运行 `TargetLockIndicatorTest.gd`，预期继续 exit code `0`。

- [ ] **Step 9：提交生命周期契约**

  只提交更新后的 `PlayerTargetingComponentTest.gd`。如果为通过本任务需要修改正式特效或组件，必须
  先确认是本计划内边界问题，并把相关文件同批纳入审查；不得扩展到 `UnitBase` 或 AI。提交信息
  建议：`test: cover target lock indicator lifecycle`。

---

## Task 5：锁定消费者回归与工程加载验证

**文件：**

- 原则上不新增或修改文件；本任务负责运行和记录验证。

**依赖：** Task 1 至 Task 4 全部完成。

**产出：** 证明正式特效没有改变现有玩家锁定接口、威胁聚焦、死亡生命周期及工程资源加载。

- [ ] **Step 1：运行两项新增测试**

  依次运行 `TargetLockIndicatorTest.gd` 与 `PlayerTargetingComponentTest.gd`。两项都必须 exit code
  `0`，分别输出明确 PASS；任何解析警告、无效资源或 orphan node 都必须先解决。

- [ ] **Step 2：运行威胁聚焦严格回归**

  运行 `PlayerThreatFocusControllerTest.gd`，必须保持 exit code `0`。重点确认它仍通过
  `request_lock()`、`PlayerBase.get_locked_target()` 和既有信号工作，不需要认识正式特效。

- [ ] **Step 3：运行死亡生命周期基线哨兵**

  运行 `UnitDeathLifecycleTest.gd`，按“当前基线与已知例外”比较结果。玩家死亡清除锁定、死亡拒绝
  新锁定、复活后可重新锁定等玩家部分不得新增失败；只有实施前已记录的 Saber 唯一失败可以原样
  保留。

- [ ] **Step 4：运行 Godot headless editor scan**

  使用 Godot 4.7 console 在 `G:\Godot\ProjectVOD` 执行 headless editor scan 并退出。预期所有新增
  `.gd`、`.gdshader`、`.tscn` 和修改后的组件场景可加载，不存在循环依赖、无效 ext_resource、
  shader 编译错误或脚本类冲突。

- [ ] **Step 5：运行项目启动烟雾测试**

  以 headless 模式启动项目并设置有限帧数/超时后退出。预期启动流程不因正式特效失败；在没有玩家
  锁定目标时正式圆环不短暂出现，Debug 范围圆环默认不可见。

- [ ] **Step 6：审计改动范围**

  检查 `git status --short`、`git diff --check` 和本功能各提交的文件列表。允许范围仅为本文“新建
  文件”和“修改文件”所列内容及其相邻新 UID；不得出现 `PlayerBase`、AI、技能、物品、GameFlow、
  测试场景或 `project.godot` 改动。

- [ ] **Step 7：处理验证阶段生成的 UID**

  如果 editor scan 生成本计划新增脚本或 shader 的合法相邻 UID，确认文件引用目标正确后补充到
  对应资源提交或使用独立维护提交。不得纳入现存无关 MCP UID 文件。建议提交信息：
  `chore: register target lock effect resource uids`。

---

## Task 6：实际战斗中的视觉验收与参数收口

**文件：**

- 仅在确认默认参数需要调整时修改：
  `UnitSystem/Visuals/Targeting/TargetLockIndicator.tscn`
- 仅在确认材质可读性需要调整时修改：
  `UnitSystem/Visuals/Targeting/TargetLockIndicator.gdshader`
- 不修改任何测试房间中的单位实例。

**依赖：** 自动测试、工程扫描与启动烟雾测试已经满足 Task 5 标准。

**产出：** 在真实战斗画面中确认第一版圆环清晰但不过度，并冻结默认视觉参数。

- [ ] **Step 1：准备人工测试，不改测试场景结构**

  打开项目现有已经包含玩家和敌人的战斗场景。只使用现有单位实例和现有锁定输入；不得由实施者
  自动向 `Scenes/TestScene.tscn` 添加、删除、移动或重新配置单位。

- [ ] **Step 2：检查首次锁定与维持**

  使用现有鼠标选取与最近目标按键分别锁定敌人，确认金黄色圆环位于目标脚下、默认约 1.2 米、
  进入时间短、维持效果轻微，不与头顶血条、仇恨描边或命中特效混淆。

- [ ] **Step 3：检查移动、遮挡和地面表现**

  观察目标移动时圆环是否稳定跟随；让目标经过当前场景可用的遮挡物，确认圆环不会穿墙显示；观察
  平地与已有轻微坡面，确认 0.03 米高度没有明显闪烁。第一版不因坡面问题加入射线贴地系统。

- [ ] **Step 4：检查快速切换与所有退出原因**

  快速切换两个目标，确认只有一个圆环直接在新目标脚下进入；测试主动解除、点击非法位置、目标
  死亡和超距，确认都只播放同一种退出表现，没有额外闪光或旧位置副本。

- [ ] **Step 5：只调整已经批准的视觉参数**

  如果可读性不足，只允许在以下范围调整：外径、环宽、金黄色色值、自发光强度、边缘软化、进入
  时长、退出时长、起始缩放、退出缩放、维持呼吸幅度和 0.03 米附近的小幅高度修正。不得新增粒子、
  箭头、图标、目标 HUD、第四状态或地面投射系统。

- [ ] **Step 6：参数调整后完整复测**

  重新运行两个新增测试、威胁聚焦回归、死亡基线哨兵、editor scan 和启动烟雾测试。任何默认参数
  改变都应同步更新邻近中文说明以及测试中锁定的合理范围。

- [ ] **Step 7：提交视觉收口**

  仅在确有调整时提交正式场景、shader、脚本说明或相关测试。提交信息建议：
  `style: tune target lock indicator presentation`。如果无需调整，本任务不制造空提交。

---

## 完整回归命令矩阵

所有脚本测试都使用：

`G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe`

并固定参数：`--headless --path 'G:\Godot\ProjectVOD' --script '<res://测试路径>'`。

| 顺序 | 测试 | 预期结果 |
|---|---|---|
| 1 | `res://UnitSystem/Tests/TargetLockIndicatorTest.gd` | exit 0，三状态与正式资源契约通过 |
| 2 | `res://UnitSystem/Tests/PlayerTargetingComponentTest.gd` | exit 0，锁定与正式特效集成通过 |
| 3 | `res://UnitSystem/Tests/PlayerThreatFocusControllerTest.gd` | exit 0，既有锁定消费者无回归 |
| 4 | `res://UnitSystem/Tests/UnitDeathLifecycleTest.gd` | 按基线规则；不得新增既有 Saber 之外的失败 |
| 5 | Godot headless editor scan | exit 0，无脚本、shader 或资源错误 |
| 6 | Godot headless project smoke | 在限定时间正常启动退出，无新增错误 |

测试矩阵不得把 `UnitDeathLifecycleTest` 当前已知的 exit code `1` 笼统写成“全部测试必须 exit 0”。
验收必须比较具体失败数量和文本，从而区分既有问题与本功能回归。

## 最终 Definition of Done

- 正式锁定圆环由独立 `.tscn`、`.gd` 和 `.gdshader` 构成，不复用 Debug 范围圆环的节点、网格、
  材质、颜色或显示开关。
- `TargetLockRangeIndicator` 仍能按原逻辑显示最大锁定距离，但被明确标记为 Debug 且默认关闭。
- `PlayerTargetingComponent` 仍是锁定状态唯一事实来源，所有现有公开方法、信号和合法性规则保持
  原语义。
- 成功锁定时正式圆环在目标脚下进入；有效锁定期间维持并跟随；所有解除原因统一退出。
- 重复锁定同一目标不重播进入；切换目标复用同一个实例并在新目标位置进入；旧目标位置不生成
  退出副本。
- 正式特效只有进入、维持、退出三个表现状态，没有确认闪光、切换闪光或第四动画状态。
- 目标被直接释放时没有失效引用，退出使用最后有效世界位置；组件销毁时立即清理。
- 正式特效关闭、资源为空、实例类型错误或视觉子节点缺失时，锁定输入、getter、方向和信号继续
  工作，诊断不会每帧刷屏。
- 圆环默认金黄色、约 1.2 米外径、正常深度遮挡、不投射阴影、不包含碰撞、不参与目标射线。
- 不增加每帧目标扫描；只在现有锁定有效性物理检查后同步当前目标位置。
- 不修改 `PlayerBase`、AI、仇恨、技能、物品、攻击、伤害、死亡、GameFlow、InputMap 或测试场景。
- 所有新增/修改导出参数和公开接口都有符合 `AGENTS.md` 的邻近简体中文说明。
- 两项新增测试和威胁聚焦回归必须 exit code `0`；工程扫描和启动烟雾测试无新增错误。
- `UnitDeathLifecycleTest` 必须符合记录的基线例外规则，不能新增玩家锁定或其他失败。
- 人工验收确认首次锁定、维持跟随、快速切换、遮挡及所有退出原因的画面符合三状态设计。
- 最终提交只包含本文列出的目标锁定正式特效、组件接入、测试和对应 UID；用户原有工作区改动保持
  原样。
