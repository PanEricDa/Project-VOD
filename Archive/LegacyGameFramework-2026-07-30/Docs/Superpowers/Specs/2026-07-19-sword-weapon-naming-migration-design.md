# 剑类武器完整重命名设计

## 目标

将“剑类共用父场景”和“具体铁剑实例”明确分开，避免编辑器中出现多个含义相近的旧名称。

## 最终目录

```text
WeaponCombatSystem/
├── 00-Weapons/
│   └── IronSword/
│       ├── IronSword.tscn
│       ├── IronSwordVisual.tscn
│       └── IronSwordDefinition.tres
└── 01-WeaponTypes/
    └── Sword/
        └── SwordBase.tscn
```

## 职责

- `SwordBase.tscn`：剑类武器的共用父场景，保存基础攻击动画与武器接口。
- `IronSword.tscn`：继承 `SwordBase.tscn` 的具体铁剑场景。
- `IronSwordVisual.tscn`：只保存铁剑的临时视觉模型。
- `IronSwordDefinition.tres`：供背包、装备和运行时加载使用的铁剑数据入口。

## 命名迁移

旧的单手剑通用命名已经完整移除。类型场景统一使用
`01-WeaponTypes/Sword/SwordBase.tscn`；具体武器、视觉和 Definition
统一存放在 `00-Weapons/IronSword/`；对应测试使用
`04-Tests/IronSwordExampleTest.gd`。

场景根节点同步改名为 `SwordBase`、`IronSword` 和 `IronSwordVisual`。Definition 使用：

```text
weapon_id = iron_sword
display_name = Iron Sword
```

## 行为约束

- 不改变装备、输入、三段连击、动画映射或运行时换装行为。
- `PlayerBase.tscn` 的起始武器改为 `IronSwordDefinition.tres`。
- 不编辑 `Scenes/TestScene.tscn`。
- `.godot` 属于生成缓存，只通过 Godot 重新扫描刷新。
