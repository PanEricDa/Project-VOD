# 新 AI 近战战斗系统设计

## 1. 目标

为基于 `UnitBase`、`AIUnitBase` 的新单位架构增加一套通用 AI 近战战斗系统。

玩家与 AI 共用：

- `WeaponData`
- 武器视觉场景
- 武器 `AnimationLibrary`
- 动画事件协议
- 近战 Hitbox 数据
- 命中反馈资源

玩家与 AI 只在攻击请求来源上分离：

- 玩家由 InputMap、输入缓存和手动连击驱动。
- AI 由行为状态机、目标、距离和公共冷却驱动。

第一阶段由 `Amy` 装备 `IronSwordData.tres` 验证完整链路。旧 AI 攻击系统继续保留，
不删除旧 Guardian、Warrior、Ranger 等场景或模块，也不修改 `TestScene.tscn`。

## 2. 第一阶段范围

实现：

- AI 装备和卸载 `WeaponData`
- 角色视觉端点标准化
- 随机单段普通攻击
- 近战接近、保持距离和攻击状态
- AI 通用公共冷却
- 保留动画位移事件协议，但 AI 不执行身体攻击位移
- 通用近战 Hitbox
- 命中信号
- AI 局部卡刀反馈
- Inspector 调试信息

暂不实现：

- 伤害数值
- 生命值扣除
- 击退、硬直和死亡
- 远程攻击
- 技能释放
- 全局战斗规则管理器
- 单位属性、Buff 或 Debuff 对公共冷却的实际修正
- 旧 AI 单位的批量迁移

## 3. 方案选择

采用“独立控制器、共享底层资产”方案：

```text
Player InputMap -> PlayerAttackController --+
                                            +-> WeaponData
AI Behavior ----> AICombatSystem ----------+   AnimationLibrary
                                                Weapon Visual
                                                Hitbox Data
```

不让玩家和 AI 继承同一个攻击控制器。玩家的输入缓存、连击和持续按键与 AI 的目标、
距离和冷却决策不同，强行建立控制器继承关系会扩大双方的状态复杂度。

不继续使用旧 `AIAttackModuleBase` 作为新系统基础。旧模块把视觉、动画、Hitbox 和攻击
算法绑定在一个攻击场景中，不符合当前角色视觉插槽和共享 `WeaponData` 的边界。

## 4. 节点架构

```text
AIUnitBase
├── Visual
│   └── ConcreteVisual
│       ├── CharacterRoot
│       │   ├── Body / Skeleton
│       │   └── WeaponSocket
│       └── CharacterAnimationPlayer
├── CollisionShape3D
├── MovementSystem
│   └── NavigationAgent3D
└── CombatSystem
    ├── AttackController
    ├── MeleeHitbox
    └── HitFeedbackBridge
```

### 4.1 AIUnitBase

`AIUnitBase` 只提供空 `Visual` 插槽，不再保存默认蓝色 `BodyMesh`。

它继续负责：

- 导航
- 常规移动
- 冲刺
- 重力
- 视觉朝向
- 唯一一次 `move_and_slide()`
- 攻击动画请求的真实物理位移

它不负责：

- 索敌
- 选择攻击时机
- 选择攻击动画
- 公共冷却
- Hitbox 查询

### 4.2 具体视觉场景

创建：

- `UnitSystem/AI/Ally/Visuals/AllyBaseVisual.tscn`
- `UnitSystem/AI/Enemy/Visuals/EnemyBaseVisual.tscn`

两个场景都遵守固定端点：

```text
ConcreteVisual
├── CharacterRoot
│   ├── BodyMesh
│   └── WeaponSocket
└── CharacterAnimationPlayer
```

友方视觉沿用当前蓝色方块，敌方视觉沿用当前红色方块。`AllyBase2` 和
`EnemyBase2` 分别装载对应视觉场景。具体单位未来可以替换整个视觉场景，只要继续提供
相同端点。

### 4.3 CombatSystem

`CombatSystem` 由 `AICombatSystem.gd` 管理，并默认装载到 `AIUnitBase`。它不区分
Ally 或 Enemy。

公开 Inspector 配置：

