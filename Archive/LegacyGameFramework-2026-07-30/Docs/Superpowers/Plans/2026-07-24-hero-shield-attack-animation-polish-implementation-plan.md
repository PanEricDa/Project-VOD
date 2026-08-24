# Hero Shield Attack Animation Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 Hero 盾牌的两段普通攻击调整为具有身体协同动作的前顶与左向右横扫，同时确保 Workbench 和运行时只使用同一份外部动画库。

**Architecture:** 不修改玩家攻击控制器和盾牌模型，只重建 `ShieldAnimationLibrary.res` 中的两个攻击动画。动画通过 `CharacterRoot` 与 `WeaponSocket` 的四条值轨道表现身体重心、转体和盾牌弧线；结构测试直接加载外部资源并检查轨道、幅度、复位和 Workbench 引用。

**Tech Stack:** Godot 4.7、GDScript、AnimationLibrary、Animation、Godot MCP Pro、Godot headless test。

## Global Constraints

- 唯一运行时动画资源必须是 `res://Item/Weapon/IronShield/ShieldAnimationLibrary.res`。
- 不修改 `res://Item/Weapon/IronSword/IronSwordAnimationLibrary.res`。
- 不修改 `PlayerAttackController.gd`、`IronShieldVisual.tscn`、盾牌材质、伤害、真实位移或 Hitbox 参数。
- 动画轨道相对 `HeroVisual/CharacterAnimationPlayer`，不得直接绑定 `IronShieldVisual`。
- 第一段总长 `0.46s`；第二段总长 `0.52s`。
- 两段最终姿势必须精确返回外部动画库的 `RESET` 值。
- 项目不是 Git 仓库；每个任务以测试与文件检查点替代提交步骤。

---

### Task 1: 建立盾动画结构回归测试

**Files:**
- Create: `UnitSystem/Tests/ShieldAnimationLibraryTest.gd`
- Read: `Item/Weapon/IronShield/ShieldAnimationLibrary.res`
- Read: `UnitSystem/Player/Hero/HeroAnimationWorkbench.tscn`

**Interfaces:**
- Consumes: `AnimationLibrary.get_animation()`、`Animation.find_track()`、`Animation.track_get_key_value()`。
- Produces: 一个可通过 Godot headless 执行、成功时退出码为 `0`、失败时退出码为 `1` 的资源结构测试。

- [ ] **Step 1: 写入会因缺少 CharacterRoot 轨道而失败的测试**

创建 `UnitSystem/Tests/ShieldAnimationLibraryTest.gd`：

