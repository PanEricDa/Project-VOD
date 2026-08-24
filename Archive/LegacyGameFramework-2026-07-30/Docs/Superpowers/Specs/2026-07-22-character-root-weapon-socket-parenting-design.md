# CharacterRoot WeaponSocket Parenting Design

## Goal

将 Hero 的 `WeaponSocket` 正式归入 `CharacterRoot`，使武器自动继承身体动作，同时保留 WeaponSocket 自身的局部攻击动画。

## Final Hierarchy

```text
HeroVisual
├── CharacterRoot
│   ├── WeaponSocket
│   │   └── <runtime or workbench weapon visual>
│   └── BodyMesh
└── CharacterAnimationPlayer
```

## Required Migration

- `PlayerAttackController` 的内部固定查找路径改为 `CharacterRoot/WeaponSocket`。
- `IronSwordAnimations.tres` 中全部 WeaponSocket 轨道改为：
  - `CharacterRoot/WeaponSocket:position`
  - `CharacterRoot/WeaponSocket:rotation`
- 仅迁移轨道 NodePath；保留用户当前编辑的动画长度、关键帧时间、插值和数值。
- Workbench 的剑实例改挂到 `HeroVisual/CharacterRoot/WeaponSocket`。
- Workbench 本地 RESET 轨道同步改为嵌套路径。
- 更新测试 rig、Hero 运行时路径和 Workbench 路径断言。

## Behavior

`CharacterRoot` 的旋转会自动作用于身体和武器；WeaponSocket 动画仍使用相对 CharacterRoot 的局部位置与旋转。CharacterRoot 初始 Transform 为单位矩阵，因此静止姿势的世界位置保持不变。

不增加新节点、脚本或 Resource，不修改移动、碰撞、WeaponData、连击状态机、旧 Hero 或 TestScene。
