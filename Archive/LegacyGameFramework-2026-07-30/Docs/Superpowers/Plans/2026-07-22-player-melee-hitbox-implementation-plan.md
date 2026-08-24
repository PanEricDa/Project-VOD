# Player Melee Hitbox Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为当前玩家武器连击系统增加由动画窗口驱动、由 WeaponData 配置、由 PlayerBase 通用组件执行的盒形近战命中判定。

**Architecture:** `CharacterAnimationEventPlayer` 只转发开关窗口事件，`PlayerAttackController` 绑定当前武器与连击段，`PlayerMeleeHitbox` 使用 `intersect_shape()` 执行物理查询并按窗口去重。武器资源保存每段盒体尺寸和中心偏移，命中只发送信号，不直接修改目标生命值。

**Tech Stack:** Godot 4.7、GDScript、AnimationPlayer method tracks、PhysicsDirectSpaceState3D、BoxShape3D、UnitBase 阵营接口。

## Global Constraints

- 所有字段与方法使用英文标识，新增代码提供详细简体中文注释。
- 不修改旧 `Scenes/ObjectScenes/Hero.tscn`、旧 `Scenes/Components/MeleeAttackModule.tscn` 或 `Scenes/TestScene.tscn`。
- 不自动向 TestScene 添加任何单位实例。
- 本阶段不实现伤害、击退、卡刀、镜头震动、音效、粒子或受击动画。
- Hitbox 不要求目标属于 `enemy_targets` 分组，敌我关系使用 `UnitBase.is_hostile_to()`。
- 项目不是 Git 仓库，不创建提交或 worktree。

---

### Task 1: WeaponData Hitbox 配置契约

**Files:**
- Modify: `UnitSystem/Combat/WeaponData.gd`
- Modify: `UnitSystem/Tests/PlayerWeaponCombatTest.gd`

**Interfaces:**
- Produces: `hitbox_sizes: Array[Vector3]`
- Produces: `hitbox_center_offsets: Array[Vector3]`

- [ ] **Step 1: 写入失败测试**

在 WeaponData 契约测试中断言两个字段存在、类型为数组且默认留空；测试还应验证数组索引与 `basic_attack_N` 使用同一个从零开始的数据索引。

- [ ] **Step 2: 运行测试并确认 RED**

```powershell
& $godot --headless --path 'G:\Godot\SipSip' --script res://UnitSystem/Tests/PlayerWeaponCombatTest.gd
```

预期：字段尚不存在，测试失败。

- [ ] **Step 3: 最小实现**

在 `WeaponData.gd` 增加：

```gdscript
@export_category("Melee Hitbox")
@export var hitbox_sizes: Array[Vector3] = []
@export var hitbox_center_offsets: Array[Vector3] = []
```

注释明确偏移的 `Z > 0` 表示设计师视角的角色前方。

- [ ] **Step 4: 运行测试并确认 GREEN**

预期：WeaponData 契约测试通过。

---

### Task 2: 通用 PlayerMeleeHitbox 组件

**Files:**
- Create: `UnitSystem/Combat/PlayerMeleeHitbox.gd`
- Create: `UnitSystem/Combat/PlayerMeleeHitbox.tscn`
- Create: `UnitSystem/Tests/PlayerMeleeHitboxTest.gd`

**Interfaces:**
- Consumes: `WeaponData.hitbox_sizes`、`WeaponData.hitbox_center_offsets`
- Consumes: `UnitBase.is_targetable()`、`UnitBase.is_dead()`、`UnitBase.is_hostile_to()`
- Produces: `attack_hit(target: UnitBase, hit_position: Vector3, hit_direction: Vector3, combo_index: int)`
- Produces: `configure_owner(owner_unit: UnitBase) -> void`
- Produces: `begin_detection(weapon_data: WeaponData, combo_index: int, locked_direction: Vector3) -> bool`
- Produces: `end_detection() -> void`
- Produces: `is_detecting() -> bool`

- [ ] **Step 1: 写入失败测试**

测试实例化组件并覆盖：窗口外不检测、配置验证、方向锁定、敌对 UnitBase 过滤、友军/中立/死亡/不可选中/错误物理层过滤、单窗口去重、多目标命中和新窗口重新命中。

