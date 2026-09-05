# Combat HUD Health Bars Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在不改变现有单位、AI 和战斗结算结构的前提下，实现左下角玩家血条与向上排列的友方 AI 血条 HUD，并为未来玩家资源和状态信息保留稳定扩展入口。

**Architecture:** 新建可绑定任意 `UnitBase` 的 `UnitHealthFrame`，只负责显示单个单位的生命状态；新建 `CombatHUD` 负责玩家框、伙伴框和屏幕布局；由现有 Autoload `GameRunController` 在当前场景切换时发现 Player/Ally 并显式绑定。生命变化完全依赖 `UnitBase` 的现有 getter 和信号，不增加轮询、单位反向 UI 引用或第二套全局场景观察器。

**Tech Stack:** Godot Engine 4.7、GDScript、Control/Container/CanvasLayer、StyleBoxFlat 场景子资源、SceneTree headless tests、PowerShell。

**Spec:** `Docs/Superpowers/Specs/2026-09-05-combat-hud-health-bars-design.md`

## Global Constraints

- 正确项目根目录固定为 `G:\Godot\ProjectVOD`；不得使用旧路径 `G:\Godot\SipSip` 或已不存在的 `G:\Godot\ProjSipSip`。
- 本计划只实现队伍生命 HUD；不实现锁定目标、顶部目标信息、专注、技能、物品、状态图标、头像资源、伤害拖尾或低血动画。
- 以当前结构为基础直接新增；除原则性错误或严重 Bug 外，不重构 `UnitBase`、Player、Ally、Enemy、AI、技能、物品、伤害或死亡系统。
- 不修改 `res://Scenes/TestScene.tscn` 中的任何单位实例；本功能也不要求向 `TestCombatRoom.tscn` 或其他测试场景添加、删除或移动单位。
- 不修改 `project.godot`；`GameRunController` 已经注册为 Autoload。
- 不修改现有 `WorldHealthBar.gd/.tscn`；屏幕 HUD 与头顶世界血条并行工作。
- HUD 只读战斗数据：不得调用 `apply_damage()`、`apply_healing()`、`revive()`，不得写入 `_current_health`，不得参与 AI、索敌、仇恨或房间胜负。
- 不进行每帧生命轮询或每帧全树单位扫描；生命更新使用信号，队伍发现只在当前场景变化后执行。
- 所有新增 `@export` 参数必须紧邻简体中文说明，包含用途、单位/取值、默认行为和影响范围。
- 所有新增公共方法、信号及外部传入参数必须在声明附近写简体中文职责和约束说明。
- 不新建 `.tres` 或 `.res`；样式使用 `.tscn` 内部子资源，避免引入正式外部 Resource UID 流程。
- 实施时保留用户已有工作树改动，只提交任务明确列出的文件；不得把无关的 `project.godot` 和 `addons/godot_mcp/commands/headless_commands.gd.uid` 纳入提交。
- 每个任务遵循 RED → GREEN → 回归 → 单独提交；若 RED 阶段未按预期失败，先检查测试是否真正覆盖契约，不得直接进入实现。

---

## File Structure

### 新建文件

- `UnitSystem/Components/UI/UnitHealthFrame.gd`：单单位生命显示、信号绑定、死亡/复活视觉状态和展示模式。
- `UnitSystem/Components/UI/UnitHealthFrame.tscn`：单单位信息框的节点结构与场景内样式。
- `UnitSystem/Tests/UnitHealthFrameTest.gd`：单单位信息框行为与接口契约测试。
- `GameFlow/UI/CombatHUD.gd`：队伍绑定、伙伴框实例管理、尺寸/边距配置和 HUD 可见性。
- `GameFlow/UI/CombatHUD.tscn`：左下锚点、队伍纵向容器和固定玩家框。
- `GameFlow/Tests/CombatHUDTest.gd`：队伍组成、去重、布局比例、稳定槽位和解绑测试。
- `GameFlow/Tests/CombatHUDBindingIntegrationTest.gd`：Autoload 对当前场景的发现、重绑和异常场景集成测试。

Godot 在编辑器扫描时生成的相邻 `.gd.uid` 文件应随对应脚本提交；不得手工编造 UID 内容。

### 修改文件

- `GameFlow/GameRunController.gd`：独立创建 `CombatHUD`，在场景变化时收集 Player/Ally 并绑定；同时消除结果界面初始化失败导致 `_ready()` 提前返回的耦合。
- `GameFlow/Tests/GameRunResultFlowTest.gd`：确认原有结果界面和玩家输入关闭契约未被 HUD 接入破坏，并确认两个 CanvasLayer 同时存在。

### 明确不修改

- `UnitSystem/Base/00_UnitBase.gd/.tscn`
- `UnitSystem/Components/UI/WorldHealthBar.gd/.tscn`
- `UnitSystem/Player/**`
- `UnitSystem/AI/**`
- `SkillSystem/**`
- `ItemSystem/**`
- `Scenes/**`
- `project.godot`

---

### Task 1: Implement the reusable UnitHealthFrame contract

**Files:**
- Create: `UnitSystem/Tests/UnitHealthFrameTest.gd`
- Create: `UnitSystem/Components/UI/UnitHealthFrame.gd`
- Create: `UnitSystem/Components/UI/UnitHealthFrame.tscn`

**Interfaces:**
- Consumes: `UnitBase.health_changed(previous_health: float, current_health: float, maximum_health: float, source: Node)`、`UnitBase.died(source: Node)`、`UnitBase.revived(current_health: float, source: Node)`、`UnitBase.get_current_health() -> float`、`UnitBase.get_maximum_health() -> float`、`Node.tree_exiting`。
- Produces: `UnitHealthFrame.PresentationMode`、`bind_unit(unit: UnitBase) -> void`、`unbind_unit() -> void`、`set_presentation_mode(mode: PresentationMode) -> void`、`refresh_immediately() -> void`、`is_bound() -> bool`。
- Produces stable node paths: `FrameContent/CoreInfo/Header/NameLabel`、`FrameContent/CoreInfo/Header/StateLabel`、`FrameContent/CoreInfo/HealthBar`、`FrameContent/CoreInfo/HealthValue`、`FrameContent/ExtensionSlot`。

