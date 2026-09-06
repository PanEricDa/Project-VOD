# Player Dash Charge HUD Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将玩家 Dash 改为不重置进度的逐层恢复，并在玩家生命条下方增加只读监控最终业务进度的淡黄色细条。

**Architecture:** `PlayerBase` 继续独占 Dash 次数、恢复计时、有效容量和连续进度计算，只增加 `get_dash_charge_capacity()` 与 `get_dash_charge_progress()` 两个只读查询。新增 `PlayerDashStatusBar` 只把查询结果赋给 ProgressBar；`CombatHUD` 通过 `UnitHealthFrame` 的通用扩展槽装配和绑定该显示组件，其他生命框不感知 Dash。

**Tech Stack:** Godot Engine 4.7、GDScript、Control/ProgressBar、StyleBoxFlat、SceneTree headless tests、PowerShell、Git。

**Spec:** `Docs/Superpowers/Specs/2026-09-06-PlayerDashChargeHudDesign.md`

## Global Constraints

- 正确项目根目录固定为 `G:\Godot\ProjectVOD`；不得使用旧目录 `G:\Godot\SipSip` 或不存在的 `G:\Godot\ProjSipSip`。
- 除原则性错误或严重 Bug 外，不整理、精简或重构现有移动与 HUD 结构，只做本功能需要的最小修改和直接扩展。
- `PlayerBase` 是 Dash 次数、CD 与连续恢复进度的唯一事实来源。
- HUD 只读取 `get_dash_charge_capacity()` 与 `get_dash_charge_progress()` 的最终结果并直接显示；不得钳制容量、计算 CD 比例、推进时间、缓存预计完成时间或写入 Dash 状态。
- 不修改 AI Dash、Dash 距离、速度、无敌阶段、攻击取消、输入映射、伙伴 AI、技能、物品、仇恨或锁定逻辑。
- 不修改 `Scenes/TestScene.tscn`，也不自动向该场景添加、删除或调整任何单位实例。
- 不修改现有公开 Dash 方法的名称、参数或返回类型；只允许增加已在规格中定义的只读查询。
- 所有新增 `@export` 参数、公开方法及其参数必须在声明附近提供简体中文说明，符合 `AGENTS.md`。
- 不创建外部 `.tres` 或 `.res`；Dash 条样式使用场景内 `StyleBoxFlat` 子资源。
- 保留工作区中与本功能无关的用户改动，不提交 `project.godot` 或无关 `.uid` 文件。

---

## File Structure

### Create

- `UnitSystem/Tests/PlayerDashRechargeTest.gd`：冻结逐层恢复、进度保留、大 `delta` 和零 CD 的业务契约。
- `UnitSystem/Components/UI/PlayerDashStatusBar.gd`：只读绑定玩家并转发最终连续进度到 ProgressBar。
- `UnitSystem/Components/UI/PlayerDashStatusBar.tscn`：定义淡黄色 8 像素 Dash 条及场景内样式。
- `UnitSystem/Tests/PlayerDashStatusBarTest.gd`：验证显示映射与“HUD 不改变业务状态”契约。

### Modify

- `UnitSystem/Player/PlayerBase.gd`：把现有整组恢复改为逐层恢复，增加有效容量与最终进度只读查询。
- `UnitSystem/Components/UI/UnitHealthFrame.gd`：增加通用扩展内容装配/清理接口并即时刷新槽位可见性。
- `UnitSystem/Components/UI/UnitHealthFrame.tscn`：把现有 `ExtensionSlot` 移到生命条下方。
- `UnitSystem/Tests/UnitHealthFrameTest.gd`：冻结扩展槽路径、装配、玩家模式与非玩家模式行为。
- `GameFlow/UI/CombatHUD.gd`：创建唯一玩家 Dash 条并同步玩家绑定/解绑。
- `GameFlow/Tests/CombatHUDTest.gd`：验证玩家框装配 Dash 条且伙伴框不装配。
- `GameFlow/Tests/CombatHUDBindingIntegrationTest.gd`：验证场景切换后 Dash 条跟随新玩家并断开旧玩家。
- `Docs/CurrentSystemUserGuide.md`：记录新 Dash 恢复规则与 HUD 含义。
- `Docs/CurrentProgressReport.md`：记录完成范围与验证结果。

### Existing Regression Tests

- `UnitSystem/Tests/PlayerDashComboContinuityTest.gd`
- `UnitSystem/Tests/UnitDeathLifecycleTest.gd`
- `GameFlow/Tests/CombatHUDTargetHealthTest.gd`
- `GameFlow/Tests/GameRunResultFlowTest.gd`

---

### Task 1: PlayerBase 逐层 Dash 恢复

**Files:**
- Create: `UnitSystem/Tests/PlayerDashRechargeTest.gd`
- Modify: `UnitSystem/Player/PlayerBase.gd:38-46, 212-217, 385-462`