- [ ] **Step 2: 运行测试并确认 RED**

```powershell
& $godot --headless --path 'G:\Godot\SipSip' --script res://UnitSystem/Tests/PlayerMeleeHitboxTest.gd
```

预期：组件脚本或场景尚不存在，测试失败。

- [ ] **Step 3: 创建检测组件场景**

```text
PlayerMeleeHitbox (Node3D, PlayerMeleeHitbox.gd)
└── DebugHitbox (MeshInstance3D, BoxMesh)
```

脚本持有运行时 `BoxShape3D`，窗口内在 `_physics_process()` 中使用：

```gdscript
var query := PhysicsShapeQueryParameters3D.new()
query.shape = _query_shape
query.transform = _build_query_transform()
query.collision_mask = target_collision_mask
query.collide_with_bodies = true
query.collide_with_areas = false
query.exclude = [_owner_unit.get_rid()]
var results := _owner_unit.get_world_3d().direct_space_state.intersect_shape(
    query,
    maximum_results
)
```

结果仅接受 `UnitBase`，依次检查目标有效、可选中、未死亡、与持有者敌对且本窗口未命中过。

- [ ] **Step 4: 实现调试盒**

导出：

```gdscript
@export_flags_3d_physics var target_collision_mask: int = 4
@export_range(1, 128, 1, "or_greater") var maximum_results: int = 32
@export var debug_hitbox_enabled: bool = true
@export var debug_idle_color := Color(1.0, 0.75, 0.08, 0.18)
@export var debug_hit_color := Color(1.0, 0.08, 0.04, 0.35)
```

检测窗口中显示与查询相同的尺寸和世界变换；首次命中后由黄变红；结束后隐藏。

- [ ] **Step 5: 运行组件测试并确认 GREEN**

预期：`PlayerMeleeHitboxTest: PASS`，无错误或警告。

---

### Task 3: PlayerBase 安装与动画事件桥

**Files:**
- Modify: `UnitSystem/PlayerBase.tscn`
- Modify: `UnitSystem/Combat/CharacterAnimationEventPlayer.gd`
- Modify: `UnitSystem/Tests/PlayerBaseMovementTest.gd`
- Modify: `UnitSystem/Tests/PlayerWeaponCombatTest.gd`

**Interfaces:**
- Consumes: `PlayerMeleeHitbox.tscn`
- Produces: `hit_window_open_requested()`、`hit_window_close_requested()`
- Produces: `open_attack_hit_window() -> void`、`close_attack_hit_window() -> void`

- [ ] **Step 1: 写入失败测试**

断言 PlayerBase 拥有 `MeleeHitbox` 实例；事件桥方法轨道接口存在，并能分别发送开窗和关窗信号。

- [ ] **Step 2: 运行测试并确认 RED**

预期：PlayerBase 节点和事件桥接口尚不存在，测试失败。

- [ ] **Step 3: 安装组件并扩展事件桥**

在 `PlayerBase.tscn` 根节点下实例化 `PlayerMeleeHitbox.tscn`，节点名固定为 `MeleeHitbox`。

在事件桥中增加：

```gdscript
signal hit_window_open_requested()
signal hit_window_close_requested()

func open_attack_hit_window() -> void:
    hit_window_open_requested.emit()

func close_attack_hit_window() -> void:
    hit_window_close_requested.emit()
```

- [ ] **Step 4: 运行相关测试并确认 GREEN**

预期：PlayerBase 与事件桥契约通过，原移动和攻击位移测试保持通过。

---

### Task 4: PlayerAttackController 调度与转发

**Files:**
- Modify: `UnitSystem/Combat/PlayerAttackController.gd`
- Modify: `UnitSystem/Tests/PlayerWeaponCombatTest.gd`

**Interfaces:**
- Consumes: 动画事件桥的开窗、关窗信号
- Consumes: `PlayerMeleeHitbox.begin_detection()`、`end_detection()`、`attack_hit`
- Produces: 控制器级 `attack_hit(target: UnitBase, hit_position: Vector3, hit_direction: Vector3, combo_index: int)`