- [ ] **Step 1: Create the failing behavior test**

创建 `UnitHealthFrameTest.gd`，沿用现有 `extends SceneTree`、`_failures`、`_expect()`、`_finish()` 测试风格。测试必须包含以下实际流程：

```gdscript
extends SceneTree

const FRAME_PATH := "res://UnitSystem/Components/UI/UnitHealthFrame.tscn"
const UNIT_PATH := "res://UnitSystem/Base/00_UnitBase.tscn"

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	_expect(ResourceLoader.exists(FRAME_PATH), "UnitHealthFrame scene exists")
	if not ResourceLoader.exists(FRAME_PATH):
		_finish()
		return

	var frame_scene := load(FRAME_PATH) as PackedScene
	var unit_scene := load(UNIT_PATH) as PackedScene
	_expect(frame_scene != null and unit_scene != null, "fixtures load")
	if frame_scene == null or unit_scene == null:
		_finish()
		return

	var frame := frame_scene.instantiate() as Control
	var first_unit := unit_scene.instantiate() as UnitBase
	first_unit.name = "测试玩家"
	first_unit.maximum_health = 200.0
	first_unit.starting_health_percentage = 75.0
	root.add_child(first_unit)
	root.add_child(frame)
	await process_frame

	_expect(frame.has_method(&"bind_unit"), "bind_unit is public")
	_expect(frame.has_method(&"unbind_unit"), "unbind_unit is public")
	_expect(frame.has_method(&"set_presentation_mode"), "presentation mode is public")
	_expect(frame.has_method(&"refresh_immediately"), "refresh is public")
	_expect(frame.has_method(&"is_bound"), "binding query is public")
	frame.call(&"bind_unit", first_unit)
	await process_frame

	var name_label := frame.get_node(^"FrameContent/CoreInfo/Header/NameLabel") as Label
	var state_label := frame.get_node(^"FrameContent/CoreInfo/Header/StateLabel") as Label
	var health_bar := frame.get_node(^"FrameContent/CoreInfo/HealthBar") as ProgressBar
	var health_value := frame.get_node(^"FrameContent/CoreInfo/HealthValue") as Label
	var extension_slot := frame.get_node(^"FrameContent/ExtensionSlot") as Control
	_expect(frame.visible and bool(frame.call(&"is_bound")), "binding shows frame")
	_expect(name_label.text == "测试玩家", "node name is the display-name fallback")
	_expect(health_value.text == "150 / 200", "initial health text is current over maximum")
	_expect(is_equal_approx(health_bar.value, 0.75), "initial ratio is correct")
	_expect(not state_label.visible and not extension_slot.visible, "unused state and extension stay collapsed")

	first_unit.apply_damage(50.0)
	await process_frame
	_expect(health_value.text == "100 / 200", "damage updates text from signal")
	_expect(is_equal_approx(health_bar.value, 0.5), "damage updates ratio from signal")

	first_unit.apply_healing(20.0)
	await process_frame
	_expect(health_value.text == "120 / 200", "healing updates text from signal")

	first_unit.apply_damage(9999.0)
	await process_frame
	_expect(frame.visible, "dead unit keeps its stable frame")
	_expect(state_label.visible and state_label.text == "倒下", "death state is explicit")
	_expect(health_value.text == "0 / 200", "lethal damage displays zero")
	_expect(first_unit.revive(40.0), "fixture revives")
	await process_frame
	_expect(not state_label.visible, "revive clears death state")
	_expect(health_value.text == "40 / 200", "revive restores health display")

	frame.call(&"unbind_unit")
	first_unit.apply_healing(10.0)
	await process_frame
	_expect(not frame.visible and not bool(frame.call(&"is_bound")), "unbind hides and clears")
	_expect(health_value.text == "0 / 0", "unbind resets the visible data")
	first_unit.apply_healing(10.0)
	await process_frame
	_expect(health_value.text == "0 / 0", "old source no longer updates after unbind")

	var second_unit := unit_scene.instantiate() as UnitBase
	second_unit.name = "第二单位"
	second_unit.maximum_health = 80.0
	root.add_child(second_unit)
	await process_frame
	frame.call(&"bind_unit", second_unit)
	frame.call(&"bind_unit", second_unit)
	second_unit.apply_damage(10.0)
	await process_frame
	_expect(health_value.text == "70 / 80", "repeat binding does not duplicate signal behavior")
	second_unit.queue_free()
	await process_frame
	_expect(not frame.visible and not bool(frame.call(&"is_bound")), "source tree exit unbinds safely")

	frame.queue_free()
	first_unit.queue_free()
	await process_frame
	_finish()
```

文件末尾实现与既有测试一致的 `_expect(condition: bool, message: String)` 和 `_finish()`：无失败打印 `UnitHealthFrameTest: PASS` 并 `quit(0)`，否则逐项 `push_error()` 并 `quit(1)`。

- [ ] **Step 2: Run the test and confirm RED**

```powershell
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' `
  --headless --path 'G:\Godot\ProjectVOD' `
  --script 'res://UnitSystem/Tests/UnitHealthFrameTest.gd'
```

Expected: exit code `1`，失败原因是 `UnitHealthFrame.tscn` 尚不存在；不得出现测试脚本自身解析错误。

- [ ] **Step 3: Create the UnitHealthFrame scene**

创建 `UnitHealthFrame.tscn`，根节点为 `PanelContainer`，脚本为 `UnitHealthFrame.gd`，并按以下精确节点树建立：

```text
UnitHealthFrame (PanelContainer)
└─ FrameContent (HBoxContainer)
   ├─ CoreInfo (VBoxContainer)
   │  ├─ Header (HBoxContainer)
   │  │  ├─ NameLabel (Label)
   │  │  └─ StateLabel (Label, text="倒下", visible=false)
   │  ├─ HealthBar (ProgressBar, min=0, max=1, show_percentage=false)
   │  └─ HealthValue (Label)
   └─ ExtensionSlot (MarginContainer, visible=false)
```

场景要求：

