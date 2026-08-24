# Ally 阵型位置资源与轻量防重叠设计

## 1. 目标

将 `AllyBehaviorStateMachine` 中描述阵型站位的数字提取为可选择的
`FormationPositionData` 资源。创建新的 Ally 继承场景时，只需在 Inspector 选择一份
阵型位置资源，不再重复填写前后距离、左右范围等数字。

第一阶段仅迁移 Amy 当前使用的阵型位置数据，不预制后卫、后腰、左边卫、右边卫、
前卫或前锋资源。资源类型需保持开放，未来可由设计师继续创建这些位置资源，也可以由
UI 在运行时为单位切换资源。

同时在现有 Formation 随机移动目标生成阶段加入轻量防重叠检查。该检查只避免多个
同队 AI 预定过近的落脚点，不增加持续排斥力、不改变速度、不创建新的移动状态。

## 2. 范围

实现范围：

- 新增 `FormationPositionData` Resource 类型。
- 首轮新增一份 `Forward.tres`，由 Amy 使用。
- `AllyBehaviorStateMachine` 可读取和运行时替换位置资源。
- Formation 随机目标生成前检查同队 AI 的当前位置和已预定目标。
- 候选点被占用时重新随机，全部候选无效时选择相对最宽松的候选。
- 保留当前 Formation 平滑、游荡刷新、分侧、掉队追赶和 Dash 行为。

暂不实现：

- 后卫、后腰、边卫、前卫和前锋等预制资源。
- 子槽位、阵型协调器或队伍中心管理器。
- 独立换位计时器。
- 每帧分离力、物理碰撞或单位互相推开。
- 阵型编辑 UI。
- Combat 站位、战斗换位或战斗防重叠。

## 3. 文件结构

```text
UnitSystem/
└── AI/
    └── Ally/
        └── Formation/
            ├── FormationPositionData.gd
            └── Positions/
                └── Forward.tres
```

现有行为算法继续保留在：

```text
UnitSystem/Components/Behavior/AllyBehaviorStateMachine.gd
```

Resource 只保存数据，不执行随机、移动、索敌或状态切换算法。

## 4. FormationPositionData

建议接口：

```gdscript
class_name FormationPositionData
extends Resource

enum SideMode {
    FREE_CROSSING,
    LOCKED_RANDOM_SIDE,
    FIXED_LEFT,
    FIXED_RIGHT,
}

@export var display_name: String = "Formation Position"

@export_category("Center")
@export var center_offset: Vector2 = Vector2(0.0, 2.5)

@export_category("Wander Area")
@export_range(0.0, 5.0, 0.05)
var lateral_radius: float = 1.1

@export_range(0.0, 5.0, 0.05)
var lateral_minimum: float = 0.0

@export_range(0.0, 5.0, 0.05)
var forward_radius: float = 0.65

@export var side_mode: SideMode = SideMode.FREE_CROSSING
```

坐标约定：

- `center_offset.x`：相对当前跟随目标朝向的左右偏移，正值为右侧。
- `center_offset.y`：相对当前跟随目标朝向的前后偏移，正值为前方。
- `lateral_radius`：中心两侧可随机游荡的最大范围。
- `lateral_minimum`：需要锁定左右区域时，距离中心线的最小偏移。
- `forward_radius`：中心前后可随机游荡的最大范围。
- `side_mode`：保留现有自由跨侧、随机锁侧和固定左右侧能力。

平滑度、最大跟随距离、紧急 Dash 距离、游荡刷新时间、朝向和战斗参数不属于阵型
位置资源，继续由行为状态机统一维护。

## 5. Amy 默认资源

`Forward.tres` 精确迁移 Amy 当前继承的 Formation 默认值：

```text
display_name = "Forward"
center_offset = Vector2(0.0, 2.5)
lateral_radius = 1.1
lateral_minimum = 0.0
forward_radius = 0.65
side_mode = FREE_CROSSING
```

Amy 继承场景只覆盖：

```text
BehaviorStateMachine.formation_position =
    Forward.tres
```

第一阶段不创建其他职业或位置资源。

## 6. 装配与运行时接口

`AllyBehaviorStateMachine` 新增强类型导出字段：

```gdscript
@export var formation_position: FormationPositionData
```

运行时接口：

```gdscript
func set_formation_position(data: FormationPositionData) -> bool
func get_formation_position() -> FormationPositionData
```

`set_formation_position()` 的职责：

- 拒绝 `null` 或结构无效的资源。
- 保存新的共享资源引用。
- 重置当前 Formation 游荡目标。
- 如果单位当前处于 Formation 或 Return，立即刷新编队中心或下一个合法目标。
- 如果单位当前处于 Combat 或 Custom，只保存选择；重新进入 Return 或 Formation 时
  才应用。

Resource 保存共享静态配置。当前随机点、移动目标、分侧锁定和计时器仍是每个 AI
实例自己的运行时状态，不写回 `.tres`。

为了安全迁移，状态机在资源缺失时继续使用现有内建 Formation 默认值并给出配置警告，
不能因此停止重力、索敌或移动。Amy 必须显式装配新资源，以验证资源路径。

## 7. Formation 数据读取

资源只参与 Formation 和归队计算：

```text
FORMATION_WANDER
FORMATION_REPOSITION
RETURN
```

中心点计算：

```text
player_position
+ player_right * center_offset.x
+ player_forward * center_offset.y
```

游荡目标继续由现有随机刷新条件触发。状态机从资源读取范围后，沿用原随机算法生成
候选点。

以下状态完全不读取阵型位置数据，也不执行占用检查：

```text
COMBAT_APPROACH
COMBAT_HOLD
COMBAT_ATTACK
CUSTOM
```

