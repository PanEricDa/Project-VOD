# Guardian 可复用盾击基础攻击实施记录

## 已实施结构

1. 将 `AIAttackProfile` 调整为武器静态参数资源，分离武器攻击距离与 AllyBase 警戒距离。
2. 将 `AIAttackModuleBase` 简化为动画生命周期模块，移除模块本地冷却。
3. 在 `AllyBase` 增加普通攻击公共冷却、攻击子状态、模块装卸接口和互斥的接近/警戒移动入口。
4. 将战斗游荡改为显式接收目标半径与容差，使警戒游荡和近战保持共享随机方法但不共享同一距离参数。
5. 在 `AllyBase/VisualRoot` 增加 `AttackModuleSocket`。
6. 完善 `ShieldAttack.tscn`，迁入盾牌临时模型、专用 Profile 和盾击动画。
7. 在 Guardian 源场景安装 ShieldAttack，并迁移所有友方职业的警戒距离字段名。

## 关键接口

```gdscript
# AllyBase
func set_attack_module(module: AIAttackModuleBase) -> void
func get_basic_attack_global_cooldown_remaining() -> float
func get_guard_distance_motion(current_distance: float) -> int

# AIAttackModuleBase
func request_attack(target: CharacterBody3D) -> bool
func cancel_attack() -> void
func reset_module() -> void
func can_attack() -> bool
func is_attacking() -> bool
func get_attack_range() -> float
func get_attack_range_tolerance() -> float
func get_approach_speed_multiplier() -> float
func should_return_to_guard_after_attack() -> bool
```

## 验证项目

- 模块动画结束后立即恢复可用，不再存在模块本地冷却。
- 只有成功攻击才启动 AllyBase 的 `1.0s` 公共冷却。
- Guardian 在 `0.8m` 内发动盾击，结束后留在近战距离。
- 无攻击模块的 Ranger、Healer、Mage 保持警戒站位行为。
- 目标失效或脱战时取消正在播放的攻击，但不重置已经开始的公共冷却。
- ShieldAttack 保留命中窗口信号，但不创建检测、伤害或反馈。
- `TestScene.tscn` 不由本次实现修改。

## 后续扩展

CrossbowAttack、StaffAttack 和 MagicballAttack 可使用同一 Profile 与调度接口，只需提供各自模型、动画、攻击距离和 Delivery 实现。实际命中、投射物、伤害与反馈应作为模块外部系统连接现有命中窗口信号。

## 继承职业的模块装配规范

- 所有职业攻击模块都必须作为 `VisualRoot/AttackModuleSocket` 的直接子节点存在。
- 子节点名称只使用模块名，例如 Guardian 使用 `ShieldAttack`、Warrior 使用 `SwordAttack`；不得把父级路径编码到节点名称中。
- 职业根节点的 `attack_module_path` 必须精确指向实际节点。路径解析失败时，`AllyBase` 会安全回退为未装备模块的警戒行为，因此不会发动普通攻击。
- 新建或修复职业场景后，应通过场景树确认父子关系，并在保存、修改任意 Inspector 参数、再次保存后复查一次，避免把节点名称问题误判为攻击调度问题。
