# Player Weapon Animation Combat Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为新 `PlayerBase -> Hero` 框架增加可换装 IronSword、三段连击、输入缓存与按住自动连击，同时保持移动、旧战斗系统和 TestScene 完全独立。

**Architecture:** `PlayerBase.tscn` 直接持有一个脚本化 `AttackController` 普通节点；`WeaponData` 只连接一个武器视觉场景与一个角色攻击 `AnimationLibrary`。Hero 的无脚本视觉场景提供稳定的 `CharacterRoot / WeaponSocket / CharacterAnimationPlayer` 约定，控制器在装备时原子验证资源、挂载视觉并注册 `weapon` 动画库。

**Tech Stack:** Godot 4.7、GDScript、PackedScene、Resource、AnimationPlayer、AnimationLibrary、SceneTree headless tests。

## Global Constraints

- 所有新增字段、方法和信号使用英文标识；新增代码提供详细简体中文注释。
- 攻击输入只读取现有 InputMap `player_attack`（鼠标左键）。
- 默认参数固定为输入缓存 `0.15s`、连击重置 `0.7s`、按住自动连击开启、轮次间隔 `0.3s`。
- 第一版只播放视觉动画和发送流程信号；不实现 Hitbox、伤害、攻击位移、反馈或 GCD。
- 不修改 `UnitSystem/PlayerBase.gd` 的移动、冲刺、重力或索敌逻辑。
- 不修改旧 `Scenes/ObjectScenes/Hero.tscn`、旧 `Scenes/Components/MeleeAttackModule.tscn` 或 `Scenes/TestScene.tscn`。
- 当前目录不是 Git 仓库，因此计划中的验证以文件和 headless 测试结果为准，不执行提交步骤。

---

## File Map

- Create `UnitSystem/Combat/WeaponData.gd`: 扁平武器数据类型。
- Create `UnitSystem/Combat/PlayerAttackController.gd`: 输入、连击、装备及动画调度。
- Modify `UnitSystem/PlayerBase.tscn`: 增加普通 `AttackController` 节点。
- Modify `UnitSystem/Players/Hero/HeroVisual.tscn`: 建立稳定角色视觉、武器插槽和通用动画播放器。
- Create `UnitSystem/Players/Hero/Weapons/IronSword/IronSwordVisual.tscn`: 无脚本铁剑视觉。
- Create `UnitSystem/Players/Hero/Weapons/IronSword/IronSwordAnimations.tres`: HeroVisual 三段攻击动画库。
- Create `UnitSystem/Players/Hero/Weapons/IronSword/IronSwordData.tres`: 连接视觉与动画库。
- Modify `UnitSystem/Players/Hero/Hero.tscn`: 为继承的 AttackController 指定初始 IronSword。
- Create `UnitSystem/Players/Hero/HeroAnimationWorkbench.tscn`: 唯一编辑器动画工作台。
- Create `UnitSystem/Tests/PlayerWeaponCombatTest.gd`: 控制器、装备、连击与失败安全测试。
- Modify `UnitSystem/Tests/HeroVisualAssemblyTest.gd`: 更新视觉结构断言。
- Modify `UnitSystem/Tests/PlayerBaseMovementTest.gd`: 验证 PlayerBase 控制器装配和视觉边界。

---

### Task 1: WeaponData 与控制器测试骨架

**Files:**
- Create: `UnitSystem/Tests/PlayerWeaponCombatTest.gd`
- Create: `UnitSystem/Combat/WeaponData.gd`

**Interfaces:**
- Produces: `class_name WeaponData extends Resource`，字段 `display_name: String`、`visual_scene: PackedScene`、`animation_library: AnimationLibrary`。
- Consumes: 无。

- [ ] **Step 1: 写入失败测试**

测试先断言 `WeaponData` 可实例化、三个字段类型正确，并断言尚未创建的控制器脚本和 IronSword 资源存在。采用现有 SceneTree 测试格式，失败统一收集到 `failures: Array[String]`。

- [ ] **Step 2: 运行测试确认 RED**

Run:

```powershell
G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe --headless --path G:\Godot\SipSip -s res://UnitSystem/Tests/PlayerWeaponCombatTest.gd
```

Expected: 非零退出，报告控制器或 IronSword 资源尚不存在。

- [ ] **Step 3: 实现最小 WeaponData**

```gdscript
class_name WeaponData
extends Resource

## 武器在 Inspector 和调试输出中的名称。
@export var display_name: String = "Weapon"
## 装备时实例化到角色 WeaponSocket 下的纯视觉场景。
@export var visual_scene: PackedScene
## 针对角色视觉层级制作的攻击动画库。
@export var animation_library: AnimationLibrary
```

- [ ] **Step 4: 重跑测试确认只剩后续资源失败**

Expected: `WeaponData` 断言通过，测试仍因控制器或 IronSword 文件缺失而失败。

---

### Task 2: PlayerAttackController 连击状态机

**Files:**
- Create: `UnitSystem/Combat/PlayerAttackController.gd`
- Modify: `UnitSystem/Tests/PlayerWeaponCombatTest.gd`

