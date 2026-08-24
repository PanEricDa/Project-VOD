# Skill System Architecture

## 依赖方向

```text
Actor Adapter
  -> SkillHostComponent
  -> SkillBase
  -> SkillDefinition strategies
  -> SkillDeliveryAgent
  -> Trajectory / Collision / Impact / Payload / Presentation
```

任何下层模块都不得反向读取上层内部状态。

## Host 生命周期

Host 只扫描 `SkillSocket` 的直接子节点。它为每个 Skill 注入施法者，维护唯一活动
槽和独立公共冷却。Host 不移动角色：超出射程时发送 `approach_requested`，需要
朝向时发送 `facing_requested`，施法禁止移动时发送 `movement_lock_requested`。

公共冷却从 `cast_started` 开始。Delivery 成功启动后活动槽立即释放，不等待命中。

## Skill 生命周期

```text
READY
-> DECISION_WAIT（仅 AI）
-> QUEUED
-> CASTING
-> Delivery 启动
-> COOLDOWN
-> READY
```

请求时检查目标、阵营关系、条件和费用可用性；施法完成时再次检查，并使用 X/Z
水平距离验证射程。只有 Delivery 接受启动后才默认开始技能冷却。

## Delivery 生命周期

```text
IDLE -> TRAVELLING -> IMPACTED
                   -> CANCELLED
```

Agent 被添加到 `delivery_parent`，然后使用 Skill 的 DeliverySocket 世界变换启动。
它不作为施法者子节点，因此不会被角色后续移动拖动。Trajectory 决定路径，
CollisionPolicy 产生结果，ImpactSelector 选择目标，Payload 依序应用效果。

`DirectTrajectory.travel_duration = 0` 会在启动流程内立即到达；大于 0 时按直线
插值。当前 ArrivalCollisionPolicy 不查询物理世界。

## 运行数据所有权

SkillContext、技能计时和 Agent 计时均属于单次运行实例。所有策略 Resource 必须
保持无状态，才能安全地被多个技能与投射物共享。

## AllyBase 安全适配层

AllyBase 根节点包含本地 `SkillHostComponent/SkillSocket`，避免继承职业为了向外部
PackedScene 实例内部添加技能而启用 Editable Children。初始化时执行：

```gdscript
skill_host.configure_owner(self, get_tree().current_scene)
```

适配层只提供显式请求转发，并同步新旧系统的公共冷却启动事件与 CASTING 动作互斥。
它不会自动选择目标、请求技能、接近目标、改变朝向或锁定移动。HolyLight 的最低
生命友军选择和自动施法仍属于后续目标选择/AI 适配阶段。
