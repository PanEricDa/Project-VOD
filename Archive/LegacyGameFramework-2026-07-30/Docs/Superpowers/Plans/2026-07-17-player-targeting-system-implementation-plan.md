# PlayerBase Player Targeting System Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将旧 Hero 的鼠标/最近目标锁定、目标有效性验证、锁定朝向和绿红范围圈安全迁移为 PlayerBase 的可拆装组件。

**Architecture:** `PlayerTargetingComponent` 独立读取锁定 InputMap、维护当前目标并生成范围圈；`PlayerBase` 只配置组件、转发信号、提供门面方法，并读取组件输出的方向决定 Visual 朝向。目标合法性统一通过 `UnitBase` 的生命、可选中和阵营接口判断。

**Tech Stack:** Godot 4.7、GDScript、CharacterBody3D、Camera3D 射线、TorusMesh、SceneTree headless 测试。

## Global Constraints

- 不修改 `Scenes/TestScene.tscn`，不向其中添加任何单位实例。
- 所有输入必须使用现有 InputMap：`player_target_select` 与 `player_target_nearest`。
- 所有代码字段和方法使用英文标识，新增代码提供详细简体中文注释。
- 索敌组件必须可删除；删除后 PlayerBase 的移动、冲刺、重力和移动朝向保持可用。
- 只迁移索敌、锁敌、锁定朝向和范围圈，不迁移攻击、技能、UI 或摄像机逻辑。
- 项目不是 Git 仓库，因此每个任务使用测试结果代替提交步骤。

---

### Task 1: PlayerTargetingComponent 核心目标状态

**Files:**
- Create: `UnitSystem/Tests/PlayerTargetingComponentTest.gd`
- Create: `UnitSystem/Components/Targeting/PlayerTargetingComponent.gd`
- Create: `UnitSystem/Components/Targeting/PlayerTargetingComponent.tscn`

**Interfaces:**
- Consumes: `UnitBase.is_targetable() -> bool`、`UnitBase.is_dead() -> bool`、`UnitBase.is_hostile_to(other: UnitBase) -> bool`。
- Produces:
  - `signal locked_target_changed(target: UnitBase)`
  - `configure(owner_unit: UnitBase) -> bool`
  - `get_locked_target() -> UnitBase`
  - `request_lock(target: UnitBase) -> bool`
  - `clear_locked_target() -> void`
  - `lock_nearest_target() -> bool`
  - `get_locked_target_direction() -> Vector3`
  - `is_valid_lock_target(target: UnitBase) -> bool`

- [ ] **Step 1: 编写核心状态失败测试**

测试实例化组件和三类 UnitBase，设置 `team_id`、`enemy_targets` 分组、距离、生命值与 `targetable`，断言：

```gdscript
_assert_true(component.configure(owner), "valid UnitBase owner configures")
_assert_true(component.request_lock(enemy), "hostile target locks")
_assert_equal(component.get_locked_target(), enemy, "locked target is stored")
_assert_false(component.request_lock(ally), "friendly target is rejected")
_assert_false(component.request_lock(neutral), "neutral target is rejected")
enemy.targetable = false
component.call("_physics_process", 0.016)
_assert_equal(component.get_locked_target(), null, "invalid target clears")
```

同时验证同一目标重复请求不重复发信号，超距、死亡、错误分组和离树目标均无效，最近目标会忽略无效候选者。

- [ ] **Step 2: 运行失败测试**

```powershell
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' --headless --path 'G:\Godot\SipSip' --script res://UnitSystem/Tests/PlayerTargetingComponentTest.gd
```

Expected: FAIL，因为组件场景和脚本尚不存在。

- [ ] **Step 3: 实现最小目标状态组件**

组件继承 `Node3D`，保存：

```gdscript
var _owner_unit: UnitBase
var _locked_target: UnitBase
```

`is_valid_lock_target()` 必须按顺序验证实例、场景树、分组、可选中、存活、敌对关系和最大距离。`request_lock()` 只在合法时更新状态；失败请求不保留非法目标。`lock_nearest_target()` 遍历候选组并选择距离平方最小者。物理帧只负责使已锁定目标失效时统一清除。

- [ ] **Step 4: 创建组件场景**

```text
PlayerTargetingComponent (Node3D, script)
└── TargetLockRangeIndicator (MeshInstance3D)
```

场景不保存运行时目标，不引用 PlayerBase 源场景。

- [ ] **Step 5: 运行核心状态测试**

运行 Step 2 命令。

