# 面向人工制作的继承式武器动画系统设计

## 目标

将当前以 `WeaponActionSet.tres`、`AttackActionDefinition` 和独立
`AnimationLibrary.tres` 为中心的武器动画方案，重构为可以直接在 Godot 编辑器中
打开、观察、编辑、继承和测试的武器场景工作流。

本次最小实现以单手剑为示例，并满足：

- 一种武器类型拥有一个基础场景，保存该类型的全部默认动画。
- 具体武器通过 Godot 继承场景创建。
- 派生武器按动画名称覆盖父类动作，未覆盖动作继续继承。
- `basic_attack_1`、`basic_attack_2`、`basic_attack_3` 等名称自动组成连击。
- 动画制作场景内存在真实可见的参考角色，动画人员直接对照参考制作。
- 参考角色只提供制作依据，不实现自动骨架匹配、重定向或模型管理。
- `.tres` 继续用于背包、商店、存档和装备数据。
- `.tscn` 用于编辑器手动装配及装备后的运行时实例。
- 鼠标左键继续通过现有 `player_attack` InputMap 发动攻击。

本次不修改 `Scenes/TestScene.tscn`，也不迁移 AI 武器、AI 攻击模块或
SkillSystem。

## 删除的旧抽象

以下内容属于旧的过度数据化动作注册方案，将在迁移完成并通过测试后删除：

```text
WeaponCombatSystem/02-Core/AttackActionDefinition.gd
WeaponCombatSystem/02-Core/WeaponActionSet.gd
WeaponCombatSystem/01-ActionSets/
```

`WeaponDefinition` 保留，但删除 `action_set` 依赖，改为引用最终具体武器场景。

`CharacterAnimationController`、`WeaponEquipmentComponent` 和
`PlayerAttackController` 保留职责边界，但改为读取武器场景提供的动画，而不是读取
ActionSet Resource。

## 数据与场景分层

### WeaponDefinition.tres

`WeaponDefinition` 是背包和装备系统持有的轻量数据：

```gdscript
weapon_id: StringName
display_name: String
icon: Texture2D
description: String
weapon_scene: PackedScene
```

后续可以增加价格、稀有度和战斗数值。本次不扩展这些尚未使用的数据。

背包保存 `WeaponDefinition`，不会保存运行中的武器节点。装备时通过
`weapon_scene.instantiate()` 创建具体武器；卸下时删除实例，Definition 仍留在背包。

### 具体武器场景

具体武器 `.tscn` 保存：

- 武器视觉。
- 从武器类型基类继承的默认动画。
- 该武器自己的动画覆盖。
- 技能插槽。
- 编辑器动画参考场景。
- 供装备组件读取的运行时接口。

Definition 单向引用具体武器场景。具体武器场景不反向引用 Definition，避免资源循环
依赖。运行时装备组件负责将当前 Definition 注入武器实例。

## 目录结构

```text
WeaponCombatSystem/
├── 00-Weapons/
│   └── IronSword/
│       ├── IronSwordDefinition.tres
│       ├── IronSwordVisual.tscn
│       └── IronSword.tscn
├── 01-WeaponTypes/
│   └── IronSword/
│       └── SwordBase.tscn
├── 02-Core/
│   ├── WeaponBase.gd
│   └── WeaponDefinition.gd
├── 03-Components/
│   ├── CharacterAnimationController.gd
│   ├── WeaponEquipmentComponent.gd
│   └── PlayerAttackController.gd
└── 04-Tests/
```

`01-ActionSets` 被 `01-WeaponTypes` 取代。文件夹中不再保存不可直接预览的动作
Resource，而是保存可直接打开的武器类型基础场景。

## SwordBase 场景

```text
SwordBase (WeaponBase)
├── RuntimeWeapon
│   ├── VisualSlot
│   └── SkillSocket
├── AnimationData
│   ├── BaseAnimations
│   └── OverrideAnimations
└── AnimationPreview
    ├── ReferenceCharacterSlot
    │   └── CSGBoxReferenceCharacter
    │       ├── BodyRoot
    │       │   └── BodyMesh
    │       └── WeaponSocket
    ├── PreviewController
    ├── PreviewGround
    └── PreviewMarkers
```

