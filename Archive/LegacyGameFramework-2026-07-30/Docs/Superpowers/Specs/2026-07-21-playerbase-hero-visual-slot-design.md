# PlayerBase 与 Hero 独立视觉插槽设计

## 目标

基于现有 `UnitBase` 重新整理玩家单位的第一层结构。当前阶段只拆分角色视觉表现，
不同时重构移动、锁敌、战斗、动画、摄像机或技能系统。

设计必须满足：

- PlayerBase 是完整可操控的通用玩家父场景。
- 具体角色视觉使用独立 PackedScene，由继承场景在编辑器中手动实例化。
- PlayerBase 不知道具体模型类型，也不负责自动加载视觉。
- 参数直接由 GDScript 导出并由具体场景覆盖，不使用 Profile Resource。
- 保持节点少、配置入口明确，并为未来替换正式角色资产保留稳定边界。

## 核心选择

采用编辑器场景继承与手动实例化：

```text
PlayerBase.tscn
    ↓ inherit
Hero.tscn
    ↓ instance under Visual
HeroVisual.tscn
```

不在 UnitBase 或 PlayerBase 中增加 `visual_scene: PackedScene`，也不增加自动实例化、
热切换或 VisualSlot 管理脚本。项目始终只有一个玩家角色，目前不需要运行时更换整套
角色外观。

## UnitBase 边界

UnitBase 继续负责最小单位身份和运行状态：

- CharacterBody3D 物理根节点。
- 生命值与生命事件。
- 阵营、队伍和目标资格。
- `Visual` 稳定节点。
- `CollisionShape3D` 基础物理结构。

现有节点 `Visual` 保持原名，但语义上作为所有单位的视觉插槽。保留原名可以避免破坏
PlayerBase、AIUnitBase 和现有测试对该稳定路径的依赖。

UnitBase 不负责具体视觉场景的加载、验证或替换。

## PlayerBase 通用框架

```text
PlayerBase extends UnitBase
├── Visual
├── CollisionShape3D
└── TargetingSystem
```

PlayerBase 是完整可操控的父场景，并继续提供：

- InputMap 玩家移动输入。
- 水平移动与加速度。
- 冲刺次数、距离、速度和冷却。
- 重力。
- 根据移动或锁定目标更新朝向。
- 玩家目标锁定的稳定公开接口。

PlayerBase 的 `Visual` 必须保持为空。PlayerBase 不包含：

- CharacterActionRig。
- BodyRoot。
- BodyMesh。
- WeaponSocket。
- 具体角色材质。
- 动画、战斗、技能或装备节点。

PlayerBase 保留玩家共有场景数据：

```text
collision_layer = 2
faction_id = Player
team_id = 1
```

移动、冲刺、重力和转向参数继续由 `PlayerBase.gd` 使用 `@export` 定义。PlayerBase
不再引用 UnitProfile 或其他角色资料 Resource。

PlayerBase 不覆盖为 Hero 定制的方盒碰撞体，而是保留 UnitBase 的合法基础碰撞结构。

## Hero 继承场景

文件位置：

```text
UnitSystem/Players/Hero/
├── Hero.tscn
└── HeroVisual.tscn
```

Hero 的节点结构：

```text
Hero extends PlayerBase
├── Visual
│   └── HeroVisual
├── CollisionShape3D
└── TargetingSystem
```

Hero 负责：

- 在继承得到的 `Visual` 节点下实例化 `HeroVisual.tscn`。
- 覆盖适合当前角色的碰撞形状与局部位置。
- 在 Inspector 中覆盖 Hero 最终使用的生命、移动、冲刺和物理参数。
- 以后承载明确只属于 Hero 的节点。

Hero 不重复创建 TargetingSystem，也不增加用于连接 PlayerBase 的中介脚本。

## HeroVisual 场景契约

当前最小结构：

```text
HeroVisual (Node3D)
└── BodyMesh (CSGBox3D)
```

约定：

- 根节点必须是 Node3D。
- 根节点局部原点对应角色脚底中心。
- 正面使用 Godot 3D 的 `-Z` 方向。
- 当前 BodyMesh 尺寸保持为 `0.5m × 0.5m × 0.5m`。
- BodyMesh 局部 Y 位置为 `0.25m`，使脚底位于根节点原点。
- 沿用当前 PlayerBase 方盒角色的 Tiffany Blue 材质。
- 场景只包含视觉表现及未来与模型直接相关的骨骼、蒙皮和视觉动画节点。
- 不包含 CharacterBody3D、CollisionShape3D、输入、移动、生命、阵营、锁敌、战斗或技能逻辑。

当前不加入 WeaponSocket、EffectSocket、AnimationPlayer 或 CameraAnchor。它们不属于
本次 Visual 拆分范围，必须在对应系统的独立设计中确定归属。

## 数据与运行关系

参数采用直接导出和场景覆盖：

```text
UnitBase.gd / PlayerBase.gd 默认值
                 ↓
        Hero.tscn Inspector 覆盖
```

不创建 Profile、Definition 或嵌套 Resource。

运行时：

```text
PlayerBase.gd 读取 InputMap
        ↓
移动 PlayerBase 的 CharacterBody3D
        ↓
旋转固定的 Visual 节点
        ↓
HeroVisual 实例自然跟随
```

PlayerBase 不保存 HeroVisual 引用，也不读取 HeroVisual 内部节点。移除或替换
HeroVisual 不应影响移动、冲刺、重力和锁敌。

## 迁移范围

本次实施修改：

- 从 `UnitSystem/PlayerBase.tscn` 删除具体角色视觉、材质和 WeaponSocket。
- 新建 `UnitSystem/Players/Hero/Hero.tscn`。
- 新建 `UnitSystem/Players/Hero/HeroVisual.tscn`。
- 更新 PlayerBase 测试，使其验证空 Visual 插槽。
- 新增 Hero 视觉场景与继承装配测试。

本次实施不修改：

- PlayerBase.gd 的移动、冲刺、重力、朝向和锁敌行为。
- UnitBase.gd 的生命、阵营和关系判断。
- AIUnitBase、AllyBase2 和 EnemyBase2 的视觉结构。
- 旧 `Scenes/ObjectScenes/Hero.tscn` 及其战斗系统。
- `Scenes/TestScene.tscn` 中任何单位实例。
- 战斗、武器、技能、动画、摄像机和特效系统。

## 失败与降级行为

PlayerBase 的 Visual 为空是合法状态，不输出错误，也不停止移动或物理处理。

HeroVisual 是具体 Hero 场景的编辑器装配内容。若实例被手动删除，Hero 仍可运行但不可见；
本阶段不增加自动恢复、自动加载或运行时配置警告。

## 验证标准

- `PlayerBase.tscn` 的 Visual 没有子节点。
- PlayerBase 不引用模型、材质、CharacterActionRig、BodyRoot 或 WeaponSocket。
- `HeroVisual.tscn` 可以独立打开并预览当前方盒角色。
- HeroVisual 根节点位于脚底中心，角色正面为 `-Z`。
- HeroVisual 不包含玩法脚本或碰撞节点。
- `Hero.tscn` 继承 PlayerBase，并在 Visual 下实例化且只实例化一个 HeroVisual。
- Hero 使用自身方盒碰撞体，而 PlayerBase 保留 UnitBase 基础碰撞。
- 删除 HeroVisual 后，Hero 的移动、冲刺、重力和锁敌仍能运行。
- 全部 UnitSystem 自动化测试通过。
- Godot 4.7 完整导入无新增错误或警告。
- 旧 Hero 文件和 TestScene 不发生修改。
