# 动画驱动技能释放设计

## 目标

修正技能与角色动画之间的依赖方向。技能只描述施法数据，不保存、查找或反向访问具体
角色动画；角色动作控制器负责选择施法动画，动画方法轨道负责决定技能实际释放与动作
结束的时间点。

本设计只处理施法动作链路，不处理 HolyLight 的友方候选目标和非战斗自动施法问题。

## 最终数据流

```text
AI 决定使用当前 Skill
→ SkillHost 计算 effective_cast_time
→ SkillHost 发出通用 action_requested(skill, target, effective_cast_time)
→ AICombatSystem 选择当前角色可用的通用施法动画
→ 动画按传入的 effective_cast_time 缩放播放速度
→ 动画方法轨道调用 release_action()
→ SkillHost 释放当前活动 Skill
→ 动画方法轨道调用 finish_action()
→ SkillHost 结束当前动作占用
```

## 职责边界

### SkillBase

- 保留 `base_cast_time` 和 `get_effective_cast_time()`。
- 删除 `action_animation_name`。
- 不读取 AnimationPlayer、WeaponData 或角色 Visual。
- 不反向查询动画长度、事件轨道或播放速度。

### SkillHostComponent

- `action_requested` 只传递当前技能、目标和 `effective_cast_time`。
- `effective_cast_time` 必须在请求发出前计算完成。
- 不允许动画控制器在回调时重新访问 SkillHost 或 SkillBase 获取施法时间。

### AICombatSystem / AIAttackController

- 接收 `effective_cast_time` 数据并选择通用施法动作。
- 第一版按固定名称顺序解析：
  1. `weapon/basic_cast_1`
  2. `character/basic_cast_1`
- 动画必须恰好包含一个 `release_action()` 方法标记。
- `effective_cast_time` 必须是有限且非负的数值。
- 播放速度只根据“动画内 release 标记时间 ÷ 传入 effective_cast_time”计算。
- 请求失败时返回 `false` 并输出包含失败原因的错误，不静默回访 Skill 或单位字段。

### CharacterAnimationEventPlayer

- `release_action()` 只发送通用释放信号。
- `finish_action()` 只发送通用动作结束信号。
- 不持有 Skill、SkillHost 或施法时间。

## 动画契约

通用施法动画名称为 `basic_cast_1`，由当前角色或当前武器的 AnimationLibrary 提供。

每个施法动画必须包含：

- 恰好一个 `release_action()`：决定技能实际交付时间点。
- 可选的 `finish_action()`：提前结束逻辑占用；缺少时由动画自然结束回收。

角色专用动画可以覆盖通用动作，但技能场景本身不记录覆盖路径。

## 失败规则

- 找不到通用施法动画：动作请求失败并报错。
- `effective_cast_time` 非有限数或小于零：动作请求失败并报错。
- 动画没有或拥有多个 `release_action()`：动作请求失败并报错。
- 回访时不存在活动技能：SkillHost 返回失败，动作控制器取消当前动作并报错。

## 验证

- Firebolt 与 HolyLight 的 Skill 场景不再保存动画名称。
- Staff 的 `basic_cast_1` 配置正确事件轨道后可以驱动 HolyLight。
- Caster 不依赖 `character/firebolt_cast` 才能释放 Firebolt。
- 动画控制器只使用请求参数中的 `effective_cast_time`。
- 失败路径有明确错误信息。
- 不修改 `Scenes/TestScene.tscn` 或其中的单位实例。

