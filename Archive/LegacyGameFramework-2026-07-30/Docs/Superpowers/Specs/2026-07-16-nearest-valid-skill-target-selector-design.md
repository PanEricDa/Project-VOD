# 最近合法技能目标选择器设计

## 目标

为独立技能系统增加可复用的最近合法目标选择器。选择器依据技能 Definition 已有的目标关系、可选中要求和施法范围寻找目标，不写死友方、敌方或 HolyLight 专属规则。

## 类型约束

`IndependentSkillDefinition` 的策略字段使用对应抽象基类作为静态类型。Inspector 中 `target_selector` 只能接受 `IndependentSkillTargetSelectorBase` 及其派生 Resource；条件、决策、消耗和施法表现槽位同步采用各自的抽象基类类型。

## 统一验证

单次请求上下文保存目标关系、可选中要求、施法范围和容差的快照。`IndependentSkillTargetSelectorBase` 提供统一的候选合法性判断：检查节点有效性、是否在场景树内、SELF/FRIENDLY/HOSTILE/NEUTRAL/ANY 关系、`targetable` 和可选的水平距离。

搜索选择器和 `SkillBase` 的最终验证调用同一接口。搜索阶段用于跳过不合格候选并继续查找；施法前复验用于处理目标删除、阵营变化或离开范围。

## 最近合法目标选择器

新增 `NearestValidTargetSelector.gd`。它遍历当前场景树中带有直接子节点 `FactionComponent` 的 `Node3D`，按上下文中的 Definition 规则过滤，并选出水平距离最近的目标。

选择器只增加一个策略参数：

```gdscript
@export var exclude_caster: bool = true
```

该参数与阵营关系独立，因为 FRIENDLY 表示同队并天然包含施法者自己。

## HolyLight 装配

`HolyLightSkillDefinition.tres` 将 `target_selector` 从 `ProvidedTargetSelector` 替换为 `NearestValidTargetSelector`，并保持 `target_relation = FRIENDLY`。`exclude_caster = true`，因此测试阶段会选择施法范围内最近的其他友方单位，不检查当前生命值。

## 范围与暂缓内容

- 本次不实现自动请求组件。
- 本次不修改 `FactionComponent` 或建立目标注册表。
- 本次不修改 AllyBase、Healer 源场景或 TestScene。
- 未来目标数量增大时，可以把场景树查询替换为注册表，不改变选择器接口和技能配置。

