# AI 索敌调试范围圈设计

## 目标

为通用 `AITargetingComponent` 增加可开关的运行时调试范围圈，让设计者能够直接观察首次索敌范围以及当前是否已经锁定目标。

## 节点与职责

- 调试范围圈属于 `AITargetingComponent.tscn`，所有继承 `AllyBase2` 的单位自动获得。
- 范围圈只负责显示，不参与碰撞、重叠检测、目标筛选或行为决策。
- 不修改 `TestScene2.tscn` 中的任何单位实例。

## Inspector 配置

每个 `AllyBase2` 单位的根节点增加唯一的索敌距离参数：

```gdscript
@export_range(0.1, 100.0, 0.1, "or_greater")
var targeting_radius: float = 6.0
```

内部 `AITargetingComponent` 增加调试显示开关：

```gdscript
@export var debug_range_visible: bool = true
```

- 每个继承单位可以在根节点独立覆盖 `targeting_radius`。
- 首次索敌半径等于 `targeting_radius`。
- 目标保持半径由系统固定计算为 `targeting_radius + 1.0m`，不提供第二个 Inspector 参数。
- 开启：显示范围圈。
- 关闭：完全隐藏范围圈。
- 默认开启，便于当前开发阶段调试；正式发布前可以在父场景统一关闭。

## 显示规则

- 圆圈半径读取持有单位的 `targeting_radius`，默认 `6m`。
- Inspector 或运行时修改索敌半径后，圆圈尺寸自动同步。
- 没有锁定目标时使用浅灰色半透明细线。
- 锁定有效目标时切换为橙红色半透明细线。
- 圆圈位于单位脚底附近并略高于地面，避免深度冲突闪烁。
- 范围圈不投射阴影，也不影响物理查询。

## 数据流

1. `AllyBase2` 把该单位的 `targeting_radius` 传给 `AITargetingComponent`。
2. 组件将首次索敌半径设为该值，并将保持半径固定计算为该值加 `1m`。
3. `AITargetingComponent` 同步当前索敌半径和调试开关。
4. `locked_target_changed` 对应的内部目标切换更新范围圈颜色。
5. 关闭调试显示时，后续锁敌仍正常运行，只是不再显示范围圈。

## 验证

- Amy 继承后无需额外装配即可显示范围圈。
- Amy 能在根节点独立覆盖 `targeting_radius`，且不会影响其他伙伴单位。
- 圆圈直径与 `targeting_radius × 2` 一致。
- 保持半径始终等于 `targeting_radius + 1.0m`。
- 锁定前为浅灰色，锁定后为橙红色，解除锁定后恢复浅灰色。
- Inspector 关闭开关后范围圈隐藏，但 Amy 仍可持续索敌。
- Godot 4.7 脚本编译、自动测试与运行输出无新增错误或警告。
