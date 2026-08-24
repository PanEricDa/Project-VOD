# 旧框架归档清单

归档日期：2026-07-30

归档根目录：

```text
res://Archive/LegacyGameFramework-2026-07-30
```

## 活动脚本迁移

以下文件仍属于当前系统，因此没有归档，而是迁移到新的职责目录：

| 原位置 | 当前活动位置 |
|---|---|
| `res://Scripts/CameraFollowController.gd` | `res://UnitSystem/Components/Camera/CameraFollowController.gd` |
| `res://Scripts/Combat/AI/TrackingArcProjectile.gd` | `res://Item/Projectiles/TrackingArcProjectile.gd` |
| `res://Scripts/Combat/Skills/FireballProjectile.gd` | `res://Item/Projectiles/FireballProjectile.gd` |

对应 `.uid` 文件与脚本同步移动，场景引用已更新。`TestScene2.tscn` 的归一化 SHA-256 在迁移前后均为：

```text
F185E86AF070412F63586FE8CF7CAF40693AB98E4C018FA11FE31DCD2595B5D3
```

这表示除相机脚本路径外，TestScene2 内容没有发生变化。

## 运行文件归档

| 原位置 | 归档位置 | 文件数 |
|---|---|---:|
| `res://Scenes/ObjectScenes` | `Archive/.../Scenes/ObjectScenes` | 7 |
| `res://Scenes/EnemyScenes` | `Archive/.../Scenes/EnemyScenes` | 2 |
| `res://Scenes/Components` | `Archive/.../Scenes/Components` | 12 |
| 完成活动脚本迁移后的 `res://Scripts` | `Archive/.../Scripts` | 31 |
| `res://Resources` | `Archive/.../Resources` | 7 |

旧运行文件合计：59。

## 文档归档

归档前 `Docs` 共 113 个文件。本次归档设计和实施计划属于当前整理工作，已恢复到新的活动 `Docs/Superpowers`；其余 111 个历史文档保存在：

```text
Archive/LegacyGameFramework-2026-07-30/Docs
```

## 隔离方式

归档根目录包含 `.gdignore`。Godot 不应扫描归档中的旧 `class_name`、场景和资源。

归档内部路径保持历史原貌，不能直接作为活动资源加载。当前活动场景、脚本、资源与测试不得引用 `res://Archive`。

## 当前替代目录

- 单位与战斗：`res://UnitSystem`
- 技能：`res://SkillSystem`
- 武器与投射物：`res://Item`
- 命中反馈与技能表现：`res://Effects`
- 当前主场景：`res://Scenes/TestScene2.tscn`

## 已完成的阶段验证

- 归档契约：PASS
- 活动 `.tres` UID 审计：PASS，共 27 个资源
- TestScene2 路径保护哈希：一致
- Firebolt 定向回归：PASS
- 脚本迁移后的 Godot 4.7 编辑器扫描：退出码 0

## 最终验证结果

- 活动旧路径静态扫描：PASS
- 归档契约：PASS
- 活动 Resource UID 审计：PASS，27 个 `.tres`
- 当前测试：41 个；38 个实际运行，29 PASS、9 FAIL
- 三个缺失 Amy 且会挂住批次的测试：沿用迁移前同一失败证据
- 本次新增失败类别：0
- Godot 4.7 headless 编辑器扫描：退出码 0
- 当前主场景 120 帧 headless 启动：退出码 0
- Godot MCP Pro Editor Error：0
- Godot MCP Pro Output：无警告和错误

当前仍失败的可退出测试：

- `SingleSceneHolyLightTest.gd`
- `AIAttackControllerTest.gd`
- `AICombatSystemTest.gd`
- `PriestHolyLightAutomaticRuntimeTest.gd`
- `RangedAttackPipelineTest.gd`
- `ShieldAnimationLibraryTest.gd`
- `UnitDirectoryLayoutTest.gd`
- `WeaponAttackRangeTest.gd`
- `WeaponDataInheritanceTest.gd`

未重复运行的三个已知挂起测试：

- `AllyBehaviorStateMachineTest.gd`
- `AllyInheritedRootRenameTest.gd`
- `AllyMeleeCombatIntegrationTest.gd`

上述三项都引用已经不存在的 `res://UnitSystem/AI/Ally/Units/Amy.tscn`。
这些既有问题需要独立修复，不影响本次归档路径验证，也没有通过恢复旧系统或移动测试来掩盖。

## 永久删除前必须执行

```powershell
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' `
  --headless --path 'G:\Godot\ProjectVOD' `
  --script 'res://UnitSystem/Tests/LegacyFrameworkArchiveContractTest.gd'

& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' `
  --headless --path 'G:\Godot\ProjectVOD' `
  --script 'res://UnitSystem/Tests/ResourceUidAuditTest.gd'

& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' `
  --headless --path 'G:\Godot\ProjectVOD' --editor --quit
```

还需人工启动 `Scenes/TestScene2.tscn`，检查 Hero、AI、近战、远程、索敌、技能和特效。永久删除归档必须由用户另行确认。
