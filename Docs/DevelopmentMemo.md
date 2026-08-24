# 当前框架开发备忘

更新日期：2026-07-30

## 不可破坏的项目规则

- 不得由 Codex 自动向 `Scenes/TestScene.tscn` 或 `Scenes/TestScene2.tscn` 添加、删除或替换单位实例。
- 正式 `.tres/.res` 不能只靠文本写入完成，必须由 Godot 正式保存并登记有效 UID。
- 强类型 Resource 必须能被 Inspector 的 Quick Load 按正确类型找到。
- `Archive` 内所有内容只供历史参考，活动场景、脚本、资源和测试不得引用 `res://Archive`。

## 当前职责边界

| 内容 | 责任 |
|---|---|
| UnitBase | 生命、阵营、队伍、可锁定、Visual 插槽、SkillHost |
| PlayerBase | 玩家输入、移动、冲刺、玩家锁敌和普通攻击入口 |
| AIUnitBase | 导航、移动、冲刺、朝向、AI 武器装配基础 |
| AllyBehaviorStateMachine | 阵型、战斗、技能接近、脱战和动作仲裁 |
| AITargetingComponent | 感知候选和持续敌方锁定 |
| CombatSystem | 武器普通攻击、动画事件、Hitbox/Projectile、公共动作冷却 |
| SkillHostComponent | 技能装载、请求、自动延迟、活动技能和共享动作接口 |
| SkillBase | 一项技能的目标规则、施法、冷却、表现和 Delivery 配置 |
| WeaponData | 武器视觉、动画库、攻击距离和交付所需静态数据 |
| Projectile | 飞行、碰撞、命中规则和命中特效 |
| Effects | 卡刀、震动和技能表现，不承担目标或伤害决策 |

## 目标概念

- `AITargetingComponent.locked_target` 是持续维护的敌方战斗目标。
- `SkillContext.resolved_target` 是一次技能请求临时解析出的作用目标。
- 治疗友方或对自己施法不能覆盖敌方战斗锁定。
- 状态机消费 TargetingComponent 的锁定结果，不另建第二套敌方锁定状态。

技能目标只配置：

- Target Relations
- Target Selection Mode
- Require Targetable
- Require Alive
- Cast Range

不要重新引入重复的 Target Source 或每技能目标 Policy Resource。

## 动画事件

- 玩家和 AI 可以复用相同角色 AnimationLibrary，但各自控制器独立处理输入或 AI 决策。
- `release_action()` 和 `finish_action()` 由角色动画方法轨道触发。
- 远程普通攻击使用 projectile release 事件。
- 近战攻击使用 hit window open/close 事件。
- 动画可以移动 Visual；真实 CharacterBody3D 位移由单位控制器执行。
- AI 当前不执行武器数据中的攻击前移，但动画事件仍照常发出。

## Hitbox 与 DebugBox

- Hitbox 使用攻击拥有者的当前世界 Transform，不能依赖玩家节点或世界原点。
- 开窗前必须先完成 Transform 同步，再显示 DebugBox 和执行检测。
- 关闭窗口后清空单窗口命中记录并隐藏 DebugBox。
- DebugBox 只用于调试，必须可关闭。
- 修改武器 Hitbox 数组后，应检查每段数组索引与 `basic_attack_N` 是否一致。

## 外部 Resource 规则

创建或移动 `.tres/.res` 后验证：

```gdscript
ResourceLoader.get_resource_uid(resource_path) != ResourceUID.INVALID_ID
```

测试资源契约时跳过 `Archive`。归档内旧资源会保留失效路径，不应为了让审计通过而重新生成 UID。

创建阵型、武器或其他强类型 `.tres` 时，必须使用其正确脚本类型保存；不要再次创建“能 load 但没有 UID、Quick Load 找不到”的文本资源。

## 当前已知维护项

- 三个测试仍引用已经不存在的 Amy 场景，需要单独选择当前测试夹具后修正。
- UnitDirectoryLayoutTest 的 TestScene2 单位数量和坐标断言已经过时。
- 部分武器测试仍断言旧资产默认值。
- HolyLight 的部分目标/治疗测试期望与当前实例配置需要单独核对。
- AICombatSystemTest 的反馈默认值和当前资源存在差异。
- RangedAttackPipelineTest 当前不是可直接作为 SceneTree/MainLoop 启动的测试。

这些问题不能通过恢复旧框架解决，也不能通过把当前测试移入 Archive 隐藏。

## 归档删除前

永久删除任何 Archive 前必须重新执行：

1. `LegacyFrameworkArchiveContractTest`
2. `ResourceUidAuditTest`
3. UnitSystem 与 SkillSystem 当前测试
4. Godot 4.7 headless 编辑器扫描
5. TestScene2 运行与人工体验测试

删除归档是用户决定，不属于本次整理的自动操作。