**Interfaces:**
- Consumes: 现有 `maximum_consecutive_dashes: int`、`dash_cooldown_duration: float`、`get_available_dash_count() -> int`、`get_dash_cooldown_remaining() -> float`。
- Produces: `get_dash_charge_capacity() -> int`、`get_dash_charge_progress() -> float`；不重置当前恢复计时的逐层恢复行为。

- [ ] **Step 1: 编写逐层恢复失败测试骨架**

创建 `UnitSystem/Tests/PlayerDashRechargeTest.gd`，使用真实 `PlayerBase.tscn`，在加入树前设置两层和 2 秒 CD。测试不得复制恢复公式；只断言公开查询的确定结果。

```gdscript
extends SceneTree

const PLAYER_PATH := "res://UnitSystem/Player/PlayerBase.tscn"

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	var player_scene := load(PLAYER_PATH) as PackedScene
	_expect(player_scene != null, "PlayerBase scene loads")
	if player_scene == null:
		_finish()
		return
	var player := player_scene.instantiate() as PlayerBase
	player.maximum_consecutive_dashes = 2
	player.dash_cooldown_duration = 2.0
	root.add_child(player)
	await process_frame

	_expect(player.get_available_dash_count() == 2, "player starts with two dash charges")
	_expect(player.has_method(&"get_dash_charge_capacity"), "dash exposes sanitized read-only capacity")
	_expect(player.has_method(&"get_dash_charge_progress"), "dash exposes final read-only progress")
	if not player.has_method(&"get_dash_charge_capacity") or not player.has_method(&"get_dash_charge_progress"):
		player.queue_free()
		await process_frame
		_finish()
		return
	_expect(player.get_dash_charge_capacity() == 2, "configured capacity is exposed by the business layer")
	_expect(is_equal_approx(player.get_dash_charge_progress(), 2.0), "full charges report full progress")

	player._start_dash(Vector3.FORWARD)
	player._finish_dash(Vector3.ZERO)
	_expect(player.get_available_dash_count() == 1, "first dash consumes one charge")
	_expect(is_equal_approx(player.get_dash_cooldown_remaining(), 2.0), "first spent charge immediately starts recharge")
	_expect(is_equal_approx(player.get_dash_charge_progress(), 1.0), "progress falls by exactly one charge")

	player._update_dash_cooldown(0.75)
	var preserved_remaining := player.get_dash_cooldown_remaining()
	_expect(is_equal_approx(preserved_remaining, 1.25), "recharge advances before second dash")
	_expect(is_equal_approx(player.get_dash_charge_progress(), 1.375), "business layer reports partial charge")

	player._start_dash(Vector3.FORWARD)
	player._finish_dash(Vector3.ZERO)
	_expect(player.get_available_dash_count() == 0, "second dash consumes the remaining full charge")
	_expect(is_equal_approx(player.get_dash_cooldown_remaining(), preserved_remaining), "second dash does not reset recharge")
	_expect(is_equal_approx(player.get_dash_charge_progress(), 0.375), "second dash preserves partial recharge and removes exactly one")

	player._update_dash_cooldown(1.25)
	_expect(player.get_available_dash_count() == 1, "one cooldown restores one charge")
	_expect(is_equal_approx(player.get_dash_cooldown_remaining(), 2.0), "missing second charge starts the next cooldown")
	player._update_dash_cooldown(2.0)
	_expect(player.get_available_dash_count() == 2, "second cooldown restores full charges")
	_expect(is_zero_approx(player.get_dash_cooldown_remaining()), "full charges stop recharge")

	player.queue_free()
	await process_frame
	_finish()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("PlayerDashRechargeTest: PASS")
		quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	print("PlayerDashRechargeTest: FAIL (%d)" % _failures.size())
	quit(1)
```

- [ ] **Step 2: 运行测试并确认旧规则失败**

Run:

```powershell
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' `
  --headless --path 'G:\Godot\ProjectVOD' `
  --script 'res://UnitSystem/Tests/PlayerDashRechargeTest.gd'
```

Expected: exit code `1`；至少因缺少只读容量/进度查询或第一次 Dash 后没有开始 CD 而失败。不得为了让红灯通过而放宽断言。

- [ ] **Step 3: 在 PlayerBase 增加只读最终进度接口**

在现有两个 Dash getter 附近增加带简体中文契约说明的方法。有效容量钳制与所有显示所需的比例合成都必须留在这里。

