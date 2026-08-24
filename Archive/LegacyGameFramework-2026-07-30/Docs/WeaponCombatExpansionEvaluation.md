# 简化武器战斗系统的扩展评估

## 当前数据流

```text
PlayerCombatModule
    └── WeaponData.tres
        ├── Weapon.tscn
        ├── WeaponAnimations.tres
        ├── hitbox_size
        └── hitbox_offset
```

旧的 `Race + WeaponType -> Database -> AnimationEntry` 查表已经从当前
`WeaponCombatSystem` 移除。项目当前体量较小，使用一件具体武器一份扁平数据更容易
由设计师定位、预览和维护。

## 新增武器的成本

新增武器只需要维护同一武器文件夹中的四份内容：

- 一份扁平 `WeaponData.tres`；
- 一份无脚本武器场景；
- 一份纯视觉场景；
- 一份外部 `AnimationLibrary`。

运行时代码、PlayerBase 和其他武器都不需要修改。连击段数由连续的
`basic_attack_1..N` 自动发现，因此增加或减少连段也不需要改控制器代码。

## 新增角色的成本

只要角色保持以下两个接口路径，就能直接复用模块：

```text
Visual/CharacterActionRig/BodyRoot
Visual/CharacterActionRig/WeaponSocket
```

若未来正式骨骼角色的路径不同，可在组合场景通过模块公开的 `configure()` 注入实际
节点；无需让 PlayerBase 依赖战斗模块。

## 职责边界

- `PlayerBase`：移动、冲刺、重力、朝向、锁定和角色视觉接口。
- `PlayerCombatModule`：输入、装备、动画加载、连击、Hitbox、前移和局部停顿。
- `WeaponData`：一件具体武器的直接资源引用和检测盒配置。
- 外部系统：伤害、生命值、声音、摄像机震动和其他命中反馈。

这套边界保留运行时换装、开放接口与可扩展性，但避免把当前规模尚不需要的数据库、
种族映射和多层自定义 Resource 带回系统。
