# Combat Threat Directory Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 实现 `CombatThreatDirectory` 事件驱动查询组件，维护"敌人→当前目标"的只读快照，供友方 AI 高效获知哪些敌人在攻击队友。

**Architecture:** 目录以 Node 形式挂载在 `EncounterController` 下，通过订阅每个敌机的 `locked_target_changed` / `died` / `tree_exiting` 维护内部哈希表。坦克等消费者通过 `get_enemies_targeting_others()` 一次查表即得结果，不需要 O(n) 轮询。

**Tech Stack:** Godot 4.7、GDScript、现有 `EnemyBase` / `AITargetingComponent` / `EncounterController`、Godot headless 测试。

## Global Constraints

- 不修改 `Scenes/TestScene.tscn` 中的任何单位实例。
- 所有新增代码字段、方法与信号使用英文标识，`@export` 参数提供简体中文注释。
- 目录不写仇恨数值、不修改 `locked_target`、不驱动移动和攻击。
- 不使用全局单例/autoload。
- 项目不是 Git 仓库，不创建提交。

---

### Task 1: CombatThreatDirectory 组件测试

**Files:**
- Create: `UnitSystem/Tests/CombatThreatDirectoryTest.gd`

**Interfaces:**
- Consumes: `EnemyBase.tscn`、`UnitBase.tscn` (`00_UnitBase.tscn`)、`AITargetingComponent.tscn`、`DefaultNearestEnemy.tres`
- Produces: 可执行测试，覆盖 register / get_target_of / get_enemies_targeting_others / 死亡清理 / 离树清理 / group 查找

- [ ] **Step 1: 写失败测试**

```gdscript
extends SceneTree

const ENEMY_SCENE_PATH := "res://UnitSystem/AI/Enemy/EnemyBase.tscn"
const UNIT_SCENE_PATH := "res://UnitSystem/Base/00_UnitBase.tscn"

var _failures: Array[String] = []
var _world: Node3D
var _directory: CombatThreatDirectory


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_world = Node3D.new()
	_world.name = "CombatThreatDirectoryTestWorld"
	root.add_child(_world)

	# --- 注册与目标查询 ---
	_directory = CombatThreatDirectory.new()
	_directory.name = "CombatThreatDirectory"
	_world.add_child(_directory)
	_expect(
		_directory.is_in_group(&"combat_threat_directory"),
		"directory registers itself in the combat_threat_directory group"
	)

	var target := _create_unit("Target", 1, Vector3.ZERO)
	var enemy := _create_enemy("EnemyA", 2, Vector3(0.0, 0.0, 2.0))
	_directory.register_enemy(enemy)
	_expect(
		_directory.get_enemy_count() == 1,
		"directory counts one registered enemy"
	)
	# 敌人初始无锁定目标
	_expect(
		_directory.get_target_of(enemy) == null,
		"enemy with no locked target returns null"
	)

	# 模拟锁定目标
	enemy.get_targeting_component().refresh_target()
	await _wait_for_physics()
	_expect(
		_directory.get_target_of(enemy) == target,
		"directory returns the current locked target after refresh"
	)
	_expect(
		_directory.get_enemies_targeting_others(target).is_empty(),
		"owner is the target, no enemies are targeting others"
	)
	var others := _directory.get_enemies_targeting_others(enemy)
	_expect(
		others.size() == 1 and others[0] == enemy,
		"owner is not the target, enemy appears in the others list"
	)

	# --- 死亡清理 ---
	target.apply_damage(9999.0)
	await process_frame
	_expect(
		_directory.get_enemy_count() == 1,
		"target death does not remove registered enemies from directory"
	)
	enemy.apply_damage(9999.0)
	await process_frame
	_expect(
		_directory.get_enemy_count() == 0,
		"enemy death removes it from directory"
	)

	# --- 多敌机、不同目标 ---
	var target_b := _create_unit("TargetB", 1, Vector3(5.0, 0.0, 0.0))
	var enemy_a := _create_enemy("MultiEnemyA", 2, Vector3(0.0, 0.0, 2.0))
	var enemy_b := _create_enemy("MultiEnemyB", 2, Vector3(6.0, 0.0, 2.0))
	_directory.register_enemy(enemy_a)
	_directory.register_enemy(enemy_b)

	enemy_a.get_targeting_component().refresh_target()
	enemy_b.get_targeting_component().refresh_target()
	await _wait_for_physics()
	# enemy_a 靠近 target (z=0)，enemy_b 靠近 target_b (x=5)
	# 两者可能分别锁定不同目标
	var a_target := _directory.get_target_of(enemy_a)
	var b_target := _directory.get_target_of(enemy_b)
	if a_target != b_target and a_target != null and b_target != null:
		var others_from_a := _directory.get_enemies_targeting_others(a_target)
		_expect(
			others_from_a.size() >= 1,
			"multi-enemy scenario: others list includes enemies targeting a different unit"
		)

	# --- 离树清理 ---
	enemy_a.queue_free()
	await process_frame
	_expect(
		_directory.get_enemy_count() == 1,
		"tree exit removes enemy from directory"
	)

	_finish()


func _create_enemy(unit_name: String, unit_team_id: int, unit_position: Vector3) -> EnemyBase:
	var unit := (load(ENEMY_SCENE_PATH) as PackedScene).instantiate() as EnemyBase
	unit.name = unit_name
	unit.team_id = unit_team_id
	unit.position = unit_position
	_world.add_child(unit)
	unit.set_physics_process(false)
	return unit


func _create_unit(unit_name: String, unit_team_id: int, unit_position: Vector3) -> UnitBase:
	var unit := (load(UNIT_SCENE_PATH) as PackedScene).instantiate() as UnitBase
	unit.name = unit_name
	unit.team_id = unit_team_id
	unit.collision_layer = 2 if unit_team_id == 1 else 4
	unit.position = unit_position
	_world.add_child(unit)
	return unit


func _wait_for_physics() -> void:
	await physics_frame
	await physics_frame


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if is_instance_valid(_world):
		_world.queue_free()
	if _failures.is_empty():
		print("CombatThreatDirectoryTest: PASS")
		quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	print("CombatThreatDirectoryTest: FAIL (%d)" % _failures.size())
	quit(1)
```

