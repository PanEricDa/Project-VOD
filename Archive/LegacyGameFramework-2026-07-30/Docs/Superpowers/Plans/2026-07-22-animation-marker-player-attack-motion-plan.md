# Animation Marker Player Attack Motion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 使用 AnimationLibrary 无参数 marker 驱动 WeaponData 数值化的玩家真实攻击位移。

**Architecture:** 动画事件桥只发信号；PlayerAttackController 选择当前段数据；PlayerBase 合并普通移动和攻击速度，并保持一次 `move_and_slide()`。武器动画二进制资源只追加方法轨道，不改变用户已有视觉轨道和关键帧。

**Tech Stack:** Godot 4.7、GDScript、AnimationPlayer method tracks、CharacterBody3D。

## Global Constraints

- 不修改 TestScene 或旧 Hero 战斗系统。
- 不改写 IronSword 现有视觉动画轨道、时长和关键帧。
- 所有新增标识使用英文，代码提供详细简体中文注释。
- 当前不是 Git 仓库，不创建提交或 worktree。

---

### Task 1: Animation event bridge and WeaponData

**Files:**
- Create: `UnitSystem/Combat/CharacterAnimationEventPlayer.gd`
- Modify: `UnitSystem/Combat/WeaponData.gd`
- Modify: `UnitSystem/Players/Hero/HeroVisual.tscn`
- Test: `UnitSystem/Tests/PlayerWeaponCombatTest.gd`

- [ ] 先测试无参数 marker 信号和 WeaponData 默认字段。
- [ ] 实现事件桥并挂到现有 CharacterAnimationPlayer。
- [ ] 增加距离数组和速度字段，验证类型与默认值。

### Task 2: PlayerBase physical attack motion

**Files:**
- Modify: `UnitSystem/PlayerBase.gd`
- Test: `UnitSystem/Tests/PlayerBaseMovementTest.gd`

- [ ] 先测试请求、锁定方向、剩余距离、取消、冲刺拒绝和 WASD 叠加。
- [ ] 使用独立 regular horizontal velocity 防止攻击速度逐帧累加。
- [ ] 在现有一次 move_and_slide 前合成攻击速度。
- [ ] 冲刺开始取消位移；无效请求安全返回 false。

### Task 3: Controller routing and IronSword markers

**Files:**
- Modify: `UnitSystem/Combat/PlayerAttackController.gd`
- Modify: `UnitSystem/Players/Hero/Weapons/IronSword/IronSwordData.tres`
- Modify in place: `UnitSystem/Players/Hero/Weapons/IronSword/IronSwordAnimationLibrary.res`
- Test: `UnitSystem/Tests/PlayerWeaponCombatTest.gd`

- [ ] 测试 ATTACKING 状态 marker 使用正确 combo distance，空闲 marker 被忽略。
- [ ] 控制器连接事件桥并转交 PlayerBase；取消、卸装和换装取消位移。
- [ ] 配置 IronSword 三段距离和共用速度。
- [ ] 向现有三个攻击动画分别追加 0.15/0.16/0.20 秒 marker，不改变其他轨道。

### Task 4: Regression verification

- [x] 运行所有 UnitSystem 测试。
- [x] 运行 Godot 4.7 editor scan 和 headless runtime scan。
- [x] 确认 TestScene、旧 Hero、旧 MeleeAttackModule 哈希不变。

---

## 实施结果（2026-07-22）

- AnimationLibrary 方法轨道只发送无参数 `request_attack_motion()` 事件。
- `WeaponData` 保存三段前移距离与共用速度；Iron Sword 默认值为 `0.12 / 0.16 / 0.28m`、`2.0m/s`。
- `PlayerAttackController` 根据当前连击段读取数据并转交 `PlayerBase`。
- `PlayerBase` 执行真实 `CharacterBody3D` 位移，与 WASD 叠加，并通过现有 `move_and_slide()` 接受碰撞阻挡。
- 攻击方向在 marker 触发时锁定；冲刺会取消攻击位移，并在冲刺期间拒绝新的位移请求。
- 取消连击、卸下武器或更换武器时会清理尚未完成的攻击位移。
- Godot 4.7 editor scan：0 errors / 0 warnings。
- Godot 4.7 headless runtime scan：0 errors / 0 warnings。
- UnitSystem 回归测试：11 passed / 0 failed。
- `Scenes/TestScene.tscn`、旧 `Scenes/ObjectScenes/Hero.tscn` 和旧 `Scenes/Components/MeleeAttackModule.tscn` 的 SHA-256 与实施前一致。
