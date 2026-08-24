# 精简武器—动画—角色框架设计

## 目标

撤回上一版把运行武器、参考角色、动画预览和动画覆盖同时放进武器场景的设计。

新框架只解决以下运行关系：

- Player 决定何时攻击以及当前连击段。
- 武器场景提供唯一的武器视觉和该武器对应的动作动画。
- 角色自己的 AnimationPlayer 实际播放动作。
- 同一武器动画以后可以由玩家控制器或 AI 控制器分别调用。

本阶段不设计动画制作工作流，不在武器场景中放置参考角色、预览地面、方向标记或预览控制器。

## 最终节点结构

### 单手剑类型父场景

```text
SwordBase (WeaponBase)
├── VisualSlot
├── SkillSocket
└── Animations
```

- `VisualSlot`：具体武器模型的唯一容器。
- `SkillSocket`：预留武器技能装配入口，本阶段不接入技能逻辑。
- `Animations`：唯一的 AnimationPlayer，保存单手剑类型使用的动作数据。

父场景的 `Animations` 提供：

```text
RESET
basic_attack_1
basic_attack_2
basic_attack_3
```

动画轨道只允许使用角色的标准动作路径：

```text
BodyRoot
WeaponSocket
```

武器场景内不需要真的存在这两个角色节点。`Animations` 是动画数据来源，不在武器场景内部播放。

### 具体单手剑场景

```text
IronSword (inherits SwordBase)
└── VisualSlot
    └── IronSwordVisual
```

具体场景中只出现一份武器视觉。默认示例不制作动画覆盖，直接继承父场景的三段攻击。

以后确实需要专属动作时，具体武器可以在同一个 `Animations` 节点中增加名为 `override` 的动画库；同名动画覆盖父类基础动画，未覆盖动作继续使用父类版本。

## 角色结构

```text
PlayerBase
└── CharacterActionRig
    ├── BodyRoot
    ├── WeaponSocket
    └── CharacterAnimationPlayer
```

- `BodyRoot`：角色身体动作目标。
- `WeaponSocket`：实际武器挂点，同时是武器动作目标。
- `CharacterAnimationPlayer`：唯一的运行时动作播放器。

装备后，具体武器场景实例放入 `WeaponSocket`。武器中的动画被复制或合并到 `CharacterAnimationPlayer`，不会由武器自己的 AnimationPlayer 直接播放。

## 职责边界

### WeaponBase

只负责：

- 返回唯一 VisualSlot。
- 返回 SkillSocket。
- 返回基础和可选覆盖动画库。
- 返回连续存在的 `basic_attack_1..N` 名称。
- 保存运行时注入的 WeaponDefinition。

删除：

- ReferenceCharacterPath。
- PreviewRootPath。
- AnimationTargetRootPath。
- AnimationProfile。
- 编辑器预览显示切换。
- 运行时删除 Preview 的逻辑。

### PlayerAttackController

负责：

- 读取 `player_attack` InputMap。
- 控制三段连击、输入缓存和超时重置。
- 根据当前武器的动画列表选择动作。
- 请求 CharacterAnimationController 播放动作。

它不保存武器模型或动画数据，也不处理 AI 攻击决策。

### CharacterAnimationController

负责：

- 读取当前 WeaponBase 的 `Animations`。
- 先载入基础动画，再应用同名覆盖动画。
- 验证轨道只指向角色已有的标准节点。
- 使用角色自己的 CharacterAnimationPlayer 播放和停止动作。

### WeaponEquipmentComponent

继续负责：

- 通过 WeaponDefinition 实例化具体武器场景。
- 支持编辑器手动放置的 WeaponBase。
- 将武器放入角色 WeaponSocket。
- 通知 CharacterAnimationController 更新动画。
- 运行时换装和卸装。

## 攻击数据流

```text
鼠标左键
→ PlayerAttackController
→ 查询当前 WeaponBase 的 basic_attack 连续段
→ CharacterAnimationController
→ PlayerBase/CharacterAnimationPlayer
→ 控制 BodyRoot 与 WeaponSocket
```

武器不读取输入，不维护玩家连击状态。

AI 将来可以使用自己的攻击控制器读取相同的武器动画，但不会复用 PlayerAttackController。

## 继承规则

- 一种武器类型一个父场景，例如 `SwordBase.tscn`。
- 具体武器继承父场景，通常只需要在 `VisualSlot` 放入模型。
- 默认动作全部由父场景提供。
- 只有需要专属动作的具体武器才增加覆盖动画。
- 相同动画名称使用子武器覆盖版本。
- 未覆盖的动画继续使用父类版本。
- 连击仍按 `basic_attack_1`、`basic_attack_2`、`basic_attack_3` 连续发现。

## 本次迁移

删除 SwordBase 和 IronSword 中的：

```text
RuntimeWeapon
AnimationData
BaseAnimations
OverrideAnimations
AnimationPreview
ReferenceCharacterSlot
BodyRoot
BodyMesh
PreviewIronSwordVisual
PreviewController
PreviewGround
PreviewMarkers
FrontMarker
```

以新的三个直接子节点替代：

```text
VisualSlot
SkillSocket
Animations
```

具体 IronSword 中只保留一份 `IronSwordVisual`。

## 暂不实施

- 动画制作专用场景。
- 参考角色和预览工具。
- Skeleton3D、重定向和不同角色体型适配。
- Hitbox、伤害和命中反馈。
- AI 武器攻击执行器。
- 武器技能逻辑。
- TestScene 单位实例修改。

## 验收标准

- 打开具体 IronSword 场景时只看到一份武器 Visual。
- SwordBase 根节点下只有 VisualSlot、SkillSocket、Animations。
- 不存在任何 Preview 或 Reference 节点。
- PlayerBase 可以默认装备单手剑。
- 鼠标左键仍可依次执行三段攻击。
- 移动、冲刺、锁敌、重力和朝向不受影响。
- 删除 PlayerCombatSystem 后 PlayerBase 原有控制仍可运行。
- 不修改 `Scenes/TestScene.tscn`。
