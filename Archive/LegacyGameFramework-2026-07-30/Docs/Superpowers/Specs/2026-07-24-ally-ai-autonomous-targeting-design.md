# Ally AI 自主索敌与稳定锁敌设计

## 目标

为当前 `AllyBase2` 增加独立、轻量、可装卸的自主索敌组件。组件负责持续感知敌方单位、按配置规则选择目标，并稳定维护当前锁定目标。

本阶段只建立“发现谁、锁定谁”的数据能力，不改变伙伴的编队移动、朝向、追击、攻击或技能行为。未来玩家策略系统可以通过替换同类型 Policy Resource 改变 AI 的目标选择倾向，但本阶段不实现玩家策略。

## 设计原则

- 索敌逻辑独立于 `AllyBase2` 的编队移动逻辑。
- 目标规则使用一个公共 `TargetSelectionPolicy.gd`，所有策略 `.tres` 都引用该脚本。
- 不为每种策略维护一份独立 Policy 脚本。
- 第一版只实现当前确实需要的“最近有效敌人”规则。
- 当前目标有效时保持锁定，不因更近目标进入感知范围而频繁切换。
- 所有路径和资源按照人类可直接查找、理解和编辑的方式组织。

## 文件结构

```text
UnitSystem/
└── Components/
    └── Targeting/
        ├── PlayerTargetingComponent.gd
        ├── PlayerTargetingComponent.tscn
        └── AI/
            ├── AITargetingComponent.gd
            ├── AITargetingComponent.tscn
            └── Policies/
                ├── TargetSelectionPolicy.gd
                └── DefaultNearestEnemy.tres
```

现有玩家索敌文件不移动。AI 索敌相关文件集中放入 `Targeting/AI`，Policy 配置统一位于 `Targeting/AI/Policies`。

## 节点结构

`AITargetingComponent.tscn`：

```text
AITargetingComponent (Area3D)
└── DetectionShape (CollisionShape3D / SphereShape3D)
```

装配后的 `AllyBase2`：

```text
AllyBase2
├── CollisionShape
├── Visual
├── MovementSystem
│   ├── NavigationAgent3D
│   ├── LocomotionComponent
│   └── FormationComponent
└── AITargetingComponent
    └── DetectionShape
```

不增加空的 `TargetingSystem` 包装节点。`AITargetingComponent` 自身就是可拖放、可替换的完整组件。

## 组件职责

### AITargetingComponent

负责：

- 配置和同步球形感知范围。
- 按固定间隔读取 `Area3D.get_overlapping_bodies()`。
- 验证当前锁定目标的保持条件。
- 将范围内 `UnitBase` 候选交给 Policy。
- 建立、保持和解除锁定。
- 发送目标变化信号。
- 提供读取、清除、刷新和更换 Policy 的公共接口。

不负责：

- 移动、追击或返回编队。
- 控制视觉朝向。
- 普通攻击或技能释放。
- 玩家策略的具体规则。

### TargetSelectionPolicy

所有 Policy `.tres` 共用的唯一脚本类型。它同时保存规则参数，并实现统一的候选验证、评分和选择方法。

第一版字段：

```gdscript
enum TargetRelation {
    HOSTILE,
    FRIENDLY,
    ANY
}

enum PriorityMode {
    NEAREST
}

@export var target_relation = TargetRelation.HOSTILE
@export var require_targetable = true
@export var require_alive = true
@export var priority_mode = PriorityMode.NEAREST
```

第一版公共算法入口：

```gdscript
func is_candidate_valid(
    owner_unit: UnitBase,
    candidate: UnitBase,
    maximum_distance: float
) -> bool

func calculate_priority(
    owner_unit: UnitBase,
    candidate: UnitBase
) -> float

func select_target(
    owner_unit: UnitBase,
    candidates: Array[UnitBase],
    maximum_distance: float
) -> UnitBase
```

`NEAREST` 使用水平距离平方作为评分，数值越小优先级越高。未来确实需要新的筛选维度或评分方式时，由开发者扩充同一个脚本的字段和枚举；设计师继续创建及编辑同类型 `.tres`。

## 双半径与持续扫描

默认参数：

```gdscript
detection_enabled = true
acquisition_radius = 6.0
retention_radius = 7.0
refresh_interval = 0.2
selection_policy = DefaultNearestEnemy.tres
```

只建立一个半径为 `retention_radius` 的 `SphereShape3D`：

- 未锁定目标时，Policy 只允许首次选择处于 `acquisition_radius` 内的候选。
- 已锁定目标只要仍符合结构条件，并且水平距离不超过 `retention_radius`，就继续保持。
- `retention_radius` 在运行时保证不小于 `acquisition_radius`。

组件每隔 `refresh_interval` 重新读取当前重叠对象，而不是只依赖一次性的 `body_entered` 事件。因此：