强制脱战仍先清理战斗，再回到现有 `FORMATION_REPOSITION`；从该时刻开始重新应用阵型
资源。

## 8. 轻量防重叠算法

防重叠不是连续运动层，也不属于 `AIUnitBase` 的速度修正。它只在现有
`_select_new_formation_wander_target()` 准备提交新目标时运行。

### 8.1 候选生成

每次原游荡逻辑需要刷新目标时：

1. 根据 `FormationPositionData` 生成一个候选世界坐标。
2. 查找相同 `team_id` 的其他 `AIUnitBase`。
3. 计算候选点到其他单位当前位置的水平距离。
4. 对处于 Formation 的其他 Ally，同时检查其公开的当前预定移动目标。
5. 两类距离均满足最小预留间距时接受候选点。

Combat 单位不提供阵型预定点，但其真实当前位置仍可作为当前空间占用信息，避免
Formation 单位把落脚点直接选择在它身体内部。Combat 单位自身不运行任何阵型逻辑。

### 8.2 重选与降级

默认配置：

```text
minimum_reserved_spacing = 0.65m
maximum_candidate_attempts = 8
```

规则：

- 候选点过近时，在同一资源定义的区域内重新随机。
- 最多生成八个候选点。
- 记录每个候选点到最近占用点的距离。
- 如果八次都不满足 `0.65m`，选择最近占用距离最大的候选点。
- 不把目标点强行投影到资源区域之外。
- 不修改角色位置、速度、加速度或 Dash。

该算法只改变移动开始前选择的目标点。实际移动继续使用现有
`set_movement_target()`、导航、平滑减速和 `move_and_slide()`，因此不会出现位置
跳变。

路径临时交叉、移动途中短暂靠近或角色穿过彼此仍然允许。下次原游荡目标刷新时会再次
选择更宽松的落脚点。

## 9. 参数归属

以下参数属于 Formation 位置资源：

- 中心左右偏移
- 中心前后偏移
- 左右游荡范围
- 中心线最小偏移
- 前后游荡范围
- 分侧模式

以下参数继续属于状态机：

- `formation_smoothness`
- `maximum_player_distance`
- `emergency_dash_distance`
- 游荡刷新时间
- 最小目标变化距离
- Dash 决策参数
- Formation 朝向参数
- Combat 参数
- 强制脱战参数
- `minimum_reserved_spacing`
- `maximum_candidate_attempts`

防重叠参数是所有 Formation 的统一行为规则，不随前锋、后卫等位置资源重复配置。

## 10. 未来扩展

未来增加阵型位置时，设计师只需复制或创建新的 `.tres`：

```text
Defender.tres
DefensiveMid.tres
LeftWingBack.tres
RightWingBack.tres
AttackingMid.tres
Forward.tres
```

不需要新增脚本或修改状态机算法。

未来 UI 只调用：

```gdscript
ally.get_behavior_state_machine().set_formation_position(selected_resource)
```

UI 可以显示 `display_name`，但不直接编辑状态机内部数字。阵型保存系统可以保存资源
路径或稳定资源 ID；本阶段不实现该保存层。

## 11. 验证

- `FormationPositionData` 能从 Inspector 强类型选择。
- Amy 装配的资源值与迁移前实际 Formation 默认值一致。
- Amy 的编队中心、游荡范围、分侧和跟随行为迁移前后保持一致。
- 资源缺失时安全使用内建默认值。
- 运行时切换资源后，下一次 Formation 目标使用新数据。
- Combat 状态不读取资源、不运行占用检查。
- 两个同队 Ally 的候选目标过近时会重新选择。
- 防重叠同时检查其他单位当前位置与 Formation 预定目标。
- 八次候选均拥挤时选择最宽松候选，不越出资源区域。
- 防重叠不改变速度、位置、Dash 或物理碰撞。
- 原索敌、战斗、公共冷却、攻击、强制脱战和编队 Dash 测试继续通过。
- 不修改或添加任何测试场景中的单位实例。

## 12. 实施结果（2026-07-26）

设计已经按本文件落地：

- `FormationPositionData.gd`、`Forward.tres` 及强类型 Inspector 入口已创建。
- Amy 源场景已选择该资源，数值与迁移前保持一致。
- Formation 候选会检查同队 AI 的当前位置和 Formation 预定目标；不同队伍被忽略。
- 候选尝试次数和最小预留间距保留在状态机行为参数中，不复制到位置资源。
- Combat 状态不会消耗 Formation 候选，也不会被占用检查替换移动目标。
- 修复了 `configure()` 自动解析 Player 时导致状态机重复初始化、连续抽取两轮候选的
  既有问题；配置阶段现在只进行一次运行时初始化。

验证证据：

- 17 项 `UnitSystem/Tests/*.gd` 测试全部通过，其中包括资源契约、运行时切换、
  Combat 隔离、同队候选重选、最宽松降级、根节点改名、索敌与近战回归。
- Godot `4.7.stable.official.5b4e0cb0f` headless 编辑器扫描退出码为 0。
- `Scenes/TestScene2.tscn`、归档场景和旧 AI 攻击模块未被修改或删除。

## 13. 标准位置资源补全（2026-07-26）

在首轮 Amy 数据迁移验证完成后，位置目录已经补齐六份通用资源：

- `Defender.tres`
- `DefensiveMid.tres`
- `LeftWingBack.tres`
- `RightWingBack.tres`
- `AttackingMid.tres`
- `Forward.tres`

原 `AmyFormationPosition.tres` 已完整重命名为 `Forward.tres`；Amy 只引用通用前锋资源，
不再持有角色专用阵型资源。左右边卫的中心偏移严格镜像，其余位置沿玩家正面方向从
后卫到前锋排列。所有资源共用同一个 `FormationPositionData.gd`，新增位置不需要新增
脚本。
