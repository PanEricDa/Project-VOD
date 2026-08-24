# 仇恨调试显示设计

## 目标

为每个 EnemyBase 提供仅用于测试的世界空间仇恨表显示，便于直接观察当前锁定目标、各单位仇恨值及排序。

## 边界

- 新组件只订阅 `ThreatComponent.threat_changed` 与 `AITargetingComponent.locked_target_changed`。
- 新组件维护一份仅用于显示的事件缓存；不计算、不提交、也不修改任何仇恨值。
- 不修改仇恨结算、目标选择、行为状态机、伤害结算或 TestScene 中的单位实例。
- 删除该组件或关闭其 Inspector 开关后，战斗行为必须与添加前完全一致。

## 显示规则

- 没有任何正仇恨时隐藏。
- 显示当前锁定目标及其数值，并以 `>` 标记表内锁定目标。
- 按数值由高到低显示最多四项。
- Label3D 位于敌人头顶、始终面向镜头，仅承担调试阅读用途。

## 接入方式

`ThreatDebugDisplay.tscn` 作为 `EnemyBase` 的直接子节点；它按固定同级节点名读取 `ThreatComponent` 与 `AITargetingComponent`。这不是核心模块之间的新依赖，而是可随时移除的调试观察器。