### RuntimeWeapon

`VisualSlot` 保存具体武器视觉实例。派生武器可以在继承场景中替换或配置这里的模型。

`SkillSocket` 是未来技能场景的开放插槽。本次只建立节点，不接入技能执行逻辑。

### BaseAnimations

`BaseAnimations` 是基础场景中直接可见的 `AnimationPlayer`，默认包含：

```text
RESET
basic_attack_1
basic_attack_2
basic_attack_3
```

动画人员打开 `SwordBase.tscn`，选择该节点后直接使用 Godot Animation 面板
编辑。动画不需要动作定义 Resource 或动画名称映射。

### OverrideAnimations

`OverrideAnimations` 是派生武器使用的第二个 `AnimationPlayer`。基础场景中保持为空。

派生武器需要修改某段动作时，在这里建立同名动画：

```text
basic_attack_3
```

运行时按名称合并：

1. 读取 `BaseAnimations`。
2. 读取 `OverrideAnimations`。
3. 同名动画使用 Override。
4. 不同名动画作为新增动作。

因此覆盖 `basic_attack_3` 不会复制或切断 `basic_attack_1` 和
`basic_attack_2` 对父类的继承。

### 连击发现规则

普通攻击通过命名约定自动发现：

```text
basic_attack_1
basic_attack_2
basic_attack_3
...
```

系统只接受正整数后缀，按数字升序排列。序号中断时在第一个缺口停止。例如只有
`basic_attack_1` 和 `basic_attack_3` 时，当前有效连击只有第一段，并输出配置警告。

本次最小运行示例使用三段攻击。攻击过程中再次按下左键只缓存下一段；当前动画自然
结束后播放下一段。没有继续输入时，在短暂续接时间后恢复第一段。本次不加入攻击前移、
Hitbox、伤害和命中反馈。

## 手动参考角色

`AnimationPreview/ReferenceCharacterSlot` 保存一个人工放置的参考角色。本次使用当前
CSGBox 角色尺寸与 `BodyRoot/WeaponSocket` 结构。

参考角色的职责只有：

- 为动画人员提供身体比例。
- 显示武器握持位置。
- 作为 AnimationPlayer 的轨道目标。
- 在编辑器内播放单段动作及整套连击。

系统不负责：

- 自动识别 Skeleton3D。
- 自动匹配骨骼。
- 自动重定向动画。
- 自动适配不同角色体型。
- 自动修复无效轨道。
- 自动维护未来角色视觉模型。

基础场景保留：

```gdscript
reference_character_path: NodePath
animation_target_root_path: NodePath
animation_profile: StringName
```

`animation_profile` 只提供兼容性提示，不执行自动转换。动画和角色不匹配时由动画师或
设计师调整。

## 编辑器与运行时显示

当武器场景自身作为当前编辑场景打开时，`AnimationPreview` 可见，且
`VisualSlot` 中武器的预览副本显示在参考角色的 WeaponSocket 下。

当具体武器作为其他场景中的实例或进入游戏运行时：

- `AnimationPreview` 隐藏并停止处理。
- 不生成预览武器副本。
- 只有 `RuntimeWeapon`、动画数据和技能插槽参与装备流程。

本次使用最小 `@tool` 预览脚本完成显示切换和预览武器同步，不开发自定义 Godot
编辑器插件，不实现自动角色配置。

## 装备入口

### Inspector 数据装配

将 `IronSwordDefinition.tres` 拖入：

```text
PlayerCombatSystem/WeaponEquipmentComponent/Starting Weapon
```

运行时装备组件读取 `weapon_scene` 并实例化。

### 场景手动装配

也可以将 `IronSword.tscn` 直接拖到 PlayerBase 的 WeaponSocket。装备组件进入运行
时后检测现有 `WeaponBase` 实例并注册，不再重复实例化。

