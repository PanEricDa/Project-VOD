# PlayerBase 武器动作框架最小示例设计

## 目标

为新 `PlayerBase` 建立一套最小但可扩展的武器动作框架，并完成一个可运行示例：

- 一把临时 CSG 单手剑。
- 一段单手剑基础攻击动画。
- 鼠标左键通过现有 `player_attack` InputMap 触发。
- 单手剑作为 PlayerBase 的默认装备。
- 动画同时驱动玩家 CSGBox 身体与 `WeaponSocket`，证明完整身体动作与武器视觉可以解耦。

本阶段不迁移旧 `MeleeAttackModule`，不加入连击、Hitbox、伤害、卡刀、震动、技能公共冷却、AI 决策、背包或换装 UI。

## 核心原则

动画文件不挂载在武器视觉场景，也不永久内嵌所有角色场景。

动画属于“武器动作类型与角色骨架接口的组合”：

```text
iron_sword + csg_box
→ CSGBoxSwordActionSet
```

角色持有动画播放器，装备的武器定义提供动作集。运行时由角色动画控制器把动作集中的 `AnimationLibrary` 装载到自身 `AnimationPlayer`，动画轨道控制角色稳定动作接口：

```text
CharacterActionRig/BodyRoot
CharacterActionRig/WeaponSocket
```

武器视觉实例只是 `WeaponSocket` 的子节点，会自然继承插槽动画。

## 独立目录

新框架放在独立目录，避免与旧 Hero、旧 AI AttackModule 和 SkillSystem 混合：

```text
WeaponCombatSystem/
├── 00-Weapons/
│   └── IronSword/
│       ├── IronSwordVisual.tscn
│       └── IronSwordDefinition.tres
├── 01-ActionSets/
│   └── IronSword/
│       └── CSGBox/
│           ├── SwordAnimations.tres
│           └── SwordActionSet.tres
├── 02-Core/
│   ├── WeaponDefinition.gd
│   ├── WeaponActionSet.gd
│   └── AttackActionDefinition.gd
├── 03-Components/
│   ├── WeaponEquipmentComponent.gd
│   ├── CharacterAnimationController.gd
│   └── PlayerAttackController.gd
├── 04-Tests/
└── 05-Docs/
```

具体武器场景与资源放在 `00-Weapons` 和 `01-ActionSets`。通用脚本不放入具体武器文件夹。

## PlayerBase 节点调整

将现有 `Visual/BodyMesh` 移入稳定动作层级：

```text
PlayerBase
├── Visual
│   └── CharacterActionRig
│       ├── BodyRoot
│       │   └── BodyMesh
│       ├── WeaponSocket
│       │   └── EquippedWeapon
│       └── CharacterAnimationController
│           └── CharacterAnimationPlayer
├── PlayerCombatSystem
│   ├── WeaponEquipmentComponent
│   └── PlayerAttackController
├── TargetingSystem
└── CollisionShape3D
```

`Visual` 继续由 `PlayerBase.gd` 负责锁定、冲刺和移动朝向。攻击动画只修改 `CharacterActionRig` 内部节点，因此不会覆盖 PlayerBase 的世界朝向。

当前 `BodyRoot` 中使用 CSGBox。未来替换美术角色时，`BodyRoot` 可以容纳 Skeleton3D；武器装备和玩家攻击控制器不需要改变。

## 数据资源

### WeaponDefinition

```gdscript
class_name WeaponDefinition
extends Resource

@export var weapon_id: StringName
@export var display_name: String
@export var visual_scene: PackedScene
@export var action_set: WeaponActionSet
@export var socket_position: Vector3
@export var socket_rotation_degrees: Vector3
```

它只描述武器是什么、显示什么以及使用哪套动作，不读取输入、不播放动画。

### WeaponActionSet

```gdscript
class_name WeaponActionSet
extends Resource

@export var action_set_id: StringName
@export var rig_profile: StringName = &"csg_box"
@export var animation_library: AnimationLibrary
@export var attack_actions: Array[AttackActionDefinition]
```

`rig_profile` 用于阻止未来将不兼容骨架的动作库装到角色上。

### AttackActionDefinition

```gdscript
class_name AttackActionDefinition
extends Resource

@export var action_id: StringName = &"basic_attack"
@export var animation_name: StringName
@export_range(0.01, 5.0, 0.01, "or_greater")
var playback_speed: float = 1.0
```

本示例只有一个动作。未来在此资源中增加连击窗口、输入缓存、移动曲线和 Hitbox Profile，而不把这些规则写入动画方法轨道。

## 组件职责

### WeaponEquipmentComponent

职责：

- 持有当前 `WeaponDefinition`。
- 在 `WeaponSocket` 下实例化或移除武器视觉。
- 通知动画控制器装载当前动作集。
- 对外发送 `weapon_changed`。

公共接口：

```gdscript
signal weapon_changed(weapon: WeaponDefinition)

func configure(
    owner_unit: UnitBase,
    weapon_socket: Node3D,
    animation_controller: CharacterAnimationController
) -> bool
func equip_weapon(weapon: WeaponDefinition) -> bool
func unequip_weapon() -> void
func get_equipped_weapon() -> WeaponDefinition
func get_current_action_set() -> WeaponActionSet
```