- [ ] **Step 2: 运行测试确认失败**

```powershell
& $GodotConsole --headless --path 'G:\Godot\SipSip' --script 'res://UnitSystem/Tests/CombatThreatDirectoryTest.gd'
```

Expected: FAIL，因为 `CombatThreatDirectory` 类尚不存在。

---

### Task 2: CombatThreatDirectory 组件实现

**Files:**
- Create: `UnitSystem/Components/Threat/CombatThreatDirectory.gd`
- Modify: `UnitSystem/Tests/CombatThreatDirectoryTest.gd` (无需修改，此时应通过)

**Interfaces:**
- Produces: `class_name CombatThreatDirectory extends Node`，公开方法:
  - `register_enemy(enemy: EnemyBase) -> void`
  - `get_enemies_targeting_others(owner: UnitBase) -> Array[EnemyBase]`
  - `get_target_of(enemy: EnemyBase) -> UnitBase`
  - `get_enemy_count() -> int`

- [ ] **Step 1: 实现目录组件**

创建 `UnitSystem/Components/Threat/CombatThreatDirectory.gd`：

```gdscript
class_name CombatThreatDirectory
extends Node

## 战斗威胁目录：事件驱动的"敌人→当前目标"只读快照。
## 本组件只维护两张哈希表并在敌机信号到来时更新；
## 不写仇恨数值，不修改 locked_target，不驱动移动和攻击。

signal enemy_registered(enemy: EnemyBase)
signal enemy_unregistered(enemy: EnemyBase)

var _target_by_enemy: Dictionary = {}  # int enemy_id -> int target_id
var _enemies_by_target: Dictionary = {}  # int target_id -> Array[int] enemy_ids
var _enemy_node_by_id: Dictionary = {}  # int -> EnemyBase
var _unit_node_by_id: Dictionary = {}  # int -> UnitBase


func _ready() -> void:
	add_to_group(&"combat_threat_directory")


## 注册一个敌人；连接其 locked_target_changed / died / tree_exiting 信号，
## 并在其已持有锁定目标时写入初始记录。
func register_enemy(enemy: EnemyBase) -> void:
	if not is_instance_valid(enemy):
		return
	var enemy_id: int = enemy.get_instance_id()
	if _enemy_node_by_id.has(enemy_id):
		return
	_enemy_node_by_id[enemy_id] = enemy
	if not enemy.locked_target_changed.is_connected(
		_on_enemy_target_changed.bind(enemy)
	):
		enemy.locked_target_changed.connect(
			_on_enemy_target_changed.bind(enemy)
		)
	if not enemy.died.is_connected(_on_enemy_died.bind(enemy)):
		enemy.died.connect(_on_enemy_died.bind(enemy))
	if not enemy.tree_exiting.is_connected(
		_on_enemy_tree_exiting.bind(enemy)
	):
		enemy.tree_exiting.connect(
			_on_enemy_tree_exiting.bind(enemy)
		)
	enemy_registered.emit(enemy)
	var current_target := enemy.get_locked_target()
	if is_instance_valid(current_target):
		_add_target_record(enemy_id, current_target.get_instance_id())
		_unit_node_by_id[current_target.get_instance_id()] = current_target


## 返回所有当前目标不是 owner 的已注册敌机列表。
## 查询只读取内部哈希表，不触发任何信号或扫描。
func get_enemies_targeting_others(owner: UnitBase) -> Array[EnemyBase]:
	var result: Array[EnemyBase] = []
	if not is_instance_valid(owner):
		return result
	var owner_id: int = owner.get_instance_id()
	for target_id: int in _enemies_by_target.keys():
		if target_id == owner_id:
			continue
		var enemy_ids: Array = _enemies_by_target[target_id] as Array
		for enemy_id: int in enemy_ids:
			var enemy := _enemy_node_by_id.get(enemy_id) as EnemyBase
			if is_instance_valid(enemy):
				result.append(enemy)
	return result


## 返回指定敌人的当前锁定目标；无记录返回 null。
func get_target_of(enemy: EnemyBase) -> UnitBase:
	if not is_instance_valid(enemy):
		return null
	var enemy_id: int = enemy.get_instance_id()
	var target_id: Variant = _target_by_enemy.get(enemy_id)
	if target_id == null:
		return null
	return _unit_node_by_id.get(int(target_id)) as UnitBase


## 调试用：返回当前注册的敌人数。
func get_enemy_count() -> int:
	_prune_invalid_refs()
	return _enemy_node_by_id.size()


## 敌机锁定目标变更时的回调；只更新哈希表，不改写信号来源的结果。
func _on_enemy_target_changed(
	_previous: UnitBase,
	current: UnitBase,
	enemy: EnemyBase
) -> void:
	if not is_instance_valid(enemy):
		return
	var enemy_id: int = enemy.get_instance_id()
	var old_target_id: Variant = _target_by_enemy.get(enemy_id)
	if old_target_id != null:
		_remove_target_record(enemy_id, int(old_target_id))
	_target_by_enemy.erase(enemy_id)
	if is_instance_valid(current):
		var new_target_id: int = current.get_instance_id()
		_add_target_record(enemy_id, new_target_id)
		_unit_node_by_id[new_target_id] = current


## 清空指定敌人的所有目录记录并断开信号，不修改敌机本身的任何状态。
func _unregister_enemy(enemy: EnemyBase) -> void:
	if not is_instance_valid(enemy):
		return
	var enemy_id: int = enemy.get_instance_id()
	var target_id: Variant = _target_by_enemy.get(enemy_id)
	if target_id != null:
		_remove_target_record(enemy_id, int(target_id))
	_target_by_enemy.erase(enemy_id)
	_enemy_node_by_id.erase(enemy_id)
	if enemy.locked_target_changed.is_connected(
		_on_enemy_target_changed
	):
		enemy.locked_target_changed.disconnect(
			_on_enemy_target_changed
		)
	if enemy.died.is_connected(_on_enemy_died):
		enemy.died.disconnect(_on_enemy_died)
	if enemy.tree_exiting.is_connected(_on_enemy_tree_exiting):
		enemy.tree_exiting.disconnect(_on_enemy_tree_exiting)
	enemy_unregistered.emit(enemy)


func _add_target_record(enemy_id: int, target_id: int) -> void:
	_target_by_enemy[enemy_id] = target_id
	var enemy_list: Array = _enemies_by_target.get(target_id, [])
	if not enemy_list.has(enemy_id):
		enemy_list.append(enemy_id)
		_enemies_by_target[target_id] = enemy_list


func _remove_target_record(enemy_id: int, target_id: int) -> void:
	var enemy_list: Array = _enemies_by_target.get(target_id, [])
	if enemy_list.has(enemy_id):
		enemy_list.erase(enemy_id)
	if enemy_list.is_empty():
		_enemies_by_target.erase(target_id)
	else:
		_enemies_by_target[target_id] = enemy_list


func _on_enemy_died(_source: Node, enemy: EnemyBase) -> void:
	_unregister_enemy(enemy)


func _on_enemy_tree_exiting(enemy: EnemyBase) -> void:
	_unregister_enemy(enemy)


func _prune_invalid_refs() -> void:
	var to_remove: Array[int] = []
	for enemy_id: int in _enemy_node_by_id.keys():
		var enemy := _enemy_node_by_id.get(enemy_id) as EnemyBase
		if not is_instance_valid(enemy) or not enemy.is_inside_tree():
			to_remove.append(enemy_id)
	for enemy_id: int in to_remove:
		_target_by_enemy.erase(enemy_id)
		_enemy_node_by_id.erase(enemy_id)
		# 不清 _enemies_by_target 中的残留，下次查询时自动过滤
```

