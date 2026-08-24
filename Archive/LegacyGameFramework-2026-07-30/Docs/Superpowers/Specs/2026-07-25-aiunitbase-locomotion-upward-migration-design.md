# AIUnitBase Locomotion 上移设计

## 目标

将当前 `LocomotionComponent` 的通用 AI 运动执行能力完整上移到 `AIUnitBase`，减少一个场景节点和一层组件装配，同时保持 AllyBase2 与 EnemyBase2 当前运行行为不变。

本阶段只迁移 Locomotion，不实施 Formation/Combat 状态机重构。

## 最终继承关系

```text
UnitBase
├── PlayerBase
└── AIUnitBase
    ├── AllyBase2
    └── EnemyBase2
```

`PlayerBase` 不继承任何 AI 运动内容。

## 节点结构

迁移前：

```text
AIUnitBase
├── Visual
├── CollisionShape3D
└── MovementSystem
    ├── NavigationAgent3D
    └── LocomotionComponent
```

迁移后：

```text
AIUnitBase
├── Visual
├── CollisionShape3D
└── MovementSystem
    └── NavigationAgent3D
```

暂时保留 `MovementSystem`，因为现有 `AllyBase2` 的 `FormationComponent` 仍位于该节点下。等 Formation/Combat 状态机重构时再统一判断是否需要继续保留这一层。

## AIUnitBase 职责

`AIUnitBase.gd` 接收原 `LocomotionComponent.gd` 的以下内容：

- 移动速度、加速度、减速距离和到达距离。
- NavigationAgent3D 路径读取。
- 持续移动目标与临时最大速度。
- 视觉朝向插值。
- 重力和稳定贴地。
- 冲刺、冲刺冷却及冲刺恢复。
- 唯一的水平速度写入和 `move_and_slide()` 调用。

固定物理顺序保持为：

```text
子类提交本帧 AI 移动意图
→ 更新冲刺冷却
→ 执行普通移动、冲刺或恢复
→ 应用重力
→ 更新 Visual 朝向
→ move_and_slide()
```

## 子类行为接口

保留现有模板入口：

```gdscript
func _update_ai_movement(delta: float) -> void
```

- `AIUnitBase` 默认实现清除移动目标，使没有行为的 EnemyBase2 平滑停下但仍受重力影响。
- `AllyBase2` 继续在该入口调用现有 FormationComponent。
- 下一阶段再将该入口改造成统一 Formation/Combat 状态机，不在本次迁移中提前改变。

## 运动公共接口

以下接口从 `LocomotionComponent` 原样迁移到 `AIUnitBase`：

```gdscript
func set_movement_target(
    target_position: Vector3,
    maximum_speed: float = -1.0
) -> void

func clear_movement_target() -> void
func has_movement_target() -> bool
func set_desired_facing(direction: Vector3) -> void
func request_dash(target_position: Vector3) -> bool
func can_dash() -> bool
func is_dashing() -> bool
func is_recovering() -> bool
func get_dash_cooldown_remaining() -> float
```

删除 `get_locomotion_component()`，因为 AIUnitBase 本身就是运动接口持有者。

## FormationComponent 过渡适配

本阶段不迁移 Formation 算法，仅进行最小适配：

- `_owner_body` 类型收紧为 `AIUnitBase`。
- 删除独立 `_locomotion: LocomotionComponent` 引用。
- `configure()` 只接收 `owner_body: AIUnitBase`。
- 原来对 `_locomotion` 的调用改为调用 `_owner_body` 的同名运动接口。

`AllyBase2` 改为：

```gdscript
_formation_component.configure(self)
```

这样 FormationComponent 的行为保持不变，并为下一阶段整体吸收进 Ally 状态机做好准备。

## 删除内容

迁移和验证完成后删除：

```text
UnitSystem/Components/Movement/LocomotionComponent.gd
UnitSystem/Components/Movement/LocomotionComponent.tscn
```

同时删除 AIUnitBase 场景中的 `LocomotionComponent` 实例及其外部资源引用。

## 安全边界

- 不修改索敌、锁定、范围圈或 TargetSelectionPolicy。
- 不修改 Formation 的站位、游荡、冲刺决策或默认参数。
- 不修改 EnemyBase2 的当前空行为。
- 不修改 PlayerBase。
- 不修改 TestScene 或 TestScene2 的任何单位实例。
- 所有导出运动参数保持现有默认值。
- 所有字段和方法使用英文标识，新增或迁移代码保留详细简体中文注释。

## 验证

- AIUnitBase 场景不再包含 LocomotionComponent 节点。
- AIUnitBase 根节点直接显示 Movement、Dash、Facing、Physics 参数。
- AllyBase2 仍可编队游荡、归队、冲刺、转向并受重力影响。
- EnemyBase2 没有移动目标时平滑停下并受重力影响。
- FormationComponent 只依赖 AIUnitBase 的公开运动接口。
- Amy 改名继承场景仍可正常加载。
- 索敌及调试范围圈行为不受影响。
- 全部 UnitSystem 测试、Godot 4.7 编辑器扫描和主场景启动通过。