- 根节点 `custom_minimum_size = Vector2(420, 90)`，默认按玩家模式预览。
- 根、容器、Label 和 ProgressBar 均设 `mouse_filter = Control.MOUSE_FILTER_IGNORE`。
- `NameLabel`、`StateLabel`、`HealthBar`、`HealthValue`、`ExtensionSlot` 设置 `unique_name_in_owner = true`，与脚本中的 `%NodeName` 引用一致。
- `CoreInfo` 水平扩展填满；`NameLabel` 水平扩展，避免状态文本挤出边界。
- `HealthBar` 设置足够的最小高度，建议 22 像素。
- 使用场景内部 `StyleBoxFlat` 定义深色半透明面板、暗色槽、绿色生命填充和清晰边框。
- 不添加头像、假资源条、假状态图标或固定空白区域。

- [ ] **Step 4: Implement minimal signal-driven frame logic**

创建 `UnitHealthFrame.gd`，公开契约和关键私有逻辑按以下结构实现：

```gdscript
class_name UnitHealthFrame
extends PanelContainer

enum PresentationMode {
	PLAYER,
	COMPACT_ALLY,
}

@onready var _name_label: Label = %NameLabel
@onready var _state_label: Label = %StateLabel
@onready var _health_bar: ProgressBar = %HealthBar
@onready var _health_value: Label = %HealthValue
@onready var _extension_slot: MarginContainer = %ExtensionSlot

var _bound_unit: UnitBase
var _presentation_mode: PresentationMode = PresentationMode.PLAYER


## 将信息框绑定到一个有效 UnitBase。重复绑定会先安全断开旧单位；传入 null 等同解绑。
func bind_unit(unit: UnitBase) -> void:
	if unit == _bound_unit and is_instance_valid(unit):
		refresh_immediately()
		return
	unbind_unit()
	if not is_instance_valid(unit):
		return
	_bound_unit = unit
	_connect_unit_signals()
	visible = true
	refresh_immediately()


## 断开当前单位的全部信号并隐藏信息框；不会修改单位本身。
func unbind_unit() -> void:
	_disconnect_unit_signals()
	_bound_unit = null
	visible = false


## 切换玩家或紧凑伙伴展示；只影响字号、间距和扩展槽，不改变绑定数据。
func set_presentation_mode(mode: PresentationMode) -> void:
	_presentation_mode = mode
	_apply_presentation_mode()


## 从当前绑定单位的 getter 重新读取全部显示值；无有效绑定时安全隐藏。
func refresh_immediately() -> void:
	if not is_instance_valid(_bound_unit):
		unbind_unit()
		return
	_update_health(
		_bound_unit.get_current_health(),
		_bound_unit.get_maximum_health()
	)
	_name_label.text = _bound_unit.name
	_set_dead_state(_bound_unit.is_dead())


## 返回当前是否持有有效 UnitBase 绑定。
func is_bound() -> bool:
	return is_instance_valid(_bound_unit)
```

补全以下私有方法，名称在后续任务和测试中保持不变：

```gdscript
func _connect_unit_signals() -> void
func _disconnect_unit_signals() -> void
func _reset_display() -> void
func _on_health_changed(
	_previous_health: float,
	current_health: float,
	maximum_health: float,
	_source: Node
) -> void
func _on_unit_died(_source: Node) -> void
func _on_unit_revived(_current_health: float, _source: Node) -> void
func _on_bound_unit_tree_exiting() -> void
func _update_health(current_health: float, maximum_health: float) -> void
func _set_dead_state(dead: bool) -> void
func _apply_presentation_mode() -> void
```

实现细则：

- 所有信号连接前使用 `is_connected()`，断开前同时检查单位有效性和 `is_connected()`。
- `_update_health()` 使用 `safe_maximum := maxf(maximum_health, 0.0)`；最大值不大于零时比例为 `0.0`。
- 进度条范围保持 `0.0..1.0`，值使用 `clampf(current / maximum, 0.0, 1.0)`。
- 数值文本使用取整后的 `"%d / %d"`；当前项目生命值虽为 float，首版 HUD 不显示小数噪声。
- `_reset_display()` 把名称清空、生命文本设为 `0 / 0`、进度设为零并清除死亡态；`unbind_unit()` 在隐藏前调用它。
- `_set_dead_state(true)` 显示“倒下”，并将根节点 `self_modulate` 设为 `Color(0.55, 0.55, 0.55, 0.9)`；复活恢复 `Color.WHITE`。
- `_on_unit_died()` 必须调用 `refresh_immediately()` 或明确更新为零后设置死亡态，不隐藏框。
- `_on_unit_revived()` 重新读取 getter，不只信任信号参数，保证最大生命同时正确。
- `_on_bound_unit_tree_exiting()` 必须解绑并隐藏。
- `_apply_presentation_mode()` 只处理展示差异：玩家模式名称/数值字号使用 18/16，伙伴模式使用 15/13；`ExtensionSlot` 仅在玩家模式且内部已有子节点时显示，空槽和紧凑模式必须折叠。
- `_exit_tree()` 调用 `_disconnect_unit_signals()`，防止场景卸载残留回调。

- [ ] **Step 5: Run focused test and confirm GREEN**

再次运行 Step 2 命令。

Expected: 输出 `UnitHealthFrameTest: PASS`，exit code `0`，无无效信号断开、除零或节点路径错误。

- [ ] **Step 6: Run immediate health regressions**

```powershell
$vodGodot = 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe'
& $vodGodot --headless --path 'G:\Godot\ProjectVOD' --script 'res://UnitSystem/Tests/UnitDeathLifecycleTest.gd'
& $vodGodot --headless --path 'G:\Godot\ProjectVOD' --script 'res://UnitSystem/Tests/WorldHealthBarTest.gd'
```

Expected: 两个既有测试均 exit code `0`；屏幕信息框不要求也不得改变世界血条的显示规则。

- [ ] **Step 7: Commit Task 1 only**

```powershell
git add -- `
  'UnitSystem/Components/UI/UnitHealthFrame.gd' `
  'UnitSystem/Components/UI/UnitHealthFrame.gd.uid' `
  'UnitSystem/Components/UI/UnitHealthFrame.tscn' `
  'UnitSystem/Tests/UnitHealthFrameTest.gd' `
  'UnitSystem/Tests/UnitHealthFrameTest.gd.uid'
