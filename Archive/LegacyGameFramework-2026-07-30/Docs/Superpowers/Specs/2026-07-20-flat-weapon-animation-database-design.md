# 扁平武器动画匹配系统设计

## 目标

撤回武器场景持有角色动画的架构。角色攻击动画保存为独立 `AnimationLibrary.tres`，
由单位 Race 与武器 WeaponType 两个字段在中央数据库中自动匹配。

第一版只实现：

```text
PLAYER_BASE + SWORD → PlayerSwordAnimationLibrary.tres
```

## 数据结构

### UnitProfile

`UnitProfile` 是单位未来基础资料的统一入口。当前只增加 Race：

```gdscript
enum Race {
    PLAYER_BASE,
}

@export var race: Race = Race.PLAYER_BASE
```

`UnitBase` 提供 `unit_profile: UnitProfile`，`PlayerBase.tscn` 使用
`PlayerBaseProfile.tres`。

### WeaponDefinition

武器 Definition 保留现有资料，并增加 WeaponType：

```gdscript
enum WeaponType {
    SWORD,
}

@export var weapon_type: WeaponType = WeaponType.SWORD
```

`IronSwordDefinition.tres` 使用 `SWORD`。

### WeaponAnimationEntry

数据库行是内嵌 Resource：

```gdscript
@export var race: UnitProfile.Race
@export var weapon_type: WeaponDefinition.WeaponType
@export var animation_library: AnimationLibrary
```

### WeaponAnimationDatabase

`WeaponAnimationDatabase.tres` 保存 `Array[WeaponAnimationEntry]`，并提供：

```gdscript
func resolve(
    race: UnitProfile.Race,
    weapon_type: WeaponDefinition.WeaponType
) -> AnimationLibrary
```

同一组合只能存在一行。空 Library、重复组合或无法匹配都会产生明确配置错误。
解析只在装备/换装时发生，不进入逐帧逻辑；保持线性表能获得最简单、最可靠的
Inspector 工作流。

## 场景与动画职责

### IronSword

`IronSword.tscn` 不再继承 `SwordBase.tscn`，结构简化为：

```text
IronSword (WeaponBase)
├── VisualRoot
│   └── IronSwordVisual
└── SkillSocket
```

`WeaponBase.gd` 只管理 Definition、VisualRoot 和 SkillSocket，不再持有或查询动画。

### PlayerSwordAnimationLibrary

独立资源保存：

```text
RESET
basic_attack_1
basic_attack_2
basic_attack_3
```

动画轨道直接指向 `CharacterActionRig` 下的真实节点：

```text
BodyRoot:position
BodyRoot:rotation
WeaponSocket:position
WeaponSocket:rotation
```

不再进行源轨道到角色轨道的重映射。

### CharacterAnimationController

控制器直接接收解析后的 `AnimationLibrary`，验证真实节点路径后以
`weapon_actions` 名称加载。控制器负责返回连续的
`basic_attack_1...N`；武器场景不再参与连击发现。

### WeaponEquipmentComponent

装备时：

1. 从持有者 `UnitProfile` 读取 Race。
2. 从 `WeaponDefinition` 读取 WeaponType。
3. 调用数据库解析 AnimationLibrary。
4. 在移除旧武器前验证场景、Library、连击和轨道。
5. 验证全部通过后才原子替换武器和动画库。

手动放置在 WeaponSocket 下的武器使用 `starting_weapon` 作为 Definition；
缺少 Definition 时只保留明确配置错误，不猜测武器类型。

### PlayerAttackController

保留动态连击、输入缓存、连击重置和按住循环。连击名称改为从
`CharacterAnimationController` 读取，不再从 `WeaponBase` 读取。

## Workbench

`SwordAnimationWorkbench.tscn` 直接实例化真实 `PlayerBase.tscn`，并在真实
WeaponSocket 下放置 IronSword，用同一份外部 AnimationLibrary 编辑动作。
Workbench 不被正式场景引用，也不修改 TestScene。

## 删除内容

- 删除 `SwordBase.tscn`。
- 删除 `RefCharacter` 与其循环引用。
- 删除武器内 AnimationPlayer、base/override Library 和轨道重映射算法。
- 删除 Definitionless 手动武器的攻击动画猜测。

## 扩展成本

新增 Race：

1. 为 Race 枚举增加一项。
2. 创建 UnitProfile。
3. 为需要支持的 WeaponType 创建 AnimationLibrary。
4. 向数据库增加对应行。

新增 WeaponType：

1. 为 WeaponType 枚举增加一项。
2. 创建武器视觉与 Definition。
3. 为支持它的 Race 创建 AnimationLibrary。
4. 向数据库增加对应行。

解析器、装备组件、动画控制器和攻击控制器均不需要修改。

