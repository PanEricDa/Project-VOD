# 头顶世界血条组件设计

日期：2026-07-31

## 目标

为所有继承 `UnitBase` 的单位提供可拆卸、可配置的头顶血条。血条平时隐藏，
受到有效伤害时显示；最后一次受伤经过可配置时间后淡出。组件不得把 UI 逻辑写入
`UnitBase`，也不得依赖玩家、AI、武器或技能实现。

## 架构选择

采用 `SubViewport + Control + Sprite3D`：

- `Control` 和 `StyleBoxFlat` 负责圆角、边框、底槽以及进度条样式。
- `SubViewport` 把 Control UI 渲染成纹理。
- `Sprite3D` 在世界空间显示该纹理，并使用 Billboard 始终面向摄像机。
- 每个单位持有独立血条实例，适合当前单位规模，也方便设计师在场景中预览和调整。

暂不采用 Mesh Shader，避免样式调试只能依赖 Shader 参数；暂不使用全局
CanvasLayer 管理器，避免为当前规模引入额外注册、投影和屏幕边界管理。

## 节点结构

```text
UnitBase
├── SkillHost
├── Visual
├── WorldUIRoot
│   └── WorldHealthBar
│       ├── HealthBarViewport
│       │   └── BarRoot
│       │       ├── EmptySlot
│       │       ├── DamageBar
│       │       ├── HealthBar
│       │       └── Border
│       └── BarSprite
└── CollisionShape3D
```

`WorldUIRoot` 是通用世界 UI 插槽。`WorldHealthBar` 是独立 PackedScene；删除实例不会
影响单位生命、移动、战斗或索敌。未来正式角色只需覆盖 `WorldUIRoot` 的局部位置，
或把该插槽对齐到模型头顶挂点。

## 依赖方向

```text
UnitBase 公开生命信号和 getter
            ↓
WorldHealthBar 主动订阅并显示
```

`UnitBase` 不持有 `WorldHealthBar` 引用，也不调用 UI 方法。血条只读取：

- `health_changed(previous_health, current_health, maximum_health, source)`
- `damaged(amount, source)`
- `get_current_health()`
- `get_maximum_health()`

## 公共接口

```gdscript
func bind_health_source(source: UnitBase) -> void
func unbind_health_source() -> void
func refresh_immediately() -> void
func show_temporarily() -> void
func hide_immediately() -> void
func is_bound() -> bool
```

组件进入运行树时默认向上查找最近的 `UnitBase` 并绑定。手动调用
`bind_health_source()` 可以覆盖自动绑定，便于未来把血条挂载到其他世界 UI 容器。

## Inspector 参数

所有设计参数位于 `WorldHealthBar` 根节点，不新增 Profile Resource：

```gdscript
@export var local_offset := Vector3(0.0, 1.15, 0.0)
@export_range(0.0, 30.0, 0.1) var visible_duration := 2.5
@export_range(0.0, 2.0, 0.01) var fade_duration := 0.2
@export_range(0.0, 2.0, 0.01) var damage_hold_duration := 0.12
@export_range(0.0, 3.0, 0.01) var damage_decay_duration := 0.35
@export var bar_pixel_size := Vector2i(128, 16)
@export_range(0, 8, 1) var border_width := 2
@export_range(0, 16, 1) var corner_radius := 5
@export var health_color := Color(...)
@export var damage_color := Color(...)
@export var empty_color := Color(...)
@export var border_color := Color(...)
```

`BarSprite.pixel_size` 仍是普通 Inspector 属性，负责世界尺寸；不再复制一份同义参数。

## 动画规则

### 受伤

1. `health_changed` 先把绿色条立即设为当前生命比例。
2. 红色条保留受伤前的比例；连续受伤时取当前红条与受伤前比例的较大值。
3. `damaged` 使血条立即显示，并重置隐藏倒计时。
4. 红条等待 `damage_hold_duration` 后，在 `damage_decay_duration` 内从右向左缩至绿条。
5. 最后一次受伤经过 `visible_duration` 后，整体在 `fade_duration` 内淡出并隐藏。

### 治疗与复活

- 如果血条已显示，绿色与红色立即同步到新生命比例。
- 如果血条已隐藏，治疗和复活不会主动显示血条。
- 治疗会停止旧的红色损血动画，避免红条低于绿色条。

### 死亡

致命伤害仍走正常受伤表现：绿色归零、红色延迟归零，随后按相同计时隐藏。

## 视觉规范

- 白色圆角边框位于最上层。
- 空槽为黑色半透明。
- 绿色条表示实时生命。
- 红色条仅表示尚未消退的最近损失生命。
- 默认固定屏幕尺寸并启用 Billboard。
- 保留深度检测；被墙体完全遮挡的单位不会隔墙显示血条。
- 初始状态隐藏，包括初始生命值低于上限的单位。
- 隐藏期间禁用该实例的 SubViewport 更新；再次受伤显示时恢复持续更新。

## 失败与边界处理

- 找不到 `UnitBase` 时保持隐藏并安全空闲，不输出每帧错误。
- 重复绑定时先断开旧信号，避免一份伤害触发多次动画。
- 解绑或退出场景树时终止 Tween 并断开信号。
- 最大生命为零时比例安全视为零。
- 所有时长钳制为非负值；零时长应立即完成相应阶段。

## 测试契约

- 场景和脚本可加载，正式场景 UID 有效。
- 初始隐藏并自动绑定最近的 UnitBase。
- 伤害后显示；绿条立即下降，红条保留旧值后消退。
- 连续伤害重置可见计时。
- 治疗隐藏单位时不会显示血条。
- 可配置时间结束后淡出并隐藏。
- 解绑后生命变化不再更新组件。
- UnitBase 场景包含 `WorldUIRoot/WorldHealthBar`，且删除组件不改变 UnitBase API。
- Godot 4.7 headless、现有生命/死亡测试和 MCP 输出无新增错误或 warning。
