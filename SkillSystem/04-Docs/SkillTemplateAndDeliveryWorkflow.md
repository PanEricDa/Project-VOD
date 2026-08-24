# 技能模板与 Delivery 配置流程

## 选择模板

新建技能时，只从两份场景模板中选择一份继承：

1. `res://SkillSystem/00-Templates/MeleeSkillTemplate.tscn`：近战技能。后续在此模板下配置近战动作、命中窗口和 Hitbox。
2. `res://SkillSystem/00-Templates/RangedSkillTemplate.tscn`：施法与远程技能。投射物、瞬发治疗、弓弩发射、地面区域都属于这一类。

两者都使用唯一的 `SkillBase.gd`。模板只区分编辑入口与未来组件组合，不产生第二套运行逻辑。

## 每个技能的最短配置

1. 在 `res://SkillSystem/00-Skills` 下创建技能文件夹。
2. 继承正确模板并保存为 `技能名Skill.tscn`。
3. 在根节点 Inspector 配置 ID、目标关系、目标策略、施法距离、施法时间、冷却和 AI 优先级。
4. 在根节点的 `Delivery` 字段新建一个内嵌的强类型配置；这是默认方式。
5. 添加直接子节点 Effect（伤害、治疗、属性修改等）。
6. 在角色施法动画的 Method Track 中调用 `release_action()` 和 `finish_action()`。
7. 将技能场景实例放入单位的 `SkillHost/SkillSocket`。

## AI 技能等待与冷却

- AI 首次发现一个可用且进入施法距离的技能时，会立刻请求角色施法动作；不会在动作前随机等待。
- 技能在动画 `release_action()` 成功启动 Delivery 后，才按根节点 `AI Usage` 中的常规等待区间随机一次；低概率额外犹豫会叠加在这段等待上。
- 释放后等待结束，才开始计算 `Skill Cooldown`。因此单次技能的实际重复间隔为“释放后等待 + 技能冷却”。
- 释放后等待只禁止同一技能再次请求，不会占用单位公共冷却；具备普攻的单位可在公共冷却结束后继续普攻。
- 任何在成功交付前取消或失败的技能都不会进入释放后等待；Delivery 启动失败是否进入冷却仍由 `Cooldown On Failed Release` 决定。

一个独立技能默认只维护这一个 `.tscn`；不需要额外创建 Definition `.tres`。

## Delivery 的三种类型

- `TrackingProjectileDeliveryConfig`：生成投射物，投射物处理轨迹、碰撞、命中与命中表现。
- `InstantTargetDeliveryConfig`：直接向当前有效目标交付 Effect；治疗和单体 Buff 的常用选择。
- `GroundAreaDeliveryConfig`：在指定地面位置生成区域交付物。

## 可选共享 Delivery 预设

以下资源位于 `res://SkillSystem/02-Delivery/Presets`：

- `InstantTargetDelivery.tres`
- `TrackingProjectileDelivery.tres`
- `GroundAreaDelivery.tres`

它们已经通过 `ResourceSaver` 创建、写入 UID 并通过独立 UID 契约测试。只有确定多项技能要共用同一份 Delivery 基础配置时，才在 `Delivery` 字段使用 Quick Load 选择它们。若某技能要单独调速度、半径或投射物场景，应继续使用内嵌配置，避免修改一个预设连带改变所有技能。

## 资源索引维护

新建或重建共享 Delivery 预设时，执行：

1. `CreateDeliveryPresets.gd`，通过 Godot `ResourceSaver` 保存资源；
2. 刷新 Godot 编辑器文件系统；
3. 运行 `DeliveryResourceIndexTest.gd`。

最后一步会验证每个 `.tres` 都有有效 UID，且加载类型属于 `SkillDeliveryConfig`。只有此测试通过，Inspector 的强类型 Quick Load 才可视为可靠。
