# 敌人待机行为设计

## 目标

为 `EnemyBehaviorStateMachine` 的 `IDLE` 状态增加可配置的待机方式，使敌人可选择原地驻守或围绕出生点小范围游荡，同时不影响现有索敌、追击、攻击、战斗游荡和脱战归位逻辑。

## Inspector 配置

在 `EnemyBehaviorStateMachine` 的 `Idle Behavior` 分类中提供：

```gdscript
enum IdleBehavior {
    STATIONARY,
    WANDER_AROUND_HOME,
}
```

- `idle_behavior`：待机模式；默认 `WANDER_AROUND_HOME`。
- `idle_wander_radius`：游荡点相对出生点的最大水平半径，默认 `0.8m`。
- `idle_wander_interval_min`：抵达或等待后重新选择游荡点的最短间隔，默认 `1.5s`。
- `idle_wander_interval_max`：重新选择游荡点的最长间隔，默认 `3.0s`。
- `idle_wander_speed_multiplier`：游荡速度相对 `AIUnitBase.movement_speed` 的倍率，默认 `0.35`。

所有可配置字段紧邻简体中文说明，明确单位、默认行为与作用范围。

## 行为规则

```text
IDLE + STATIONARY
  清除移动目标；继续由 AITargetingComponent 扫描。

IDLE + WANDER_AROUND_HOME
  在出生点半径内选择随机目标点；低速移动；抵达后等待随机间隔再选点。

获得有效锁定目标
  无条件清除待机游荡目标；本帧切入 CHASE。

RETURN_HOME 抵达出生点
  恢复索敌；切回 IDLE；按当前 idle_behavior 执行。
```

## 与现有行为的边界

- 待机游荡只在 `IDLE` 执行。
- 现有 `ATTACK` 状态的目标周围战斗游荡保持不变，使用独立的状态、计时器和候选点。
- `CHASE`、`ATTACK`、`RETURN_HOME` 进入时均清除待机游荡的运行时目标，避免两个游荡逻辑竞争 `AIUnitBase` 的移动请求。
- 出生点仍只在敌人配置时或复活时记录；待机游荡不会改变出生点，也不会越过 `leash_distance`。

## 测试范围

- 静止模式在 IDLE 不提交移动目标。
- 游荡模式提交的目标始终位于出生点半径内，且速度使用倍率。
- 间隔未到前抵达目标不会立即重选。
- 获得目标、进入追击、攻击、归位或死亡时清除待机移动。
- 归位完成后恢复已选的待机模式。
- 既有战斗游荡测试与编辑器扫描继续通过。

## 实施验证（2026-08-01）

- 已实现 `STATIONARY` 与 `WANDER_AROUND_HOME` 两种待机模式，默认使用出生点游荡。
- 游荡参数默认值为：半径 `0.8m`、等待间隔 `1.5–3.0s`、速度倍率 `0.35`。
- 待机游荡在进入追击、攻击、归位、死亡或复活时会清理，不会与现有战斗游荡竞争移动目标。
- 已通过 `EnemyBehaviorStateMachineTest`、`AITargetingComponentTest`、`AICombatInheritanceTest`、`UnitDirectoryLayoutTest`、Godot headless 编辑器扫描；MCP 编辑器错误数为零。