```gdscript
@export var starting_weapon: WeaponData

@export_range(0.0, 10.0, 0.05)
var base_global_cooldown_duration: float = 1.0

@export var debug_hitbox_enabled: bool = false
```

具体 `AllyBase2`、`EnemyBase2` 默认不装备武器。Amy 的继承场景覆盖：

```text
starting_weapon = res://Item/Weapon/Sword/IronSwordData.tres
```

CombatSystem 对外提供只读 Debug 信息：

- Equipped Weapon
- Current Attack Target
- Current Attack Animation
- Global Cooldown Remaining

这些属性不参与场景保存，也不能修改运行状态。

## 5. 职责边界

### 5.1 AICombatSystem

负责：

- 装备和卸载武器
- 维护公共冷却
- 验证是否允许提交新的普通攻击
- 成功提交攻击后立即启动公共冷却
- 向行为状态机提供武器攻击距离
- 转发攻击生命周期与命中信号

不负责：

- 搜索目标
- 选择目标
- 导航
- 直接播放动画
- Hitbox 查询

### 5.2 AIAttackController

负责：

- 解析角色视觉端点
- 实例化武器视觉
- 注入和卸载武器 AnimationLibrary
- 从 `basic_attack_1...n` 中随机选择一段
- 播放、取消和恢复攻击动画
- 响应攻击位移与 Hitbox 动画事件
- 管理当前攻击目标、攻击序号和锁定攻击方向
- 暂停和恢复动画、攻击位移与 Hitbox

不负责：

- InputMap
- 索敌
- 攻击距离移动
- 公共冷却
- 伤害结算

随机规则使用洗牌袋：

- 每个有效 `basic_attack_n` 在一袋中只出现一次。
- 袋子耗尽后重新洗牌。
- 有多个动作时，新袋第一招不与上一袋最后一招相同。
- 每次 AI 请求只播放一段，不自动播放完整玩家连击。

### 5.3 MeleeHitboxComponent

现有 `PlayerMeleeHitbox` 泛化并迁移为玩家和 AI 共用的
`MeleeHitboxComponent`。

负责：

- 从 `WeaponData` 读取当前攻击序号的盒体尺寸和中心偏移
- 按攻击开始时锁定的水平朝向构造查询
- 排除持有者
- 使用 `UnitBase.is_hostile_to()` 判断敌我
- 忽略不可选中或已死亡单位
- 单窗口内按实例 ID 去重
- 发送命中信号
- 可选显示与真实查询一致的调试盒

不负责：

- 伤害
- 击退
- 攻击状态
- 公共冷却
- 动画播放

## 6. WeaponData 扩充

新增：

```gdscript
@export_category("Attack Range")
@export_range(0.1, 10.0, 0.1, "or_greater")
var attack_range: float = 1.0

@export_range(0.0, 2.0, 0.05)
var attack_range_tolerance: float = 0.1
```

`IronSwordData.tres` 使用旧 Warrior 参数：

```text
attack_range = 1.0
attack_range_tolerance = 0.1
```

旧 `AIAttackProfile` 参数迁移关系：

| 旧参数 | 新位置 |
|---|---|
| `attack_range` | `WeaponData.attack_range` |
| `attack_range_tolerance` | `WeaponData.attack_range_tolerance` |
| `approach_speed_multiplier` | Ally 行为状态机 |
| `return_to_guard_after_attack` | 第一阶段移除 |
| 攻击冷却 | `AICombatSystem` 公共冷却 |

武器不保存 AI 决策或公共冷却。玩家也可以继续忽略新增攻击距离字段。

## 7. AI 公共冷却

基础公共冷却默认 `1.0s`。

规则：

- 只有攻击控制器成功开始攻击后才启动。
- 从攻击成功开始时立即计时，不等待动画结束。
- 目标切换、取消动作或脱战不会清除已启动冷却。
- 公共冷却完成但当前动画尚未结束时，仍不能重叠发起新攻击。
- 接近目标、重力、Hitbox 卡刀和其他单位行为不会暂停公共冷却计时。

公开接口：

