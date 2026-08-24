# 最小测试战斗房间与自动摄像机实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让 `TestCombatRoom` 成为不含自动单位实例的可导航测试房间，并让 `CameraFollowController` 自动跟随唯一的 Player 阵营单位。

**Architecture:** 摄像机只从当前场景树递归识别 `UnitBase.faction_id == "Player"` 的唯一单位，运行时缓存该对象并在失效时重新查找。战斗房间只补充出生点与敌方容器节点；它不引入波次、生成或战斗结算逻辑。

**Tech Stack:** Godot 4.7、GDScript、Godot headless 测试、Godot MCP Pro。

## 全局约束

- 所有新增可配置 `@export` 字段、公开方法与信号都必须紧邻写出详细简体中文说明。
- 不自动添加、删除或修改 `res://Scenes/TestScene.tscn` 内的任何单位实例。
- 本任务不添加任何单位实例到 `TestCombatRoom.tscn`；用户在编辑器中手动放置并定位 Hero、伙伴和敌人。
- 不创建新 `.tres/.res` 外部资源。
- 项目不是 Git 工作区；不创建提交。

---

### Task 1：自动 Player 目标解析与回归测试

**Files:**
- Create: `UnitSystem/Tests/CameraFollowControllerTest.gd`
- Modify: `UnitSystem/Components/Camera/CameraFollowController.gd`

**Interfaces:**
- Consumes: `UnitBase` 的 `faction_id` 枚举字符串，Player 值为 `"Player"`。
- Produces: `func get_resolved_target() -> UnitBase`，返回当前已自动解析的 Player；无唯一 Player 时返回 `null`。

- [x] **Step 1: 写出失败的摄像机目标解析测试**

测试以临时场景树创建 `CameraFollowController` 与 `UnitBase`：

```gdscript
func _verify_unique_player_is_resolved() -> void:
	var player := _create_unit("RenamedHero", "Player")
	_scene_root.add_child(player)
	_camera_rig._resolve_follow_target()
	_assert(_camera_rig.get_resolved_target() == player, "唯一 Player 必须被自动绑定")
```

覆盖以下契约：改名与嵌套层级不影响绑定；无 Player 时不报错且可在后续加入后绑定；多个 Player 时保持未绑定；已绑定 Player `queue_free()` 后会清理引用并可重新绑定唯一候选。

- [x] **Step 2: 运行测试，确认它因接口尚不存在而失败**

运行：

```powershell
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' --headless --path 'G:\Godot\SipSip' --script 'res://UnitSystem/Tests/CameraFollowControllerTest.gd'
```

预期：测试失败，指出 `_resolve_follow_target()` 或 `get_resolved_target()` 尚未定义。

- [x] **Step 3: 实现统一的自动解析流程**

在 `CameraFollowController.gd` 中：

```gdscript
const PLAYER_FACTION_ID: StringName = &"Player"
const TARGET_RESOLUTION_RETRY_INTERVAL: float = 0.25

func _resolve_follow_target() -> void:
	var candidates: Array[UnitBase] = []
	_collect_player_units(get_tree().current_scene, candidates)
	if candidates.size() == 1:
		_assign_target(candidates[0])
	elif candidates.size() == 0:
		_clear_target()
	else:
		_clear_target()
		_warn_multiple_players_once(candidates.size())

func get_resolved_target() -> UnitBase:
	return target
```

移除 `target_path` 与 `_ready()` 中的 `push_error()/set_process(false)` 分支。`_process()` 先验证缓存目标；无目标时按固定间隔重试，找到唯一候选后调用 `snap_to_target()`。使用递归子节点遍历，不依赖节点名称、层级、Group 或手填路径。多个候选只警告一次；候选恢复唯一后重置该警告标记。以只读 Inspector 调试字段显示当前目标 NodePath 或空值，不写回场景。

- [x] **Step 4: 运行摄像机测试，确认通过**

运行同一 headless 命令。

预期：输出 `CameraFollowControllerTest: PASS`，且没有 `target_path` 配置错误。

### Task 2：移除旧手写路径并补齐测试房间结构

**Files:**
- Modify: `Scenes/TestCombatRoom.tscn`
- Modify: `Scenes/TestScene2.tscn`
- Modify: `UnitSystem/Tests/CameraFollowControllerTest.gd`