Expected: `PlayerTargetingComponentTest: PASS`，退出码 0。

---

### Task 2: 输入、摄像机射线与范围圈

**Files:**
- Modify: `UnitSystem/Tests/PlayerTargetingComponentTest.gd`
- Modify: `UnitSystem/Components/Targeting/PlayerTargetingComponent.gd`
- Modify: `UnitSystem/Components/Targeting/PlayerTargetingComponent.tscn`

**Interfaces:**
- Consumes: Task 1 的目标状态接口和活动 Viewport `Camera3D`。
- Produces:
  - `select_target_at_screen_position(position: Vector2) -> bool`
  - 导出 InputMap、射线、候选组和范围圈配置。

- [ ] **Step 1: 编写表现与输入失败测试**

新增断言：

```gdscript
_assert_equal(component.target_select_action, &"player_target_select", "select action")
_assert_equal(component.target_nearest_action, &"player_target_nearest", "nearest action")
_assert_near(component.maximum_lock_distance, 5.0, 0.001, "lock distance")
_assert_equal(component.selection_collision_mask, 5, "ray mask")
var ring := component.get_node(^"TargetLockRangeIndicator") as MeshInstance3D
_assert_true(ring.mesh is TorusMesh, "range indicator uses TorusMesh")
_assert_color_near(
    (ring.material_override as StandardMaterial3D).albedo_color,
    component.indicator_idle_color,
    "idle ring is green"
)
component.request_lock(enemy)
_assert_color_near(
    (ring.material_override as StandardMaterial3D).albedo_color,
    component.indicator_locked_color,
    "locked ring is red"
)
```

验证没有活动摄像机时 `select_target_at_screen_position()` 安全返回 `false` 并清除锁定；用 `InputEventAction` 验证最近目标动作复用 `lock_nearest_target()`。

- [ ] **Step 2: 运行测试确认因表现/输入缺失而失败**

运行 Task 1 的测试命令。

Expected: FAIL，失败项指向 TorusMesh、颜色或输入处理尚未实现。

- [ ] **Step 3: 实现范围圈**

在 `_ready()` 或 `configure()` 中运行 `_configure_indicator()`：

```gdscript
var ring_mesh := TorusMesh.new()
ring_mesh.inner_radius = maxf(maximum_lock_distance - indicator_thickness, 0.001)
ring_mesh.outer_radius = maximum_lock_distance
ring_mesh.rings = 96
ring_mesh.ring_segments = 6
```

创建透明、无光照、双面、无阴影材质。锁定状态变化只更新材质颜色，不改变检测范围。

- [ ] **Step 4: 实现 InputMap 和射线**

`_unhandled_input()` 只响应两个导出动作。最近目标动作调用 `lock_nearest_target()`；鼠标动作读取 `InputEventMouseButton.position` 并调用 `select_target_at_screen_position()`。射线使用：

```gdscript
PhysicsRayQueryParameters3D.create(
    ray_origin,
    ray_end,
    selection_collision_mask,
    [_owner_unit.get_rid()]
)
```

任何无摄像机、空命中或无效命中均调用 `clear_locked_target()` 并返回 `false`。

- [ ] **Step 5: 运行组件测试**

运行 Task 1 的测试命令。

Expected: `PlayerTargetingComponentTest: PASS`，无新增 warning/error。

---

### Task 3: PlayerBase 装配、门面与朝向

**Files:**
- Modify: `UnitSystem/Tests/PlayerBaseMovementTest.gd`
- Modify: `UnitSystem/PlayerBase.gd`
- Modify: `UnitSystem/PlayerBase.tscn`

**Interfaces:**
- Consumes: Task 1/2 的 `PlayerTargetingComponent` 公共接口。
- Produces:
  - `signal locked_target_changed(target: UnitBase)`
  - `get_locked_target() -> UnitBase`
  - `clear_locked_target() -> void`
  - `@export_node_path("Node") var targeting_component_path`

- [ ] **Step 1: 编写 PlayerBase 接入失败测试**

新增断言：

```gdscript
var targeting := player.get_node_or_null(^"TargetingSystem")
_assert_true(targeting != null, "PlayerBase assembles targeting component")
_assert_equal(targeting.call("get_owner_unit"), player, "owner is configured")
_assert_true(player.has_method(&"get_locked_target"), "facade getter exists")
_assert_true(player.has_method(&"clear_locked_target"), "facade clear exists")
```