git commit -m 'feat: add reusable unit health HUD frame'
```

如果 Godot 尚未生成某个 `.gd.uid`，先执行一次本计划最终 editor scan，再只添加实际存在的文件；不得创建空 UID 文件。

---

### Task 2: Implement CombatHUD party composition and layout

**Files:**
- Create: `GameFlow/Tests/CombatHUDTest.gd`
- Create: `GameFlow/UI/CombatHUD.gd`
- Create: `GameFlow/UI/CombatHUD.tscn`

**Interfaces:**
- Consumes: `UnitHealthFrame.bind_unit(unit: UnitBase) -> void`、`unbind_unit() -> void`、`set_presentation_mode(mode: UnitHealthFrame.PresentationMode) -> void`。
- Produces: `CombatHUD.bind_party(player: UnitBase, allies: Array[UnitBase]) -> void`、`unbind_party() -> void`、`refresh_party(player: UnitBase, allies: Array[UnitBase]) -> void`。
- Produces stable node paths: `SafeArea/PartyColumn/AllyFrames`、`SafeArea/PartyColumn/PlayerFrame`。

- [ ] **Step 1: Create the failing composition and layout test**

创建 `CombatHUDTest.gd`。使用一个普通 `UnitBase` 作为 Player 数据源、四个普通 `UnitBase` 作为 Ally 数据源，不依赖任何 AI 脚本。测试核心如下：

```gdscript
extends SceneTree

const HUD_PATH := "res://GameFlow/UI/CombatHUD.tscn"
const UNIT_PATH := "res://UnitSystem/Base/00_UnitBase.tscn"

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	_expect(ResourceLoader.exists(HUD_PATH), "CombatHUD scene exists")
	if not ResourceLoader.exists(HUD_PATH):
		_finish()
		return
	var hud := (load(HUD_PATH) as PackedScene).instantiate() as CanvasLayer
	root.add_child(hud)
	var player := _make_unit("玩家", "Player", 300.0)
	var allies: Array[UnitBase] = []
	for index: int in 4:
		allies.append(_make_unit("伙伴%d" % index, "Ally", 100.0))
	await process_frame

	_expect(hud.has_method(&"bind_party"), "bind_party is public")
	_expect(hud.has_method(&"unbind_party"), "unbind_party is public")
	_expect(hud.has_method(&"refresh_party"), "refresh_party is public")
	hud.call(&"bind_party", player, allies)
	await process_frame

	var player_frame := hud.get_node(^"SafeArea/PartyColumn/PlayerFrame") as Control
	var ally_frames := hud.get_node(^"SafeArea/PartyColumn/AllyFrames") as VBoxContainer
	_expect(hud.visible and player_frame.visible, "valid player shows HUD")
	_expect(ally_frames.get_child_count() == 4, "one frame exists per ally")
	_expect(player_frame.custom_minimum_size == Vector2(420, 90), "player size uses default")
	for child: Node in ally_frames.get_children():
		var ally_frame := child as Control
		_expect(ally_frame != null, "ally frame is Control")
		if ally_frame != null:
			_expect(ally_frame.custom_minimum_size == Vector2(280, 60), "ally is two thirds size")
			_expect(is_equal_approx(ally_frame.global_position.x, player_frame.global_position.x), "frames align left")
			_expect(ally_frame.global_position.y < player_frame.global_position.y, "allies appear above player")

	var duplicate_input: Array[UnitBase] = [allies[0], allies[0], player, null]
	hud.call(&"refresh_party", player, duplicate_input)
	await process_frame
	await process_frame
	_expect(ally_frames.get_child_count() == 1, "invalid, duplicate, and player entries are skipped")

	var stable_frame := ally_frames.get_child(0) as Control
	allies[0].apply_damage(9999.0)
	await process_frame
	_expect(stable_frame.visible, "dead ally frame stays in its slot")
	_expect(ally_frames.get_child_count() == 1, "death does not reorder party")

	hud.call(&"unbind_party")
	await process_frame
	await process_frame
	_expect(not hud.visible, "unbind hides HUD")
	_expect(ally_frames.get_child_count() == 0, "unbind removes dynamic ally frames")

	hud.call(&"bind_party", null, allies)
	await process_frame
	_expect(not hud.visible, "invalid player stays safely hidden")
	_cleanup(hud, player, allies)
	await process_frame
	_finish()


func _make_unit(unit_name: String, faction: String, maximum: float) -> UnitBase:
	var unit := (load(UNIT_PATH) as PackedScene).instantiate() as UnitBase
	unit.name = unit_name
	unit.faction_id = faction
	unit.maximum_health = maximum
	root.add_child(unit)
	return unit
```

补全 `_cleanup()`、`_expect()` 和 `_finish()`；清理时只 `queue_free()` 本测试创建的节点。不要用测试访问私有字段，所有断言通过公开方法和稳定节点路径完成。

- [ ] **Step 2: Run the test and confirm RED**

```powershell
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' `
  --headless --path 'G:\Godot\ProjectVOD' `
  --script 'res://GameFlow/Tests/CombatHUDTest.gd'
```

Expected: exit code `1`，失败原因是 `CombatHUD.tscn` 尚不存在。

- [ ] **Step 3: Create the responsive CombatHUD scene**

创建 `CombatHUD.tscn`，节点结构严格为：

```text
CombatHUD (CanvasLayer, layer=10)
└─ SafeArea (MarginContainer, full rect)
   └─ PartyColumn (VBoxContainer, bottom-left alignment)
      ├─ AllyFrames (VBoxContainer)
      └─ PlayerFrame (UnitHealthFrame instance)
```

场景与布局要求：

- `CombatHUD.visible = false`，直到绑定有效玩家。
- `SafeArea` 使用全屏锚点；`PartyColumn` 设置 `size_flags_horizontal = Control.SIZE_SHRINK_BEGIN`、`size_flags_vertical = Control.SIZE_SHRINK_END`，由容器定位在左下，不得写死屏幕绝对位置。
- `SafeArea`、`PartyColumn`、`AllyFrames` 和玩家框均忽略鼠标。
- `SafeArea`、`PartyColumn`、`AllyFrames` 和 `PlayerFrame` 设置 `unique_name_in_owner = true`，与脚本中的 `%NodeName` 引用一致。
- `PlayerFrame` 默认 `PresentationMode.PLAYER`。
- `AllyFrames` 放在玩家框之前，使伙伴自然位于上方；新增伙伴按输入数组顺序从上到下排列。
- CanvasLayer 使用 `layer = 10`，明确低于 `RunResultOverlay.layer = 100`。

