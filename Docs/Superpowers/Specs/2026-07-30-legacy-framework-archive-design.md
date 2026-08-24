# 旧游戏框架安全归档设计

日期：2026-07-30

## 目标

将已经由当前 `UnitSystem`、`SkillSystem`、`Item` 与 `Effects` 取代的旧场景、脚本、资源、测试和文档从活动文件系统中移除，集中保存到带日期的隔离归档中。

归档完成后，项目根目录只保留当前运行框架及与之对应的使用说明，Godot 不再扫描旧脚本和旧资源，开发者也不会再被过时路径或旧架构文档误导。

本次不删除任何旧文件。归档内容需经过后续测试确认后，才可由用户另行决定是否永久删除。

## 当前系统边界

以下目录属于当前活动框架，必须保留：

- `res://UnitSystem`
- `res://SkillSystem`
- `res://Item`
- `res://Effects`
- `res://Materials`
- `res://Assets`
- `res://addons`
- `res://Scenes/TestScene2.tscn`
- `res://project.godot`

以下已有归档保持原样：

- `res://Archive/LegacyHero`
- `res://Archive/SkillSystemLegacy-2026-07-28`

不得修改 `res://Scenes/TestScene.tscn` 或 `res://Scenes/TestScene2.tscn` 中任何单位实例。允许仅为保持当前主场景有效而更新 `TestScene2.tscn` 的脚本资源路径。

## 归档结构

创建：

```text
Archive/
└── LegacyGameFramework-2026-07-30/
    ├── .gdignore
    ├── README.md
    ├── Scenes/
    ├── Scripts/
    ├── Resources/
    └── Docs/
```

`.gdignore` 用于阻止 Godot 扫描归档内的旧 `class_name`、场景和资源。归档文件保留其原始内部内容，作为历史实现参考，不尝试把归档内部修复成可运行状态。

`README.md` 记录归档日期、来源路径、归档原因、隔离方式，以及归档内容不能直接作为活动资源重新引用的约束。

## 运行文件归档范围

### 旧场景

归档以下目录：

- `res://Scenes/ObjectScenes`
- `res://Scenes/EnemyScenes`
- `res://Scenes/Components/AI`
- `res://Scenes/Components/AiAttackModules`
- `res://Scenes/Components/Combat`
- `res://Scenes/Components/SkillModules`

保留：

- `res://Scenes/TestScene2.tscn`

若清理后 `res://Scenes/Components` 成为空目录，则不要求保留该空目录。

### 旧脚本

归档：

- `res://Scripts/AI`
- 旧攻击模块、旧技能模块、旧 Health/Faction 组件及其辅助脚本

以下三个脚本仍被当前框架使用，不得归档：

```text
res://Scripts/CameraFollowController.gd
res://Scripts/Combat/AI/TrackingArcProjectile.gd
res://Scripts/Combat/Skills/FireballProjectile.gd
```

它们需要在归档前迁移到当前职责目录：

```text
res://UnitSystem/Components/Camera/CameraFollowController.gd
res://Item/Projectiles/TrackingArcProjectile.gd
res://Item/Projectiles/FireballProjectile.gd
```

对应 `.uid` 文件与脚本一起移动，并更新所有活动场景、资源和测试引用。迁移后，若 `res://Scripts` 不再包含活动文件，则整个剩余目录归档。

### 旧资源

归档：

- `res://Resources/Combat`

当前 `UnitSystem` 的武器数据、动画库和投射物资源继续保存在 `res://Item`；技能场景继续保存在 `res://SkillSystem`；战斗反馈与技能特效继续保存在 `res://Effects`。

## 文档整理

当前 `res://Docs` 中混合了旧系统计划、历史实现总结和当前系统设计。为避免逐文件判断造成遗漏，实施时先将现有文档保存为历史快照：

```text
res://Archive/LegacyGameFramework-2026-07-30/Docs/
```

以下本次归档设计与实施计划属于新文档，必须保留在重建后的 `res://Docs`：

- `Docs/Superpowers/Specs/2026-07-30-legacy-framework-archive-design.md`
- 本设计审核通过后创建的对应实施计划

