# UnitSystem 目录与武器资产使用说明

## 当前目录

```text
res://
├── Item/
│   └── Weapon/
│       ├── WeaponData.gd
│       └── IronSword/
│           ├── IronSwordData.tres
│           ├── IronSwordVisual.tscn
│           └── IronSwordAnimationLibrary.res
│
└── UnitSystem/
    ├── Base/
    │   ├── 00_UnitBase.gd
    │   ├── 00_UnitBase.tscn
    │   ├── AIUnitBase.gd
    │   └── AIUnitBase.tscn
    ├── Player/
    │   ├── PlayerBase.gd
    │   ├── PlayerBase.tscn
    │   └── Hero/
    │       ├── Hero.tscn
    │       ├── HeroVisual.tscn
    │       └── HeroAnimationWorkbench.tscn
    ├── AI/
    │   ├── Ally/
    │   │   └── AllyBase2.*
    │   └── Enemy/
    │       └── EnemyBase2.*
    ├── Components/
    │   ├── Animation/
    │   ├── Combat/
    │   ├── Movement/
    │   └── Targeting/
    └── Tests/
        └── UnitDirectoryLayoutTest.gd
```

## 内容应该放在哪里

### 新增武器

每件具体武器在 `res://Item/Weapon/<WeaponName>/` 下维护自己的资源：

- `<WeaponName>Data.tres`：武器数据入口。
- `<WeaponName>Visual.tscn`：武器视觉场景。
- `<WeaponName>AnimationLibrary.res`：当前角色使用该武器的动作库。

所有武器数据继续使用 `res://Item/Weapon/WeaponData.gd`。武器目录不放玩家输入、AI 判断、角色移动或命中反馈控制器。

### 新增单位类型

- 所有单位共同内容放入 `UnitSystem/Base`。
- 玩家控制层和具体玩家角色放入 `UnitSystem/Player`。
- 友方与敌方 AI 场景分别放入 `UnitSystem/AI/Ally`、`UnitSystem/AI/Enemy`。
- 可以独立装配或有单一职责的功能放入 `UnitSystem/Components` 对应分类。

### Components 分类

- `Animation`：角色动画方法轨道与动画事件接口。
- `Combat`：单位运行时攻击调度和 Hitbox 等战斗组件。
- `Movement`：移动、冲刺、阵营站位与游荡组件。
- `Targeting`：目标选择、锁定与范围显示组件。

## 本次路径迁移

| 旧位置 | 新位置 |
|---|---|
| `UnitSystem/Combat/WeaponData.gd` | `Item/Weapon/WeaponData.gd` |
| `UnitSystem/Players/Hero/Weapons/IronSword/` | `Item/Weapon/IronSword/` |
| `UnitSystem/Combat/PlayerAttackController.gd` | `UnitSystem/Components/Combat/PlayerAttackController.gd` |
| `UnitSystem/Combat/PlayerMeleeHitbox.*` | `UnitSystem/Components/Combat/PlayerMeleeHitbox.*` |
| `UnitSystem/Combat/CharacterAnimationEventPlayer.gd` | `UnitSystem/Components/Animation/CharacterAnimationEventPlayer.gd` |
| `UnitSystem/00_UnitBase.*` | `UnitSystem/Base/00_UnitBase.*` |
| `UnitSystem/AIUnitBase.*` | `UnitSystem/Base/AIUnitBase.*` |
| `UnitSystem/PlayerBase.*` | `UnitSystem/Player/PlayerBase.*` |
| `UnitSystem/Players/Hero/` | `UnitSystem/Player/Hero/` |
| `UnitSystem/AllyBase2.*` | `UnitSystem/AI/Ally/AllyBase2.*` |
| `UnitSystem/EnemyBase2.*` | `UnitSystem/AI/Enemy/EnemyBase2.*` |

## 注意事项

- `AllyBase2` 与 `EnemyBase2` 仍保留当前名称，避免和旧系统的同名类冲突。
- 移动脚本时必须同时移动对应 `.gd.uid`，不要重新生成同名脚本替代。
- 不要手动修改 `.godot` UID 缓存；移动并修正路径后让 Godot 编辑器重新扫描。
- 历史 `Docs/Superpowers` 文档中的旧路径记录实施当时的真实结构，不需要追溯修改。
- 向 `Scenes/TestScene.tscn` 添加任何单位时，仍必须由用户在 Godot 编辑器中手动完成。
