# Legacy Game Framework Archive

归档日期：2026-07-30

本目录保存已经由当前游戏框架取代的旧场景、脚本、资源和历史文档。归档来源包括：

- `res://Scenes/ObjectScenes`
- `res://Scenes/EnemyScenes`
- `res://Scenes/Components`
- `res://Scripts` 中完成活动脚本迁移后的剩余内容
- `res://Resources`
- 归档实施前的 `res://Docs`

这些内容不再由当前游戏框架使用。当前替代系统为：

- `res://UnitSystem`
- `res://SkillSystem`
- `res://Item`
- `res://Effects`

根目录的 `.gdignore` 会阻止 Godot 扫描此处的历史脚本、场景与资源。归档内部保留旧 `res://` 路径，没有把它们重写成可运行状态，因此不能直接作为活动资源加载或引用。

如需恢复某项实现，必须先将所需文件移出 `Archive`，迁移到当前职责目录，修复全部资源引用，并重新执行当前项目的 UID 审计、测试、Godot 4.7 编辑器扫描和主场景启动验证。

本归档用于安全观察期，不代表其中内容已经永久删除。