```gdscript
extends SceneTree

const LIBRARY_PATH: String = (
	"res://Item/Weapon/IronShield/ShieldAnimationLibrary.res"
)
const WORKBENCH_PATH: String = (
	"res://UnitSystem/Player/Hero/HeroAnimationWorkbench.tscn"
)
const LIBRARY_NAME: StringName = &"ShieldAnimationLibrary"
const REQUIRED_ANIMATIONS: Array[StringName] = [
	&"RESET",
	&"basic_attack_1",
	&"basic_attack_2",
]

var failures: Array[String] = []


func _initialize() -> void:
	var library: AnimationLibrary = load(LIBRARY_PATH) as AnimationLibrary
	_expect(library != null, "ShieldAnimationLibrary.res must load")
	if library == null:
		_finish()
		return

	for animation_name: StringName in REQUIRED_ANIMATIONS:
		_expect(
			library.has_animation(animation_name),
			"Missing animation: %s" % animation_name
		)

	var attack_1: Animation = library.get_animation(&"basic_attack_1")
	var attack_2: Animation = library.get_animation(&"basic_attack_2")
	var reset: Animation = library.get_animation(&"RESET")
	if attack_1 == null or attack_2 == null or reset == null:
		_finish()
		return

	_expect(
		is_equal_approx(attack_1.length, 0.46),
		"basic_attack_1 length must be 0.46s"
	)
	_expect(
		is_equal_approx(attack_2.length, 0.52),
		"basic_attack_2 length must be 0.52s"
	)

	var required_paths: Array[NodePath] = [
		^"CharacterRoot:position",
		^"CharacterRoot:rotation",
		^"CharacterRoot/WeaponSocket:position",
		^"CharacterRoot/WeaponSocket:rotation",
	]
	for animation: Animation in [attack_1, attack_2]:
		for track_path: NodePath in required_paths:
			_expect(
				animation.find_track(
					track_path,
					Animation.TYPE_VALUE
				) >= 0,
				"%s missing track %s" % [
					animation.resource_name,
					track_path,
				]
			)

	var attack_1_socket_position_track: int = attack_1.find_track(
		^"CharacterRoot/WeaponSocket:position",
		Animation.TYPE_VALUE
	)
	if attack_1_socket_position_track >= 0:
		var minimum_z: float = INF
		for key_index: int in range(
			attack_1.track_get_key_count(attack_1_socket_position_track)
		):
			var value: Vector3 = attack_1.track_get_key_value(
				attack_1_socket_position_track,
				key_index
			)
			minimum_z = minf(minimum_z, value.z)
		_expect(
			minimum_z <= -0.45,
			"basic_attack_1 must visibly thrust forward"
		)

	var attack_2_socket_position_track: int = attack_2.find_track(
		^"CharacterRoot/WeaponSocket:position",
		Animation.TYPE_VALUE
	)
	if attack_2_socket_position_track >= 0:
		var minimum_x: float = INF
		var maximum_x: float = -INF
		for key_index: int in range(
			attack_2.track_get_key_count(attack_2_socket_position_track)
		):
			var value: Vector3 = attack_2.track_get_key_value(
				attack_2_socket_position_track,
				key_index
			)
			minimum_x = minf(minimum_x, value.x)
			maximum_x = maxf(maximum_x, value.x)
		_expect(
			maximum_x - minimum_x >= 0.70,
			"basic_attack_2 must have a readable left-to-right arc"
		)

	_assert_animation_returns_to_reset(
		attack_1,
		reset,
		^"CharacterRoot:position"
	)
	_assert_animation_returns_to_reset(
		attack_1,
		reset,
		^"CharacterRoot:rotation"
	)
	_assert_animation_returns_to_reset(
		attack_1,
		reset,
		^"CharacterRoot/WeaponSocket:position"
	)
	_assert_animation_returns_to_reset(
		attack_1,
		reset,
		^"CharacterRoot/WeaponSocket:rotation"
	)
	_assert_animation_returns_to_reset(
		attack_2,
		reset,
		^"CharacterRoot:position"
	)
	_assert_animation_returns_to_reset(
		attack_2,
		reset,
		^"CharacterRoot:rotation"
	)
	_assert_animation_returns_to_reset(
		attack_2,
		reset,
		^"CharacterRoot/WeaponSocket:position"
	)
	_assert_animation_returns_to_reset(
		attack_2,
		reset,
		^"CharacterRoot/WeaponSocket:rotation"
	)

	var workbench_scene: PackedScene = load(WORKBENCH_PATH) as PackedScene
	_expect(workbench_scene != null, "HeroAnimationWorkbench must load")
	if workbench_scene != null:
		var workbench: Node = workbench_scene.instantiate()
		var animation_player: AnimationPlayer = workbench.get_node(
			"HeroVisual/CharacterAnimationPlayer"
		) as AnimationPlayer
		var mounted_library: AnimationLibrary = (
			animation_player.get_animation_library(LIBRARY_NAME)
		)
		_expect(
			mounted_library != null,
			"Workbench must mount ShieldAnimationLibrary"
		)
		if mounted_library != null:
			_expect(
				mounted_library.resource_path == LIBRARY_PATH,
				"Workbench must reference the external shield library"
			)
		workbench.free()

	_finish()


func _assert_animation_returns_to_reset(
	animation: Animation,
	reset: Animation,
	track_path: NodePath
) -> void:
	var animation_track: int = animation.find_track(
		track_path,
		Animation.TYPE_VALUE
	)
	var reset_track: int = reset.find_track(
		track_path,
		Animation.TYPE_VALUE
	)
	_expect(
		animation_track >= 0,
		"%s missing return track %s" % [
			animation.resource_name,
			track_path,
		]
	)
	_expect(
		reset_track >= 0,
		"RESET missing track %s" % track_path
	)
	if animation_track < 0 or reset_track < 0:
		return
	var final_value: Vector3 = animation.track_get_key_value(
		animation_track,
		animation.track_get_key_count(animation_track) - 1
	)
	var reset_value: Vector3 = reset.track_get_key_value(reset_track, 0)
	_expect(
		final_value.is_equal_approx(reset_value),
		"%s does not return %s to RESET" % [
			animation.resource_name,
			track_path,
		]
	)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("ShieldAnimationLibraryTest: PASS")
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	print(
		"ShieldAnimationLibraryTest: FAIL (%d)" % failures.size()
	)
	quit(1)
```

- [ ] **Step 2: 运行测试并确认按预期失败**

Run:

```powershell
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' `
  --headless `
  --path 'G:\Godot\SipSip' `
  --script res://UnitSystem/Tests/ShieldAnimationLibraryTest.gd
