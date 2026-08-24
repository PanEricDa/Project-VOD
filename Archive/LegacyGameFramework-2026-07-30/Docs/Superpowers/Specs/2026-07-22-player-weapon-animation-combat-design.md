# Player 武器动画攻击系统设计

## 1. 目标

在当前 `UnitBase -> PlayerBase -> Hero` 与独立 `HeroVisual.tscn` 架构上，增加一套轻量、数据驱动且可以更换武器的玩家攻击系统。

第一版只实现 IronSword 三段连击的视觉动作与流程信号，不实现 Hitbox、伤害、攻击位移、受击反馈或战斗冷却。旧 Hero 战斗系统保持不变，`Scenes/TestScene.tscn` 不作任何修改。

## 2. 核心原则

- 玩家攻击输入与连击规则只有一套，由 `PlayerAttackController.gd` 统一管理。
- 武器不保存算法，只通过一个扁平的 `WeaponData` 提供武器视觉和角色攻击动画库。
- 攻击动画属于角色视觉骨架的动作数据，不嵌在武器场景节点中。
- `PlayerBase.tscn` 直接包含普通 `AttackController` 节点，不额外创建控制器场景或包装插槽。
- `Hero.tscn` 只指定初始武器；更换武器时替换同一个 `WeaponData`。
- 当前项目始终只操控一个 Hero，因此使用稳定节点约定，避免为单一角色额外增加视觉接口脚本。

## 3. 节点结构

### 3.1 PlayerBase

```text
PlayerBase
├── ...现有玩家节点
├── Visual
│   └── <由继承场景提供的视觉实例>
└── AttackController
```

`AttackController` 是普通 `Node`，直接挂载 `PlayerAttackController.gd`。它读取 InputMap、管理装备、连击状态和动画调度，不负责移动、碰撞或伤害。

### 3.2 HeroVisual

```text
HeroVisual
├── CharacterRoot
│   └── BodyMesh
├── WeaponSocket
└── CharacterAnimationPlayer
```

`HeroVisual.tscn` 保持无脚本。`CharacterAnimationPlayer` 是角色的通用动画播放器，未来可以同时承担 `idle / walk / run` 等动画，并非攻击专用播放器。

攻击动画仅允许控制 `HeroVisual` 内的 `CharacterRoot` 和 `WeaponSocket`，不得修改 `PlayerBase` 根节点、碰撞体、移动速度或摄像机。

## 4. WeaponData

`WeaponData.gd` 是唯一新增的武器数据类型：

```gdscript
class_name WeaponData
extends Resource

@export var display_name: String
@export var visual_scene: PackedScene
@export var animation_library: AnimationLibrary
```

- `visual_scene`：实例化到 `HeroVisual/WeaponSocket` 下的纯视觉场景。
- `animation_library`：针对当前角色视觉结构制作的攻击动画库。
- 不在 WeaponData 中重复保存动画名称、连击数量或连击控制参数。

第一版 IronSword 由以下三个文件组成：

```text
IronSwordData.tres
IronSwordVisual.tscn
IronSwordAnimations.tres
```

## 5. 动画命名与发现

武器动画库在 `CharacterAnimationPlayer` 中统一注册为 `weapon`：

```text
weapon/RESET
weapon/basic_attack_1
weapon/basic_attack_2
weapon/basic_attack_3
```

控制器从 `basic_attack_1` 开始自动发现连续编号的动画，因此不维护额外动画名称数组。

有效武器至少必须包含：

- `RESET`
- `basic_attack_1`

连续编号中不允许出现断档。例如存在 `basic_attack_1` 和 `basic_attack_3`、但缺少 `basic_attack_2` 时，整件武器配置无效并拒绝装备。

## 6. 连击行为

攻击使用现有 InputMap 动作 `player_attack`，绑定鼠标左键。

默认参数由 `PlayerAttackController.gd` 导出到 Inspector：

```text
input_buffer_duration = 0.15s
combo_reset_duration = 0.7s
hold_to_auto_chain = true
hold_combo_restart_delay = 0.3s
```

行为规则：

