# Legacy Hero 归档

归档日期：2026-07-23

本目录保存已经由 `res://UnitSystem/Player/Hero/Hero.tscn` 替代的旧玩家实现，当前仅用于历史对照并等待最终删除。

## 归档范围

- `Scenes/Hero.tscn`：旧 Hero 源场景。
- `Scenes/MeleeAttackModule.tscn`：旧玩家三连击模块。
- `Scenes/TestScene.tscn`：仍实例化旧 Hero 的旧测试场景。
- `Scripts/HeroController.gd`：旧玩家控制器。
- `Scripts/MeleeAttackModule.gd`：旧三连击控制脚本。
- `Scripts/MeleeHitDetector.gd`：旧近战检测脚本。

对应的 `.uid` 文件与脚本一同归档。

## 隔离说明

根目录包含 `.gdignore`，因此 Godot 不会扫描或导入这些待删除资源。归档内文件保留原始依赖路径，仅用于源代码和历史实现对照，不能直接作为项目运行场景使用。

## 未归档的共享资源

以下资源仍由新 PlayerBase 或 AI 攻击模块使用，不能随旧 Hero 删除：

- `res://Effects/Combat/HitFeedbackBridge.tscn`
- `res://Effects/Combat/HitFeedbackBridge.gd`
- `res://Effects/Combat/HitFeedbackProfile.gd`
- `res://Effects/Combat/DefaultMeleeHitFeedback.tres`
- Health、Faction 等通用战斗组件。

项目当前运行入口为 `res://Scenes/TestScene2.tscn`。