```

Expected: `FAIL`，原因包括两段动画缺少 `CharacterRoot:position` 或 `CharacterRoot:rotation`，并且动画长度仍为旧值 `0.4s`。

---

### Task 2: 重建两段盾牌攻击动画

**Files:**
- Modify: `Item/Weapon/IronShield/ShieldAnimationLibrary.res`
- Verify only: `UnitSystem/Player/Hero/HeroAnimationWorkbench.tscn`
- Test: `UnitSystem/Tests/ShieldAnimationLibraryTest.gd`

**Interfaces:**
- Consumes: 外部动画库中的现有 `RESET` 持盾姿势。
- Produces: `basic_attack_1: Animation` 和 `basic_attack_2: Animation`，各包含四条相对 `HeroVisual` 的值轨道。

- [ ] **Step 1: 补齐 RESET 的 CharacterRoot 基准轨道**

通过 Godot MCP Pro 的 `execute_editor_script` 加载：

```gdscript
var library: AnimationLibrary = load(
	"res://Item/Weapon/IronShield/ShieldAnimationLibrary.res"
) as AnimationLibrary
```

保留 `RESET` 当前的 WeaponSocket 持盾值，并为新加入的身体轨道补充明确的零值：

```gdscript
var reset: Animation = library.get_animation(&"RESET")
var reset_root_position_track: int = reset.find_track(
	^"CharacterRoot:position",
	Animation.TYPE_VALUE
)
if reset_root_position_track < 0:
	reset_root_position_track = reset.add_track(Animation.TYPE_VALUE)
	reset.track_set_path(
		reset_root_position_track,
		^"CharacterRoot:position"
	)
	reset.track_insert_key(
		reset_root_position_track,
		0.0,
		Vector3.ZERO
	)

var reset_root_rotation_track: int = reset.find_track(
	^"CharacterRoot:rotation",
	Animation.TYPE_VALUE
)
if reset_root_rotation_track < 0:
	reset_root_rotation_track = reset.add_track(Animation.TYPE_VALUE)
	reset.track_set_path(
		reset_root_rotation_track,
		^"CharacterRoot:rotation"
	)
	reset.track_insert_key(
		reset_root_rotation_track,
		0.0,
		Vector3.ZERO
	)
```

- [ ] **Step 2: 使用 Godot Editor API 重建 basic_attack_1**

替换 `basic_attack_1`。设置：

```gdscript
attack_1.resource_name = "basic_attack_1"
attack_1.length = 0.46
```

按以下关键帧写入四条 `Animation.TYPE_VALUE` 轨道，并将插值设置为 `Animation.INTERPOLATION_CUBIC`：

```gdscript
var attack_1_times := PackedFloat32Array([
	0.00,
	0.10,
	0.20,
	0.26,
	0.46,
])

var attack_1_root_positions: Array[Vector3] = [
	Vector3.ZERO,
	Vector3(0.0, 0.0, 0.025),
	Vector3(0.0, 0.0, -0.045),
	Vector3(0.0, 0.0, -0.035),
	Vector3.ZERO,
]

var attack_1_root_rotations: Array[Vector3] = [
	Vector3.ZERO,
	Vector3(
		deg_to_rad(-8.0),
		deg_to_rad(10.0),
		deg_to_rad(-3.0)
	),
	Vector3(
		deg_to_rad(9.0),
		deg_to_rad(-5.0),
		deg_to_rad(2.0)
	),
	Vector3(
		deg_to_rad(7.0),
		deg_to_rad(-4.0),
		deg_to_rad(1.0)
	),
	Vector3.ZERO,
]

var attack_1_socket_positions: Array[Vector3] = [
	Vector3(0.356302, 0.28, -0.068774),
	Vector3(0.30, 0.43, -0.02),
	Vector3(0.32, 0.44, -0.50),
	Vector3(0.32, 0.42, -0.48),
	Vector3(0.356302, 0.28, -0.068774),
]

var attack_1_socket_rotations: Array[Vector3] = [
	Vector3(0.072405, -1.538329, 0.002350),
	Vector3(-0.30, -1.25, -0.16),
	Vector3(0.18, -1.67, 0.08),
	Vector3(0.14, -1.62, 0.05),
	Vector3(0.072405, -1.538329, 0.002350),
]
```

每个关键帧的 transition 使用：

```gdscript
PackedFloat32Array([0.75, 1.65, 1.0, 0.70, 1.0])
```

- [ ] **Step 3: 重建 basic_attack_2**

替换 `basic_attack_2`，设置：

```gdscript
attack_2.resource_name = "basic_attack_2"
attack_2.length = 0.52
```

写入：

```gdscript
var attack_2_times := PackedFloat32Array([
	0.00,
	0.12,
	0.25,
	0.32,
	0.52,
])

