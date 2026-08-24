# Guardian 可复用盾击基础攻击设计

## 目标

Guardian 使用独立的 `ShieldAttack` 攻击模块。模块携带盾牌临时模型、攻击动画和武器 Profile；`AllyBase` 继续负责感知、目标、移动、朝向、脱战与普通攻击公共冷却。

本阶段只实现攻击表现和调度，不实现检测盒、伤害、受击反馈或 TestScene 单位配置。

## 距离与状态

- `combat_guard_distance`：职业在未执行攻击接近时使用的警戒距离，Guardian 为 `1.5m`。
- `AIAttackProfile.attack_range`：武器真正允许发动攻击的距离，盾击为 `0.8m`。
- 两套距离分别维护迟滞容差，不能在同一帧共同计算移动目标。
- 普通攻击子状态为 `GUARD / APPROACH / ATTACK / HOLD / RETURN_TO_GUARD`。
- ShieldAttack 的 `return_to_guard_after_attack=false`，因此攻击结束后留在近战距离；目标移远时重新接近。

## 公共冷却

`AllyBase.basic_attack_global_cooldown` 是当前单位所有普通攻击共享的冷却，默认 `1.0s`。只有 `request_attack()` 返回成功时才启动，从攻击开始而非动画结束计时。切换目标、取消动画或脱战不会清零已经开始的公共冷却。

攻击模块本身只维护 `IDLE / ATTACKING`，动画结束后立即回到 IDLE。实际下一次攻击必须同时满足模块空闲和公共冷却结束。

## 模块边界

`AIAttackModuleBase` 不读取 InputMap、不搜索目标、不移动持有者，也不计算公共冷却。它通过 Profile 提供攻击距离、容差、接近速度倍率及攻击后是否回到警戒位。

`AllyBase.set_attack_module()` 是通用装卸入口。无模块或模块配置无效时，友方单位保持原有警戒游荡，不进入攻击接近。

## Guardian 默认配置

```text
Profile: Guardian Shield Bash
attack_range: 0.8m
attack_range_tolerance: 0.1m
approach_speed_multiplier: 1.25
return_to_guard_after_attack: false
basic_attack_global_cooldown: 1.0s
```

盾击动画总长 `0.48s`：先轻微收盾，再快速前顶，最后复位。逻辑命中窗口在 `0.14–0.27s` 开放，但当前没有检测或伤害消费者。

## 项目约束

- 目标版本为 Godot 4.7。
- 代码字段与方法使用英文标识，新增逻辑使用简体中文注释。
- 不自动向 `res://Scenes/TestScene.tscn` 添加或修改单位实例。
