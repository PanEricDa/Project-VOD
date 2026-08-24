# HolyLight 战斗表现与动作策略修正设计

## 根因

- HolyLight 的实际 `resolved_target` 是友方，但施法期间的持续朝向仍可能被敌方战斗
  移动覆盖，因此视觉上像向敌人施法。
- `release_effect_scene` 目前统一生成在动作发射点，目标瞬发治疗特效没有目标锚点配置。
- `BASIC_ONLY` 没有阻止自动技能请求，枚举名称与运行语义不一致。
- `TestScene2` 中 Priest 实例保留了旧的 `combat_action_policy = 0` 覆盖，因此技能冷却
  期间会执行普通攻击。

## 修正

- SkillBase 增加通用 `release_effect_anchor`：
  `ACTION_ORIGIN / RESOLVED_TARGET / TARGET_POSITION`。
- HolyLight 选择 `RESOLVED_TARGET`；其他技能保持默认发射点。
- 行为状态机在技能动作期间保存技能目标，并持续优先面向该目标；动作终止时清理。
- `BASIC_ONLY` 完全禁止自动技能；另外两种策略维持其既有名称语义。
- TestScene2 中现有 Priest 实例恢复为
  `SKILL_ONLY_WITH_BASIC_WHEN_DISABLED`。

## 边界

- 不改变目标阵营筛选、治疗数值、技能冷却和敌方锁定。
- 不修改或添加 `Scenes/TestScene.tscn` 中的单位。