var attack_2_root_positions: Array[Vector3] = [
	Vector3.ZERO,
	Vector3(-0.04, 0.0, 0.02),
	Vector3(0.05, 0.0, -0.03),
	Vector3(0.07, 0.0, -0.01),
	Vector3.ZERO,
]

var attack_2_root_rotations: Array[Vector3] = [
	Vector3.ZERO,
	Vector3(
		deg_to_rad(-3.0),
		deg_to_rad(18.0),
		deg_to_rad(-5.0)
	),
	Vector3(
		deg_to_rad(5.0),
		deg_to_rad(-20.0),
		deg_to_rad(6.0)
	),
	Vector3(
		deg_to_rad(3.0),
		deg_to_rad(-23.0),
		deg_to_rad(7.0)
	),
	Vector3.ZERO,
]

var attack_2_socket_positions: Array[Vector3] = [
	Vector3(0.356302, 0.28, -0.068774),
	Vector3(-0.18, 0.33, -0.18),
	Vector3(0.58, 0.34, -0.40),
	Vector3(0.66, 0.30, -0.22),
	Vector3(0.356302, 0.28, -0.068774),
]

var attack_2_socket_rotations: Array[Vector3] = [
	Vector3(0.072405, -1.538329, 0.002350),
	Vector3(-0.10, deg_to_rad(22.0), -0.20),
	Vector3(0.22, deg_to_rad(-118.0), 0.16),
	Vector3(0.16, deg_to_rad(-128.0), 0.22),
	Vector3(0.072405, -1.538329, 0.002350),
]
```

每个关键帧的 transition 使用：

```gdscript
PackedFloat32Array([0.70, 1.80, 1.0, 0.65, 1.0])
```

- [ ] **Step 4: 保存唯一外部资源**

使用 Godot Editor API 保存同一个资源实例：

```gdscript
var save_error: Error = ResourceSaver.save(
	library,
	"res://Item/Weapon/IronShield/ShieldAnimationLibrary.res"
)
if save_error != OK:
	push_error(
		"Failed to save ShieldAnimationLibrary.res: %s"
		% error_string(save_error)
	)
```

保存前确认当前 Workbench 没有另一份未保存的盾动画副本；保存后刷新资源并保持：

```text
libraries/ShieldAnimationLibrary = ExtResource(...)
```

- [ ] **Step 5: 运行结构测试并确认通过**

Run:

```powershell
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' `
  --headless `
  --path 'G:\Godot\SipSip' `
  --script res://UnitSystem/Tests/ShieldAnimationLibraryTest.gd
```

Expected:

```text
ShieldAnimationLibraryTest: PASS
```

---

### Task 3: 编辑器预览与项目回归验证

**Files:**
- Verify: `Item/Weapon/IronShield/ShieldAnimationLibrary.res`
- Verify: `UnitSystem/Player/Hero/HeroAnimationWorkbench.tscn`
- Verify: `Item/Weapon/IronShield/IronSieldData.tres`

**Interfaces:**
- Consumes: Task 2 生成的外部 AnimationLibrary。
- Produces: 编辑器与运行时验证记录，不新增运行时代码。

- [ ] **Step 1: 在 Workbench 预览两段动画**

在 `HeroAnimationWorkbench.tscn` 的 `CharacterAnimationPlayer` 中依次播放：

```text
ShieldAnimationLibrary/basic_attack_1
ShieldAnimationLibrary/basic_attack_2
```

检查：

- 第一段先抬盾后向前顶出。
- 第二段从左侧蓄力并横扫穿过正前方。
- 身体旋转不会使角色根节点或碰撞体发生真实位移。
- 两段结尾都回到同一个基础持盾姿势。

- [ ] **Step 2: 执行 Godot 4.7 编辑器扫描**

Run:

```powershell
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' `
  --headless `
  --editor `
  --path 'G:\Godot\SipSip' `
  --quit
```

Expected: exit code `0`，无资源加载、动画轨道或脚本编译错误。

- [ ] **Step 3: 执行主场景无窗口启动**

Run:

```powershell
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' `
  --headless `
  --path 'G:\Godot\SipSip' `
  --quit-after 120
```

Expected: exit code `0`，Output 不出现新增 error 或 warning。

- [ ] **Step 4: 使用 MCP 检查编辑器错误**

调用 Godot MCP Pro 的 `get_editor_errors`，Expected:

```text
count = 0
```

- [ ] **Step 5: 等待用户在 Workbench 中确认视觉手感**

向用户说明两个动画的总长、身体最大转角和盾牌扫击方向，请用户在 Workbench 中 Preview。只有用户确认视觉效果后，本轮动画调整才视为最终定稿。