```gdscript
## 返回不小于 1 的有效最大 Dash 次数；只读消费者无需重复处理 Inspector 异常值。
func get_dash_charge_capacity() -> int:
	return maxi(maximum_consecutive_dashes, 1)


## 返回 0 到最大 Dash 次数之间的连续业务进度：完整可用次数加当前恢复层完成比例。
## 本方法只读取 PlayerBase 已有状态，供 HUD 与调试工具监控；调用者不得据此写回或推进 Dash。
func get_dash_charge_progress() -> float:
	var maximum_count := get_dash_charge_capacity()
	var available_count := clampi(_available_dash_count, 0, maximum_count)
	if available_count >= maximum_count:
		return float(maximum_count)
	var cooldown_duration := maxf(dash_cooldown_duration, 0.0)
	if cooldown_duration <= 0.0 or _dash_cooldown_remaining <= 0.0:
		return float(available_count)
	var layer_progress := 1.0 - clampf(
		_dash_cooldown_remaining / cooldown_duration,
		0.0,
		1.0
	)
	return clampf(
		float(available_count) + layer_progress,
		0.0,
		float(maximum_count)
	)
```

- [ ] **Step 4: 将冷却启动移动到次数消耗点**

在 `_start_dash()` 扣除次数后调用私有启动方法；从 `_finish_dash()` 删除“仅耗尽才启动”的分支。

```gdscript
	_available_dash_count = maxi(_available_dash_count - 1, 0)
	_ensure_dash_recharge_started()
```

```gdscript
## 在 Dash 次数未满且没有活动计时时启动当前层恢复；已有计时保持不变。
func _ensure_dash_recharge_started() -> void:
	var maximum_count := get_dash_charge_capacity()
	_available_dash_count = clampi(_available_dash_count, 0, maximum_count)
	if _available_dash_count >= maximum_count:
		_dash_cooldown_remaining = 0.0
		return
	var cooldown_duration := maxf(dash_cooldown_duration, 0.0)
	if cooldown_duration <= 0.0:
		_available_dash_count = maximum_count
		_dash_cooldown_remaining = 0.0
		return
	if _dash_cooldown_remaining <= 0.0:
		_dash_cooldown_remaining = cooldown_duration
```

`_finish_dash()` 在完成水平速度收尾后直接返回，不再写 `_dash_cooldown_remaining`。

- [ ] **Step 5: 实现可保留时间余量的逐层恢复**

替换 `_update_dash_cooldown()`。循环只处理本帧实际跨越的完整周期；零 CD 在进入循环前收束，避免死循环。

```gdscript
func _update_dash_cooldown(delta: float) -> void:
	var maximum_count := get_dash_charge_capacity()
	_available_dash_count = clampi(_available_dash_count, 0, maximum_count)
	if _available_dash_count >= maximum_count:
		_dash_cooldown_remaining = 0.0
		return
	var cooldown_duration := maxf(dash_cooldown_duration, 0.0)
	if cooldown_duration <= 0.0:
		_available_dash_count = maximum_count
		_dash_cooldown_remaining = 0.0
		return
	if _dash_cooldown_remaining <= 0.0:
		_dash_cooldown_remaining = cooldown_duration
	_dash_cooldown_remaining -= maxf(delta, 0.0)
	while _dash_cooldown_remaining <= 0.0 and _available_dash_count < maximum_count:
		_available_dash_count += 1
		if _available_dash_count >= maximum_count:
			_dash_cooldown_remaining = 0.0
			break
		_dash_cooldown_remaining += cooldown_duration
```

- [ ] **Step 6: 扩充业务测试的边界场景**

在同一测试中创建独立玩家夹具，增加以下明确断言：

```gdscript
# 0 层、2 秒 CD，推进 4.5 秒应直接恢复至 2 层且停止计时。
large_delta_player._start_dash(Vector3.FORWARD)
large_delta_player._finish_dash(Vector3.ZERO)
large_delta_player._start_dash(Vector3.FORWARD)
large_delta_player._finish_dash(Vector3.ZERO)
large_delta_player._update_dash_cooldown(4.5)
_expect(large_delta_player.get_available_dash_count() == 2, "large delta restores every elapsed layer")
_expect(is_zero_approx(large_delta_player.get_dash_cooldown_remaining()), "full result discards unused overflow")

# 零 CD 消耗后立即保持满层，不进入循环。
zero_cooldown_player.dash_cooldown_duration = 0.0
zero_cooldown_player._start_dash(Vector3.FORWARD)
_expect(zero_cooldown_player.get_available_dash_count() == 2, "zero cooldown immediately restores all missing charges")
_expect(is_zero_approx(zero_cooldown_player.get_dash_cooldown_remaining()), "zero cooldown has no active timer")
```

- [ ] **Step 7: 运行 Dash 业务与既有连续攻击测试**

Run:

```powershell
$godot = 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe'
& $godot --headless --path 'G:\Godot\ProjectVOD' --script 'res://UnitSystem/Tests/PlayerDashRechargeTest.gd'
& $godot --headless --path 'G:\Godot\ProjectVOD' --script 'res://UnitSystem/Tests/PlayerDashComboContinuityTest.gd'
```