- [ ] **Step 4: Implement configurable party binding**

创建 `CombatHUD.gd`，导出字段必须带完整中文说明：

```gdscript
class_name CombatHUD
extends CanvasLayer

const UNIT_HEALTH_FRAME_SCENE: PackedScene = preload(
	"res://UnitSystem/Components/UI/UnitHealthFrame.tscn"
)

@export_category("Layout")
## HUD 与屏幕左边缘的安全距离，单位为像素；默认 48，只影响队伍 HUD 布局。
@export_range(0.0, 512.0, 1.0, "or_greater")
var safe_margin_left: float = 48.0
## HUD 与屏幕下边缘的安全距离，单位为像素；默认 48，只影响队伍 HUD 布局。
@export_range(0.0, 512.0, 1.0, "or_greater")
var safe_margin_bottom: float = 48.0
## 玩家与伙伴信息框之间以及伙伴之间的纵向间距，单位为像素；默认 10。
@export_range(0, 128, 1, "or_greater")
var frame_separation: int = 10
## 玩家信息框最小尺寸，单位为像素；默认 420×90，为未来玩家资源内容保留空间。
@export var player_frame_size: Vector2 = Vector2(420.0, 90.0)
## 伙伴信息框最小尺寸，单位为像素；默认 280×60，即玩家框宽高的三分之二。
@export var ally_frame_size: Vector2 = Vector2(280.0, 60.0)

@onready var _safe_area: MarginContainer = %SafeArea
@onready var _party_column: VBoxContainer = %PartyColumn
@onready var _ally_frames: VBoxContainer = %AllyFrames
@onready var _player_frame: UnitHealthFrame = %PlayerFrame

var _active_ally_frames: Array[UnitHealthFrame] = []
```

公开方法按以下语义实现：

```gdscript
## 用一个玩家和一组伙伴重建队伍显示。玩家无效时安全解绑；伙伴中的 null、重复项和玩家自身会被跳过。
func bind_party(player: UnitBase, allies: Array[UnitBase]) -> void:
	unbind_party()
	if not is_instance_valid(player) or not player.is_inside_tree():
		return
	_apply_layout_configuration()
	_player_frame.set_presentation_mode(UnitHealthFrame.PresentationMode.PLAYER)
	_player_frame.custom_minimum_size = _sanitize_size(player_frame_size)
	_player_frame.bind_unit(player)
	var seen_ids: Dictionary = {player.get_instance_id(): true}
	for ally: UnitBase in allies:
		if not is_instance_valid(ally) or not ally.is_inside_tree():
			continue
		var instance_id := ally.get_instance_id()
		if seen_ids.has(instance_id):
			continue
		seen_ids[instance_id] = true
		_add_ally_frame(ally)
	visible = true


## 清除所有单位信号和动态伙伴框并隐藏 HUD；不会释放 HUD 自身。
func unbind_party() -> void:
	if is_instance_valid(_player_frame):
		_player_frame.unbind_unit()
	for frame: UnitHealthFrame in _active_ally_frames:
		if is_instance_valid(frame):
			frame.unbind_unit()
			frame.queue_free()
	_active_ally_frames.clear()
	visible = false


## 以完整队伍快照刷新 HUD；当前实现与重新绑定等价，不做增量排序或状态复制。
func refresh_party(player: UnitBase, allies: Array[UnitBase]) -> void:
	bind_party(player, allies)
```

补全并保持以下私有方法名：

```gdscript
func _ready() -> void
func _exit_tree() -> void
func _add_ally_frame(ally: UnitBase) -> void
func _apply_layout_configuration() -> void
func _sanitize_size(value: Vector2) -> Vector2
```

实现细则：

- `_ready()` 应用布局配置并保持未绑定隐藏；场景编辑器直接实例化时也安全。
- `_add_ally_frame()` 检查 PackedScene 实例化结果，失败时 `push_error()` 后继续处理其他伙伴。
- 新伙伴框先加入 `AllyFrames`，设置 `COMPACT_ALLY`、`ally_frame_size`，最后绑定单位。
- `_sanitize_size()` 将两个分量钳制到不小于 `1.0`，防止 Inspector 负值破坏容器。
- `_apply_layout_configuration()` 使用 `add_theme_constant_override()` 更新 `SafeArea` 的 `margin_left` / `margin_bottom`，并更新 `PartyColumn` 与 `AllyFrames` 的 `separation`；不要在 `_process()` 重复执行。
- `unbind_party()` 对尚未 `_ready()` 的情况安全，不假定 onready 引用都有效。
- 因伙伴死亡不会触发 HUD 重绑，动态框不会移除或换位；伙伴 `tree_exiting` 只让自己的框隐藏。
- `ExtensionSlot` 不由 `CombatHUD` 填充；本阶段只保留命名节点。

- [ ] **Step 5: Run focused test and confirm GREEN**

再次运行 Step 2 命令。

Expected: 输出 `CombatHUDTest: PASS`，exit code `0`；所有伙伴框位于玩家框上方并左对齐，重复输入只产生一个框。

- [ ] **Step 6: Run Task 1 regression and editor parse scan**

```powershell
$vodGodot = 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe'
& $vodGodot --headless --path 'G:\Godot\ProjectVOD' --script 'res://UnitSystem/Tests/UnitHealthFrameTest.gd'
& $vodGodot --headless --editor --path 'G:\Godot\ProjectVOD' --quit
```

Expected: 测试 exit code `0`；editor scan exit code `0`，并为新增脚本生成正常 `.gd.uid`。检查输出中没有 `Parser Error`、`Invalid get index`、`Node not found` 或新信号警告。

- [ ] **Step 7: Commit Task 2 only**

```powershell
git add -- `
  'GameFlow/UI/CombatHUD.gd' `
  'GameFlow/UI/CombatHUD.gd.uid' `
  'GameFlow/UI/CombatHUD.tscn' `
  'GameFlow/Tests/CombatHUDTest.gd' `
  'GameFlow/Tests/CombatHUDTest.gd.uid'
