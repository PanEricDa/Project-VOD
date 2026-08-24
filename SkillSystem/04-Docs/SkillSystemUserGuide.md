# 单场景技能系统使用指南

## 1. 核心概念

每个技能只维护一个场景。技能的名称、索敌关系、施法距离、施法时间、冷却、
AI 使用参数、表现和交付方式都在该场景的 `SkillBase` 根节点配置。

角色只负责：

- 通过 `SkillHostComponent` 装载与请求技能；
- 播放角色施法动画；
- 在动画关键帧调用 `release_action()` 和 `finish_action()`。

技能负责验证目标、交付表现和启动技能冷却。投射物负责自己的飞行、碰撞、
范围、命中和命中特效。

## 2. 文件位置

```text
SkillSystem/
├── 00-Skills/       具体技能场景
├── 01-Core/         SkillBase、SkillHost、Context
├── 02-Delivery/     交付配置与执行器
├── 03-Extensions/   可选条件、消耗、效果
├── 04-Docs/         使用说明
└── 05-Tests/        自动测试
```

技能本身的美术特效继续放在 `Effects/Skills`，投射物继续放在
`Item/Projectiles`，角色施法动画由对应角色 Visual 维护。

## 3. 新建技能的标准流程

1. 在 `00-Skills` 下创建技能文件夹。
2. 继承 `01-Core/SkillBase.tscn`。
3. 保存为唯一需要人工维护的 `SkillNameSkill.tscn`。
4. 在根节点 Inspector 依次配置：
   - `Identity`：ID、显示名、图标、AI 优先级；
   - `Targeting`：目标来源、关系、施法距离、释放时复验；
   - `Casting`：角色动作名、基础施法时间、移动和转向许可；
   - `Cooldown`：技能独立冷却；
   - `AI Usage`：自动施法与随机决策延迟；
   - `Presentation`：施法、释放、取消特效；
   - `Delivery`：内嵌交付配置。
5. 在 `Delivery` 字段选择合适类型：
   - `TrackingProjectileDeliveryConfig`：生成并追踪目标的投射物；
   - `InstantTargetDeliveryConfig`：直接对目标交付效果；
   - `GroundAreaDeliveryConfig`：在目标位置生成地面区域。
6. 只有技能确实需要特殊规则时，才在根节点下添加
   `SkillConditionBase`、`SkillCostBase` 或 `SkillEffectBase` 子组件。
7. 将技能场景实例拖入单位的 `SkillHost/SkillSocket`。
8. 在该角色的 `CharacterAnimationPlayer` 中制作与
   `action_animation_name` 同名的动画：
   - 唯一一个 `release_action()`：实际交付技能；
   - 一个 `finish_action()`：结束角色动作占用。
9. 运行对应装配测试与运行测试。

## 4. 施法时间与动画

`base_cast_time` 是技能数据，角色还可以通过公开接口提供施法速度倍率。
系统读取动画中的唯一 `release_action()` 时间点，并自动缩放播放速度，使该
关键帧对齐有效施法时间。`base_cast_time = 0` 时，释放关键帧也必须位于 `0`。

动画方法轨道应指向 `CharacterAnimationPlayer`。动画只操作角色 Visual 内部
节点，不应直接移动 Unit 根节点或投射物世界坐标。

## 5. 两个初始示例

### Firebolt

`00-Skills/Firebolt/FireboltSkill.tscn`

- 敌方指定目标；
- `character/firebolt_cast`；
- 0.75 秒基础施法时间；
- 内嵌追踪投射物配置；
- 复用 `Item/Projectiles/FireBall.tscn`；
- 投射物自行管理飞行、碰撞、爆炸和命中。

### HolyLight

`00-Skills/HolyLight/HolyLightSkill.tscn`

- 自动选择候选列表中生命比例最低的友方；
- 内嵌目标瞬发配置；
- `HealthChangeSkillEffect` 直接子节点恢复 25 点生命；
- 释放表现使用金白色 HolyLight 特效。

## 6. 注意事项

- 不再为每个技能维护独立 Definition `.tres` 和 Delivery `.tscn`。
- `DeliveryConfig` 应保存在技能场景内部，不要另存为第二份人工配置资产。
- 投射物发射必须使用动作控制器提供的最新世界 `Transform3D`，不得从技能
  本地坐标推导，否则会再次出现从世界原点发射的问题。
- 技能冷却只在成功交付后启动；配置错误、目标失效或效果接口缺失默认不进入冷却。
- AI 的普通攻击与技能共用角色层共享动作冷却；技能自身冷却独立计时。
- 正式 `.tres`、`.res` 必须通过 Godot `ResourceSaver` 保存并验证有效 UID。
- 添加单位到 `TestScene.tscn` 必须由使用者手动完成。
