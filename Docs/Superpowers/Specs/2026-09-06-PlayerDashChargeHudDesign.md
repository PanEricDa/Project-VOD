# 玩家 Dash 逐层恢复与 HUD 监控设计

日期：2026-09-06

## 目标

在不重构现有玩家移动系统、不新增 Dash 业务组件的前提下，将玩家 Dash 从“全部次数耗尽后统一冷却、统一回满”调整为“任意一层被消耗后开始固定冷却、每个冷却周期恢复一层”。同时在玩家生命条正下方增加一条较细的淡黄色 Dash 条，持续显示当前完整次数与正在恢复的一层进度。

HUD 必须是严格的只读监控者。Dash 次数、冷却、逐层恢复、进度保留和最终连续进度全部由 `PlayerBase` 计算；HUD 不维护第二份状态、不倒计时、不预测恢复、不修改 Dash。

## 项目约束

- 正确项目根目录为 `G:\Godot\ProjectVOD`。
- 使用 Godot Engine 4.7 与现有 GDScript、场景和 SceneTree headless 测试体系。
- 除原则性错误或严重 Bug 外，不评估、精简或重构现有结构；优先在已实现框架上最小修改和直接扩展。
- 不修改 AI 单位的 Dash；本设计只涉及 `PlayerBase`。
- 不修改 Dash 距离、速度、无敌时间、攻击取消、输入映射和移动优先级。
- 不修改伙伴与顶部目标生命框的表现。
- 不向 `Scenes/TestScene.tscn` 自动添加或修改任何单位实例。
- HUD 的存在、隐藏、解绑或释放不得影响 Dash 业务状态。

## 当前实现与问题

`PlayerBase` 当前持有以下状态与配置：

- `maximum_consecutive_dashes`：最大连续 Dash 次数，当前默认值为 2；
- `dash_cooldown_duration`：恢复冷却，当前默认值为 2 秒；
- `_available_dash_count`：当前可用的完整次数；
- `_dash_cooldown_remaining`：当前剩余冷却；
- `get_available_dash_count()`：只读返回完整次数；
- `get_dash_cooldown_remaining()`：只读返回剩余冷却。

现规则只在 `_available_dash_count` 归零且最后一次 Dash 结束后启动冷却，冷却结束后直接恢复至最大次数。因此最大次数为 2 时，使用一次后会永久停留在 1/2，除非玩家主动消耗最后一次。这会鼓励玩家为了触发恢复而浪费应急 Dash，与拉怪、规避和保留机动余量的玩法相冲突。

## 已确认的新规则

### 基本规则

- 玩家进入场景时仍以最大 Dash 次数开始。
- 每次 Dash 开始时立即消耗一个完整次数，保持现有扣除时机。
- 只要当前次数低于最大次数，就存在一个“当前恢复层”的固定 CD。
- 每完成一个完整 CD，只恢复一层。
- 恢复一层后若仍未满，立即开始下一层的同长度 CD。
- 恢复至满层后停止计时，剩余 CD 固定为 0。
- Dash 过程中仍禁止开始下一次 Dash，保持现有移动状态约束。

### 再次消耗不重置恢复

恢复进行期间再次使用 Dash：

- 当前完整次数减少一层；
- 正在进行的恢复计时保持原值；
- 已经积累的恢复进度不会丢失；
- HUD 的总长度准确下降 `1 / n`。

例如最大次数为 2，当前剩余 1 层且下一层已恢复 60%，则业务连续进度为 `1.6`。再次 Dash 后完整次数变为 0，但 60% 的恢复进度保留，连续进度变为 `0.6`。

### 大帧间隔

如果单帧 `delta` 大于一个甚至多个恢复周期，Dash 系统应按真实经过时间连续结算所有已经完成的层，并把剩余时间保留到下一层。不能因为低帧率或调试暂停后的大 `delta` 每帧最多只恢复一层，也不能丢弃超过当前周期的时间。

### 零冷却

`dash_cooldown_duration <= 0` 延续“无冷却”的直观含义：消耗后立即恢复到最大次数，不进入循环计时。玩家仍受“当前 Dash 尚未结束时不能再次 Dash”的现有约束，因此不会在同一 Dash 动作中重复启动。

### 死亡和输入禁用

- 玩家死亡时沿用当前 `_physics_process()` 的提前返回规则，Dash 恢复计时冻结。
- 玩家复活后保留死亡前的完整次数和当前层恢复进度，并从冻结处继续。
- 房间结算等原因只禁用玩家输入时，恢复计时继续运行；输入许可不属于 Dash 资源时间轴。
- 死亡仍清除正在执行的位移、方向和无敌阶段，不恢复已经消耗的次数。

## Dash 状态权威与只读接口

`PlayerBase` 继续是 Dash 状态的唯一事实来源。现有字段、输入处理、移动执行和公开查询不迁移到其他组件。

新增两个只读查询：

```gdscript
func get_dash_charge_capacity() -> int
func get_dash_charge_progress() -> float
```

`get_dash_charge_capacity()` 返回经过 `PlayerBase` 规则收束、不小于 1 的有效最大次数。HUD 不直接
钳制 `maximum_consecutive_dashes`。