**Interfaces:**
- Consumes: `WeaponData`。
- Produces:
  - `equip_weapon(weapon_data: WeaponData) -> bool`
  - `unequip_weapon() -> void`
  - `request_attack() -> void`
  - `cancel_combo() -> void`
  - `is_attacking() -> bool`
  - `get_combo_index() -> int`
  - Signals `weapon_equipped`、`weapon_unequipped`、`attack_started`、`attack_finished`、`combo_finished`。

- [ ] **Step 1: 扩充失败测试**

建立运行时最小 rig：父节点、`Visual/HeroVisual/WeaponSocket`、`CharacterAnimationPlayer` 和控制器。使用内存 AnimationLibrary 验证：

```gdscript
_assert_near(controller.input_buffer_duration, 0.15, 0.001, "input buffer")
_assert_near(controller.combo_reset_duration, 0.7, 0.001, "combo reset")
_assert_true(controller.hold_to_auto_chain, "hold chain enabled")
_assert_near(controller.hold_combo_restart_delay, 0.3, 0.001, "round delay")
_assert_true(controller.equip_weapon(valid_weapon), "valid weapon equips")
controller.request_attack()
_assert_equal(controller.get_combo_index(), 1, "first attack starts")
```

继续验证有效提前输入进入第二段、三段后不出现第四段、等待 `0.7s` 重置、持续按住后等待 `0.3s` 重开第一段，以及 `cancel_combo()` 恢复 RESET。

- [ ] **Step 2: 运行测试确认控制器缺失**

Expected: 非零退出，报告 `PlayerAttackController.gd` 不存在或接口缺失。

- [ ] **Step 3: 实现控制器最小完整状态机**

使用 `IDLE / ATTACKING / CHAIN_WAIT / ROUND_WAIT` 四态；动画名固定按 `weapon/basic_attack_%d` 组成。`_process(delta)` 只负责 InputMap 边沿、缓存倒计时、连击重置和按住轮次倒计时；动画结束由 `AnimationPlayer.animation_finished` 驱动。

关键规则：

```gdscript
func request_attack() -> void:
	if _attack_animation_count <= 0:
		return
	match _state:
		AttackState.IDLE:
			_start_attack(1)
		AttackState.ATTACKING:
			_input_buffer_remaining = input_buffer_duration
		AttackState.CHAIN_WAIT:
			_start_attack(_combo_index + 1)
		AttackState.ROUND_WAIT:
			_start_attack(1)
```

`_on_animation_finished()` 必须先发送 `attack_finished`；如果不是最后一段且缓存仍有效或左键持续按住，则立即开始下一段，否则进入 `CHAIN_WAIT`。最后一段发送 `combo_finished`，持续按住时进入 `ROUND_WAIT`，否则恢复空闲。

- [ ] **Step 4: 实现原子装备验证**

验证 `WeaponData` 非空、视觉场景根为 Node3D、动画库包含 `RESET` 和从 `basic_attack_1` 开始的无断档连续编号。全部验证通过后才取消旧连击、替换视觉和 `weapon` library；失败返回 `false` 并保持旧装备。

- [ ] **Step 5: 运行控制器测试确认 GREEN**

Expected: 控制器内存 rig 的装备、连击、缓存、超时、hold 和失败安全断言全部通过；实际资源存在性断言仍可等待 Task 4。

---

### Task 3: PlayerBase 与 HeroVisual 装配

**Files:**
- Modify: `UnitSystem/PlayerBase.tscn`
- Modify: `UnitSystem/Players/Hero/HeroVisual.tscn`
- Modify: `UnitSystem/Tests/HeroVisualAssemblyTest.gd`
- Modify: `UnitSystem/Tests/PlayerBaseMovementTest.gd`

**Interfaces:**
- Consumes: `PlayerAttackController.gd`。
- Produces: `PlayerBase/AttackController`、`HeroVisual/CharacterRoot`、`HeroVisual/WeaponSocket`、`HeroVisual/CharacterAnimationPlayer`。

- [ ] **Step 1: 更新结构测试并确认 RED**

HeroVisual 测试应断言根节点无脚本、`CharacterRoot/BodyMesh` 保持 `0.5m` 方块与 Tiffany Blue 材质、存在空 `WeaponSocket` 和 `CharacterAnimationPlayer`。PlayerBase 测试应断言 `AttackController` 存在但 `Visual` 仍为空，且 `PlayerBase.gd` 未增加攻击代码。

- [ ] **Step 2: 修改 HeroVisual 节点结构**

将现有 `BodyMesh` 移到 `CharacterRoot` 下，保持世界局部位置 `Vector3(0, 0.25, 0)`；新增空 `WeaponSocket`，默认位置 `Vector3(0.32, 0.28, -0.22)`；新增通用 `CharacterAnimationPlayer`。

- [ ] **Step 3: 将 AttackController 直接装入 PlayerBase**

为 `PlayerBase.tscn` 增加控制器脚本 ext_resource，并添加：

```text
[node name="AttackController" type="Node" parent="."]
script = ExtResource("player_attack_controller")
```

不修改 `PlayerBase.gd`。

- [ ] **Step 4: 运行结构与移动测试**

