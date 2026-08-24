# UnitSystem 与武器资产目录整理设计

## 目标

在不改变任何运行行为的前提下，整理当前 `UnitSystem` 的文件职责边界：将可被玩家、AI、背包、商店和掉落系统共同使用的武器资产迁移到项目级 `res://Item/Weapon/`，并将单位基类、玩家、AI 与可装卸组件按浅层职责重新归类。

本次工作是资源位置迁移，不是单位架构重构。所有现有类名、节点结构、动画内容、Inspector 参数与场景实例配置保持不变。

## 最终目录

```text
res://
├── Item/
│   └── Weapon/
│       ├── WeaponData.gd
│       ├── WeaponData.gd.uid
│       └── IronSword/
│           ├── IronSwordData.tres
│           ├── IronSwordVisual.tscn
│           └── IronSwordAnimationLibrary.res
│
└── UnitSystem/
    ├── Base/
    │   ├── 00_UnitBase.gd
    │   ├── 00_UnitBase.gd.uid
    │   ├── 00_UnitBase.tscn
    │   ├── AIUnitBase.gd
    │   ├── AIUnitBase.gd.uid
    │   └── AIUnitBase.tscn
    │
    ├── Player/
    │   ├── PlayerBase.gd
    │   ├── PlayerBase.gd.uid
    │   ├── PlayerBase.tscn
    │   └── Hero/
    │       ├── Hero.tscn
    │       ├── HeroVisual.tscn
    │       └── HeroAnimationWorkbench.tscn
    │
    ├── AI/
    │   ├── Ally/
    │   │   ├── AllyBase2.gd
    │   │   ├── AllyBase2.gd.uid
    │   │   └── AllyBase2.tscn
    │   └── Enemy/
    │       ├── EnemyBase2.gd
    │       ├── EnemyBase2.gd.uid
    │       └── EnemyBase2.tscn
    │
    ├── Components/
    │   ├── Animation/
    │   │   ├── CharacterAnimationEventPlayer.gd
    │   │   └── CharacterAnimationEventPlayer.gd.uid
    │   ├── Combat/
    │   │   ├── PlayerAttackController.gd
    │   │   ├── PlayerAttackController.gd.uid
    │   │   ├── PlayerMeleeHitbox.gd
    │   │   ├── PlayerMeleeHitbox.gd.uid
    │   │   └── PlayerMeleeHitbox.tscn
    │   ├── Movement/
    │   └── Targeting/
    │
    └── Tests/
```

`Movement` 和 `Targeting` 保持现有内部内容，仅因其他文件移动而更新必要的资源路径。用户在实施前主动删除了原 `UnitSystem/Tests`，因此只重建本次迁移所需的专项目录契约测试，不恢复已删除的旧测试集合。

## 职责边界

### Item/Weapon

保存武器定义及具体武器资产。`WeaponData.gd` 是武器数据类型；IronSword 子目录保存铁剑的数据资源、视觉场景与动画库。该目录不包含玩家输入、角色移动、命中查询或摄像机反馈算法。

### UnitSystem/Base

保存所有单位共同使用的 `UnitBase`，以及自动控制单位共同使用的 `AIUnitBase`。本次只移动文件，不改名、不改变继承关系。

### UnitSystem/Player

保存玩家控制层与唯一玩家角色 Hero。`PlayerBase` 继续负责玩家移动、冲刺及对外门面接口；Hero 子目录保存 Hero 场景、视觉场景与动画工作台。武器资产不再由 Hero 私有目录维护。

### UnitSystem/AI

保存当前新 AI 基础场景。`AllyBase2` 与 `EnemyBase2` 保留原名称和实现，避免与尚未迁移的旧系统同名类冲突。本阶段不正式重构这两个部分。

### UnitSystem/Components

保存可装配或职责独立的运行组件：

- `Animation`：角色动画方法轨道使用的事件桥。
- `Combat`：玩家攻击调度与玩家近战 Hitbox；它们属于单位运行逻辑，不属于武器物品。
- `Movement`：AI 移动与阵营游荡组件。
- `Targeting`：玩家选取和锁定目标组件。

## 迁移映射

