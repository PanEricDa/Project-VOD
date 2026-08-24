# 单位根节点配置与武器编辑器预览设计

## 目标

让设计师可以直接在单位根节点配置武器和阵型位置，并在编辑器中看到已配置武器的视觉模型，同时不改变运行时战斗装配流程。

## 设计

- `AIUnitBase` 根节点暴露唯一的 `starting_weapon: WeaponData`。
- `AllyBase2` 根节点暴露唯一的 `formation_position: FormationPositionData`。
- 子节点 `CombatSystem` 与 `BehaviorStateMachine` 不再向 Inspector 暴露重复配置；运行时由父节点把根节点配置转交给它们。
- `PlayerBase` 同样由根节点持有 `starting_weapon`，Hero 只需在根节点配置。
- 编辑器预览由独立的 `@tool` 预览逻辑执行：根据 `starting_weapon.visual_scene` 在 `WeaponSocket` 创建临时实例，预览节点不保存、不参与运行时。
- 预览只负责显示模型，不加载动画、不连接 Hitbox、不执行攻击逻辑。

## 边界

- 不修改 TestScene 中的单位实例。
- 不改变 WeaponData、攻击动画、Hitbox、AI 状态机的运行时接口。
- 没有 Visual 或 WeaponSocket 时只给出编辑器提示，运行时仍保持原有安全降级。
