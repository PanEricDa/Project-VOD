# 玩家通用近战 Hitbox 设计

日期：2026-07-22

## 目标

在当前玩家武器攻击系统上增加简单、可调试、可换装的近战命中判定：攻击动画只标记判定窗口，`WeaponData` 保存每段攻击的盒体参数，`PlayerBase` 上的通用组件执行物理查询，`PlayerAttackController` 负责调度和对外转发命中信号。

本阶段只判定命中并发送信号，不直接造成伤害、击退、卡刀、音效或其他反馈。

## 职责边界

### WeaponData

每件武器直接保存各连击段的 Hitbox 数据，不引入额外 `HitboxProfile.tres`：

```gdscript
@export var hitbox_sizes: Array[Vector3] = []
@export var hitbox_center_offsets: Array[Vector3] = []
```

索引 `0` 对应 `basic_attack_1`，索引 `1` 对应 `basic_attack_2`，依此类推。

偏移采用面向设计师的约定：

- `X`：左右位置，正数为角色右侧。
- `Y`：相对角色底面原点的高度。
- `Z`：正数代表角色前方；组件内部转换为 Godot 本地 `-Z`。

数组缺项或尺寸无效时，该段动画仍可正常播放，但不产生 Hitbox 检测。

### CharacterAnimationEventPlayer

增加两个无参数方法，供 AnimationLibrary 的方法轨道调用：

```gdscript
func open_attack_hit_window() -> void
func close_attack_hit_window() -> void
```

这两个方法只发送对应信号，不读取武器、不保存连击段数，也不执行物理查询。

### PlayerAttackController

控制器继续维护当前装备和连击状态，并负责：

- 接收动画发出的打开、关闭窗口事件。
- 只在 `ATTACKING` 状态接受打开事件。
- 把当前 `WeaponData`、`combo_index` 和锁定朝向传递给检测组件。
- 在动画结束、取消连击、冲刺、卸装、换装或节点退出时保底关闭检测。
- 将组件的 `attack_hit` 信号原样转发给外部系统。

控制器不计算空间查询，也不直接调用目标的生命值接口。

### PlayerMeleeHitbox

在 `PlayerBase` 上安装一个通用检测组件：

```text
PlayerBase
├── Visual
├── CollisionShape3D
├── TargetingSystem
├── AttackController
└── MeleeHitbox
    └── DebugHitbox
```

组件使用 `PhysicsDirectSpaceState3D.intersect_shape()` 执行盒体查询，不创建常驻碰撞 `Area3D`。窗口开启后每个物理帧查询一次，以覆盖在窗口期间进入范围的移动目标。

公开接口：

```gdscript
signal attack_hit(
    target: UnitBase,
    hit_position: Vector3,
    hit_direction: Vector3,
    combo_index: int
)

func configure_owner(owner_unit: UnitBase) -> void
func begin_detection(
    weapon_data: WeaponData,
    combo_index: int,
    locked_direction: Vector3
) -> bool
func end_detection() -> void
func is_detecting() -> bool
```

## 命中流程

```text
AnimationLibrary 方法标记
        ↓
open_attack_hit_window / close_attack_hit_window
        ↓
CharacterAnimationEventPlayer 信号
        ↓
PlayerAttackController
        ↓ 当前 WeaponData + combo_index + 锁定方向
PlayerMeleeHitbox
        ↓ 每物理帧盒体查询与目标过滤
attack_hit 信号
        ↓
未来伤害、卡刀、音效、击退监听器
```

Hitbox 方向在窗口打开时锁定，并在整个窗口中保持不变。这与当前攻击位移的方向锁定规则一致，避免玩家中途转向导致检测盒突然旋转。

## 目标过滤

候选对象必须依次满足：

1. 位于 `target_collision_mask` 指定的物理层，默认掩码为 `4`。
2. 是 `UnitBase`。
3. 不是攻击持有者自身。
4. `is_targetable()` 返回 `true`。
5. 目标未死亡。
6. `owner_unit.is_hostile_to(target)` 返回 `true`。
7. 当前窗口尚未命中过该实例。

Hitbox 不强制依赖 `enemy_targets` 分组；分组继续服务索敌系统，实际敌我关系统一由 `UnitBase.team_id` 判断。

同一攻击窗口可以分别命中多个敌人，但每个敌人最多发出一次命中信号。关闭并重新开启下一段窗口后，可以再次命中同一目标。

## 命中结果

- `hit_direction` 使用窗口开启时锁定的水平前方方向。
- `hit_position` 当前使用目标身体中心附近的稳定估算点。
- `combo_index` 使用窗口开启时的攻击段数。
- 组件和控制器都不调用 `apply_damage()`。

## 调试显示

`MeleeHitbox/DebugHitbox` 使用半透明 `BoxMesh` 显示与实际查询完全相同的尺寸和世界变换：

- `debug_hitbox_enabled` 控制总开关，默认开启。
- 只在有效攻击窗口内显示。
- 尚未命中时为半透明黄色。
- 当前窗口至少命中一个目标后变为半透明红色。
- 关闭窗口后立即隐藏。

调试盒以角色底面原点、锁定朝向和 `WeaponData` 偏移计算，不跟随临时剑模型轨迹。

## Iron Sword 默认数据

```text
第一击：size (1.2, 0.8, 1.0)，offset (0.0, 0.4, 0.65)
第二击：size (1.3, 0.8, 1.1)，offset (0.0, 0.4, 0.70)
第三击：size (1.5, 0.9, 1.2)，offset (0.0, 0.45, 0.80)
```

每段攻击动画各放置一对 `open_attack_hit_window()` 与 `close_attack_hit_window()` 方法关键帧。具体时刻依据当前视觉挥砍阶段设置，不由代码硬编码。

## 故障安全

- 重复打开窗口时先结束旧窗口，再尝试建立新窗口。
- 关闭未开启的窗口安全无操作。
- 武器数据缺项、尺寸非正数或方向无效时返回 `false`，不启动检测。
- 动画结束但遗漏关闭 marker 时，控制器仍会关闭窗口。
- 取消连击、冲刺、卸装、换装和节点退出都会清理检测状态及单窗口去重记录。
- 配置错误不会阻止攻击动画、移动或装备系统继续运行。

## 测试范围

- 窗口外不产生命中。
- 三段攻击分别读取正确的尺寸和偏移。
- 窗口打开时可以检测已经位于盒体内的敌人。
- 友军、中立、不可选中、死亡对象和错误物理层对象被忽略。
- 同一窗口对同一目标只发送一次，对多个敌人分别发送一次。
- 新窗口可以再次命中同一目标。
- 开窗后角色转向不会改变本窗口的检测方向。
- 动画方法标记可以实际打开与关闭检测。
- 动画结束、取消、冲刺、卸装和换装不会遗留检测状态。
- 调试盒的显隐、尺寸、位置和颜色与查询状态一致。
- Godot 4.7 UnitSystem 回归测试、编辑器扫描和无窗口运行扫描无新增错误或警告。

## 本阶段不实施

- 伤害数值与生命值扣除。
- 卡刀、镜头震动、音效、粒子与受击动画。
- 击退、硬直和无敌帧。
- 剑刃轨迹级 ShapeCast 或骨骼挂点碰撞。
- 修改或自动添加 `TestScene.tscn` 中的单位实例。
