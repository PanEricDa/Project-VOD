# Ranged Projectile Pipeline Implementation Plan

**Goal:** 让弓的攻击动画事件生成 Arrow 投射物，并由 Arrow 自己管理追踪抛物线与抵达命中。

**Architecture:** `RangedWeaponData` 仅引用 `projectile_scene`。`AIRangedCombatSystem` 监听标准 `release_projectile` 事件，在角色 `ProjectileOrigin` 创建投射物；Arrow 以 `TARGET_ARRIVAL` 规则抵达锁定目标并转发命中。

## Constraints

- 不修改 `Scenes/TestScene.tscn` 的单位实例。
- 不实现物理碰撞、范围伤害、墙体阻挡或伤害数值。
- BowData 与 Arrow.tscn 通过 Godot ResourceSaver 保存并验证 UID。

## Tasks

- [x] 添加失败的装配契约测试。
- [x] 将投射物弹道字段迁移到 Arrow，并精简 RangedWeaponData。
- [x] 添加 ProjectileOrigin、动画事件与 AIRangedCombatSystem 投射物交付。
- [x] 重存资源并执行编辑器、场景与契约验证。