Expected: both exit code `0` and print `PASS`。

- [ ] **Step 8: 提交独立业务改动**

```powershell
git add -- 'UnitSystem/Player/PlayerBase.gd' 'UnitSystem/Tests/PlayerDashRechargeTest.gd'
git commit -m 'feat: recharge player dash charges sequentially'
```

---

### Task 2: 只读 PlayerDashStatusBar 组件

**Files:**
- Create: `UnitSystem/Components/UI/PlayerDashStatusBar.gd`
- Create: `UnitSystem/Components/UI/PlayerDashStatusBar.tscn`
- Create: `UnitSystem/Tests/PlayerDashStatusBarTest.gd`

**Interfaces:**
- Consumes: `PlayerBase.get_dash_charge_capacity() -> int`、`PlayerBase.get_dash_charge_progress() -> float`。
- Produces: `bind_player(player: PlayerBase) -> void`、`unbind_player() -> void`、`is_bound() -> bool`。

- [ ] **Step 1: 编写 HUD 只读监控失败测试**

创建 `UnitSystem/Tests/PlayerDashStatusBarTest.gd`。测试必须在调用 HUD 更新前后保存玩家业务状态，证明显示没有写回。

```gdscript
extends SceneTree

const BAR_PATH := "res://UnitSystem/Components/UI/PlayerDashStatusBar.tscn"
const PLAYER_PATH := "res://UnitSystem/Player/PlayerBase.tscn"

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	_expect(ResourceLoader.exists(BAR_PATH), "dash status bar scene exists")
	var bar_scene := load(BAR_PATH) as PackedScene
	var player_scene := load(PLAYER_PATH) as PackedScene
	_expect(bar_scene != null and player_scene != null, "dash HUD fixtures load")
	if bar_scene == null or player_scene == null:
		_finish()
		return

	var bar := bar_scene.instantiate() as PlayerDashStatusBar
	var player := player_scene.instantiate() as PlayerBase
	player.maximum_consecutive_dashes = 2
	player.dash_cooldown_duration = 2.0
	root.add_child(player)
	root.add_child(bar)
	await process_frame

	_expect(not bar.visible and not bar.is_bound(), "unbound dash bar stays hidden")
	bar.bind_player(player)
	await process_frame
	_expect(bar.visible and bar.is_bound(), "valid player reveals dash bar")
	_expect(is_equal_approx(bar.max_value, float(player.get_dash_charge_capacity())), "bar maximum directly mirrors business capacity")
	_expect(is_equal_approx(bar.value, player.get_dash_charge_progress()), "bar directly mirrors final business progress")

	player._start_dash(Vector3.FORWARD)
	player._finish_dash(Vector3.ZERO)
	player._update_dash_cooldown(0.5)
	var count_before := player.get_available_dash_count()
	var cooldown_before := player.get_dash_cooldown_remaining()
	await process_frame
	_expect(is_equal_approx(bar.value, player.get_dash_charge_progress()), "partial recharge is mirrored without HUD interpolation")
	_expect(player.get_available_dash_count() == count_before, "HUD update does not change dash count")
	_expect(is_equal_approx(player.get_dash_cooldown_remaining(), cooldown_before), "HUD update does not advance cooldown")

	bar.unbind_player()
	_expect(not bar.visible and not bar.is_bound(), "unbind clears and hides dash bar")
	player.queue_free()
	bar.queue_free()
	await process_frame
	_finish()
```

补齐与现有测试一致的 `_expect()`、`_finish()`。注意测试中的 `process_frame` 不应让 `PlayerBase` 发生额外物理推进；若测试运行环境产生物理帧，则在断言前显式 `player.set_physics_process(false)`，随后只手动调用业务推进方法。

- [ ] **Step 2: 运行测试并确认场景缺失失败**

Run:

```powershell
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' `
  --headless --path 'G:\Godot\ProjectVOD' `
  --script 'res://UnitSystem/Tests/PlayerDashStatusBarTest.gd'
```

Expected: exit code `1`，报告 Dash 条场景或类型不存在。

- [ ] **Step 3: 创建淡黄色 Dash 条场景**

创建 `PlayerDashStatusBar.tscn`，根节点直接使用 `ProgressBar`，避免无意义包装节点。