清理完成后重新建立以下面向当前框架的文档：

```text
Docs/
├── CurrentProgressReport.md
├── CurrentSystemUserGuide.md
├── DevelopmentMemo.md
└── ArchiveManifest.md
```

文档职责：

- `CurrentProgressReport.md`：说明当前已完成系统、测试状态和仍未完成的工作。
- `CurrentSystemUserGuide.md`：以实际配置顺序说明如何创建单位、配置武器、装载战斗系统、装载技能及运行测试。
- `DevelopmentMemo.md`：记录关键约束、已知风险、后续扩展接口和禁止重复发生的问题。
- `ArchiveManifest.md`：列出本次移动的来源与归档位置，并说明仍被当前系统复用的资源。

新文档不得继续把旧 `Scenes/ObjectScenes`、旧 AttackModules 或旧 SkillModules 描述为当前实现。

## 路径迁移原则

活动资源必须指向活动目录，不得引用 `res://Archive`。

路径迁移按照以下顺序执行：

1. 为三个仍在使用的脚本建立新位置。
2. 更新活动场景、资源和测试的引用。
3. 运行定向测试，确认新路径可用。
4. 移动旧场景、脚本和资源到归档目录。
5. 扫描所有非归档文件，确认不存在指向本次旧目录的运行时引用。
6. 重建当前文档。

不通过复制保留活动脚本的双份版本。路径迁移成功后，旧位置只允许存在于带 `.gdignore` 的归档中。

## 外部资源和 UID

移动已有 `.tres`、`.res`、`.tscn` 和脚本时必须保留 Godot 已登记的 UID；相关 `.uid` 文件必须与脚本同步移动。

本次原则上不创建新的正式游戏 `.tres` 或 `.res`。如果实施过程中确实需要创建正式外部资源，则必须通过 Godot 编辑器 API、Godot MCP Resource 工具或 `ResourceSaver` 保存，并验证：

```gdscript
ResourceLoader.get_resource_uid(resource_path) != ResourceUID.INVALID_ID
```

强类型 Resource 还必须能在 Inspector 的 `Quick Load` 中按正确类型检索。

## 安全与回滚

- 本次只移动和重写引用，不永久删除旧内容。
- 归档目录使用日期命名，避免覆盖已有归档。
- 移动前生成来源清单，移动后生成 `ArchiveManifest.md`。
- 若活动资源仍引用旧路径，停止归档流程并先修复引用。
- 若 Godot 扫描、当前测试或主场景启动出现新增错误，保留归档内容并修复活动路径，不通过重新启用旧框架绕过问题。
- 项目不是 Git 仓库，因此不依赖 Git 回滚；归档目录本身承担可恢复副本的职责。

## 验证标准

实施完成必须满足：

1. 所有非归档 `.gd`、`.tscn`、`.tres`、`.res` 和 `project.godot` 不再引用已归档的旧运行路径。
2. `Scenes/TestScene2.tscn` 仍是项目主场景，现有单位实例未被增删或改写配置。
3. 当前 `UnitSystem`、`SkillSystem`、远程投射物、近战命中反馈及技能特效的相关测试通过。
4. Godot 4.7 headless 编辑器扫描退出码为 `0`，没有新增脚本解析错误、资源缺失或 UID 错误。
5. `Scenes/TestScene2.tscn` 可启动，当前 Hero、AI、攻击、索敌、技能和投射物链路没有因路径迁移失效。
6. `Archive/LegacyGameFramework-2026-07-30` 包含 `.gdignore` 和可核对的归档说明。
7. 新建的四份当前文档只描述活动框架，路径与项目实际文件一致。

## 暂不处理

- 不永久删除任何归档。
- 不重构当前 `UnitSystem`、`SkillSystem`、武器、技能或 AI 算法。
- 不改变战斗数值、动画、InputMap、碰撞层或 Inspector 参数。
- 不向测试场景添加、删除或替换单位实例。
- 不整理 `Assets`、`Materials`、`Effects` 或 `Item` 内仍在使用的美术与游戏资源。
