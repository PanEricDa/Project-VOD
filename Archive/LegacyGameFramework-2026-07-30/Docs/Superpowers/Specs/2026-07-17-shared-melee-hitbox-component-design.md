# 角色共享近战 Hitbox 组件设计备档

## 状态

已确认设计，尚未实施。

本备档只记录后续迁移方向，不修改当前玩家、Ally、普通攻击模块或 SkillSystem
的运行行为。

## 设计目标

项目采用粗粒度近战判定：攻击有效期间检测角色正前方的一块 BoxShape3D 范围，
不追踪剑刃轨迹，也不为短剑、重剑、盾牌等武器分别建立精细碰撞轨迹。

主要目标：

- 在角色源场景中直接看到并调整 Hitbox 的位置与尺寸；
- 武器场景只负责视觉，不保存攻击逻辑或判定盒；
- 普攻与主动技能统一由 SkillSystem 调度；
- Hitbox 查询、技能时序和 Gameplay 结果保持解耦；
- 复用当前玩家与 AI 已验证过的盒体检测、目标过滤和单轮去重逻辑。

## 推荐节点结构

```text
AllyBase / Hero
├── CombatComponents
│   └── MeleeHitboxComponent
│       ├── HitboxShapeCast
│       └── DebugHitbox
├── WeaponSocket
│   └── WeaponVisual
├── ActionAnimationController
└── SkillHostComponent
    └── SkillSocket
```

`MeleeHitboxComponent` 是角色永久装配的通用战斗能力组件。它与
`HealthComponent` 类似，不包含 Warrior、Guardian 或具体武器知识。

## 职责边界

### MeleeHitboxComponent

- 保存角色默认近战盒体的位置、尺寸和目标过滤配置；
- 在编辑器与运行时提供可选 DebugHitbox；
- 在有效窗口内执行 ShapeCast3D 查询；
- 排除持有者；
- 过滤碰撞层、阵营或目标分组；
- 同一检测窗口内对同一目标只报告一次；
- 通过通用信号报告命中目标、位置和方向。

预期最小接口：

```gdscript
signal hit_detected(
    target: CharacterBody3D,
    hit_position: Vector3,
    hit_direction: Vector3
)

func begin_detection(context: RefCounted) -> bool
func end_detection() -> void
func is_detecting() -> bool
```

### SkillSystem

- SkillDefinition 保存施法距离、施法时间、技能冷却和目标关系；
- SkillHost 统一仲裁普攻与技能，并维护唯一公共冷却；
- 近战技能决定前摇、有效窗口和恢复时间；
- 技能通过动作 ID 请求角色播放对应动画；
- Delivery 将 HitboxComponent 的命中结果转换成 SkillDeliveryResult；
- ImpactSelector 与 Payload 决定受影响目标和最终 Gameplay 结果。

### WeaponVisual

- 只保存 Mesh、材质、握持偏移和表现挂点；
- 不保存 Hitbox、冷却、攻击距离、伤害或技能状态；
- 更换武器视觉不直接修改角色的默认近战判定范围。

### ActionAnimationController

- 接收技能发送的动作 ID；
- 播放角色身体与 WeaponSocket 的表现动画；
- 动画缺失时不得阻止技能和命中流程安全结束；
- 动画只负责表现，不作为伤害结果的权威来源。

## 运行流程

```text
SkillHost 允许近战技能开始
→ 技能请求播放攻击动作
→ 等待前摇
→ Delivery 调用 MeleeHitboxComponent.begin_detection()
→ HitboxComponent 在有效窗口内检测并去重
→ Delivery 将命中转换为 Impact/Payload
→ 有效窗口结束并调用 end_detection()
→ 技能进入独立冷却；公共冷却继续由 SkillHost 管理
```

## 第一版范围

- 每个角色只有一个共享的默认近战 Hitbox；
- 使用 BoxShape3D 与 ShapeCast3D；
- Hitbox 固定在角色正前方，不跟随武器轨迹；
- 不按武器类别创建不同 Hitbox；
- 不制作自定义编辑器插件；
- 不迁移玩家攻击或现有 AI 普攻，直到后续实施计划获得确认；
- 不修改 `Scenes/TestScene.tscn`。

## 预留扩展

未来只有实际玩法需要时，才允许技能传入可选的盒体尺寸或偏移覆盖。默认情况下
所有近战技能继续使用角色组件中的 Inspector 配置，避免过早增加配置层级。

## 后续实施原则

实施时应先为共享组件和 SkillSystem 适配增加自动测试，再逐个迁移单位。迁移期间
旧普通攻击模块继续工作，确认新路径稳定后再删除旧的镜像公共冷却和攻击调度逻辑。