```text
[gd_scene load_steps=4 format=3]

[ext_resource type="Script" path="res://UnitSystem/Components/UI/PlayerDashStatusBar.gd" id="1_script"]

[sub_resource type="StyleBoxFlat" id="StyleBoxFlat_background"]
bg_color = Color(0.18, 0.15, 0.06, 0.65)
corner_radius_top_left = 3
corner_radius_top_right = 3
corner_radius_bottom_right = 3
corner_radius_bottom_left = 3

[sub_resource type="StyleBoxFlat" id="StyleBoxFlat_fill"]
bg_color = Color(1, 0.88, 0.42, 0.95)
corner_radius_top_left = 3
corner_radius_top_right = 3
corner_radius_bottom_right = 3
corner_radius_bottom_left = 3

[node name="PlayerDashStatusBar" type="ProgressBar"]
visible = false
custom_minimum_size = Vector2(0, 8)
mouse_filter = 2
theme_override_styles/background = SubResource("StyleBoxFlat_background")
theme_override_styles/fill = SubResource("StyleBoxFlat_fill")
min_value = 0.0
max_value = 1.0
step = 0.001
value = 0.0
show_percentage = false
script = ExtResource("1_script")
```

- [ ] **Step 4: 实现严格只读监控脚本**

`PlayerDashStatusBar.gd` 不声明本地 CD、次数或 Tween。`_process()` 只能校验引用并复制权威值。

```gdscript
class_name PlayerDashStatusBar
extends ProgressBar

## 玩家 Dash 的纯只读 HUD 监控条。
## 本组件只复制 PlayerBase 已结算的最大次数与连续进度，不计算 CD、不推进时间，也不写入玩家状态。

var _bound_player: PlayerBase


func _ready() -> void:
	visible = false
	set_process(false)


## 绑定唯一玩家数据源；传入 null 等同解绑。组件不会修改玩家的 Dash 状态。
func bind_player(player: PlayerBase) -> void:
	unbind_player()
	if not is_instance_valid(player) or not player.is_inside_tree():
		return
	_bound_player = player
	max_value = float(player.get_dash_charge_capacity())
	value = player.get_dash_charge_progress()
	visible = true
	set_process(true)


## 清除玩家引用并隐藏显示；不会重置玩家的次数或 CD。
func unbind_player() -> void:
	_bound_player = null
	value = 0.0
	visible = false
	set_process(false)


## 返回当前是否持有有效玩家引用，只用于 HUD 生命周期测试与诊断。
func is_bound() -> bool:
	return is_instance_valid(_bound_player)


func _process(_delta: float) -> void:
	if not is_instance_valid(_bound_player) or not _bound_player.is_inside_tree():
		unbind_player()
		return
	max_value = float(_bound_player.get_dash_charge_capacity())
	value = _bound_player.get_dash_charge_progress()


func _exit_tree() -> void:
	unbind_player()
```

HUD 不得自行钳制容量或进度；两个显示值均直接来自 `PlayerBase` 的只读查询。不得添加 `_cooldown_remaining`、`_available_count`、`create_tween()` 或任何对 `_bound_player` 的赋值。

- [ ] **Step 5: 完成视觉与只读断言**

在测试中读取样式并增加：

```gdscript
var fill_style := bar.get_theme_stylebox(&"fill") as StyleBoxFlat
_expect(bar.custom_minimum_size.y == 8.0, "dash bar uses the specified thin height")
_expect(
	fill_style != null
	and fill_style.bg_color.is_equal_approx(Color(1.0, 0.88, 0.42, 0.95)),
	"dash bar uses the approved pale yellow fill"
)
_expect(not bar.show_percentage, "dash bar does not display text")
```

- [ ] **Step 6: 运行组件测试**

Run:

```powershell
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' `
  --headless --path 'G:\Godot\ProjectVOD' `
  --script 'res://UnitSystem/Tests/PlayerDashStatusBarTest.gd'
```

Expected: exit code `0` and `PlayerDashStatusBarTest: PASS`。

- [ ] **Step 7: 提交独立显示组件**

```powershell
git add -- 'UnitSystem/Components/UI/PlayerDashStatusBar.gd' `
  'UnitSystem/Components/UI/PlayerDashStatusBar.tscn' `
  'UnitSystem/Tests/PlayerDashStatusBarTest.gd'
git commit -m 'feat: add read-only player dash status bar'
```

---

### Task 3: 玩家生命框下方装配 Dash 条

**Files:**
- Modify: `UnitSystem/Components/UI/UnitHealthFrame.tscn:59-156`
- Modify: `UnitSystem/Components/UI/UnitHealthFrame.gd:65-71, 105-117, 310-345`
- Modify: `UnitSystem/Tests/UnitHealthFrameTest.gd`
- Modify: `GameFlow/UI/CombatHUD.gd:11-45, 48-96`
- Modify: `GameFlow/Tests/CombatHUDTest.gd`
- Modify: `GameFlow/Tests/CombatHUDBindingIntegrationTest.gd`

**Interfaces:**
- Consumes: `PlayerDashStatusBar.bind_player(player: PlayerBase) -> void`、`unbind_player() -> void`。
- Produces: `UnitHealthFrame.set_extension_content(content: Control) -> void`、`clear_extension_content() -> void`；固定玩家框下方的唯一 Dash 监控条。

- [ ] **Step 1: 先扩充 UnitHealthFrame 的失败测试**

