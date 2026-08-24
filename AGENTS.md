# 项目协作规则

## 参数说明规范

- 每一个可配置的 `@export` 参数必须紧邻提供简体中文说明，明确其用途、单位或取值含义、默认行为，以及它影响的系统范围。
- 每一个公开方法、信号或需要由其他模块传入的参数，必须在其声明附近说明参数的职责与关键约束；不允许依赖名称猜测语义。
- 参数说明应随字段重命名、默认值或行为变化同步更新，避免 Inspector 与实际逻辑不一致。

- 当任务需要向 `res://Scenes/TestScene.tscn` 添加任何玩家、友方、敌方或其他单位实例时，不得由 Codex 自动添加或修改该单位实例。
- Codex 应明确告知用户需要添加的场景文件、目标父节点及必要的初始位置或 Inspector 参数，并由用户在 Godot 编辑器中手动完成添加。
- Codex 可以在用户添加完成后检查实例配置、诊断问题，并在用户明确要求时修改单位自身的源场景或脚本，但仍不得代替用户向 TestScene 添加单位。

## Godot 外部 Resource 创建规则

- 创建任何正式 `.tres` 或 `.res` 外部资源时，不得只通过文本文件写入后便视为完成。
- 资源必须通过 Godot 编辑器 API、Godot MCP 资源工具或 `ResourceSaver` 正式保存一次，
  使 Godot 为其生成并登记有效的 `uid://`。
- 交付前必须验证 `ResourceLoader.get_resource_uid(resource_path) !=
  ResourceUID.INVALID_ID`；仅验证 `load(resource_path)` 成功不算完成。
- 凡是用于 `@export` 强类型 Resource 字段的资源，还必须确认其脚本类型正确，并能够被
  Inspector 的 `Quick Load` 按对应类型检索。
- 如果测试中创建了新的资源类型或正式资源样例，应把“有效 UID”加入该资源的契约测试，
  防止后续文本迁移、复制或重命名再次破坏 Inspector 索引。
