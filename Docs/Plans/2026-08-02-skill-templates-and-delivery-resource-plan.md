# 技能模板与 Delivery 资源索引实施计划

## 目标

在不增加第二套技能脚本父类的前提下，以唯一的 `SkillBase.gd` 为运行骨架，建立两份面向编辑器的场景模板：

- `MeleeSkillTemplate.tscn`：近战技能的编辑入口；未来承载近战动作、命中窗口与专属 Hitbox 配置。
- `RangedSkillTemplate.tscn`：施法/远程技能的编辑入口；承载施法动作与 Delivery 配置。

`FireboltSkill` 与 `HolyLightSkill` 迁移为 `RangedSkillTemplate` 的继承场景。它们仍只维护自身场景内的技能数据与效果节点。

## Delivery 资源规则

1. 每个技能场景默认使用场景内嵌 Delivery 配置，避免“一个技能必须同时维护 `.tscn` 与 `.tres`”的负担。
2. `02-Delivery/Presets` 提供可选的共享 Delivery `.tres`：瞬发、追踪投射物、地面区域。
3. 这些外部资源必须由 `ResourceSaver` 保存、拥有有效 UID、能作为 `SkillDeliveryConfig` 的子类型被 Inspector Quick Load 检索。
4. 共享预设只适合确定要多技能共用的基础配置；单独技能应优先保持内嵌配置，避免意外联动修改。

## 迁移步骤

1. 新建 `00-Templates`，创建两个仅继承 `SkillBase.tscn` 的模板场景。
2. 将现有 Firebolt 与 HolyLight 改为继承 Ranged 模板，并保留它们各自的 Delivery、效果与数值。
3. 用 Godot `ResourceSaver` 创建三份 Delivery 预设并验证 UID、脚本类型与加载结果。
4. 增加契约测试，保证模板继承、现有技能迁移及外部资源索引不会回退。
5. 运行 SkillSystem 测试与 Godot 编辑器扫描。

## 暂缓内容

- 不在本次直接实现 Guardian 近战技能。
- 不修改既有普通攻击、武器 Hitbox 或 TestScene 单位实例。
- 近战专属动作、Hitbox 与命中载荷会在 `MeleeSkillTemplate` 稳定后，以共享攻击管线接入，避免把技能数据回填进武器数据。