- 敌人持续停留在范围内时仍会参与之后的每次索敌。
- 组件暂时禁用、Policy 暂时无结果或目标状态之后发生变化时，后续刷新仍能重新发现目标。
- 不需要额外维护容易残留无效引用的长期候选数组。

## 目标生命周期

每次刷新按以下顺序执行：

```text
检测是否启用？
├─ 否：清除当前锁定并结束
└─ 是：检查当前锁定
        ├─ 当前目标仍存活、可选中、敌对、位于 7m 内
        │   └─ 保持锁定，不与其他候选比较
        └─ 当前目标无效
            ├─ 解除当前锁定
            ├─ 读取球内全部重叠对象
            ├─ 提取 UnitBase 候选
            ├─ Policy 按 6m 获取范围筛选和评分
            └─ 锁定最优目标；没有结果则保持空目标
```

目标在以下任一条件发生时失效：

- 节点已删除或退出场景树。
- 不再是可用的 `UnitBase`。
- 已死亡且 Policy 要求存活。
- 已变为不可选中且 Policy 要求可选中。
- 与持有者的阵营关系不再符合 Policy。
- 与持有者的水平距离超过保持半径。

新目标进入范围不会覆盖一个仍然有效的当前目标。这是第一版的锁定稳定机制。

## 公共接口

`AITargetingComponent`：

```gdscript
signal locked_target_changed(
    previous_target: UnitBase,
    current_target: UnitBase
)

func configure(owner_unit: UnitBase) -> bool
func get_locked_target() -> UnitBase
func has_locked_target() -> bool
func refresh_target() -> void
func clear_locked_target() -> void
func set_selection_policy(
    policy: TargetSelectionPolicy,
    refresh_immediately: bool = true
) -> void
```

`configure()` 显式注入持有者，避免组件反向依赖 `AllyBase2` 的具体类型。未来其他 `UnitBase` 派生 AI 也可以复用该组件。

`AllyBase2`：

```gdscript
signal locked_target_changed(
    previous_target: UnitBase,
    current_target: UnitBase
)

func get_targeting_component() -> AITargetingComponent
func get_locked_target() -> UnitBase
```

`AllyBase2` 使用固定子节点 `$AITargetingComponent`，不额外导出一个必须手工填写的 NodePath。它只配置组件、转发信号和开放读取接口。

## Inspector 与配置安全

- `selection_policy` 使用强类型 `TargetSelectionPolicy`，Inspector 只能接受对应 Resource。
- Area3D 碰撞掩码直接使用 Godot 节点已有属性，不重复导出相同字段。
- `CollisionShape3D` 的 Shape 必须是 `SphereShape3D`。
- 运行时调整双半径时，组件同步修改球体半径。
- 球体 Shape 在配置时复制为单位私有资源，避免一个 Ally 修改范围后影响其他实例。
- 本阶段不增加视野圆环、视线遮挡、扇形视野或目标标识特效。

## 异常处理

- 重叠对象不是 `UnitBase`：忽略。
- 候选就是持有者自身：忽略。
- Policy 缺失：只发出一次清晰配置警告，保持空目标，不中断 Ally 的其他行为。
- 持有者、DetectionShape 或 SphereShape 缺失：配置失败，禁用组件并报告明确错误。
- `detection_enabled` 变为 `false`：停止刷新并清除当前锁定。
- 运行时切换 Policy：根据参数决定是否立即重新筛选。
- 组件退出场景树：清除当前目标引用，不操作目标单位本身。

## 测试范围

新增独立自动测试，不修改 `Scenes/TestScene.tscn`：

- 感知范围内最近的有效敌人会被锁定。
- 友方、中立、死亡、不可选中对象被忽略。
- 非 `UnitBase` 重叠物体被忽略。
- 敌人持续位于范围内时，后续刷新仍能发现它。
- 位于 `6m–7m` 的目标不能首次获取。
- 已锁定目标可以在 `6m–7m` 保持。
- 当前目标有效时，不因更近敌人进入而切换。
- 当前目标失效后自动选择下一个有效目标。
- 禁用组件会清除锁定。
- 更换 Policy 可以立即刷新目标。
- 多个 Ally 的感知半径资源互不影响。
- `AllyBase2` 正确读取并转发目标变化，同时编队移动仍保持现有行为。
- Godot 4.7 脚本编译、headless 测试、项目扫描和编辑器错误检查通过。

## 暂缓内容

- 玩家策略指令及策略 UI。
- 追击、攻击距离、普通攻击和技能调度。
- 自动面向目标。
- 视线遮挡和视野角度。
- 仇恨表、伤害来源、职业威胁和 Boss 权重。
- 感知范围可视化与锁定标记。
- Enemy AI 使用该组件的正式装配。

这些内容以后只消费 `get_locked_target()`、监听 `locked_target_changed`，或更换 `TargetSelectionPolicy.tres`，不需要侵入球形感知的内部实现。
