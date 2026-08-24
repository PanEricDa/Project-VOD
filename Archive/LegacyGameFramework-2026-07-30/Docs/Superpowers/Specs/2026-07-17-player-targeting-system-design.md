# PlayerBase 玩家索敌与锁敌系统设计

## 目标

将旧 `HeroController.gd` 中已经验证可用的玩家索敌、锁敌、锁定朝向和范围圈逻辑迁移到新的 `PlayerBase` 架构，同时保持移动、冲刺、重力和未来技能系统彼此解耦。

本次迁移只处理玩家主动锁定目标，不迁移攻击、技能自动释放、目标 UI 或摄像机逻辑。

## 总体架构

索敌功能由可拆装的 `PlayerTargetingComponent` 独立承担，`PlayerBase` 只负责：

- 在进入场景时为组件注入自身作为持有者。
- 转发锁定目标变化信号。
- 提供少量稳定的门面接口。
- 在计算视觉朝向时优先使用锁定目标方向。

推荐节点结构：

```text
PlayerBase
├── Visual
├── CollisionShape3D
└── TargetingSystem
    └── TargetLockRangeIndicator
```

对应文件：

```text
UnitSystem/
├── PlayerBase.gd
├── PlayerBase.tscn
└── Components/
    └── Targeting/
        ├── PlayerTargetingComponent.gd
        └── PlayerTargetingComponent.tscn
```

`PlayerTargetingComponent` 可以从 `PlayerBase` 中删除。删除后玩家仍可移动、冲刺、受重力影响并按移动方向转身，只失去锁定功能。

## 输入与选择规则

全部输入继续使用现有 InputMap：

- `player_target_select`：鼠标中键，按屏幕位置发射摄像机射线。
- `player_target_nearest`：F 键，锁定范围内距离玩家最近的有效敌方单位。

鼠标射线采用以下规则：

1. 使用当前 Viewport 的活动 `Camera3D`。
2. 射线排除玩家持有者自身的 RID。
3. 射线检测层默认掩码为 `5`，兼容地面与敌人。
4. 命中有效敌方 `UnitBase` 时尝试锁定。
5. 命中地面、非敌方、不可选目标、范围外目标或空白位置时取消当前锁定。

最近目标选择从 `enemy_targets` 组读取候选者，并在所有有效候选者中选择三维世界距离最近者。本阶段保持旧行为，不加入屏幕可见性或视线遮挡检查。

## 目标有效性

目标必须同时满足：

- 是有效且仍在场景树中的 `UnitBase`。
- 属于可配置的候选组，默认 `enemy_targets`。
- `is_targetable()` 返回 `true`。
- `is_dead()` 返回 `false`。
- 玩家持有者的 `is_hostile_to(target)` 返回 `true`。
- 与玩家之间的距离不超过 `maximum_lock_distance`，默认 `5.0m`。

组件在每个物理帧重新验证当前目标。任一条件失效时统一调用 `clear_locked_target()`，更新范围圈并发送一次目标变更信号。

中立单位和同队单位不能被锁定。目标关系以 `UnitBase.team_id` 为准，不再只依赖 `enemy_targets` 分组。

## 公共配置与接口

`PlayerTargetingComponent` 导出参数：

```gdscript
@export var target_select_action: StringName = &"player_target_select"
@export var target_nearest_action: StringName = &"player_target_nearest"
@export_range(0.5, 50.0, 0.1, "or_greater")
var maximum_lock_distance: float = 5.0
@export_flags_3d_physics var selection_collision_mask: int = 5
@export_range(10.0, 2000.0, 1.0, "or_greater")
var selection_ray_length: float = 1000.0
@export var candidate_group: StringName = &"enemy_targets"
@export var indicator_enabled: bool = true
@export_range(0.005, 0.25, 0.005, "or_greater")
var indicator_thickness: float = 0.03
@export_range(0.0, 1.0, 0.005)
var indicator_height: float = 0.03
@export var indicator_idle_color: Color = Color(0.18, 0.9, 0.32, 0.32)
@export var indicator_locked_color: Color = Color(1.0, 0.12, 0.08, 0.58)
```

公共信号和方法：

