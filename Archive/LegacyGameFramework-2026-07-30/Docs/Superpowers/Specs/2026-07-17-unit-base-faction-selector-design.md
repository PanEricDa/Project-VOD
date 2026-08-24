# UnitBase 阵营下拉选择设计

## 目标

将 `UnitBase` 当前可自由输入的 `faction_id` 改为 Inspector 固定下拉选项，避免大小写和拼写错误，同时不改变现有敌我关系算法。

## 字段设计

`faction_id` 使用 `@export_enum` 提供以下四个固定选项：

- `Neutral`
- `Player`
- `Ally`
- `Enemy`

字段继续表示便于编辑器、调试和存档识别的阵营名称。`team_id` 仍是运行时判断友方、敌方和中立关系的唯一依据。

阵营名称不会自动改写 `team_id`。例如 `Player` 和 `Ally` 都可以配置为 `team_id = 1`，从而被现有关系接口判断为友方；未来也可以为不同敌方队伍配置不同的非零编号。

## 兼容范围

- 不修改 `is_friendly_to()`、`is_hostile_to()` 和 `is_neutral_to()` 的判断规则。
- 不增加临时阵营切换逻辑。
- 不迁移 Hero、AllyBase 或 EnemyBase。
- 不修改 `TestScene.tscn`。

## 验证

- Godot Inspector 中 `faction_id` 显示为四项下拉选择。
- UnitBase 的生命值测试继续通过。
- 相同非零 `team_id` 仍为友方，不同非零 `team_id` 仍为敌方，零仍为中立。
- Godot 4.7 项目扫描无新增脚本错误。
