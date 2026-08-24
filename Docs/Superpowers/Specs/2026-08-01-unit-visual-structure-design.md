# Unit Visual 结构整理说明

## 目录

```text
UnitSystem/Visuals/
├── Base/UnitVisualBase.tscn
├── Player/HeroVisual.tscn
├── Ally/AllyVisual.tscn
├── Ally/CasterVisual.tscn
├── Enemy/EnemyVisual.tscn
└── Workbench/HeroAnimationWorkbench.tscn
```

## 唯一公共视觉父场景

`UnitVisualBase.tscn` 不包含具体模型，只提供统一节点契约：

```text
UnitVisualBase
└── CharacterRoot
    ├── ModelRoot
    └── WeaponSocket
        └── ProjectileOrigin
└── CharacterAnimationPlayer
```

具体角色只负责在 `ModelRoot` 下放置模型、材质和角色专属节点。视觉结构不再按 Ally/Enemy 阵营划分父类。

## 已移除的重复场景

- `UnitSystem/AI/Ally/Visuals/00-UnitBaseVisual.tscn`
- `UnitSystem/AI/Ally/Visuals/AllyBaseVisual.tscn`
- `UnitSystem/AI/Enemy/Visuals/EnemyBaseVisual.tscn`
- `UnitSystem/Player/Hero/HeroVisual.tscn` 旧位置

所有活动单位和测试引用均已切换到 `UnitSystem/Visuals` 下的新路径。没有修改 TestScene 中的单位实例。

## 视觉契约

战斗、技能和武器系统只依赖以下公共路径：

- `CharacterRoot`
- `CharacterRoot/WeaponSocket`
- `CharacterRoot/WeaponSocket/ProjectileOrigin`
- `CharacterAnimationPlayer`

模型可以是 CSG、MeshInstance3D 或未来的骨骼角色，不影响单位逻辑。
