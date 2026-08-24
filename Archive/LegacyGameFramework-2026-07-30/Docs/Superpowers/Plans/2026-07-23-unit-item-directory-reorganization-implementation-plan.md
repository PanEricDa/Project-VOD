# UnitSystem 与武器资产目录整理实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将武器资产迁移到项目级 `Item/Weapon`，并按 Base、Player、AI、Components 整理 UnitSystem，同时保持所有运行行为和现有场景单位配置不变。

**Architecture:** 迁移只改变资源位置和 `res://` 引用，不改变类名、继承、节点或参数。先建立会因旧目录而失败的迁移契约测试，再分两批移动武器/组件与单位文件，最后通过资源扫描、场景实例化和哈希进行验收。

**Tech Stack:** Godot 4.7、GDScript、Godot 文本资源、PowerShell 原生文件移动。

## Global Constraints

- 所有现有 `class_name`、文件名、场景 UID 和 `.gd.uid` 保持不变。
- 不修改脚本算法、节点结构、动画内容或 Inspector 参数。
- `Scenes/TestScene2.tscn` 只更新资源路径，不增删、重建或移动单位实例。
- `Scenes/TestScene.tscn`、旧 `Scenes/ObjectScenes/Hero.tscn`、旧 `Scenes/Components/MeleeAttackModule.tscn` 完全不修改。
- 不手动编辑 `.godot` 缓存。
- 历史设计和实施文档不批量改写。
- 用户已主动删除旧 `UnitSystem/Tests`；本计划只重建迁移所需的专项契约测试。
- 项目不是 Git 仓库，不创建提交或 worktree。

---

### Task 1: 建立迁移契约与保护快照

**Files:**
- Create: `UnitSystem/Tests/UnitDirectoryLayoutTest.gd`
- Modify: `Docs/Superpowers/Specs/2026-07-22-unit-item-directory-reorganization-design.md`

**Interfaces:**
- Produces: 新目录存在、旧目录消失、场景加载和 TestScene2 实例保持不变的自动契约。

- [x] 记录 `Scenes/TestScene.tscn`、旧 Hero、旧 MeleeAttackModule 的 SHA-256。
- [x] 记录 `TestScene2` 中 `AllyBase2`、`EnemyBase2`、`Hero` 的节点名和 Transform。
- [x] 新建 `UnitDirectoryLayoutTest.gd`，明确断言全部目标路径存在、全部旧路径不存在。
- [x] 在测试中加载并实例化 `UnitBase`、`AIUnitBase`、`PlayerBase`、`Hero`、`AllyBase2`、`EnemyBase2`、`IronSwordData` 和 `TestScene2`。
- [x] 断言 TestScene2 仍包含且只包含既有三个单位节点，并核对各自 Transform。
- [x] 运行测试确认 RED；失败原因必须是目标新路径尚不存在，而不是脚本解析错误。
- [x] 将设计规格的旧 13 项测试要求修正为当前迁移专项测试，记录这是用户主动删除旧测试后的范围调整。

---

### Task 2: 迁移武器资产与运行组件

**Files:**
- Move: `UnitSystem/Combat/WeaponData.gd*` → `Item/Weapon/WeaponData.gd*`
- Move: `UnitSystem/Players/Hero/Weapons/IronSword/*` → `Item/Weapon/IronSword/*`
- Move: `UnitSystem/Combat/PlayerAttackController.gd*` → `UnitSystem/Components/Combat/PlayerAttackController.gd*`
- Move: `UnitSystem/Combat/PlayerMeleeHitbox.gd*` → `UnitSystem/Components/Combat/PlayerMeleeHitbox.gd*`
- Move: `UnitSystem/Combat/PlayerMeleeHitbox.tscn` → `UnitSystem/Components/Combat/PlayerMeleeHitbox.tscn`
- Move: `UnitSystem/Combat/CharacterAnimationEventPlayer.gd*` → `UnitSystem/Components/Animation/CharacterAnimationEventPlayer.gd*`
- Modify: moved scenes/resources and their consumers.

**Interfaces:**
- Preserves: `WeaponData`, `PlayerAttackController`, `PlayerMeleeHitbox`, `CharacterAnimationEventPlayer` class contracts.

- [x] 创建并核对 `Item/Weapon/IronSword`、`UnitSystem/Components/Combat`、`UnitSystem/Components/Animation` 的解析后绝对路径均位于工作区内。
- [x] 将文件和对应 `.gd.uid` 一起移动，不复制、不重新创建资源。
- [x] 使用 `apply_patch` 更新 IronSwordData、Hero、HeroVisual、HeroAnimationWorkbench、PlayerBase 和 PlayerMeleeHitbox 场景中的路径。
- [x] 扫描实际运行文件，确认不再引用 `UnitSystem/Combat` 或 Hero 私有 Weapons 目录。
- [x] 运行 Godot 编辑器扫描，确认本批次资源可被识别后再继续。