**Interfaces:**
- Consumes: Task 1 自动解析接口。
- Produces: 不含 `target_path` 的 CameraRig 场景配置，以及可供用户手动摆放单位的房间容器层级。

- [x] **Step 1: 扩展失败测试，断言房间结构和无手写相机目标**

测试加载 `res://Scenes/TestCombatRoom.tscn` 并断言：

```gdscript
_assert(room.get_node_or_null("PlayerSpawn") is Marker3D, "必须存在 PlayerSpawn")
_assert(room.get_node_or_null("PartySpawn") is Marker3D, "必须存在 PartySpawn")
_assert(room.get_node_or_null("EnemyContainer/Pack_A") is Node3D, "必须存在 Pack_A")
_assert(room.get_node_or_null("CameraRig").get("target_path") == null, "不得保留手写目标路径")
```

并断言 `EnemyContainer` 及三个 `Pack_*` 均不附加脚本、不自动实例化单位。

- [x] **Step 2: 运行测试，确认旧场景结构尚不满足契约**

运行 Task 1 的 headless 命令。

预期：缺少出生点/敌人容器或仍存在旧路径配置导致失败。

- [x] **Step 3: 最小化编辑场景结构**

从 `TestCombatRoom.tscn` 和 `TestScene2.tscn` 删除 `target_path = NodePath(...)`。在 `TestCombatRoom` 根节点下添加：

```text
PlayerSpawn       Marker3D
PartySpawn        Marker3D
EnemyContainer    Node3D
├── Pack_A         Node3D
├── Pack_B         Node3D
└── Pack_C         Node3D
```

不添加脚本、单位、EncounterController、波次、生成器或奖励节点。`PlayerSpawn` 置于世界原点附近，`PartySpawn` 在其后侧，三个 Pack 容器在不同前方位置，仅作为用户手动摆放单位的空间标记。

- [x] **Step 4: 运行场景结构与摄像机测试**

运行 Task 1 的 headless 命令。

预期：`CameraFollowControllerTest: PASS`。

### Task 3：导航烘焙、导航检查与完整验证

**Files:**
- Modify: `Scenes/TestCombatRoom.tscn`（仅在当前 NavigationMesh 尚未包含多边形时）
- Modify: `UnitSystem/Tests/CameraFollowControllerTest.gd`
- Modify: `Docs/Superpowers/Specs/2026-08-01-test-combat-room-and-camera-design.md`
- Modify: `Docs/Superpowers/Plans/2026-08-01-test-combat-room-and-camera-implementation-plan.md`

**Interfaces:**
- Consumes: 当前 `NavigationRegion3D` 与 `Ground`。
- Produces: 覆盖 Ground 的有效导航网格与可重复验证记录。

- [x] **Step 1: 写出导航有效性断言**

在房间加载测试中获取 `NavigationRegion3D.navigation_mesh`，验证其存在且 `get_polygon_count() > 0`：

```gdscript
var navigation_mesh := navigation_region.navigation_mesh
_assert(navigation_mesh != null and navigation_mesh.get_polygon_count() > 0, "战斗房间导航网格必须已烘焙")
```

- [x] **Step 2: 运行测试，确认当前网格状态**

运行 Task 1 的 headless 命令。

预期：若网格未烘焙，导航断言失败；若已有效，则直接通过。

- [x] **Step 3: 仅在需要时烘焙现有 Ground**

使用 Godot 编辑器或 MCP 对 `TestCombatRoom/NavigationRegion3D` 的现有 NavigationMesh 进行烘焙，使其覆盖 CSG 地面。只保存该场景的导航数据；不添加或改动单位实例。

- [x] **Step 4: 执行完整验证并记录结果**

运行：

```powershell
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' --headless --path 'G:\Godot\SipSip' --script 'res://UnitSystem/Tests/CameraFollowControllerTest.gd'
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' --headless --path 'G:\Godot\SipSip' --script 'res://UnitSystem/Tests/EnemyBehaviorStateMachineTest.gd'
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' --headless --editor --path 'G:\Godot\SipSip' --quit
```

随后通过 Godot MCP Pro 刷新项目并读取编辑器错误面板。把实际通过命令、导航结果和“未自动添加单位”的结论追加到设计文档验证记录，并把本计划所有复选框标记完成。