在 `UnitHealthFrameTest.gd` 中增加扩展内容夹具并验证槽位位置和展示模式：

```gdscript
_expect(
	extension_slot.get_parent() == frame.get_node(^"FrameContent/CoreInfo")
	and extension_slot.get_index() > health_bar.get_index(),
	"extension slot is directly below the health bar"
)
_expect(frame.has_method(&"set_extension_content"), "frame exposes extension attachment")
_expect(frame.has_method(&"clear_extension_content"), "frame exposes extension cleanup")

var extension := Control.new()
extension.name = "TestExtension"
extension.custom_minimum_size = Vector2(0.0, 8.0)
frame.call(&"set_extension_content", extension)
frame.call(&"set_presentation_mode", UnitHealthFrame.PresentationMode.PLAYER)
_expect(extension_slot.visible and extension.get_parent() == extension_slot, "player mode shows attached extension")
frame.call(&"set_presentation_mode", UnitHealthFrame.PresentationMode.COMPACT_ALLY)
_expect(not extension_slot.visible, "ally mode collapses attached extension")
frame.call(&"set_presentation_mode", UnitHealthFrame.PresentationMode.TARGET)
_expect(not extension_slot.visible, "target mode collapses attached extension")
frame.call(&"set_presentation_mode", UnitHealthFrame.PresentationMode.PLAYER)
frame.call(&"clear_extension_content")
_expect(not extension_slot.visible and extension_slot.get_child_count() == 0, "clearing extension collapses the slot")
```

- [ ] **Step 2: 运行 UnitHealthFrameTest 并确认失败**

Run:

```powershell
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' `
  --headless --path 'G:\Godot\ProjectVOD' `
  --script 'res://UnitSystem/Tests/UnitHealthFrameTest.gd'
```

Expected: exit code `1`，报告扩展槽仍在右侧或装配方法缺失。

- [ ] **Step 3: 将 ExtensionSlot 移到生命条正下方**

在 `UnitHealthFrame.tscn` 中保持节点名称和 `unique_name_in_owner` 不变，只把父路径从 `FrameContent` 改为 `FrameContent/CoreInfo`，并置于 `HealthBar` 之后：

```text
[node name="ExtensionSlot" type="MarginContainer" parent="FrameContent/CoreInfo"]
unique_name_in_owner = true
visible = false
layout_mode = 2
mouse_filter = 2
```

不要修改玩家、伙伴、目标框尺寸常量；8 像素条加现有间距仍位于 420×90 玩家框的预留空间内。

- [ ] **Step 4: 增加通用扩展内容接口**

在 `UnitHealthFrame.gd` 的公开绑定方法附近增加：

```gdscript
## 用唯一 Control 内容替换玩家信息框的扩展显示；UnitHealthFrame 接管其节点生命周期。
## 内容只在 PLAYER 模式显示，本接口不读取或修改内容承载的业务状态。
func set_extension_content(content: Control) -> void:
	clear_extension_content()
	if not is_instance_valid(content):
		return
	_extension_slot.add_child(content)
	_apply_presentation_mode()


## 释放当前扩展内容并折叠槽位；不会调用扩展内容绑定的数据源。
func clear_extension_content() -> void:
	for child: Node in _extension_slot.get_children():
		_extension_slot.remove_child(child)
		child.queue_free()
	_apply_presentation_mode()
```

保留 `_apply_presentation_mode()` 的既有条件：仅玩家模式且子节点数量大于零时显示。

- [ ] **Step 5: 运行 UnitHealthFrameTest**

Run:

```powershell
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' `
  --headless --path 'G:\Godot\ProjectVOD' `
  --script 'res://UnitSystem/Tests/UnitHealthFrameTest.gd'
```

Expected: exit code `0` and `UnitHealthFrameTest: PASS`。

- [ ] **Step 6: 先扩充 CombatHUD 装配失败测试**

在 `CombatHUDTest.gd` 的玩家绑定断言后增加：

```gdscript
var extension_slot := player_frame.get_node(^"FrameContent/CoreInfo/ExtensionSlot") as MarginContainer
_expect(extension_slot.get_child_count() == 1, "player frame owns one HUD extension")
var dash_bar := extension_slot.get_child(0) as PlayerDashStatusBar if extension_slot.get_child_count() == 1 else null
_expect(dash_bar != null and dash_bar.is_bound(), "player extension is the bound dash status bar")
for child: Node in ally_frames.get_children():
	_expect(
		child.get_node(^"FrameContent/CoreInfo/ExtensionSlot").get_child_count() == 0,
		"ally frames do not instantiate player dash bars"
	)
```

在 `CombatHUDBindingIntegrationTest.gd` 中记录第一个玩家切换前的 Dash 条，切换场景后断言其 `value` 与第二个玩家的 `get_dash_charge_progress()` 一致；对旧玩家手动推进 Dash 后，条形仍保持第二个玩家的结果。