- [ ] **Step 2: 运行测试确认通过**

```powershell
& $GodotConsole --headless --path 'G:\Godot\SipSip' --script 'res://UnitSystem/Tests/CombatThreatDirectoryTest.gd'
```

Expected: PASS。

---

### Task 3: EncounterController 注册入口

**Files:**
- Modify: `UnitSystem/Encounter/EncounterController.gd`

**Interfaces:**
- Consumes: `CombatThreatDirectory.register_enemy(enemy: EnemyBase)`
- Produces: 每个登记的 Pack 中所有敌机均在目录中注册。

- [ ] **Step 1: 在 _register_pack 中创建目录并注册敌机**

在 `EncounterController._register_pack` 方法末尾（`_attach_pack_target_fallback_resolvers(record)` 之后，方法结束前）插入：

```gdscript
	# 创建或复用 CombatThreatDirectory 并注册本 Pack 的全部敌机。
	var directory: CombatThreatDirectory
	if has_node(^"CombatThreatDirectory"):
		directory = get_node(^"CombatThreatDirectory") as CombatThreatDirectory
	else:
		directory = CombatThreatDirectory.new()
		directory.name = "CombatThreatDirectory"
		add_child(directory)
	for enemy: EnemyBase in record.enemies:
		directory.register_enemy(enemy)
```

