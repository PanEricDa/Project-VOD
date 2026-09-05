# 战斗 HUD 血条设计

日期：2026-09-05

## 目标与范围

本阶段只实现屏幕空间的队伍生命 HUD，不实现锁定目标、顶部目标信息、专注、技能、物品、
状态图标或头像资源。HUD 必须直接读取现有 `UnitBase` 生命数据，不改变玩家、友方 AI、敌人、
伤害和死亡逻辑。

布局遵循已经确认的规则：玩家信息框固定在屏幕左下角；友方 AI 信息框在玩家框上方自下向上
排列并与玩家框左边缘对齐；友方框的宽高约为玩家框的三分之二。玩家框预留后续资源和状态
信息的扩展位置，但本阶段不显示无意义的占位内容。

## 基本原则

- 以当前结构为基础做直接新增，不因 UI 需求重构 `UnitBase`、玩家或 AI。
- 数据源只依赖所有单位已经共有的生命 getter 与信号。
- HUD 只读战斗状态，不参与伤害、治疗、死亡、复活和 AI 决策。
- 不做每帧单位扫描或生命轮询；场景绑定一次，生命变化由信号驱动。
- 屏幕 HUD 与现有头顶 `WorldHealthBar` 相互独立，两者可以同时存在或分别关闭。
- 当前只建立已经需要的接口，不提前制作完整的技能栏、Buff 栏或队伍编成系统。

## 架构选择

新增两个独立场景：

```text
GameFlow/UI/CombatHUD.tscn
GameFlow/UI/CombatHUD.gd

UnitSystem/Components/UI/UnitHealthFrame.tscn
UnitSystem/Components/UI/UnitHealthFrame.gd
```

职责关系如下：

```text
GameRunController
  ├─ 发现当前场景中的玩家与友方单位
  ├─ 创建并持有 CombatHUD
  └─ 在场景切换时解绑旧队伍、绑定新队伍
                       │
                       ▼
CombatHUD（布局与队伍槽位）
  ├─ 玩家 UnitHealthFrame：标准模式
  └─ 友方 UnitHealthFrame：紧凑模式，可重复实例化
                       │
                       ▼
UnitBase（生命 getter、health_changed、died、revived）
```

`GameRunController` 已经负责跨房间 UI 和当前场景观察，因此只在这里增加 HUD 的创建与重新绑定，
不新建第二套全局场景监听器。结果界面和战斗 HUD 应分别初始化：任意一个实例化失败，只影响自身，
不得因为 `_ready()` 提前返回而让另一个系统失效。

## 单位发现与绑定

`GameRunController` 在当前场景稳定后递归收集 `UnitBase`：

- `faction_id == "Player"` 的唯一单位作为玩家。
- `faction_id == "Ally"` 的有效单位作为伙伴。
- 敌人和中立单位不进入队伍 HUD。
- 伙伴沿场景树发现顺序排列，使顺序稳定且不新增队伍排序配置。
- 没有玩家时 HUD 整体隐藏。
- 多于一个玩家时不猜测主角：HUD 隐藏并只输出一次明确警告。
- 已失效或正在退出树的伙伴跳过，不阻塞其他槽位。

`CombatHUD` 提供明确的外部绑定边界：

```gdscript
func bind_party(player: UnitBase, allies: Array[UnitBase]) -> void
func unbind_party() -> void
func refresh_party(player: UnitBase, allies: Array[UnitBase]) -> void
```

`bind_party()` 先清除旧绑定，再建立玩家框与伙伴框；`refresh_party()` 允许未来在同一房间中招募、
离队或召唤伙伴时由上层主动刷新。本阶段不监听任意节点增删，也不进行周期扫描。

## UnitHealthFrame 职责与接口

`UnitHealthFrame` 是绑定任意 `UnitBase` 的可复用显示组件，不认识 Player、Guardian 或具体职业。

```gdscript
enum PresentationMode { PLAYER, COMPACT_ALLY }

func bind_unit(unit: UnitBase) -> void
func unbind_unit() -> void
func set_presentation_mode(mode: PresentationMode) -> void
func refresh_immediately() -> void
func is_bound() -> bool
```

绑定时立即读取：

- `get_current_health()`
- `get_maximum_health()`
- 单位显示名；当前使用 `unit.name` 作为稳定回退值。

随后监听：

- `health_changed(previous_health, current_health, maximum_health, source)`
- `died(source)`
- `revived(current_health, source)`
- 单位的 `tree_exiting`，用于安全解绑。

组件退出树、重新绑定或绑定单位退出时，必须断开旧信号。重复绑定同一单位不得产生重复连接。

本阶段不为显示名修改 `UnitBase`。未来若单位数据层增加 `get_display_name()`，只需修改本组件的
名称解析策略，不改变 HUD 和队伍绑定接口。

## 显示内容与状态

玩家框与伙伴框均显示：

- 单位名称。
- 当前生命 / 最大生命的数值文本。
- 实时生命进度条。

生命变化立即更新，不加入延迟损血条、低血闪烁或 Tween。最大生命为零时比例按零处理，数值不得
出现除零、NaN 或负数。

死亡后不删除也不重排槽位：血量显示为 `0 / 最大生命`，整个框进入明确的降低亮度状态，并显示
“倒下”文本。这样聚怪战斗中队伍位置不会因连续死亡跳动。复活时原槽位立即恢复正常显示。

绑定单位意外失效时，该框重置并隐藏；正常死亡不隐藏。

## 节点与布局

建议节点结构：