git commit -m 'feat: add extensible party health HUD'
```

---

### Task 3: Integrate CombatHUD with GameRunController scene lifecycle

**Files:**
- Create: `GameFlow/Tests/CombatHUDBindingIntegrationTest.gd`
- Modify: `GameFlow/GameRunController.gd:3-136`

**Interfaces:**
- Consumes: `CombatHUD.bind_party(player: UnitBase, allies: Array[UnitBase]) -> void`、`CombatHUD.unbind_party() -> void`。
- Produces: Autoload 子节点 `GameRunController/CombatHUD`；当前场景中恰好一个 `faction_id == "Player"` 时绑定全部 `faction_id == "Ally"` 单位。
- Preserves: `GameRunController/RunResultOverlay`、房间完成/失败信号、重开和玩家输入开关的现有契约。

- [ ] **Step 1: Create the failing scene-binding integration test**

创建 `CombatHUDBindingIntegrationTest.gd`，测试真实 Autoload 而不是手工实例化第二个控制器：

```gdscript
extends SceneTree

const UNIT_PATH := "res://UnitSystem/Base/00_UnitBase.tscn"

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	var game_run := root.get_node_or_null(^"GameRunController")
	_expect(game_run != null, "GameRunController autoload exists")
	if game_run == null:
		_finish()
		return
	var hud := game_run.get_node_or_null(^"CombatHUD") as CanvasLayer
	_expect(hud != null, "GameRunController creates CombatHUD")
	if hud == null:
		_finish()
		return

	var first_scene := Node3D.new()
	first_scene.name = "FirstHUDScene"
	root.add_child(first_scene)
	current_scene = first_scene
	var first_player := _add_unit(first_scene, "玩家A", "Player", 200.0)
	var ally_a := _add_unit(first_scene, "守卫", "Ally", 300.0)
	var ally_b := _add_unit(first_scene, "牧师", "Ally", 100.0)
	_add_unit(first_scene, "敌人", "Enemy", 100.0)
	await process_frame
	await process_frame
	await process_frame

	var ally_frames := hud.get_node(^"SafeArea/PartyColumn/AllyFrames") as VBoxContainer
	var player_frame := hud.get_node(^"SafeArea/PartyColumn/PlayerFrame") as Control
	_expect(hud.visible and player_frame.visible, "one player binds automatically")
	_expect(ally_frames.get_child_count() == 2, "only Ally units receive compact frames")
	var first_name := player_frame.get_node(^"FrameContent/CoreInfo/Header/NameLabel") as Label
	_expect(first_name.text == "玩家A", "first scene player is bound")
	if ally_frames.get_child_count() == 2:
		var first_ally_name := ally_frames.get_child(0).get_node(
			^"FrameContent/CoreInfo/Header/NameLabel"
		) as Label
		var second_ally_name := ally_frames.get_child(1).get_node(
			^"FrameContent/CoreInfo/Header/NameLabel"
		) as Label
		_expect(first_ally_name != null and second_ally_name != null, "ally labels exist")
		if first_ally_name != null and second_ally_name != null:
			_expect(
				first_ally_name.text == "守卫" and second_ally_name.text == "牧师",
				"ally frames preserve scene-tree discovery order"
			)

	var second_scene := Node3D.new()
	second_scene.name = "SecondHUDScene"
	root.add_child(second_scene)
	var second_player := _add_unit(second_scene, "玩家B", "Player", 500.0)
	_add_unit(second_scene, "新伙伴", "Ally", 120.0)
	current_scene = second_scene
	await process_frame
	await process_frame
	await process_frame
	_expect(first_name.text == "玩家B", "scene change rebinds player frame")
	_expect(ally_frames.get_child_count() == 1, "old ally frames are cleared")
	first_player.apply_damage(10.0)
	await process_frame
	_expect(first_name.text == "玩家B", "old scene signals cannot update new binding")

	var no_player_scene := Node3D.new()
	root.add_child(no_player_scene)
	current_scene = no_player_scene
	await process_frame
	await process_frame
	_expect(not hud.visible, "scene without player hides HUD")

	var ambiguous_scene := Node3D.new()
	root.add_child(ambiguous_scene)
	_add_unit(ambiguous_scene, "玩家一", "Player", 100.0)
	_add_unit(ambiguous_scene, "玩家二", "Player", 100.0)
	current_scene = ambiguous_scene
	await process_frame
	await process_frame
	_expect(not hud.visible, "multiple players are not guessed")

	current_scene = null
	for scene: Node in [first_scene, second_scene, no_player_scene, ambiguous_scene]:
		if is_instance_valid(scene):
			scene.queue_free()
	await process_frame
	_finish()
```

`_add_unit(parent, unit_name, faction, maximum) -> UnitBase` 必须在加入父节点前设置 name、faction 和 maximum；补全标准 `_expect()` / `_finish()`。`ally_a`、`ally_b` 和 `second_player` 若只用于保持清晰语义，可用显式类型变量并在测试断言中检查其有效性，避免未使用变量 warning。

- [ ] **Step 2: Run the integration test and confirm RED**

```powershell
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' `
  --headless --path 'G:\Godot\ProjectVOD' `
  --script 'res://GameFlow/Tests/CombatHUDBindingIntegrationTest.gd'
```

Expected: exit code `1`，失败原因是 Autoload 尚未创建 `CombatHUD`；不得因测试构造场景方式产生无关解析错误。

- [ ] **Step 3: Separate result-overlay and HUD initialization**

修改 `GameRunController.gd`，增加：

```gdscript
const COMBAT_HUD_SCENE: PackedScene = preload("res://GameFlow/UI/CombatHUD.tscn")

var _combat_hud: CombatHUD
```

把 `_ready()` 改为独立初始化，禁止任一 UI 失败导致整个方法提前结束：