| 旧路径 | 新路径 |
|---|---|
| `res://UnitSystem/Combat/WeaponData.gd` | `res://Item/Weapon/WeaponData.gd` |
| `res://UnitSystem/Players/Hero/Weapons/IronSword/` | `res://Item/Weapon/IronSword/` |
| `res://UnitSystem/Combat/PlayerAttackController.gd` | `res://UnitSystem/Components/Combat/PlayerAttackController.gd` |
| `res://UnitSystem/Combat/PlayerMeleeHitbox.gd` | `res://UnitSystem/Components/Combat/PlayerMeleeHitbox.gd` |
| `res://UnitSystem/Combat/PlayerMeleeHitbox.tscn` | `res://UnitSystem/Components/Combat/PlayerMeleeHitbox.tscn` |
| `res://UnitSystem/Combat/CharacterAnimationEventPlayer.gd` | `res://UnitSystem/Components/Animation/CharacterAnimationEventPlayer.gd` |
| `res://UnitSystem/00_UnitBase.*` | `res://UnitSystem/Base/00_UnitBase.*` |
| `res://UnitSystem/AIUnitBase.*` | `res://UnitSystem/Base/AIUnitBase.*` |
| `res://UnitSystem/PlayerBase.*` | `res://UnitSystem/Player/PlayerBase.*` |
| `res://UnitSystem/Players/Hero/`（武器目录除外） | `res://UnitSystem/Player/Hero/` |
| `res://UnitSystem/AllyBase2.*` | `res://UnitSystem/AI/Ally/AllyBase2.*` |
| `res://UnitSystem/EnemyBase2.*` | `res://UnitSystem/AI/Enemy/EnemyBase2.*` |

## 资源与场景迁移规则

- 脚本的 `.gd.uid` 必须与 `.gd` 一同移动，保留 Godot 资源身份。
- `.tscn`、`.tres`、`.res` 文件保持原 UID 和内部内容；只修改因迁移而失效的 `res://` 路径。
- 不手动编辑 `.godot` 目录或 UID 缓存，由 Godot 4.7 编辑器扫描重新建立缓存。
- 更新实际运行资源、测试脚本与当前使用说明中的旧路径。
- 历史 `Docs/Superpowers` 设计和实施计划保留当时路径，不批量改写；新增独立迁移说明记录新旧路径。
- 旧目录内容迁空后删除 `UnitSystem/Combat`、`UnitSystem/Players` 以及空的中间目录，不保留重复副本。

## 场景保护规则

- `Scenes/TestScene.tscn` 完全不修改，且迁移前后 SHA-256 必须一致。
- `Scenes/TestScene2.tscn` 只允许更新已存在单位场景的资源路径；不得增删、重建或移动任何单位实例，不改变节点名称、位置和 Inspector 配置。
- 不修改旧 `Scenes/ObjectScenes/Hero.tscn` 与旧 `Scenes/Components/MeleeAttackModule.tscn`。
- 不向任何测试场景自动添加单位。

## 失败处理与回滚边界

- 迁移前记录所有目标文件和受保护场景哈希。
- 按职责组分批移动并立即更新引用，避免新旧位置长期并存。
- 每批迁移后运行资源路径扫描；发现旧运行路径或加载失败时，先修复当前批次，不继续下一批。
- 若 Godot 无法加载资源，优先核对文本路径、UID 伴随文件和大小写，不通过创建重复资源规避问题。
- 本项目不是 Git 仓库，因此不执行提交或 worktree；验收依赖文件清单、哈希和自动测试证据。

## 验证标准

- `res://Item/Weapon/` 可以独立找到 WeaponData 和完整 IronSword 资产。
- `UnitSystem` 根目录不再堆放单位文件，原 `Combat` 与 `Players` 目录迁空后不存在。
- 所有实际运行文件中不再引用旧路径。
- `UnitSystem/Tests/UnitDirectoryLayoutTest.gd` 通过，且无 ERROR、WARNING 或 FAIL；原 13 个旧测试已由用户主动删除，不属于本次恢复范围。
- Godot 4.7 编辑器扫描退出码为 0，无脚本或资源加载问题。
- 项目主场景无窗口运行退出码为 0。
- `TestScene2` 的现有单位数量、节点名称、位置和配置保持不变。
- `Scenes/TestScene.tscn`、旧 Hero 与旧 MeleeAttackModule 的哈希保持不变。

## 明确不在本次范围内

- 不重命名 `AllyBase2`、`EnemyBase2`、`00_UnitBase` 或任何 `class_name`。
- 不改变 UnitBase、PlayerBase、AIUnitBase 的职责或继承关系。
- 不重构攻击、Hitbox、动画、移动、锁敌或反馈算法。
- 不新增武器、物品基类、背包、装备栏、掉落或商店系统。
- 不迁移或清理旧单位系统。
