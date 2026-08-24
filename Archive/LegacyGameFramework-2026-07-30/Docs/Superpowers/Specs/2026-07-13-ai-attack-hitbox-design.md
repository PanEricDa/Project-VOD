# AI 攻击模块通用 Hitbox 设计

## 目标

为 `AIAttackModuleBase` 增加可由所有子攻击场景继承的命中检测能力。父模块统一管理攻击窗口、目标过滤、单轮去重和命中信号；ShieldAttack 只配置是否启用、盒体尺寸和局部位置。

本阶段只检测并发送命中事件，不实现伤害、生命值、击退、受击反馈或状态变化，也不修改 `res://Scenes/TestScene.tscn`。

## 架构

`AttackModuleBase.tscn` 在现有 `DeliveryRoot` 下内置独立检测组件：

```text
AttackModuleBase
└── DeliveryRoot
    └── HitboxDetector
        ├── HitboxShapeCast
        └── DebugHitbox
```

- `AIAttackModuleBase` 继续管理攻击生命周期，并在动画方法轨道打开或关闭命中窗口时同步启停检测组件。
- `AIAttackHitbox` 使用零长度 `ShapeCast3D` 作为固定体积查询，负责物理检测、分组过滤、单轮去重和调试显示。
- `AllyBase.set_attack_module()` 将持有者注入模块，检测组件据此排除持有者 RID，不依赖固定祖先层级。
- 父模块默认关闭 Hitbox，避免 CrossbowAttack、StaffAttack、MagicballAttack 在尚未设计 Delivery 时误用近战检测。

采用 ShapeCast 而不是 `Area3D.body_entered`，保证敌人在攻击窗口开启前已经位于区域内时仍能被检测；检测逻辑保持在独立组件中，避免继续扩大攻击生命周期脚本。

## 公共接口

`AIAttackModuleBase` 新增：

```gdscript
signal attack_hit(
    target: CharacterBody3D,
    hit_position: Vector3,
    hit_direction: Vector3
)

@export var hitbox_enabled: bool = false
@export_node_path("Node3D")
var hitbox_detector_path: NodePath = ^"DeliveryRoot/HitboxDetector"

func configure_attack_owner(body: CharacterBody3D) -> void
```

`AIAttackHitbox` 提供：

```gdscript
signal hit_detected(
    target: CharacterBody3D,
    hit_position: Vector3,
    hit_direction: Vector3
)

@export_flags_3d_physics var target_collision_mask: int = 4
@export var target_group: StringName = &"enemy_targets"
@export_range(1, 128, 1) var maximum_results: int = 32
@export var debug_hitbox_enabled: bool = false
@export var debug_idle_color: Color = Color(1.0, 0.75, 0.08, 0.18)
@export var debug_hit_color: Color = Color(1.0, 0.08, 0.04, 0.35)

func configure(owner_body: CharacterBody3D) -> void
func begin_detection() -> void
func end_detection() -> void
func is_detecting() -> bool
```

模块在 `hit_detected` 后原样转发 `attack_hit`。信号不携带伤害值；未来伤害系统可以从发送信号的模块及其 Profile 获取攻击来源和静态配置。

## 检测规则

- `_open_hit_window()` 在模块处于 ATTACKING 且 `hitbox_enabled=true` 时调用 `begin_detection()`。
- `_close_hit_window()`、`cancel_attack()`、`reset_module()`、脱战和卸装都会调用 `end_detection()`。
- 检测组件在有效窗口内每个物理帧调用 `force_shapecast_update()`，遍历不超过 `maximum_results` 个碰撞结果。
- 只接受 `target_collision_mask=4` 且属于 `enemy_targets` 的 `CharacterBody3D`。
- 使用目标实例 ID 保存当前窗口已经命中的对象；一个窗口可命中多个敌人，但每个敌人只发送一次事件。
- 每次 `begin_detection()` 清空去重集合。
- `hit_position` 优先使用 ShapeCast 返回的碰撞点。
- `hit_direction` 使用检测组件世界朝向的水平 `-Z`；异常时回退到 `Vector3.FORWARD`。
- 调试盒只在有效窗口显示；未命中为半透明黄色，至少命中一次后变为半透明红色。

## ShieldAttack 配置

ShieldAttack 覆盖父场景参数：

```text
hitbox_enabled = true
debug_hitbox_enabled = true
BoxShape3D.size = Vector3(0.75, 0.55, 0.65)
HitboxDetector.position = Vector3(0.12, 0.30, -0.55)
target_collision_mask = 4
target_group = enemy_targets
```

区域固定在角色正前方并略偏右，不跟随临时盾牌视觉动画。现有动画窗口保持 `0.14–0.27s`；未来正式资产可把检测组件改挂骨骼或武器挂点，而无需改变 `attack_hit` 接口。

## 异常与兼容行为

- 检测组件、ShapeCast 或碰撞形状缺失时，攻击动画仍可播放；模块跳过检测并报告清晰配置警告。
- 未配置持有者时仍可检测目标，但不执行持有者 RID 排除，便于独立场景测试。
- 父场景默认禁用近战 Hitbox，因此现有其他继承攻击模块的运行行为不变。
- 当前 EnemyBase 的物理第 3 层和 `enemy_targets` 分组直接满足默认过滤规则。

## 验证标准

- 父场景和全部继承场景保留通用检测节点与模块接口。
- 窗口外无命中；盾击窗口内能检测已经重叠的 Dummy。
- 同一窗口对同一目标只发出一次，多个目标分别发出一次。
- 下一轮窗口可再次命中同一目标。
- 取消攻击、重置、脱战和卸装后立即停止检测并隐藏调试盒。
- 命中只发送事件，不改变敌人脚本属性、速度或状态。
- Godot 4.7 自动测试、场景加载和 MCP 编辑器错误检查通过。

## 实施结果

最终实现采用本设计中的父场景 ShapeCast 方案，节点路径为：

```text
DeliveryRoot/HitboxDetector/HitboxShapeCast
DeliveryRoot/HitboxDetector/DebugHitbox
```

为了避免新 `class_name` 在 Godot 首次文件扫描前产生全局脚本类缓存顺序依赖，`AIAttackModuleBase` 通过稳定的节点接口持有检测器，而不对该成员使用全局类静态类型注解。检测组件自身仍保留 `class_name AIAttackHitbox`，供编辑器识别和未来复用。