- [ ] **Step 1: 写入失败测试**

测试只有 `ATTACKING` 状态可开窗；当前段数、武器和锁定方向正确传入组件；空闲 marker 被忽略；组件命中被原样转发；动画结束和所有取消路径会关闭窗口。

- [ ] **Step 2: 运行测试并确认 RED**

预期：控制器尚未连接 Hitbox 事件或对外信号，测试失败。

- [ ] **Step 3: 实现调度**

控制器解析同级 `MeleeHitbox`，配置其 owner，连接动画事件和命中信号。开窗时调用：

```gdscript
_melee_hitbox.begin_detection(
    _equipped_weapon,
    _combo_index,
    actor.get_attack_forward_direction()
)
```

`cancel_combo()`、`_on_animation_finished()`、`_finish_combo()`、换装、卸装和 `_exit_tree()` 均调用统一 `_close_attack_hit_window()`。

- [ ] **Step 4: 运行测试并确认 GREEN**

预期：PlayerWeaponCombatTest 通过，现有输入缓存、连击复位、自动连击和攻击位移行为无回归。

---

### Task 5: Iron Sword 数据与动画窗口

**Files:**
- Modify: `UnitSystem/Players/Hero/Weapons/IronSword/IronSwordData.tres`
- Modify in place: `UnitSystem/Players/Hero/Weapons/IronSword/IronSwordAnimationLibrary.res`
- Modify: `UnitSystem/Tests/PlayerWeaponCombatTest.gd`

**Interfaces:**
- Consumes: `open_attack_hit_window()`、`close_attack_hit_window()`
- Produces: 三段 Iron Sword Hitbox 配置与三对动画窗口 marker

- [ ] **Step 1: 写入失败测试**

断言 Iron Sword 的三段尺寸和偏移为：

```text
(1.2, 0.8, 1.0) / (0.0, 0.4, 0.65)
(1.3, 0.8, 1.1) / (0.0, 0.4, 0.70)
(1.5, 0.9, 1.2) / (0.0, 0.45, 0.80)
```

并断言每个 `basic_attack_N` 恰好包含一个开窗和一个关窗方法键，且满足 `0 <= open_time < close_time <= animation.length`。

- [ ] **Step 2: 运行测试并确认 RED**

预期：Iron Sword 尚无数据与窗口 marker，测试失败。

- [ ] **Step 3: 配置资源与方法轨道**

在 `IronSwordData.tres` 写入三段数组。使用一次性 Godot 迁移脚本安全编辑二进制 AnimationLibrary：保留用户现有轨道、长度和关键帧，只追加方法轨道中的开窗与关窗键；完成后删除迁移脚本。

开关时刻根据每个当前动画的视觉关键帧区间计算并限制在动画长度内，不硬编码动画总长度；测试只约束相对顺序，不限制用户以后调整动画长度。

- [ ] **Step 4: 运行自动事件链测试并确认 GREEN**

通过 `AnimationPlayer.advance()` 播放到 marker，验证真实组件窗口开关和控制器信号链，而不只检查资源文本。

---

### Task 6: 全量验证与文档回填

**Files:**
- Modify: `Docs/Superpowers/Plans/2026-07-22-player-melee-hitbox-implementation-plan.md`

- [ ] **Step 1: 运行全部 UnitSystem 测试**

逐个运行 `UnitSystem/Tests/*.gd`，要求全部输出 `PASS`，进程退出码为 `0`，且无 `ERROR`、`SCRIPT ERROR`、`WARNING` 或 `FAIL`。

- [ ] **Step 2: 运行 Godot 4.7 扫描**

```powershell
& $godot --headless --editor --path 'G:\Godot\SipSip' --quit
& $godot --headless --path 'G:\Godot\SipSip' --quit-after 5
```

要求编辑器扫描与运行扫描均为 `0 errors / 0 warnings`。

- [ ] **Step 3: 核对受保护文件**

验证以下 SHA-256 与实施前一致：

```text
Scenes/ObjectScenes/Hero.tscn
Scenes/Components/MeleeAttackModule.tscn
Scenes/TestScene.tscn
```