```gdscript
func _ready() -> void:
	_initialize_result_overlay()
	_initialize_combat_hud()
	call_deferred(&"_refresh_scene_bindings")


func _initialize_result_overlay() -> void:
	_result_overlay = RESULT_OVERLAY_SCENE.instantiate() as CanvasLayer
	if not is_instance_valid(_result_overlay):
		push_error("GameRunController: RunResultOverlay could not be instantiated.")
		return
	add_child(_result_overlay)
	if not _result_overlay.has_signal(&"restart_requested"):
		push_error("GameRunController: RunResultOverlay is missing restart_requested.")
		return
	_result_overlay.connect(&"restart_requested", _on_restart_requested)


func _initialize_combat_hud() -> void:
	_combat_hud = COMBAT_HUD_SCENE.instantiate() as CombatHUD
	if not is_instance_valid(_combat_hud):
		push_error("GameRunController: CombatHUD could not be instantiated.")
		return
	add_child(_combat_hud)
```

为这三个私有方法增加简体中文职责说明，强调它们彼此独立，尤其不得在 `_initialize_result_overlay()` 的错误分支阻止 HUD 创建。

- [ ] **Step 4: Add scene-level binding orchestration**

将当前 `_process()` 的场景切换分支调整为：

```gdscript
func _process(_delta: float) -> void:
	var active_scene: Node = get_tree().current_scene
	if active_scene == _observed_scene:
		return
	_observed_scene = active_scene
	_disconnect_room_controller()
	_unbind_combat_hud()
	if is_instance_valid(_result_overlay):
		_result_overlay.call(&"hide_result")
	call_deferred(&"_refresh_scene_bindings")
```

增加并使用以下方法：

```gdscript
func _refresh_scene_bindings() -> void:
	_refresh_room_binding()
	_refresh_combat_hud_binding()


func _refresh_combat_hud_binding() -> void:
	if not is_instance_valid(_combat_hud):
		return
	var players: Array[UnitBase] = []
	var allies: Array[UnitBase] = []
	_collect_party_units(get_tree().current_scene, players, allies)
	if players.is_empty():
		_combat_hud.unbind_party()
		return
	if players.size() != 1:
		push_warning(
			"GameRunController: CombatHUD requires exactly one Player; found %d."
			% players.size()
		)
		_combat_hud.unbind_party()
		return
	_combat_hud.bind_party(players[0], allies)


func _collect_party_units(
	node: Node,
	players: Array[UnitBase],
	allies: Array[UnitBase]
) -> void:
	if node == null:
		return
	if node is UnitBase:
		var unit := node as UnitBase
		if unit.faction_id == "Player":
			players.append(unit)
		elif unit.faction_id == "Ally":
			allies.append(unit)
	for child: Node in node.get_children():
		_collect_party_units(child, players, allies)


func _unbind_combat_hud() -> void:
	if is_instance_valid(_combat_hud):
		_combat_hud.unbind_party()
```

实施约束：

- `_refresh_room_binding()` 保留现有房间控制器发现与信号行为；不要把 HUD 是否可用作为它的前置条件。
- `_refresh_scene_bindings()` 即使当前场景没有 `CombatRoomController`，也必须继续尝试绑定 HUD。
- `_collect_party_units()` 保留深度优先场景树顺序；不排序名字、不读取 AI 子组件。
- 玩家唯一性按 `faction_id` 判定，与设计一致；不要改用 `PlayerBase` 类型，以便未来其他玩家职业仍只依赖通用单位协议。
- `_exit_tree()` 在原有 `_disconnect_room_controller()` 后调用 `_unbind_combat_hud()`。
- `_on_restart_requested()` 不需要直接刷新 HUD；`reload_current_scene()` 后由 `_process()` 的场景变化统一处理。
- 无玩家场景不输出警告；多玩家每次场景绑定最多输出一次警告，不在 `_process()` 每帧刷屏。

- [ ] **Step 5: Run integration test and confirm GREEN**

再次运行 Step 2 命令。

Expected: 输出 `CombatHUDBindingIntegrationTest: PASS`，exit code `0`。多玩家用例允许且应出现一次设计内 warning，但不得出现脚本错误。

- [ ] **Step 6: Run focused HUD regressions**

```powershell
$vodGodot = 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe'
& $vodGodot --headless --path 'G:\Godot\ProjectVOD' --script 'res://UnitSystem/Tests/UnitHealthFrameTest.gd'
& $vodGodot --headless --path 'G:\Godot\ProjectVOD' --script 'res://GameFlow/Tests/CombatHUDTest.gd'
```

Expected: 两项均 exit code `0`；Autoload 新增 HUD 后，独立组件测试仍可退出且不残留节点。

- [ ] **Step 7: Commit Task 3 only**

```powershell
git add -- `
  'GameFlow/GameRunController.gd' `
  'GameFlow/Tests/CombatHUDBindingIntegrationTest.gd' `
  'GameFlow/Tests/CombatHUDBindingIntegrationTest.gd.uid'
git commit -m 'feat: bind combat HUD to current party'
```

---

### Task 4: Preserve result-flow behavior and verify complete delivery

**Files:**
- Modify: `GameFlow/Tests/GameRunResultFlowTest.gd`
- Verify only: `GameFlow/GameRunController.gd`
- Verify only: `GameFlow/UI/CombatHUD.gd`
- Verify only: `UnitSystem/Components/UI/UnitHealthFrame.gd`

**Interfaces:**
- Consumes: `GameRunController/RunResultOverlay` 和 `GameRunController/CombatHUD` 两个独立 CanvasLayer。
- Produces: 完整回归证据；本任务不新增运行时接口。
- Preserves: 胜利/失败仍关闭玩家输入，结果界面 layer 100 覆盖 HUD layer 10，重新开始仍由原流程处理。

- [ ] **Step 1: Extend the result-flow regression before changing runtime code**

在 `GameRunResultFlowTest.gd::_verify_result_signal_disables_player_input()` 中，获得 `game_run` 后加入：

```gdscript
var hud := game_run.get_node_or_null(^"CombatHUD") as CanvasLayer
var overlay := game_run.get_node_or_null(^"RunResultOverlay") as CanvasLayer
_expect(hud != null, "GameRunController creates the combat HUD independently")
_expect(overlay != null, "GameRunController keeps the result overlay")
if hud != null and overlay != null:
	_expect(hud.layer < overlay.layer, "result overlay renders above combat HUD")