```gdscript
signal locked_target_changed(target: UnitBase)

func configure(owner_unit: UnitBase) -> bool
func get_locked_target() -> UnitBase
func request_lock(target: UnitBase) -> bool
func clear_locked_target() -> void
func lock_nearest_target() -> bool
func select_target_at_screen_position(position: Vector2) -> bool
func get_locked_target_direction() -> Vector3
func is_valid_lock_target(target: UnitBase) -> bool
```

返回布尔值的方法用于告诉调用方请求是否成功，不要求调用方读取组件内部字段。

`PlayerBase` 对外保留：

```gdscript
signal locked_target_changed(target: UnitBase)

func get_locked_target() -> UnitBase
func clear_locked_target() -> void
```

未来技能、UI 或伙伴管控逻辑只依赖 `PlayerBase` 的门面接口和信号，无需知道组件节点路径。

## 朝向优先级

玩家移动与玩家视觉朝向分开处理。每个物理帧的朝向优先级为：

1. 有效锁定目标方向。
2. 当前冲刺方向。
3. 当前移动输入方向。

锁定只旋转 `PlayerBase/Visual`，不旋转 `CharacterBody3D` 根节点，不改变移动向量、冲刺方向、碰撞体或固定摄像机方向。

## 范围圈表现

`TargetLockRangeIndicator` 为组件场景内部的 `MeshInstance3D`，运行时生成 `TorusMesh`：

- 外半径与 `maximum_lock_distance` 保持一致。
- 内半径由外半径减去 `indicator_thickness` 得到。
- 未锁定时持续显示绿色半透明材质。
- 锁定有效目标时显示红色半透明材质。
- 取消锁定后恢复绿色。
- 材质使用透明、无光照、双面显示，并关闭阴影。
- 节点高度由 `indicator_height` 控制，避免与地面深度冲突。

若 `indicator_enabled=false`，只隐藏显示，不影响锁定判定。

## 初始化与容错

- `configure()` 只接受有效的 `UnitBase`；配置失败时返回 `false`，清理锁定并停止输入处理。
- 缺少活动摄像机时，鼠标选择返回 `false` 并取消当前锁定。
- 缺少范围圈节点时发出清晰配置警告，但索敌仍可工作。
- InputMap 动作不存在时给出配置警告，相应输入不可用，但不阻断玩家移动。
- 组件被卸载或退出场景树时清理持有者引用和当前锁定。
- 重复锁定同一目标不重复发送 `locked_target_changed`。

## PlayerBase 接入

`PlayerBase.tscn` 在根节点下实例化 `PlayerTargetingComponent.tscn`，默认路径为 `TargetingSystem`。

`PlayerBase.gd` 增加可配置组件路径：

```gdscript
@export_node_path("Node")
var targeting_component_path: NodePath = ^"TargetingSystem"
```

`_ready()` 中安全获取组件、调用 `configure(self)` 并连接组件信号。组件缺失时不报致命错误，玩家的已有行为继续运行。

`_physics_process()` 在组件存在时读取 `get_locked_target_direction()`，并按既定优先级覆盖视觉朝向。组件不直接修改 `PlayerBase.velocity`、`Visual.rotation` 或冲刺状态。

## 测试范围

新增独立组件测试，验证：

- 默认配置和公共接口存在。
- 合法敌方目标可以锁定。
- 同队、中立、死亡、不可选、离树、超距或错误分组目标被拒绝。
- 重复锁定不重复发信号。
- 清除和目标失效只发出一次 `null` 变更。
- 最近目标选择正确，并忽略无效候选者。
- 范围圈半径、颜色和显示开关与配置一致。
- 缺少摄像机或持有者时安全失败。

更新 `PlayerBase` 测试，验证：

- 场景装配了独立索敌组件。
- 组件收到 PlayerBase 持有者。
- PlayerBase 门面接口和转发信号正常。
- 锁定目标时朝向优先于移动和冲刺。
- 删除组件后移动、冲刺、重力与移动朝向仍可运行。

最后运行全部 `UnitSystem` 测试、项目既有 headless 测试和 Godot 4.7 脚本扫描。不得修改 `Scenes/TestScene.tscn` 或代替用户添加单位实例。

## 暂缓内容

本次不实现：

- 锁定目标轮廓、头顶标记或生命 UI。
- 目标切换列表或手柄摇杆选择。
- 墙体视线遮挡。
- 摄像机自动对焦或旋转。
- 技能自动释放或技能系统目标注入。
- 旧 `HeroController.gd` 的删除。