默认装备通过 PlayerBase 场景中该组件的 `starting_weapon` Inspector 属性配置。

### CharacterAnimationController

职责：

- 独占角色的 `CharacterAnimationPlayer`。
- 验证角色 `rig_profile` 与动作集一致。
- 动态添加和移除武器 `AnimationLibrary`。
- 播放、停止和查询角色动作。

公共接口：

```gdscript
signal action_started(action_id: StringName)
signal action_finished(action_id: StringName)

func load_action_set(action_set: WeaponActionSet) -> bool
func clear_action_set() -> void
func play_action(action: AttackActionDefinition) -> bool
func stop_action() -> void
func is_action_playing() -> bool
```

动作库使用固定库名 `weapon_actions`。换武器前移除旧库，避免动画名称冲突。

### PlayerAttackController

职责：

- 独立读取 `player_attack` InputMap。
- 从装备组件获取当前动作集。
- 请求动画控制器播放 `basic_attack`。
- 在动作播放期间拒绝重复请求。

公共接口：

```gdscript
signal attack_started(action_id: StringName)
signal attack_finished(action_id: StringName)

func configure(
    equipment: WeaponEquipmentComponent,
    animation_controller: CharacterAnimationController
) -> bool
func request_basic_attack() -> bool
func cancel_attack() -> void
func is_attacking() -> bool
```

该组件不依赖 `PlayerBase.gd`、TargetingSystem、AI、SkillSystem 或 GCD。

## 示例动画

`SwordAnimations.tres` 保存一个 `AnimationLibrary`：

```text
basic_attack
```

总长约 `0.45s`：

1. `0.00–0.10s`：BodyRoot 轻微后收，WeaponSocket 向右后方蓄力。
2. `0.10–0.27s`：BodyRoot 向前扭转，WeaponSocket 从右后方向左前方快速挥砍。
3. `0.27–0.45s`：身体和插槽平滑恢复初始姿态。

动画只控制：

```text
BodyRoot:position
BodyRoot:rotation
WeaponSocket:position
WeaponSocket:rotation
```

不控制 PlayerBase 根节点、Visual 世界朝向、碰撞体、速度、摄像机或 TargetingSystem。

## 单手剑视觉

`IronSwordVisual.tscn` 使用简单 CSG 节点组成剑身与剑柄。场景根节点为 `Node3D`，不包含 AnimationPlayer、输入脚本或攻击算法。

持握偏移由 `IronSwordDefinition.tres` 的 socket 参数决定，使同一个视觉场景可以在 Inspector 中调节，而无需改动画轨道。

## 运行流程

```text
PlayerBase 进入场景
→ WeaponEquipmentComponent 配置起始单手剑
→ 在 WeaponSocket 下生成 IronSwordVisual
→ CharacterAnimationController 加载 CSGBox 单手剑动作库
→ 玩家按下 player_attack
→ PlayerAttackController 请求 basic_attack
→ CharacterAnimationPlayer 驱动 BodyRoot 与 WeaponSocket
→ 动画结束
→ PlayerAttackController 回到可攻击状态
```

玩家移动、冲刺、锁定朝向和重力在攻击期间继续运行，与旧 Hero 当前行为保持一致。

## AI 复用边界

本阶段不修改任何 AI 场景或脚本。

未来 AI 可以读取同一个 `WeaponDefinition`、`WeaponActionSet` 和 `AnimationLibrary`，但由 AI 自己的攻击执行器决定何时播放。AI 不实例化 `PlayerAttackController`，玩家也不依赖 AI AttackModule 或 SkillSystem。

## 容错

- 没有装备武器时，攻击请求返回 `false`。
- 动作集为空、骨架不兼容、动画库缺失或动画名称不存在时返回 `false`，不破坏移动。
- 换武器或卸下武器时停止当前动作并恢复 BodyRoot、WeaponSocket 默认姿态。
- 删除 `PlayerCombatSystem` 后，PlayerBase 的移动、冲刺、锁定和重力仍然可用。
- 重复装备同一资源不会重复生成视觉实例或重复添加动画库。

## 测试范围

- 三个 Resource 类型的默认值、强类型导出和查询接口。
- 单手剑视觉场景不包含动画与攻击脚本。
- 装备后只生成一个武器视觉实例。
- 动作库正确加载到角色 AnimationPlayer。
- `player_attack` 和公开请求都能启动唯一攻击动作。
- 动作播放期间拒绝重复请求，结束后恢复可用。
- BodyRoot 与 WeaponSocket 在动画中发生变化并最终复位。
- PlayerBase 移动、冲刺和锁定朝向不受攻击控制器影响。
- 卸下武器或删除 PlayerCombatSystem 后基础 PlayerBase 仍可运行。
- Godot 4.7 脚本扫描、headless 测试与 MCP 错误面板无新增错误。

## 暂缓内容

- 连击、输入缓存和取消窗口。
- Hitbox、伤害、命中反馈和攻击前移。
- AnimationTree 状态机与正式 Skeleton3D。
- AI 装配。
- 玩家技能、动作优先级和技能打断。
- 运行时换装界面、背包和存档。
- 删除旧 Hero 与旧 MeleeAttackModule。
