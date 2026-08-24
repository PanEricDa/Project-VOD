# 角色动画与固定 NodePath 精简设计

## 目标

在不改变玩家攻击、武器换装、三段连击和动画轨道行为的前提下，完成两项结构精简：

1. 将 `CharacterAnimationController` 与其内部唯一的
   `CharacterAnimationPlayer` 合并为一个节点。
2. 删除只指向框架固定节点、没有实际装配价值的 Inspector NodePath。

本轮不修改 `TestScene.tscn`，不调整移动、锁敌、阵营、编队或 AI 系统。

## 最终节点结构

`PlayerBase` 的角色动作部分由：

```text
CharacterActionRig
├── BodyRoot
├── WeaponSocket
└── CharacterAnimationController
    └── CharacterAnimationPlayer
```

精简为：

```text
CharacterActionRig
├── BodyRoot
├── WeaponSocket
└── CharacterAnimationController（AnimationPlayer）
```

`CharacterAnimationController.gd` 改为继承 `AnimationPlayer`。节点自身保存运行时
武器动画库、播放动画并发送 `action_started` 与 `action_finished` 信号。

合并后的 `root_node` 设置为 `..`，继续以 `CharacterActionRig` 作为动画轨道解析根。
`BodyRoot` 和 `WeaponSocket` 的既有轨道路径不变。

## 删除的固定 NodePath

### CharacterAnimationController

删除：

```gdscript
animation_player_path
_animation_player
configure(animation_player)
```

控制器直接调用自身的 AnimationPlayer API，不再需要播放器注入。

### WeaponBase

删除 Inspector 导出：

```gdscript
runtime_visual_root_path
skill_socket_path
animations_player_path
```

节点仍保留，脚本使用固定内部路径：

```gdscript
const VISUAL_SLOT_PATH: NodePath = ^"VisualSlot"
const SKILL_SOCKET_PATH: NodePath = ^"SkillSocket"
const ANIMATIONS_PATH: NodePath = ^"Animations"
```

`get_runtime_visual_root()`、`get_skill_socket()` 和
`get_animations_player()` 的公共接口保持不变。

### PlayerAttackController

删除 Inspector 导出：

```gdscript
equipment_component_path
animation_controller_path
```

PlayerAttackController 继续位于 `PlayerCombatSystem` 下，并通过两个固定内部路径自动
装配：

```gdscript
const EQUIPMENT_COMPONENT_PATH: NodePath = ^"../WeaponEquipmentComponent"
const ANIMATION_CONTROLLER_PATH: NodePath = \
    ^"../../Visual/CharacterActionRig/CharacterAnimationController"
```

公开的 `configure(equipment_component, animation_controller)` 继续保留，供测试、运行时
生成对象和未来外部装配使用。

## 明确保留的路径

以下路径负责真正的跨场景装配，本轮不修改：

- `WeaponEquipmentComponent.owner_unit_path`
- `WeaponEquipmentComponent.weapon_socket_path`
- `WeaponEquipmentComponent.animation_controller_path`
- `FormationComponent.player_path`
- `FormationComponent.player_facing_node_path`

它们的目标可能因单位类型或外部场景层级而变化，不属于重复配置。

## 外部接口与兼容性

- `CharacterAnimationController` 的动画加载、播放、停止和状态查询方法名称保持不变。
- `WeaponEquipmentComponent` 仍接收 `CharacterAnimationController` 类型。
- `PlayerAttackController` 的输入、连击缓存和信号接口保持不变。
- `WeaponBase` 的三个节点 getter 保持不变。
- `PlayerBase` 中外部引用的 Controller 节点路径保持为
  `Visual/CharacterActionRig/CharacterAnimationController`。
- 仅删除不再需要的 `CharacterAnimationController.configure(AnimationPlayer)`。

## 验证范围

- 先增加失败测试，确认 Controller 必须是 AnimationPlayer 且不再包含播放器子节点。
- 确认三个被删除组件不再暴露对应固定 NodePath 属性。
- 验证武器基础动画与同名覆盖仍能复制到角色。
- 验证三段连击、输入缓存、取消攻击和动画结束信号。
- 验证 Inspector 起始武器和运行时换装。
- 验证卸下整个 `PlayerCombatSystem` 后玩家移动与锁敌仍然工作。
- Godot 4.7 headless 测试与编辑器加载不得产生新增错误或 warning。

## 不在本轮处理

- 不删除 `SkillSocket` 节点。
- 不精简 WeaponDefinition 字段。
- 不修改 WeaponEquipmentComponent 的跨场景路径。
- 不修改 FormationComponent。
- 不修改旧版 Ally、Enemy、Skill 或攻击模块。
- 不修改 `TestScene.tscn` 中任何单位实例。
