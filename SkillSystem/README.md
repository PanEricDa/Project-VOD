# SkillSystem

Godot 4.7 单场景技能系统。一个具体技能只维护一个 `.tscn`：通用参数集中在
`SkillBase` 根节点，交付方式使用内嵌的强类型 `DeliveryConfig`，只有特殊条件、
消耗或效果才添加直接子组件。

## 目录

- `00-Skills`：可直接装载的具体技能；当前示例为 Firebolt、HolyLight。
- `01-Core`：`SkillBase`、`SkillHostComponent` 和运行时上下文。
- `02-Delivery`：投射物、目标瞬发、地面区域的交付配置与执行器。
- `03-Extensions`：可选 Condition、Cost、Effect 组件。
- `04-Docs`：面向设计师和开发者的配置说明。
- `05-Tests`：核心、装配、运行和 UID 契约测试。

## 最短流程

1. 继承 `01-Core/SkillBase.tscn`。
2. 保存一个具体的 `SkillNameSkill.tscn`。
3. 在根节点 Inspector 配置 Identity 至 Delivery。
4. 在 `Delivery` 字段中新建正确类型的内嵌配置。
5. 仅在确有需要时添加 Condition、Cost 或 Effect 直接子节点。
6. 将技能场景实例放入单位的 `SkillHost/SkillSocket`。
7. 在角色动画中添加 `release_action()` 与 `finish_action()` 方法关键帧。
8. 运行配置测试和运行时测试。

详细说明见 [技能系统使用指南](04-Docs/SkillSystemUserGuide.md)。

向 `Scenes/TestScene.tscn` 添加任何单位实例仍必须由使用者在 Godot 编辑器中手动完成。