- [ ] **Step 7: 运行 CombatHUDTest 并确认缺少装配而失败**

Run:

```powershell
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' `
  --headless --path 'G:\Godot\ProjectVOD' `
  --script 'res://GameFlow/Tests/CombatHUDTest.gd'
```

Expected: exit code `1`，报告玩家扩展槽没有 Dash 条。

- [ ] **Step 8: 在 CombatHUD 初始化唯一 Dash 条**

增加预加载与字段：

```gdscript
const PLAYER_DASH_STATUS_BAR_SCENE: PackedScene = preload(
	"res://UnitSystem/Components/UI/PlayerDashStatusBar.tscn"
)

var _player_dash_status_bar: PlayerDashStatusBar
```

在 `_ready()` 中调用 `_initialize_player_dash_status_bar()`：

```gdscript
## 创建固定玩家框的唯一 Dash 监控条；失败只关闭该扩展，不影响生命与目标 HUD。
func _initialize_player_dash_status_bar() -> void:
	var candidate := PLAYER_DASH_STATUS_BAR_SCENE.instantiate() as PlayerDashStatusBar
	if not is_instance_valid(candidate):
		push_error("CombatHUD: PlayerDashStatusBar could not be instantiated.")
		return
	_player_dash_status_bar = candidate
	_player_frame.set_extension_content(_player_dash_status_bar)
```

调用顺序必须保证 `_player_frame` 已进入树并完成 `@onready` 初始化。

- [ ] **Step 9: 同步绑定和解绑，不加入任何 Dash 计算**

在 `bind_party()` 完成玩家生命框绑定后：

```gdscript
if is_instance_valid(_player_dash_status_bar):
	_player_dash_status_bar.bind_player(player as PlayerBase)
```

在 `unbind_party()` 的玩家生命框解绑前：

```gdscript
if is_instance_valid(_player_dash_status_bar):
	_player_dash_status_bar.unbind_player()
```

不得在 `CombatHUD` 中读取 `get_available_dash_count()`、`get_dash_cooldown_remaining()` 或计算 `(duration - remaining) / duration`。

- [ ] **Step 10: 处理 CombatHUD 退出时的所有权**

`UnitHealthFrame` 已接管扩展节点生命周期，因此 `CombatHUD._exit_tree()` 只需先执行现有 `unbind_party()`；不重复 `queue_free()` Dash 条。若在退出流程中显式调用 `clear_extension_content()`，调用后必须立即把 `_player_dash_status_bar` 设为 `null`，避免悬空引用。首选依赖场景树自然释放，不增加重复清理分支。

- [ ] **Step 11: 运行 HUD 层测试**

Run:

```powershell
$godot = 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe'
& $godot --headless --path 'G:\Godot\ProjectVOD' --script 'res://UnitSystem/Tests/UnitHealthFrameTest.gd'
& $godot --headless --path 'G:\Godot\ProjectVOD' --script 'res://UnitSystem/Tests/PlayerDashStatusBarTest.gd'
& $godot --headless --path 'G:\Godot\ProjectVOD' --script 'res://GameFlow/Tests/CombatHUDTest.gd'
& $godot --headless --path 'G:\Godot\ProjectVOD' --script 'res://GameFlow/Tests/CombatHUDBindingIntegrationTest.gd'
& $godot --headless --path 'G:\Godot\ProjectVOD' --script 'res://GameFlow/Tests/CombatHUDTargetHealthTest.gd'
```

Expected: all exit code `0` and print `PASS`。多玩家夹具产生的既有一次性 warning 是测试覆盖的一部分，不算失败。

- [ ] **Step 12: 提交 HUD 装配改动**

```powershell
git add -- 'UnitSystem/Components/UI/UnitHealthFrame.gd' `
  'UnitSystem/Components/UI/UnitHealthFrame.tscn' `
  'UnitSystem/Tests/UnitHealthFrameTest.gd' `
  'GameFlow/UI/CombatHUD.gd' `
  'GameFlow/Tests/CombatHUDTest.gd' `
  'GameFlow/Tests/CombatHUDBindingIntegrationTest.gd'
