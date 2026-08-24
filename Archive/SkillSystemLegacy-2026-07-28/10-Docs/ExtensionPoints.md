# Extension Points

新功能应继承对应 Base，而不是修改 SkillBase 或 BasicDeliveryAgent 的职责边界。

## Conditions

继承 `SkillConditionBase`，实现：

```gdscript
func evaluate(context) -> bool
func get_failure_reason(context) -> StringName
```

## Targeting

继承 `SkillTargetSelectorBase`，实现 `resolve_target(context) -> bool`，并把结果写入
`context.resolved_target` 和 `context.target_position`。

## Decisions

继承 `SkillDecisionPolicyBase`，实现：

```gdscript
func get_decision_delay(context, random_generator) -> float
```

Resource 不得保存随机运行状态。

## Costs

继承 `SkillCostBase`，实现 `can_pay`、`commit`、`refund` 和失败原因。Delivery
启动被拒绝时，SkillBase 会对已提交费用调用一次 refund。

## Trajectories

继承 `SkillTrajectoryBase`，实现持续时间和 `sample_transform`。抛物线、追踪或回旋
路径都属于这里，不应写进 SkillBase。

## Collisions

继承 `SkillCollisionPolicyBase`，每个物理帧返回 null 或 SkillDeliveryResult。ShapeCast、
环境碰撞和穿透属于 CollisionPolicy。

## Impact Selectors

继承 `SkillImpactSelectorBase`，根据 Result 返回实际目标数组。单体、碰撞点范围、
目标扩散、地面范围和链式选择都属于这里。

## Payloads

继承 `SkillPayloadBase`，实现：

```gdscript
func apply(context, result, target) -> bool
```

Payload 只改变 Gameplay 数据，不控制弹道、冷却或表现。

## Presentation

继承 `SkillPresentationBase` 或直接配置 SceneSkillPresentation。表现失败不得改变技能
命中与数值结果。音效可以作为表现场景中的 AudioStreamPlayer3D 一并管理。