- [ ] **Step 2: 运行 EncounterController 测试确认无回归**

```powershell
& $GodotConsole --headless --path 'G:\Godot\SipSip' --script 'res://UnitSystem/Tests/EncounterControllerTest.gd'
```

Expected: PASS，且输出中无新增错误。

---

### Task 4: 全量回归验证

- [ ] **Step 1: 运行新增测试与相关回归**

```powershell
& $GodotConsole --headless --path 'G:\Godot\SipSip' --script 'res://UnitSystem/Tests/CombatThreatDirectoryTest.gd'
& $GodotConsole --headless --path 'G:\Godot\SipSip' --script 'res://UnitSystem/Tests/EncounterControllerTest.gd'
& $GodotConsole --headless --path 'G:\Godot\SipSip' --script 'res://UnitSystem/Tests/EnemyBehaviorStateMachineTest.gd'
& $GodotConsole --headless --path 'G:\Godot\SipSip' --script 'res://UnitSystem/Tests/EnemyThreatComponentTest.gd'
& $GodotConsole --headless --path 'G:\Godot\SipSip' --script 'res://UnitSystem/Tests/UnitDirectoryLayoutTest.gd'
```

- [ ] **Step 2: Godot headless 编辑器扫描**

```powershell
& $GodotConsole --headless --editor --path 'G:\Godot\SipSip' --quit
```

Expected: 退出码 0，无新增脚本或场景解析错误。

---

## 实施顺序

Task 1 → Task 2 → Task 3 → Task 4。每个 Task 完成后即可独立验证，不依赖后续 Task。

Task 1 和 Task 2 可在没有 EncounterController 的环境下独立测试（目录自己创建管理生命周期）。Task 3 把目录接入真实遭遇流程。Task 4 是最终回归。