git commit -m 'feat: show dash recharge below player health'
```

---

### Task 4: 回归验证、实际画面检查与活动文档

**Files:**
- Modify: `Docs/CurrentSystemUserGuide.md`
- Modify: `Docs/CurrentProgressReport.md`

**Interfaces:**
- Consumes: Tasks 1-3 的最终 Dash 与 HUD 行为。
- Produces: 可复现的验证记录和当前系统说明；不新增运行时接口。

- [ ] **Step 1: 运行完整相关回归矩阵**

```powershell
$godot = 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe'
$tests = @(
  'res://UnitSystem/Tests/PlayerDashRechargeTest.gd',
  'res://UnitSystem/Tests/PlayerDashStatusBarTest.gd',
  'res://UnitSystem/Tests/PlayerDashComboContinuityTest.gd',
  'res://UnitSystem/Tests/UnitDeathLifecycleTest.gd',
  'res://UnitSystem/Tests/UnitHealthFrameTest.gd',
  'res://GameFlow/Tests/CombatHUDTest.gd',
  'res://GameFlow/Tests/CombatHUDBindingIntegrationTest.gd',
  'res://GameFlow/Tests/CombatHUDTargetHealthTest.gd',
  'res://GameFlow/Tests/GameRunResultFlowTest.gd'
)
foreach ($test in $tests) {
  & $godot --headless --path 'G:\Godot\ProjectVOD' --script $test
  if ($LASTEXITCODE -ne 0) { throw "Failed: $test" }
}
```

Expected: every test exits `0`。任何失败先判断是否由当前变更引入；不得修改无关业务以追求全绿。

- [ ] **Step 2: 运行 Godot 4.7 编辑器扫描**

```powershell
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' `
  --headless --editor --path 'G:\Godot\ProjectVOD' --quit
```

Expected: exit code `0`，无新增脚本解析、场景加载、资源缺失或类型错误。

- [ ] **Step 3: 在现有测试场景手动检查画面，不修改单位实例**

由用户在 Godot 编辑器运行现有 `Scenes/TestScene.tscn`；实施者不得自动添加或修改场景中的单位。检查：

1. 玩家满层时 Dash 条为完整淡黄色；
2. 使用一次后立即减少总宽度的一半；
3. 条形从一半连续恢复至满；
4. 恢复中再次 Dash 时准确下降一半且不跳回恢复起点；
5. 连续耗尽后依次恢复到一半和满；
6. 条形位于玩家生命条正下方，不挤压伙伴框或顶部目标框；
7. 无百分比文字、Tween 拖尾或额外黑色外框；
8. 玩家死亡时条形随玩家框变暗，复活后继续反映真实业务状态。

- [ ] **Step 4: 更新当前系统使用说明**

在 `Docs/CurrentSystemUserGuide.md` 的玩家移动/Dash 与 HUD 章节加入：

- Dash 最大次数由 `maximum_consecutive_dashes` 配置；
- 任意缺失层都会按 `dash_cooldown_duration` 逐层恢复；
- 恢复期间再次 Dash 不重置当前层进度；
- 玩家生命条下方淡黄色细条显示完整次数加当前层恢复进度；
- HUD 是只读监控，不影响 Dash。

- [ ] **Step 5: 更新当前进度报告**

在 `Docs/CurrentProgressReport.md` 记录日期、文件范围、规则变化、HUD 位置、只读边界以及实际通过的测试命令。只记录真实执行结果，不预先填写 `PASS`。

- [ ] **Step 6: 检查范围与工作区污染**

```powershell
git status --short
git diff --check
git diff --stat
```

Expected: 只有计划列出的代码、场景、测试和活动文档发生变化；`project.godot`、插件生成的无关 `.uid` 与用户既有改动未被暂存。

- [ ] **Step 7: 提交文档和最终验证记录**

```powershell
git add -- 'Docs/CurrentSystemUserGuide.md' 'Docs/CurrentProgressReport.md'
git commit -m 'docs: describe sequential player dash recharge'
```

- [ ] **Step 8: 最终完成条件**

实施只有在以下条件同时满足时才可声明完成：

- Dash 第一次消耗后立即启动当前层恢复；
- 再次消耗不重置当前层进度；
- 每个 CD 恢复一层，未满时自动继续；
- `get_dash_charge_capacity()` 与 `get_dash_charge_progress()` 分别是有效容量和连续进度的唯一公开权威；
- HUD 只赋值显示，不计算或写回 Dash；
- 玩家生命条下方显示 8 像素淡黄色条；
- 伙伴与顶部目标框没有 Dash 条；
- 所有相关测试和编辑器扫描通过；
- 用户完成实际画面检查；
- 无关工作区改动未被提交。

---

## Plan Self-Review

- **Spec coverage:** 逐层恢复、进度保留、大 `delta`、零 CD、死亡冻结、只读接口、HUD 单向数据流、生命条下方布局、降级和回归矩阵均有对应任务。
- **Placeholder scan:** 文档不包含未定义接口、模糊处理要求或未指定测试；所有创建、修改、运行与预期结果均明确。
- **Type consistency:** `get_dash_charge_capacity() -> int`、`get_dash_charge_progress() -> float`、`bind_player(player: PlayerBase) -> void`、`set_extension_content(content: Control) -> void` 在生产者和消费者任务中保持一致。
- **Scope:** 本计划不包含临时仇恨、专注资源、AI Dash、动态伙伴 HUD 或其他战斗扩展，可独立实施和验收。