```gdscript
func is_global_cooldown_ready() -> bool
func get_global_cooldown_remaining() -> float
func start_global_cooldown(base_duration: float = -1.0) -> void
func calculate_global_cooldown_duration(base_duration: float) -> float
```

第一阶段 `calculate_global_cooldown_duration()` 只夹取并返回基础值。未来在此唯一入口组合：

```text
全局战斗规则基础值
× 单位属性修正
× Buff / Debuff 修正
= 实际公共冷却
```

不在第一阶段创建全局单例、属性系统依赖或修正公式。

## 8. 攻击位移

`AnimationLibrary` 继续通过
`CharacterAnimationEventPlayer.attack_motion_requested` 在原时间点发送位移 marker，
玩家控制器仍可按照 `WeaponData` 执行真实攻击位移。

AI 控制器刻意不订阅该信号，因此 AI 攻击时不会驱动 CharacterBody3D 前移。动画序列、
方法轨道和信号协议保持不变，未来若某个专用 AI 行为需要位移，可以通过独立行为重新
接入，而不必修改武器动画资产。

## 9. 行为状态机

`AllyBehaviorStateMachine` 新增：

```gdscript
COMBAT_ATTACK
```

战斗状态流：

```text
FORMATION
   ↓ 锁定有效目标
COMBAT_APPROACH
   ↓ 进入武器攻击距离
COMBAT_HOLD
   ↓ 公共冷却完成且攻击请求成功
COMBAT_ATTACK
   ├─ 动画完成且目标仍在范围 → COMBAT_HOLD
   ├─ 动画完成且目标离开范围 → COMBAT_APPROACH
   └─ 目标失效或强制脱战 → RETURN
```

状态规则：

- 装备有效近战武器时，接近和保持距离读取 `WeaponData`。
- 未装备武器时，继续使用原 `preferred_combat_distance` 和既有战斗游荡，不报错。
- `COMBAT_ATTACK` 清除普通导航目标，但保持目标朝向和重力。
- 动画攻击位移不属于普通导航，因此不会被清除普通移动目标取消。
- 攻击完成后默认留在武器距离，不返回旧职业警戒距离。
- 目标失效时取消动画、Hitbox 和剩余攻击位移；已经启动的公共冷却继续计时。

新增单位级行为参数：

```gdscript
@export_range(0.1, 3.0, 0.05, "or_greater")
var combat_approach_speed_multiplier: float = 1.2
```

该参数描述单位接敌积极程度，不属于武器。

## 10. 公共接口

`AICombatSystem`：

```gdscript
func configure(owner: AIUnitBase) -> bool

func equip_weapon(weapon_data: WeaponData) -> bool
func unequip_weapon() -> void

func request_basic_attack(target: UnitBase) -> bool
func cancel_current_action() -> void

func can_request_basic_attack(target: UnitBase) -> bool
func is_attacking() -> bool

func get_attack_range() -> float
func get_attack_range_tolerance() -> float

func is_global_cooldown_ready() -> bool
func get_global_cooldown_remaining() -> float
func start_global_cooldown(base_duration: float = -1.0) -> void
func calculate_global_cooldown_duration(base_duration: float) -> float
```

信号：

```gdscript
signal weapon_equipped(weapon_data: WeaponData)
signal weapon_unequipped()

signal attack_started(target: UnitBase, attack_index: int)
signal attack_finished(target: UnitBase, attack_index: int)
signal attack_cancelled(target: UnitBase, attack_index: int)

signal attack_hit(
	target: UnitBase,
	hit_position: Vector3,
	hit_direction: Vector3,
	attack_index: int
)

signal global_cooldown_started(duration: float)
signal global_cooldown_finished()
```

`AIUnitBase`：

```gdscript
func get_combat_system() -> AICombatSystem

func request_attack_motion(
	direction: Vector3,
	distance: float,
	speed: float
) -> bool

func cancel_attack_motion() -> void
func set_attack_motion_suspended(active: bool) -> void
```

## 11. 命中反馈

复用：

- `Effects/Combat/HitFeedbackBridge.tscn`
- `Effects/Combat/DefaultAIHitFeedback.tres`

AI 默认效果：