返回范围为 `0.0` 到有效最大次数，返回值由两部分组成：

```text
当前完整次数 + 当前正在恢复的一层的完成比例
```

例如最大次数为 2：

| 状态 | 返回值 |
|---|---:|
| 满层 | 2.0 |
| 剩余一层，尚未开始填充 | 1.0 |
| 剩余一层，当前层恢复 40% | 1.4 |
| 无完整层，当前层恢复 60% | 0.6 |
| 第一层刚恢复、第二层刚开始 | 1.0 |

这个接口属于 Dash 业务状态查询，不包含颜色、像素、ProgressBar 或 HUD 节点概念。所有除法、钳制、零冷却处理和当前层进度合成都在 `PlayerBase` 内完成。

既有接口保持名称和类型不变：

```gdscript
func get_available_dash_count() -> int
func get_dash_cooldown_remaining() -> float
func is_player_dashing() -> bool
```

其中 `get_dash_cooldown_remaining()` 的语义扩大为“当前正在恢复的一层的剩余 CD”。只要次数未满，它就可能大于零，不再要求次数必须为零。当前工程没有外部业务消费者依赖旧限制。

`maximum_consecutive_dashes` 和 `dash_cooldown_duration` 继续是进入场景前配置的 Inspector 参数。本阶段不支持在玩家运行期间动态修改最大次数或 CD；未来装备确实需要动态修改时，再设计正式的配置刷新入口。

## 内部恢复算法边界

`PlayerBase` 内部仍只使用 `_available_dash_count` 与 `_dash_cooldown_remaining`，不为每一层创建 Timer、数组、字典或独立对象。

建议增加两个私有辅助方法：

```gdscript
func _ensure_dash_recharge_started() -> void
func _complete_elapsed_dash_recharges(delta: float) -> void
```

职责如下：

- `_start_dash()` 完成次数扣除后调用 `_ensure_dash_recharge_started()`；
- `_ensure_dash_recharge_started()` 只在未满且没有活动计时时启动当前层 CD；已有计时绝不重置；
- `_complete_elapsed_dash_recharges()` 使用本帧 `delta` 推进当前层，并在必要时循环结算多个完整周期；
- `_finish_dash()` 不再启动冷却，只保留位移收尾职责；
- 满层、零冷却和异常负值均在 Dash 系统内部收束为合法状态。

不增加 DashManager、ChargeComponent、Timer 子节点或 Autoload。

## HUD 架构

### PlayerDashStatusBar

新增独立的纯显示场景与脚本：

```text
UnitSystem/Components/UI/PlayerDashStatusBar.tscn
UnitSystem/Components/UI/PlayerDashStatusBar.gd
```

组件职责只有：

- 绑定或解绑一个 `PlayerBase`；
- 从 `get_dash_charge_capacity()` 读取已经收束的 ProgressBar 最大值；
- 每个显示帧读取 `get_dash_charge_progress()`；
- 将读取结果直接写入 ProgressBar 的 `value`；
- 玩家引用失效或解绑时隐藏并停止处理。

组件明确禁止：

- 读取剩余次数和剩余 CD 后自行合成比例；
- 自己递减 CD；
- 使用 Tween 猜测恢复进度；
- 缓存“预计恢复完成时间”；
- 调用 `_start_dash()`、请求输入或写入任何 PlayerBase 字段；
- 在显示动画结束时通知 Dash 系统恢复次数。

因此删除整个 HUD、关闭其 `_process()` 或让场景加载失败，都只会失去显示，不会影响 Dash。

### UnitHealthFrame 扩展槽

复用现有 `UnitHealthFrame.ExtensionSlot`，但将它从 `FrameContent` 的右侧移动到 `CoreInfo` 中、生命条的正下方。该槽继续只在玩家展示模式且存在扩展内容时显示；伙伴和目标模式始终折叠。

为避免 `CombatHUD` 访问 `UnitHealthFrame` 私有节点路径，增加通用内容接口：

```gdscript
func set_extension_content(content: Control) -> void
func clear_extension_content() -> void
```

接口只管理 UI 子节点与槽位可见性，不了解 Dash。`UnitHealthFrame` 不引用 `PlayerBase`，也不读取 Dash 状态。这同时修复现有扩展槽“运行时加入内容后不会自动刷新可见性”的开放性缺口。

### CombatHUD 绑定

`CombatHUD` 负责实例化一个 `PlayerDashStatusBar`，通过 `set_extension_content()` 装入固定玩家框，并与玩家生命框同步绑定和解绑：

```text
GameRunController
    ↓ 提供玩家与伙伴快照
CombatHUD
    ├─ PlayerFrame.bind_unit(player)
    ├─ PlayerDashStatusBar.bind_player(player as PlayerBase)
    ├─ AllyFrames（保持现状）
    └─ TargetFrame（保持现状）
```

若阵营为 `Player` 的单位不是 `PlayerBase`，玩家生命框仍正常显示，Dash 条安全隐藏。Dash 条实例化失败也只输出一次诊断并跳过 Dash 显示，不阻断生命 HUD、目标 HUD 或战斗流程。