Run:

```powershell
G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe --headless --path G:\Godot\SipSip -s res://UnitSystem/Tests/HeroVisualAssemblyTest.gd
G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe --headless --path G:\Godot\SipSip -s res://UnitSystem/Tests/PlayerBaseMovementTest.gd
```

Expected: 两项 PASS；PlayerBase 移动、冲刺和索敌原测试保持通过。

---

### Task 4: IronSword 视觉、动画库、数据与工作台

**Files:**
- Create: `UnitSystem/Players/Hero/Weapons/IronSword/IronSwordVisual.tscn`
- Create: `UnitSystem/Players/Hero/Weapons/IronSword/IronSwordAnimations.tres`
- Create: `UnitSystem/Players/Hero/Weapons/IronSword/IronSwordData.tres`
- Modify: `UnitSystem/Players/Hero/Hero.tscn`
- Create: `UnitSystem/Players/Hero/HeroAnimationWorkbench.tscn`
- Modify: `UnitSystem/Tests/PlayerWeaponCombatTest.gd`

**Interfaces:**
- Consumes: `WeaponData`、HeroVisual 稳定节点路径、PlayerBase AttackController。
- Produces: Hero 的可运行 IronSword 初始装备与三段动画。

- [ ] **Step 1: 添加实际资源失败测试**

断言 IronSwordData 类型正确、视觉根为无脚本 Node3D、动画库包含 `RESET` 和恰好三段连续攻击；实例化 Hero 后等待一帧，断言剑位于 `Visual/HeroVisual/WeaponSocket` 下且 `CharacterAnimationPlayer` 注册 `weapon` library。

- [ ] **Step 2: 创建无脚本铁剑视觉**

用 `MatGridLight.tres` Blade 与 `MatGridDark.tres` Handle 创建简单 CSGBox3D 剑。场景不包含 AnimationPlayer、脚本、Hitbox 或攻击逻辑。

- [ ] **Step 3: 创建外部 AnimationLibrary**

动画长度分别为 `0.32s / 0.36s / 0.45s`。每段只为 `CharacterRoot:rotation`、`WeaponSocket:position` 和 `WeaponSocket:rotation` 建轨，并在末帧恢复 RESET 值；不添加方法轨道、位移根节点或命中窗口。

- [ ] **Step 4: 创建 IronSwordData 并配置 Hero**

`IronSwordData.tres` 引用视觉与动画库；`Hero.tscn` 只覆盖继承节点 `AttackController.starting_weapon`。不得在 Hero 根脚本中增加攻击依赖。

- [ ] **Step 5: 创建单一工作台**

`HeroAnimationWorkbench.tscn` 实例化同一 `HeroVisual.tscn`，在其 WeaponSocket 下放入同一 IronSwordVisual，并给同一 CharacterAnimationPlayer 注册 `weapon` 动画库。场景不被 Hero 或 TestScene 引用。

- [ ] **Step 6: 运行 PlayerWeaponCombatTest**

Expected: 资源结构、Hero 自动装备和三段动画断言全部 PASS。

---

### Task 5: 全量回归与编辑器扫描

**Files:**
- Modify only if required by a proven regression: files already listed above.

**Interfaces:**
- Consumes: 完成后的全部新资源。
- Produces: Godot 4.7 可编译、现有 UnitSystem 行为不回归的证据。

- [ ] **Step 1: 运行全部 UnitSystem SceneTree 测试**

```powershell
Get-ChildItem UnitSystem\Tests -Filter '*.gd' | ForEach-Object {
  & G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe --headless --path G:\Godot\SipSip -s ("res://UnitSystem/Tests/" + $_.Name)
  if ($LASTEXITCODE -ne 0) { throw "Test failed: $($_.Name)" }
}
```

Expected: 每个测试打印 `PASS`，所有进程退出码为 0。

- [ ] **Step 2: 运行项目导入和主场景无窗口扫描**

```powershell
G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe --headless --editor --path G:\Godot\SipSip --quit
G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe --headless --path G:\Godot\SipSip --quit-after 5
```

Expected: 无脚本解析错误、资源加载错误或新增 warning。

- [ ] **Step 3: 核对禁止修改范围**

对实施前记录的旧 Hero、旧 MeleeAttackModule 与 TestScene 文件哈希进行比较，Expected: 三者哈希不变。

- [ ] **Step 4: 更新计划复选框与验证结果**

在本计划中勾选已完成任务，并追加实际测试命令、通过数量与任何已确认限制；不得把未执行的手动游戏体验检查标记为已验证。

---

## Implementation Result

- Status: implemented on 2026-07-22.
- Automated tests: `11/11` UnitSystem SceneTree tests passed.
- Godot 4.7 editor scan: `0` errors and `0` warnings.
- Headless main-scene startup: `0` errors and `0` warnings.
- Protected legacy files: old Hero, old MeleeAttackModule, and TestScene SHA-256 hashes unchanged.
- Manual visual feel check in the interactive editor remains for the user; automated tests verify the animation resources, lengths, mounting paths, combo state machine, input buffer, hold chaining, round delay, safe cancellation, and atomic equip failure.