1. 空闲时按下左键，从 `basic_attack_1` 开始。
2. 攻击期间的有效提前输入会被缓存，当前段结束后播放下一段。
3. 连击等待超过 `0.7s` 后重置，下一次输入从第一段开始。
4. 持续按住左键时自动衔接当前轮剩余段数。
5. 最后一段结束后，如果左键仍按住，则等待 `0.3s`，随后自动开始下一轮第一段，无需松开按键。
6. 每段结束时恢复 `weapon/RESET`。未来接入 locomotion 动画后，再由角色动画状态决定应恢复的基础动画。
7. 攻击动画不锁定移动，不改变角色速度，不产生攻击位移。

## 7. 控制器接口

```gdscript
func equip_weapon(weapon_data: WeaponData) -> bool
func unequip_weapon() -> void
func request_attack() -> void
func cancel_combo() -> void
func is_attacking() -> bool
func get_combo_index() -> int
```

信号保持最小集合：

```gdscript
signal weapon_equipped(weapon_data: WeaponData)
signal weapon_unequipped()
signal attack_started(combo_index: int)
signal attack_finished(combo_index: int)
signal combo_finished()
```

当前不预留命中窗口、伤害或位移信号；相关系统在真正实施攻击判定时再扩展。

## 8. 装备与换装流程

装备采用原子式流程：

1. 验证 `WeaponData`、视觉场景和动画库。
2. 验证 `RESET`、`basic_attack_1` 及连续动画编号。
3. 验证全部通过后，取消当前连击。
4. 移除旧武器视觉和旧 `weapon` 动画库。
5. 将新视觉实例化到 `WeaponSocket`。
6. 将新动画库注册到 `CharacterAnimationPlayer`。
7. 播放 `weapon/RESET` 并发送装备信号。

若新武器验证失败，保留当前武器和动画库，不产生半装备状态。`PlayerBase` 未装备武器时，攻击输入安全无响应且不报运行时错误。

## 9. 动画制作工作台

创建唯一的 `HeroAnimationWorkbench.tscn`，使用与实际 Hero 相同的 `HeroVisual` 实例作为参考，用于在编辑器中制作和预览 `IronSwordAnimations.tres`。

工作台只服务编辑器制作，不参与游戏运行，也不建立多套 Preview 场景或额外运行时依赖。未来角色视觉资产发生变化时，用更新后的同一视觉场景维护相应动画库。

## 10. 文件结构

```text
UnitSystem/
├── PlayerBase.tscn
├── PlayerBase.gd
├── Combat/
│   ├── PlayerAttackController.gd
│   └── WeaponData.gd
└── Players/
    └── Hero/
        ├── Hero.tscn
        ├── HeroVisual.tscn
        ├── HeroAnimationWorkbench.tscn
        └── Weapons/
            └── IronSword/
                ├── IronSwordData.tres
                ├── IronSwordVisual.tscn
                └── IronSwordAnimations.tres
```

## 11. 测试与验收

- 单击只播放第一段并在超时后重置。
- 连续输入按顺序播放三段，不出现第四段。
- 验证 `0.15s` 输入缓存与 `0.7s` 连击重置。
- 按住左键可以自动完成三段，并在 `0.3s` 后自动开始下一轮。
- 松开左键后不会自动开始新一轮。
- 攻击中换装会安全取消当前连击。
- 无武器时输入不会报错。
- 缺少资源、缺少 `RESET`、缺少第一段或动画编号断档时拒绝装备并保留旧武器。
- 武器视觉只出现在 `WeaponSocket` 下；卸下后视觉与 `weapon` 动画库均被移除。
- 攻击期间现有移动与转向逻辑不被控制器修改。
- 通过 Godot 4.7 脚本编译与 UnitSystem 相关测试。
- 不修改旧 Hero 战斗实现，不修改或添加 `Scenes/TestScene.tscn` 中的单位实例。

## 12. 暂缓范围

以下内容明确不属于第一版：

- Hitbox、命中检测与伤害
- 攻击前移、旋转或 Root Motion
- 命中暂停、震动、音效和粒子反馈
- AI 普通攻击与技能系统接入
- 多角色种族动画映射
- locomotion 与攻击动画混合

这些功能后续通过控制器信号和角色通用动画播放器逐步接入，不提前增加空接口或配置层。