## 视觉规格

- Dash 条位于玩家生命条正下方，与生命条左右边缘对齐。
- 默认高度为 8 像素，明显细于 22 像素生命条。
- 填充色使用低饱和淡黄色，建议 `Color(1.0, 0.88, 0.42, 0.95)`。
- 槽底使用深黄褐色半透明背景，保持可读但不形成黑色外框。
- 不显示数字、百分比、名称、图标或冷却文字。
- 不使用损耗残影、闪烁、发光或 Tween。
- 每次消耗由业务进度立即下降一个完整单位，视觉长度自然下降 `1 / n`。
- 恢复期间根据业务层返回的连续值平滑增长。
- 第一版不绘制分段线；最大次数改变时无需重新创建视觉节点。
- 玩家死亡时作为 `PlayerFrame` 的子内容随整个框体一起变暗。

## 数据流

```text
玩家 Dash 输入
    ↓
PlayerBase._start_dash()
    ├─ 扣除完整次数
    └─ 启动或保留当前恢复层计时
             ↓ 每个物理帧
PlayerBase 推进并结算逐层恢复
             ↓ 只读 getter
PlayerBase.get_dash_charge_progress()
             ↓ 每个显示帧直接读取
PlayerDashStatusBar.value
```

数据流严格单向。不存在从 HUD 返回 `PlayerBase` 的箭头。

## 生命周期与降级

- `CombatHUD` 初始化时至多创建一个玩家 Dash 条实例。
- HUD 未绑定队伍时，Dash 条解绑并隐藏。
- 重绑新玩家时，先解绑旧玩家，再绑定新玩家。
- 玩家离开场景树后，Dash 条清空引用并隐藏。
- 切换房间时沿用 `CombatHUD.unbind_party()`，不得残留旧玩家引用。
- 伙伴动态信息框不创建 Dash 条。
- 顶部锁定目标框不创建 Dash 条，即使目标本身是 `PlayerBase`。
- Dash 条资源无法实例化时，玩家生命 HUD 继续正常工作。
- `PlayerBase` 不检查 HUD 是否存在，也不发起 HUD 创建。

## 测试契约

### Dash 业务测试

至少覆盖：

- 初始次数与连续进度均为最大值；
- 第一次消耗后即启动恢复，不要求耗尽；
- 每次消耗准确减少一层；
- 恢复期间再次消耗不重置剩余 CD；
- 连续进度在再次消耗时准确下降 1.0；
- 一个 CD 只恢复一层；
- 未满时自动进入下一层恢复；
- 满层后剩余 CD 为 0；
- 大 `delta` 能结算多个恢复周期并保留余量；
- 零 CD 不进入死循环并立即恢复满层；
- 现有攻击取消、冲刺无敌、死亡与复活测试不回归。

### HUD 监控测试

至少覆盖：

- Dash 条场景可加载并具有 8 像素默认高度和淡黄色填充；
- 未绑定时隐藏且不处理；
- 绑定玩家后最大值等于 `get_dash_charge_capacity()`；
- 显示值逐帧精确等于 `get_dash_charge_progress()`；
- HUD 更新前后玩家次数和剩余 CD 完全不变；
- HUD 不包含本地冷却 Tween 或独立倒计时状态；
- 解绑或释放 HUD 后 Dash 仍能正常恢复；
- 扩展槽位于生命条下方，只在玩家模式显示；
- 伙伴框和目标框不出现 Dash 条；
- 场景切换与结果界面不破坏现有 HUD。

### 回归测试

至少运行：

- `PlayerDashRechargeTest.gd`
- `PlayerDashStatusBarTest.gd`
- `PlayerDashComboContinuityTest.gd`
- `UnitDeathLifecycleTest.gd`
- `UnitHealthFrameTest.gd`
- `CombatHUDTest.gd`
- `CombatHUDBindingIntegrationTest.gd`
- `CombatHUDTargetHealthTest.gd`
- `GameRunResultFlowTest.gd`
- Godot 4.7 headless 编辑器扫描

## 明确不做

- 不给每层 Dash 建立独立并行计时器。
- 不修改 AI Dash。
- 不增加 Dash 数字、图标、键位提示或音效。
- 不增加分段线、损耗残影或充满闪光。
- 不让 HUD 推进 CD 或恢复次数。
- 不引入通用资源系统、技能资源系统或全局 HUD 数据总线。
- 不支持运行时修改最大次数和 CD。
- 不顺带处理动态伙伴加入 HUD 的既有扩展问题。

## 验收标准

最大次数为 2 时，玩家从满层使用一次 Dash，淡黄色条立即从满长度下降到一半，并在一个固定 CD 内从一半连续恢复到满。若恢复到 60% 时再次 Dash，条立即下降总长度的一半，但当前 60% 恢复进度不丢失；之后每经过一个固定 CD 恢复一层，直到满层。

关闭、解绑或删除 HUD 后，相同输入与时间推进必须产生完全相同的 Dash 次数和冷却结果。HUD 代码中不存在 Dash CD 推导、次数恢复或业务状态写入。