---

### Task 3: 迁移单位基类、玩家与 AI 文件

**Files:**
- Move: `UnitSystem/00_UnitBase.*`, `UnitSystem/AIUnitBase.*` → `UnitSystem/Base/`
- Move: `UnitSystem/PlayerBase.*` → `UnitSystem/Player/`
- Move: `UnitSystem/Players/Hero/*` → `UnitSystem/Player/Hero/`
- Move: `UnitSystem/AllyBase2.*` → `UnitSystem/AI/Ally/`
- Move: `UnitSystem/EnemyBase2.*` → `UnitSystem/AI/Enemy/`
- Modify: moved scenes and `Scenes/TestScene2.tscn` resource paths.

**Interfaces:**
- Preserves: `UnitBase`、`AIUnitBase`、`PlayerBase`、`AllyBase2`、`EnemyBase2` 类和场景契约。

- [x] 创建并核对 Base、Player/Hero、AI/Ally、AI/Enemy 目标目录位于工作区内。
- [x] 移动每组文件及对应 `.gd.uid`，保留名称和 UID。
- [x] 使用 `apply_patch` 更新所有实际资源、测试常量与 TestScene2 的 `res://` 路径。
- [x] 检查 TestScene2 的三个单位节点定义和 Transform 与快照一致，除 ext_resource path 外不允许其他差异。
- [x] 确认旧 Combat、Players 和 Hero/Weapons 目录为空后，以非递归方式删除空目录。
- [x] 运行迁移契约测试确认 GREEN。

---

### Task 4: 迁移说明与完整验收

**Files:**
- Create: `Docs/UnitSystemDirectoryMigration.md`
- Modify: `Docs/Superpowers/Plans/2026-07-23-unit-item-directory-reorganization-implementation-plan.md`

**Interfaces:**
- Produces: 面向维护者的新旧路径映射与新增内容放置规则。

- [x] 写入最终目录树、旧→新映射、武器与单位组件职责边界以及新增武器的放置位置。
- [x] 运行 `UnitDirectoryLayoutTest.gd`，要求 PASS 且无 ERROR、WARNING、FAIL。
- [x] 扫描 `.gd/.tscn/.tres/.res/.godot`，确认没有实际运行文件引用旧路径。
- [x] 运行 Godot 4.7 `--headless --editor --quit`，要求退出码 0 且无问题。
- [x] 运行项目主场景 `--headless --quit-after 5`，要求退出码 0 且无问题。
- [x] 核对三个受保护旧场景 SHA-256 与迁移前一致。
- [x] 核对 TestScene2 只发生三条 ext_resource 路径更新，单位节点和 Transform 不变。
- [x] 回填最终验证结果和实际文件数量。

---

## 实施结果（2026-07-23）

- `Item/Weapon` 当前包含 5 个文件：WeaponData 脚本及 UID、IronSword 的数据、视觉和动画库。
- `UnitSystem` 当前包含 36 个文件；根目录只保留 Base、Player、AI、Components、Tests 五个职责目录。
- 原 `UnitSystem/Combat` 与 `UnitSystem/Players` 已在确认内容为空后删除。
- `UnitDirectoryLayoutTest.gd`：PASS，覆盖新旧路径、六个单位场景实例化、IronSwordData、Hero 起始武器与 TestScene2 三个单位快照。
- 实际运行资源旧路径扫描：0 条残留。
- Godot 4.7 编辑器扫描：退出码 0，无 ERROR、WARNING、FAIL。
- 项目主场景无窗口运行：退出码 0，无 ERROR、WARNING、FAIL。
- TestScene2 将三条新路径规范化回旧路径后的 SHA-256 与迁移前一致：`29E8A0207A9B5285FD1D2118136E1236CDFE94E9CDDB237F5832C09A03C8CFF7`。
- 三个受保护旧场景 SHA-256 保持不变：
  - `Scenes/TestScene.tscn`：`ED61E6208F63EAB5FF28EEA2D6142BD321A13B5A077D87E28DBC4DBFA0C723A1`
  - `Scenes/ObjectScenes/Hero.tscn`：`A00DE9820394CA6702615C5905CE5E637D42727273910E6ECDF823D0832E9F38`
  - `Scenes/Components/MeleeAttackModule.tscn`：`17B6C6301097937D955AA703B837A54E9F43A3A0305F9A893DC311B435DE506A`