- 局部卡刀开启
- 摄像机震动关闭
- 不使用 `Engine.time_scale`

新 `AIAttackController.attack_hit` 使用四参数签名，与现有效果桥兼容。卡刀期间仅暂停：

- 当前攻击动画
- 当前攻击位移
- 当前 Hitbox 的新查询

公共冷却、重力、导航系统、其他单位和游戏世界继续运行。

## 12. 文件结构

```text
UnitSystem/
├── Base/
│   ├── AIUnitBase.gd
│   └── AIUnitBase.tscn
├── Components/
│   ├── Animation/
│   │   └── CharacterAnimationEventPlayer.gd
│   └── Combat/
│       ├── Common/
│       │   ├── MeleeHitboxComponent.gd
│       │   └── MeleeHitboxComponent.tscn
│       └── AI/
│           ├── AICombatSystem.gd
│           ├── AICombatSystem.tscn
│           └── AIAttackController.gd
└── AI/
    ├── Ally/
    │   ├── Visuals/
    │   │   └── AllyBaseVisual.tscn
    │   ├── AllyBase2.tscn
    │   └── Units/
    │       └── Amy.tscn
    └── Enemy/
        ├── Visuals/
        │   └── EnemyBaseVisual.tscn
        └── EnemyBase2.tscn
```

## 13. 安全迁移顺序

1. 泛化现有玩家 Hitbox，并先验证玩家行为不变。
2. 创建友方和敌方视觉场景，再移除 `AIUnitBase` 的默认 BodyMesh。
3. 扩充 `WeaponData` 并配置 IronSword。
4. 实现 AI 攻击位移。
5. 实现 `AIAttackController`。
6. 实现 `AICombatSystem` 与公共冷却。
7. 将 CombatSystem 装载到 AIUnitBase。
8. 接入 AllyBehaviorStateMachine。
9. 只在 Amy 装备 IronSword。
10. 运行完整回归后再进行人工场景观察。

每一步都必须保持无武器、无视觉或组件配置缺失时安全降级，不允许因为攻击系统缺失而
停止 AI 的重力、移动、索敌或返回编队。

## 14. 验证

- AIUnitBase 无视觉、无武器时可安全运行。
- AllyBase2 与 EnemyBase2 保持当前蓝色、红色方块外观。
- Amy 自动装备 IronSword。
- Amy 锁定敌人后按 `1.0m ± 0.1m` 接近和保持。
- GCD 未结束时无法重复攻击。
- GCD 从成功攻击开始时计时。
- 随机袋能消耗全部有效动作，并避免袋边界连续重复。
- 动画事件触发真实、受碰撞阻挡的攻击位移。
- Hitbox 只命中有效敌对 UnitBase。
- 同一窗口对同一目标只发送一次命中。
- AI 卡刀不产生摄像机震动。
- 攻击取消能关闭动画、Hitbox 与攻击位移。
- 玩家原有攻击、换武器、连击、Hitbox 与反馈不发生行为回归。
- Godot 4.7 headless 测试和编辑器扫描无新增错误或警告。
- 不修改 `Scenes/TestScene.tscn`；需要运行观察时由用户手动添加 Amy 和目标单位。

## 15. 实施结果（2026-07-25）

本设计已按第一阶段范围完成。最终采用的实际节点路径为：

```text
AIUnitBase/CombatSystem
├── AttackController
├── MeleeHitbox
└── HitFeedbackBridge
```

Amy 通过继承场景覆盖 `CombatSystem.starting_weapon` 装备 IronSword。武器距离的最终
语义确定为“最大可发动距离”，而不是必须精确站在距离环带上；目标位于最大距离以内
即可攻击，公共冷却期间才使用原持距游荡修正位置。

验证证据：

- 15 项 `UnitSystem/Tests/*.gd` 全部通过。
- Godot 4.7 headless 编辑器文件扫描完成，无脚本错误。
- 当前活动目录中不存在 `res://Scenes/TestScene.tscn`；本次未创建或修改
  `TestScene2.tscn`、归档 TestScene 或其中的单位实例。
- 第一阶段仍不包含伤害、生命值扣除、击退、硬直或死亡。