- [ ] **Step 4: 回填最终结果**

在本计划末尾记录测试数量、扫描结果、Iron Sword 最终参数和受保护文件校验结论。

---

## 实施结果（2026-07-22）

- 新增 `PlayerMeleeHitbox` 通用组件，并装配到 `PlayerBase/MeleeHitbox`。
- `WeaponData` 新增每连击段 `hitbox_sizes` 与 `hitbox_center_offsets`。
- `CharacterAnimationEventPlayer` 新增无参数开窗、关窗事件桥。
- `PlayerAttackController` 负责窗口调度、冲刺/取消/动画结束保底清理及 `attack_hit` 转发。
- Iron Sword Hitbox：
  - 第一击：`size (1.2, 0.8, 1.0)`，`offset (0.0, 0.4, 0.65)`。
  - 第二击：`size (1.3, 0.8, 1.1)`，`offset (0.0, 0.4, 0.70)`。
  - 第三击：`size (1.5, 0.9, 1.2)`，`offset (0.0, 0.45, 0.80)`。
- Iron Sword 判定窗口 marker：
  - 第一击：`0.110s–0.235s`。
  - 第二击：`0.150s–0.270s`。
  - 第三击：`0.280s–0.440s`。
- 保留用户当前攻击位移距离 `0.12 / 0.20 / 0.50m`，未回写旧测试默认值。
- UnitSystem 回归测试：`12 passed / 0 failed`。
- Godot 4.7 editor scan：`0 errors / 0 warnings`。
- Godot 4.7 headless runtime scan：`0 errors / 0 warnings`。
- 临时动画迁移文件：`0` 个残留。
- `Scenes/TestScene.tscn`、旧 `Scenes/ObjectScenes/Hero.tscn` 与旧 `Scenes/Components/MeleeAttackModule.tscn` 的 SHA-256 均与实施前一致。

### 调试盒同步修正

- 调试盒开窗时保持隐藏，直到首个真实物理查询帧写入当前世界 Transform 后才显示。
- 每个检测物理帧只计算一份 `query_transform`，由实际 `intersect_shape()` 和调试盒共同使用。
- 写入调试盒世界坐标后调用 `force_update_transform()`，避免渲染线程短暂显示上一窗口缓存位置。
- 增加“下一轮攻击位置变化”和“有效窗口内角色持续位移”的回归测试。
- 修正后 UnitSystem 测试仍为 `12 passed / 0 failed`，编辑器与运行扫描均为 `0 errors / 0 warnings`。

### 调试盒旧世界坐标二次修正

- 用户实际渲染复测表明，仅在首个物理帧延迟显示仍不足以消除闪帧。
- 进一步确认逻辑段数、偏移和锁定方向在 `end_detection()` 中已经清空；残留来自 `top_level` MeshInstance 独立保存的世界 Transform。
- `DebugHitbox` 已取消 `top_level`，隐藏期间回到玩家节点层级并自然继承玩家移动。
- 关闭窗口时立即隐藏并将调试盒局部 Transform 复位为 `Transform3D.IDENTITY`。
- 有效窗口期间仍由每物理帧共享的 `query_transform` 覆盖全局变换，因此实际查询与调试显示继续保持一致，锁定方向不受影响。
- 测试改为使用与 PlayerBase 相同的真实父子层级，并验证隐藏节点不再保留上一击世界坐标。

### Hero 事件桥继承覆盖修正

- Inspector 保存后，`Hero.tscn` 曾生成 `CharacterAnimationPlayer.script = null` 覆盖，导致动画方法轨道无法调用事件桥方法。
- 已删除该继承覆盖，运行时重新继承 `HeroVisual.tscn` 的 `CharacterAnimationEventPlayer.gd`。
- 回归测试现在明确验证 Hero 运行实例的 AnimationPlayer 脚本身份，并在缺失时安全停止后续方法调用测试。
- Hitbox 参数测试不再锁死设计默认尺寸，只验证三段数量匹配及所有尺寸分量为正数；用户当前第一段尺寸 `Vector3(0.8, 0.8, 1.0)` 保持不变。