```

复用后文的 `overlay` 变量，不得在同一作用域重复声明。房间加入 Hero 并等待绑定后增加：

```gdscript
if hud != null:
	_expect(hud.visible, "combat room player makes the HUD visible")
```

在 `room_controller.room_completed.emit()` 和 `room_failed.emit()` 后保持现有断言，并新增：

```gdscript
if hud != null:
	_expect(hud.visible, "result overlay does not destroy or unbind current HUD")
```

该测试用于固化两个 UI 能共存的契约；不要让测试依赖颜色、字体或屏幕截图。

- [ ] **Step 2: Run the extended result-flow test**

```powershell
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' `
  --headless --path 'G:\Godot\ProjectVOD' `
  --script 'res://GameFlow/Tests/GameRunResultFlowTest.gd'
```

Expected: exit code `0`。若失败，先修复 Task 3 的初始化/绑定生命周期；不得通过删除原有房间完成、失败或输入断言来获得通过。

- [ ] **Step 3: Run the complete targeted regression matrix**

```powershell
$vodGodot = 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe'
$vodTests = @(
  'res://UnitSystem/Tests/UnitHealthFrameTest.gd',
  'res://GameFlow/Tests/CombatHUDTest.gd',
  'res://GameFlow/Tests/CombatHUDBindingIntegrationTest.gd',
  'res://GameFlow/Tests/GameRunResultFlowTest.gd',
  'res://UnitSystem/Tests/WorldHealthBarTest.gd',
  'res://UnitSystem/Tests/UnitDeathLifecycleTest.gd',
  'res://GameFlow/Rooms/Tests/CombatRoomControllerTest.gd'
)
foreach ($vodTest in $vodTests) {
  & $vodGodot --headless --path 'G:\Godot\ProjectVOD' --script $vodTest
  if ($LASTEXITCODE -ne 0) {
    throw "HUD regression failed: $vodTest"
  }
}
```

Expected: 所有脚本 exit code `0`。允许测试刻意触发的多玩家 warning；不允许 Parser Error、Invalid call、已释放实例访问、重复连接或节点未找到。

- [ ] **Step 4: Run final editor and project startup scans**

```powershell
$vodGodot = 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe'
& $vodGodot --headless --editor --path 'G:\Godot\ProjectVOD' --quit
if ($LASTEXITCODE -ne 0) { throw 'Godot editor scan failed' }
& $vodGodot --headless --path 'G:\Godot\ProjectVOD' --quit-after 120
if ($LASTEXITCODE -ne 0) { throw 'Godot project startup failed' }
```

Expected: 两项 exit code `0`。检查新增 `.gd.uid` 已生成且引用正常；不得把 `.godot/` 导入缓存加入 Git。

- [ ] **Step 5: Perform manual 2560×1440 visual acceptance**

在 Godot 编辑器运行当前主场景，仅观察，不修改场景实例。逐项核对并记录结果：

1. 玩家框贴近左下安全区域，默认尺寸约 420×90。
2. 伙伴框位于玩家框上方、左边缘对齐，默认尺寸约 280×60。
3. 玩家和伙伴名称、当前/最大生命在深色与明亮场景中都可读。
4. 受到伤害和治疗后数值与条形立即一致，不需要重新进入场景。
5. 伙伴倒下后原位置保留并出现“倒下”，其他伙伴不跳位。
6. 玩家框当前没有空白的假专注条、技能、物品或头像，但 `ExtensionSlot` 节点存在且折叠。
7. 世界头顶血条仍按原规则工作；屏幕 HUD 不影响其显隐。
8. 胜利/战败结果层显示在 HUD 上方。
9. 窗口从 2560×1440 调整到其他宽高时，HUD 仍贴左下且不越出屏幕。
10. 屏幕中没有锁定圆环、顶部目标框或其他本阶段外内容。

若仅需调整视觉参数，应优先修改 `CombatHUD.tscn` / `UnitHealthFrame.tscn` 的样式子资源或已定义的布局导出默认值；不得因此更改单位、AI 或战斗代码。

- [ ] **Step 6: Audit scope and repository state**

```powershell
git status --short
git diff --check
git diff --name-only HEAD~3..HEAD
```

Expected: 功能差异只涉及本计划 File Structure 中列出的 HUD、测试和 `GameRunController.gd` 文件；用户原有 `project.godot` 与 Godot MCP UID 状态保持原样，没有 `Scenes/**`、AI、技能、物品、锁定或世界血条修改。

- [ ] **Step 7: Commit the regression contract**

```powershell
git add -- 'GameFlow/Tests/GameRunResultFlowTest.gd'
git commit -m 'test: verify combat HUD result-flow compatibility'
```

若 editor scan 更新了本计划新增脚本对应的 `.gd.uid`，将它们加入各自所属任务的提交或单独使用 `chore: register combat HUD script UIDs` 提交；不得夹带任何无关 UID。

---

## Final Definition of Done

- `UnitHealthFrame` 仅依赖 `UnitBase` 的现有生命接口，完整处理初始值、伤害、治疗、死亡、复活、重复绑定、解绑和源节点退出。
- `CombatHUD` 有效绑定一名玩家和任意数量伙伴，玩家框左下、伙伴框向上排列且宽高约为玩家框三分之二。
- 伙伴死亡不删除、不重排框；失效节点安全隐藏；重新绑定会清理旧信号和动态实例。
- `GameRunController` 仅在场景变化时发现队伍，Player/Ally 判定使用现有 `faction_id`，没有每帧全树扫描。
- `RunResultOverlay` 与 `CombatHUD` 独立初始化；任何一个失败不阻止另一个和房间绑定逻辑继续工作。
- 没有玩家时 HUD 隐藏；多个玩家时 HUD 隐藏并只在绑定尝试时输出一次警告。
- 所有新增公共 API 与导出参数具有符合 `AGENTS.md` 的简体中文邻近文档。
- 不存在新外部 `.tres/.res`，不修改现有单位、AI、战斗、技能、物品、锁定、世界血条、测试场景或 `project.godot`。
- 三个新增测试、结果流程测试、生命/死亡/世界血条/房间控制器回归、editor scan 和 project startup 全部 exit code `0`。
- 2560×1440 与至少一个不同宽高比下的手动可读性验收完成，并确认结果层位于 HUD 之上。