两种方式共用同一个注册流程：

```text
解析武器实例
→ 注入 Definition（若存在）
→ 收集基础动画
→ 应用同名覆盖
→ 发现 basic_attack 连击
→ 注册技能插槽
→ 武器可用
```

编辑器手动实例没有 Definition 时仍可进行视觉和动画测试；依赖背包数据的战斗属性在
Definition 注入前保持不可用。

## PlayerBase 集成

PlayerBase 继续拥有角色级动画播放器。武器场景中的 Base/Override AnimationPlayer
是制作和动画数据来源；装备后由 `CharacterAnimationController` 将有效动画装入角色
自己的 AnimationPlayer。

武器动画只允许控制角色动画目标根下的轨道。本次参考结构为：

```text
BodyRoot
WeaponSocket
```

PlayerBase 的移动、冲刺、重力、锁敌和 Visual 世界朝向不由武器动画控制。

删除 `PlayerCombatSystem` 后，PlayerBase 原有行为必须继续工作。

## 公共接口

### WeaponBase

```gdscript
func get_base_animation_library() -> AnimationLibrary
func get_override_animation_library() -> AnimationLibrary
func get_effective_animation(animation_name: StringName) -> Animation
func get_basic_attack_animation_names() -> Array[StringName]
func get_runtime_visual_root() -> Node3D
func get_skill_socket() -> Node
func configure_definition(definition: WeaponDefinition) -> void
```

### WeaponEquipmentComponent

```gdscript
func equip_definition(definition: WeaponDefinition) -> bool
func register_weapon_instance(weapon: WeaponBase) -> bool
func unequip_weapon() -> void
func get_equipped_definition() -> WeaponDefinition
func get_equipped_weapon() -> WeaponBase
```

### CharacterAnimationController

```gdscript
func load_weapon_animations(weapon: WeaponBase) -> bool
func clear_weapon_animations() -> void
func play_weapon_animation(animation_name: StringName) -> bool
```

### PlayerAttackController

```gdscript
func request_basic_attack() -> bool
func cancel_attack() -> void
func is_attacking() -> bool
func get_combo_index() -> int
```

## 配置错误处理

- Definition 缺少 `weapon_scene`：装备失败，保留原武器。
- 手动实例不是 `WeaponBase`：忽略并输出明确警告。
- 缺少 BaseAnimations：武器视觉仍可装备，但不能攻击。
- 缺少 `basic_attack_1`：普通攻击请求返回 `false`。
- 连击序号中断：只使用连续有效部分并输出警告。
- Override 同名动画：正常覆盖，不产生警告。
- 动画轨道找不到角色节点：拒绝播放该动画并输出轨道路径，不修改移动状态。
- 参考角色缺失：运行时不受影响；编辑器显示配置警告。

## 最小实现验证

- 打开 `SwordBase.tscn` 可以直接看见参考角色、武器和动画列表。
- Animation 面板可以直接播放 `basic_attack_1/2/3`。
- `IronSword.tscn` 继承基础场景并替换视觉。
- 派生场景同名覆盖一段动画时，其他两段继续来自父类。
- Definition 可以作为轻量背包数据引用具体武器场景。
- Starting Weapon 可以运行时实例化武器。
- 手动放入 WeaponSocket 的武器实例可以被识别。
- 鼠标左键可以依次触发三段基础攻击。
- 移除武器后动画库与视觉正确清理。
- 移除 PlayerCombatSystem 后移动、冲刺、锁敌和重力继续工作。
- Godot 4.7 编辑器扫描、无窗口测试和 MCP 场景加载无新增错误。

## 暂缓内容

- 正式 Skeleton3D 和美术角色资产。
- 自动动画重定向和跨骨架适配。
- 自定义武器动画编辑器插件。
- AI 复用。
- 技能执行和 SkillSystem 集成。
- Hitbox、伤害、命中反馈和攻击前移。
- 背包 UI、装备 UI、掉落和存档实现。
- 武器数值、品质、价格和强化系统。