创建前方敌人并锁定，给玩家侧向移动输入，断言 Visual 更朝向目标而非移动方向。随后复制/实例化 PlayerBase、删除 `TargetingSystem`、执行移动和冲刺，断言旧行为仍正常。

- [ ] **Step 2: 运行测试确认因 PlayerBase 尚未接入而失败**

```powershell
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' --headless --path 'G:\Godot\SipSip' --script res://UnitSystem/Tests/PlayerBaseMovementTest.gd
```

Expected: FAIL，缺少 `TargetingSystem` 或 PlayerBase 门面接口。

- [ ] **Step 3: 修改 PlayerBase 场景和初始化**

在 `PlayerBase.tscn` 根节点下实例化组件并设置：

```gdscript
targeting_component_path = NodePath("TargetingSystem")
```

在 PlayerBase `_ready()` 中安全获取组件、连接信号、配置持有者。组件缺失时只保持 `_targeting_component=null`，不禁用物理处理。

- [ ] **Step 4: 实现门面和朝向优先级**

门面方法只转发组件：

```gdscript
func get_locked_target() -> UnitBase:
    if not is_instance_valid(_targeting_component):
        return null
    return _targeting_component.get_locked_target()

func clear_locked_target() -> void:
    if is_instance_valid(_targeting_component):
        _targeting_component.clear_locked_target()
```

物理帧朝向改为：

```gdscript
var facing_direction := Vector3.ZERO
if is_instance_valid(_targeting_component):
    facing_direction = _targeting_component.get_locked_target_direction()
if facing_direction.length_squared() <= 0.0001:
    facing_direction = _dash_direction if is_player_dashing() else movement_direction
```

- [ ] **Step 5: 运行 PlayerBase 和组件测试**

运行 Task 2 与 Task 3 测试命令。

Expected: 两个测试均 PASS。

---

### Task 4: 回归与 Godot 4.7 验证

**Files:**
- Verify only; no TestScene modifications.

**Interfaces:**
- Consumes: 完成后的组件和 PlayerBase。
- Produces: 可重复的验证证据。

- [ ] **Step 1: 运行全部 UnitSystem 测试**

```powershell
$godot = 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe'
Get-ChildItem 'G:\Godot\SipSip\UnitSystem\Tests' -Filter '*.gd' | Sort-Object Name | ForEach-Object {
    & $godot --headless --path 'G:\Godot\SipSip' --script ('res://UnitSystem/Tests/' + $_.Name)
    if ($LASTEXITCODE -ne 0) { throw "Failed: $($_.Name)" }
}
```

Expected: 所有 UnitSystem 测试退出码 0。

- [ ] **Step 2: 运行项目既有 Tests**

```powershell
$godot = 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe'
Get-ChildItem 'G:\Godot\SipSip\Tests' -Filter '*.gd' | Sort-Object Name | ForEach-Object {
    & $godot --headless --path 'G:\Godot\SipSip' --script ('res://Tests/' + $_.Name)
    if ($LASTEXITCODE -ne 0) { throw "Failed: $($_.Name)" }
}
```

Expected: 所有既有测试退出码 0。

- [ ] **Step 3: 执行编辑器扫描和无窗口启动**

```powershell
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' --headless --editor --path 'G:\Godot\SipSip' --quit
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' --headless --path 'G:\Godot\SipSip' --quit-after 10
```

Expected: 无脚本解析错误，无新增 warning/error。

- [ ] **Step 4: 使用 MCP 刷新并检查编辑器**

刷新项目文件系统，重新加载新脚本，检查 Godot 编辑器错误和 Output。确认 `Scenes/TestScene.tscn` 未被修改。

## 2026-07-17 实施验证记录

- PlayerTargetingComponent 独立测试：PASS。
- PlayerBase 移动与索敌装配测试：PASS。
- UnitSystem 全量测试：8/8 PASS。
- 项目既有 `Tests`：25/26 PASS。
- 唯一既有失败：`MageSkillAssemblyTest.gd` 期望 Mage 的 `ranger_path` 为
  `../Ranger`，当前场景实际配置为 `../Mage2`；该配置与本次 PlayerBase 索敌迁移无关，
  实施过程中未修改 Mage 场景或测试预期。
- Godot 4.7 `--headless --editor --quit`：退出码 0。
- Godot 4.7 项目无窗口启动：退出码 0。
- MCP 文件系统刷新成功；两个新脚本和两个相关场景均可加载。
- 清空 MCP Output 后，编辑器错误数：0。
- `Scenes/TestScene.tscn` 未被修改，也未自动添加任何单位实例。