```text
CombatHUD (CanvasLayer)
└─ SafeArea (MarginContainer，全屏左下锚点)
   └─ PartyColumn (VBoxContainer，底部对齐)
      ├─ AllyFrames (VBoxContainer)
      └─ PlayerFrame (UnitHealthFrame)

UnitHealthFrame (PanelContainer)
└─ FrameContent (HBoxContainer)
   ├─ CoreInfo (VBoxContainer)
   │  ├─ Header (名称、倒下状态)
   │  ├─ HealthBar
   │  └─ HealthValue
   └─ ExtensionSlot (MarginContainer)
```

`PartyColumn` 的视觉顺序保持伙伴在上、玩家在下。新增伙伴时按稳定数组顺序加入 `AllyFrames`；
视觉上离玩家最近的是数组中的最后一个伙伴，不需要反转运行时数据。

默认设计基准为：

- 玩家框最小尺寸约 `420 × 90` 像素。
- 伙伴框最小尺寸约 `280 × 60` 像素，即宽高均为玩家框的三分之二。
- 左、下安全边距以及框间距由 `CombatHUD` 的导出参数配置。
- 使用左下锚点和容器布局，不写死屏幕坐标；分辨率变化时仍贴合左下安全区域。

`ExtensionSlot` 在没有内容时折叠，不制造空白占位；它只是明确的节点接口，未来玩家专注值、职业
资源或状态摘要可以作为子场景挂入。紧凑伙伴模式始终隐藏该插槽。

## 样式边界

首版采用场景内 `StyleBoxFlat` 子资源和控件样式覆盖，避免仅为首版新增正式 `.tres` 主题资源。
基础视觉为深色半透明底板、清晰边框、高对比生命色和可读文本。玩家框与伙伴框使用同一组件，
只通过展示模式调整尺寸、字号、边距和扩展槽可见性。

当更多 HUD 元素形成统一视觉语言后，再把颜色、字体和边框迁移到共享 Theme；此次结构不会阻碍
迁移，也不提前引入尚无复用价值的主题配置层。

## 生命周期与层级

- `CombatHUD` 使用独立 `CanvasLayer`，层级低于当前 `RunResultOverlay` 的 100。
- 当前场景变化时，先 `unbind_party()`，再延迟发现并绑定新场景单位，防止旧场景信号残留。
- 重开房间复用相同流程，不在 HUD 中调用 `reload_current_scene()`。
- 战败或胜利时结果界面自然覆盖 HUD；首版无需额外隐藏或冻结 HUD。
- HUD 不拦截鼠标输入，所有纯显示节点使用忽略鼠标的过滤方式。

## 开放性边界

此次开放性集中在稳定的扩展点，而不是预制未来系统：

- `UnitHealthFrame` 可绑定任何 `UnitBase`，未来可用于召唤物、小队、Boss 队友或其他队伍界面。
- 玩家与伙伴共用一个显示组件，避免后续修复生命显示时维护两套逻辑。
- `CombatHUD` 只接收单位引用，不读取 AI 组件、职业、技能或物品结构。
- `refresh_party()` 为运行时队伍变化保留入口。
- `ExtensionSlot` 为玩家框未来内容保留组合入口。
- 所有可配置 `@export` 参数和公共方法、信号都必须按项目规则就近写简体中文说明。

明确不做：抽象 UI 数据总线、全局单位注册表、通用 MVVM 层、动态布局配置资源。等实际出现第二个
消费者或运行时编队需求后再扩展，避免首版为了假设需求改动现有框架。

## 失败处理

- HUD 场景或单个信息框实例化失败时输出明确错误，其余游戏流程继续运行。
- 绑定无效玩家时执行安全解绑并隐藏 HUD。
- 重复刷新不得残留旧伙伴框或重复信号。
- 数组中的 `null`、非树内单位或重复单位会被跳过；玩家不得同时生成伙伴框。
- 一个信息框更新失败不得影响其他单位，也不得回写生命值。

## 验证契约

新增针对性自动测试，至少覆盖：

- `UnitHealthFrame` 绑定后正确显示初始当前/最大生命和名称。
- 伤害与治疗通过现有信号立即更新进度和文本。
- 死亡时槽位保留并显示倒下状态，复活后恢复。
- 重绑、解绑和单位退出树后不再响应旧单位信号。
- 一名玩家和多名伙伴生成正确数量的框，玩家在左下，伙伴在其上方且左对齐。
- 伙伴框默认宽高约为玩家框的三分之二，紧凑模式不显示扩展槽。
- 场景切换和重开后旧绑定清除，新场景重新绑定。
- 没有玩家或存在多个玩家时安全隐藏，不影响结果界面和房间流程。
- HUD 不生成锁定目标显示，也不修改现有 `WorldHealthBar`。

完成后还应运行现有生命、死亡、世界血条和游戏流程测试，并以 Godot headless 加载新增场景，确认
没有新增脚本解析错误、无效节点引用或信号连接警告。

## 实施顺序

1. 为 `UnitHealthFrame` 编写失败测试，覆盖绑定、生命变化、死亡/复活和解绑。
2. 实现通用信息框及玩家/伙伴两种展示模式。
3. 为 `CombatHUD` 编写布局和多单位绑定测试。
4. 实现左下队伍布局、稳定槽位与公开绑定接口。
5. 为 `GameRunController` 补充场景发现、切换和两个 UI 独立初始化的集成测试。
6. 接入 `CombatHUD`，不修改单位战斗与 AI 结构。
7. 运行新增与相关回归测试，在实际测试房间核对 1 名玩家与多名伙伴的可读性。

## 验收结果

进入含玩家和伙伴的战斗房间后，左下角持续显示玩家真实生命；伙伴生命框在其上方稳定排列。
伤害、治疗、死亡、复活以及场景重开均能正确更新，且整个功能可以通过删除/停用 `CombatHUD`
恢复到原状态，不影响任何战斗行为。锁定系统保持未实现状态，等待后续单独设计。
