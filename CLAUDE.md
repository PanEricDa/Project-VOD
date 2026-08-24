# 神代遗痕（ProjectVOD）项目开发准则

## 项目身份（2026-08-24 起）

- 正式名称：**神代遗痕 / Vestiges of the divine**；工程文件夹 **ProjectVOD**；`project.godot` 的 `config/name` 为 `Vestiges of the divine`。
- 命名唯一权威：`Docs/Vestiges of the divine/GameName.md`。
- 旧名（SipSip、Sip Sip Carnival／吨吨游乐园、深渊清扫者）仅存在于 `Archive/` 与带日期的历史过程文档中，活动文件不得再使用。

## 命名规范（项目级决议，覆盖全局章程第十一条中的文件名规范）

- 文件与目录名统一 **PascalCase**（含 .gd / .tscn / .tres / .res / .md）。
- 例外：Godot 强制约定不改动——`project.godot`、`addons/`、`.godot/` 及插件内部文件。
- GDScript 代码标识符仍遵循 Godot 官方风格：类名/节点名 PascalCase，函数/变量/信号 snake_case，常量 UPPER_SNAKE_CASE。
- 全局章程其余条款继续适用。

## Archive 政策

- `Archive/` 仅作历史备份：活动代码、测试、场景与文档**不得引用**其中内容，正常工作流不读取。
- 带日期的历史过程文档（`Docs/Superpowers/`、`Docs/Plans/` 下的 Spec/Plan 与 `.superpowers/`）保留当时记录原样（含旧路径与旧名），不回改。

## 设计讨论行为规范

在进行任何设计讨论（如系统分析、方案设计、功能拓展）时，必须遵循以下流程：

1. **罗列关注点**：思考后，先列出本次设计需要关注和决策的所有关键点
2. **先提问再分析**：就每个关注点向用户提问，收集用户的需求、偏好和约束
3. **结合回答再输出**：在获得用户的明确回答后，再进行分析、拓展、评估和设计方案的输出

禁止在未向用户确认需求前直接给出完整的分析结论和设计方案。
