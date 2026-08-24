# Bow, Staff and MagicGlobe Weapon Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在新 `Item/Weapon` 架构中创建可装备的 Bow、Staff、MagicGlobe 三套 `WeaponData + Visual + AnimationLibrary` 资源，并迁移旧单位对应的简易视觉与动作风格。

**Architecture:** 三种武器均为无专用脚本的扁平资源包。Visual 只保存 CSG 视觉，AnimationLibrary 只驱动 Hero 的 `CharacterRoot` 与 `WeaponSocket`，WeaponData 只连接同目录 Visual 和 AnimationLibrary；本阶段不建立远程 Delivery。

**Tech Stack:** Godot 4.7、GDScript、AnimationLibrary、CSGBox3D、CSGCylinder3D、CSGSphere3D、Godot MCP Pro、PowerShell。

## Global Constraints

- 只创建 `Item/Weapon/Bow`、`Item/Weapon/Staff`、`Item/Weapon/MagicGlobe` 下的新资源及对应测试。
- 不修改旧 Ranger、Healer、Mage、CrossbowAttack、StaffAttack、MagicballAttack 或 `Scenes/TestScene.tscn`。
- 不修改 `PlayerAttackController.gd`、`WeaponData.gd`、Hero 源场景或当前盾牌 Workbench 配置。
- 每套 AnimationLibrary 只包含 `RESET` 与 `basic_attack_1`。
- 每段动画只包含四条值轨道，不包含 Method Track。
- `attack_forward_distances`、`hitbox_sizes`、`hitbox_center_offsets` 保持空数组。
- 不实例化 Arrow，不生成法术、治疗、伤害或远程 Delivery。
- 三个 Visual 根节点必须是无脚本的 `Node3D`，局部原点对应 `WeaponSocket`。
- 项目不是 Git 仓库；以测试和受保护文件哈希检查代替提交。

---

## Resource Map

**Create:**

```text
Item/Weapon/Bow/BowData.tres
Item/Weapon/Bow/BowVisual.tscn
Item/Weapon/Bow/BowAnimationLibrary.res
Item/Weapon/Staff/StaffData.tres
Item/Weapon/Staff/StaffVisual.tscn
Item/Weapon/Staff/StaffAnimationLibrary.res
Item/Weapon/MagicGlobe/MagicGlobeData.tres
Item/Weapon/MagicGlobe/MagicGlobeVisual.tscn
Item/Weapon/MagicGlobe/MagicGlobeAnimationLibrary.res
UnitSystem/Tests/RangedWeaponResourceMigrationTest.gd
```

**Read-only references:**

```text
Scenes/Components/AiAttackModules/CrossbowAttack.tscn
Scenes/ObjectScenes/Healer.tscn
Scenes/ObjectScenes/Mage.tscn
Item/Weapon/WeaponData.gd
UnitSystem/Player/Hero/HeroVisual.tscn
```

---

### Task 1: 建立迁移资源的失败测试

**Files:**
- Create: `UnitSystem/Tests/RangedWeaponResourceMigrationTest.gd`
- Test targets: the nine new weapon resources

**Interfaces:**
- Consumes: `WeaponData.visual_scene`、`WeaponData.animation_library`、`AnimationLibrary` 和 `PackedScene`。
- Produces: 一个验证三套资源完整性、轨道契约和玩家装备入口的 headless test。

- [ ] **Step 1: 记录受保护旧文件哈希**

Run:

```powershell
$protected = @(
  'Scenes\ObjectScenes\Ranger.tscn',
  'Scenes\ObjectScenes\Healer.tscn',
  'Scenes\ObjectScenes\Mage.tscn',
  'Scenes\Components\AiAttackModules\CrossbowAttack.tscn',
  'Scenes\Components\AiAttackModules\StaffAttack.tscn',
  'Scenes\Components\AiAttackModules\MagicballAttack.tscn',
  'Scenes\TestScene.tscn'
)
$protected |
  Where-Object { Test-Path -LiteralPath $_ } |
  Get-FileHash -Algorithm SHA256 |
  Select-Object Path, Hash |
  ConvertTo-Json |
  Set-Content -LiteralPath '.superpowers\weapon-migration-protected-hashes.json' `
    -Encoding utf8
```

Expected: `.superpowers/weapon-migration-protected-hashes.json` contains every protected file that currently exists.

- [ ] **Step 2: 创建结构测试**

`RangedWeaponResourceMigrationTest.gd` 使用以下固定定义：

```gdscript
extends SceneTree

const HERO_PATH: String = "res://UnitSystem/Player/Hero/Hero.tscn"
const DEFINITIONS: Array[Dictionary] = [
	{
		"name": "Bow",
		"data": "res://Item/Weapon/Bow/BowData.tres",
		"visual": "res://Item/Weapon/Bow/BowVisual.tscn",
		"library": (
			"res://Item/Weapon/Bow/BowAnimationLibrary.res"
		),
		"length": 0.38,
	},
	{
		"name": "Staff",
		"data": "res://Item/Weapon/Staff/StaffData.tres",
		"visual": "res://Item/Weapon/Staff/StaffVisual.tscn",
		"library": (
			"res://Item/Weapon/Staff/StaffAnimationLibrary.res"
		),
		"length": 0.55,
	},
	{
		"name": "MagicGlobe",
		"data": "res://Item/Weapon/MagicGlobe/MagicGlobeData.tres",
		"visual": (
			"res://Item/Weapon/MagicGlobe/MagicGlobeVisual.tscn"
		),
		"library": (
			"res://Item/Weapon/MagicGlobe/"
			+ "MagicGlobeAnimationLibrary.res"
		),
		"length": 0.48,
	},
]

const TRACK_PATHS: Array[NodePath] = [
	^"CharacterRoot:position",
	^"CharacterRoot:rotation",
	^"CharacterRoot/WeaponSocket:position",
	^"CharacterRoot/WeaponSocket:rotation",
]

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for definition: Dictionary in DEFINITIONS:
		_validate_definition(definition)
	await process_frame
	await _validate_equipment()
	if failures.is_empty():
		print("RangedWeaponResourceMigrationTest: PASS")
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	print(
		"RangedWeaponResourceMigrationTest: FAIL (%d)"
		% failures.size()
	)
	quit(1)


func _validate_definition(definition: Dictionary) -> void:
	var weapon_name: String = definition["name"]
	var data: WeaponData = load(definition["data"]) as WeaponData
	_expect(data != null, "%s data must load" % weapon_name)
	if data == null:
		return
	_expect(
		data.visual_scene != null,
		"%s visual_scene must be assigned" % weapon_name
	)
	_expect(
		data.animation_library != null,
		"%s animation_library must be assigned" % weapon_name
	)
	_expect(
		data.attack_forward_distances.is_empty(),
		"%s attack motion must remain empty" % weapon_name
	)
	_expect(
		data.hitbox_sizes.is_empty(),
		"%s hitbox sizes must remain empty" % weapon_name
	)
	_expect(
		data.hitbox_center_offsets.is_empty(),
		"%s hitbox offsets must remain empty" % weapon_name
	)

	var visual_scene: PackedScene = load(
		definition["visual"]
	) as PackedScene
	_expect(
		visual_scene != null,
		"%s visual scene must load" % weapon_name
	)
	if visual_scene != null:
		var visual: Node = visual_scene.instantiate()
		_expect(
			visual is Node3D,
			"%s visual root must be Node3D" % weapon_name
		)
		_expect(
			visual.get_script() == null,
			"%s visual must not contain a root script" % weapon_name
		)
		visual.free()

	var library: AnimationLibrary = load(
		definition["library"]
	) as AnimationLibrary
	_expect(
		library != null,
		"%s animation library must load" % weapon_name
	)
	if library == null:
		return
	var animation_names: Array[StringName] = (
		library.get_animation_list()
	)
	_expect(
		animation_names == [&"RESET", &"basic_attack_1"],
		"%s library must contain RESET and basic_attack_1 only"
		% weapon_name
	)
	var reset: Animation = library.get_animation(&"RESET")
	var attack: Animation = library.get_animation(&"basic_attack_1")
	if reset == null or attack == null:
		return
	_expect(
		is_equal_approx(attack.length, float(definition["length"])),
		"%s attack length is incorrect" % weapon_name
	)
	_expect(
		attack.get_track_count() == 4,
		"%s attack must contain four tracks" % weapon_name
	)
	for track_path: NodePath in TRACK_PATHS:
		var attack_track: int = attack.find_track(
			track_path,
			Animation.TYPE_VALUE
		)
		var reset_track: int = reset.find_track(
			track_path,
			Animation.TYPE_VALUE
		)
		_expect(
			attack_track >= 0,
			"%s missing attack track %s" % [
				weapon_name,
				track_path,
			]
		)
		_expect(
			reset_track >= 0,
			"%s missing RESET track %s" % [
				weapon_name,
				track_path,
			]
		)
		if attack_track < 0 or reset_track < 0:
			continue
		var final_value: Vector3 = attack.track_get_key_value(
			attack_track,
			attack.track_get_key_count(attack_track) - 1
		)
		var reset_value: Vector3 = reset.track_get_key_value(
			reset_track,
			0
		)
		_expect(
			final_value.is_equal_approx(reset_value),
			"%s does not return %s to RESET" % [
				weapon_name,
				track_path,
			]
		)
	for track_index: int in range(attack.get_track_count()):
		_expect(
			attack.track_get_type(track_index) != Animation.TYPE_METHOD,
			"%s must not contain method tracks" % weapon_name
		)


func _validate_equipment() -> void:
	var hero_scene: PackedScene = load(HERO_PATH) as PackedScene
	_expect(hero_scene != null, "Hero scene must load")
	if hero_scene == null:
		return
	var hero: Node = hero_scene.instantiate()
	root.add_child(hero)
	await process_frame
	var controller: Node = hero.get_node("AttackController")
	for definition: Dictionary in DEFINITIONS:
		var data: WeaponData = load(definition["data"]) as WeaponData
		_expect(
			controller.call("equip_weapon", data) == true,
			"%s must equip through PlayerAttackController"
			% definition["name"]
		)
	controller.call("unequip_weapon")
	hero.queue_free()
	await process_frame


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
```

- [ ] **Step 3: 运行测试并确认因为资源尚未创建而失败**

Run:

```powershell
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' `
  --headless `
  --path 'G:\Godot\SipSip' `
  --script res://UnitSystem/Tests/RangedWeaponResourceMigrationTest.gd
```

Expected: exit code `1`，错误明确指出 Bow、Staff、MagicGlobe Data 尚未加载。

---

### Task 2: 创建三套 Visual

**Files:**
- Create: all three `*Visual.tscn`

**Interfaces:**
- Consumes: `WeaponData.gd`、旧场景中的 CSG 尺寸和现有 Material。
- Produces: 可实例化的纯视觉 PackedScene。

- [ ] **Step 1: 创建 BowVisual.tscn**

使用无脚本 `Node3D` 根节点 `BowVisual`，迁移：

```text
Stock:      CSGBox3D, position (0, 0, -0.08), size (0.10, 0.10, 0.38)
BowLimbs:   CSGBox3D, position (0, 0, -0.27), size (0.46, 0.06, 0.07)
Grip:       CSGBox3D, position (0, -0.12, -0.02),
            rotation.x 约 0.25rad, size (0.08, 0.18, 0.08)
LoadedBolt: CSGBox3D, position (0, 0.065, -0.16),
            size (0.025, 0.025, 0.48)
```

四个节点统一使用：

```text
res://Materials/MatGridYellow.tres
```

- [ ] **Step 2: 创建 StaffVisual.tscn**

使用无脚本 `Node3D` 根节点 `StaffVisual`：

```text
StaffShaft: CSGCylinder3D, position (0, 0.05, 0),
            radius 0.025, height 0.85, sides 12
FocusOrb:   CSGSphere3D, position (0, 0.52, 0),
            radius 0.09, radial_segments 16, rings 8
FocusBar:   CSGBox3D, position (0, 0.43, 0),
            size (0.24, 0.035, 0.035)
```

三个节点统一使用 `MatGridYellow.tres`。

- [ ] **Step 3: 创建 MagicGlobeVisual.tscn**

使用无脚本 `Node3D` 根节点 `MagicGlobeVisual`，包含：

```text
MagicGlobe: CSGSphere3D, position (0, 0, 0),
            radius 0.10, radial_segments 16, rings 8,
            material res://Materials/MatGridBlue.tres
```

---

### Task 3: 创建外部 AnimationLibrary 与 WeaponData

**Files:**
- Create: `BowAnimationLibrary.res`
- Create: `StaffAnimationLibrary.res`
- Create: `MagicGlobeAnimationLibrary.res`
- Create: all three `*Data.tres`
- Test: `RangedWeaponResourceMigrationTest.gd`

**Interfaces:**
- Consumes: `HeroVisual` 的固定 CharacterRoot 与 WeaponSocket 路径。
- Produces: 每种武器的 `RESET` 和 `basic_attack_1`。

- [ ] **Step 1: 创建统一 RESET 轨道**

每个 RESET 长度为 `0.01s`，在 `0.0s` 写入：

```text
CharacterRoot.position = Vector3.ZERO
CharacterRoot.rotation = Vector3.ZERO
```

各武器 WeaponSocket 基准：

```text
Bow:
  position = Vector3(0.30, 0.34, -0.20)
  rotation = Vector3.ZERO

Staff:
  position = Vector3(0.30, 0.35, -0.10)
  rotation = Vector3(0.15, 0.0, 0.0)

MagicGlobe:
  position = Vector3(0.34, 0.38, -0.12)
  rotation = Vector3.ZERO
```

- [ ] **Step 2: 创建 Bow basic_attack_1**

长度 `0.38s`，Cubic 插值，关键帧：

```text
times: 0.00, 0.10, 0.16, 0.38

CharacterRoot.position:
  (0,0,0), (0,0,0.01), (0,0,-0.01), (0,0,0)

CharacterRoot.rotation:
  (0,0,0), (-3°,3°,0°), (4°,-2°,0°), (0,0,0)

WeaponSocket.position:
  (0.30,0.34,-0.20),
  (0.30,0.37,-0.30),
  (0.30,0.36,-0.17),
  (0.30,0.34,-0.20)

WeaponSocket.rotation:
  (0,0,0), (-0.08,0,0), (0.10,0,0), (0,0,0)
```

- [ ] **Step 3: 创建 Staff basic_attack_1**

长度 `0.55s`，Cubic 插值，关键帧：

```text
times: 0.00, 0.16, 0.30, 0.38, 0.55

CharacterRoot.position:
  (0,0,0), (0,0,0.02), (0,0,-0.03), (0,0,-0.02), (0,0,0)

CharacterRoot.rotation:
  (0,0,0), (-4°,14°,-3°), (6°,-8°,3°),
  (4°,-6°,2°), (0,0,0)

WeaponSocket.position:
  (0.30,0.35,-0.10),
  (0.25,0.42,-0.02),
  (0.33,0.50,-0.38),
  (0.33,0.48,-0.35),
  (0.30,0.35,-0.10)

WeaponSocket.rotation:
  (0.15,0,0), (-0.30,0.30,-0.18), (0.40,-0.10,0.08),
  (0.34,-0.08,0.06), (0.15,0,0)
```

- [ ] **Step 4: 创建 MagicGlobe basic_attack_1**

长度 `0.48s`，Cubic 插值，关键帧：

```text
times: 0.00, 0.14, 0.27, 0.34, 0.48

CharacterRoot.position:
  (0,0,0), (0,0,0.02), (0,0,-0.025), (0,0,-0.02), (0,0,0)

CharacterRoot.rotation:
  (0,0,0), (-5°,12°,-4°), (7°,-7°,3°),
  (5°,-5°,2°), (0,0,0)

WeaponSocket.position:
  (0.34,0.38,-0.12),
  (-0.10,0.52,-0.04),
  (0.18,0.50,-0.48),
  (0.20,0.48,-0.44),
  (0.34,0.38,-0.12)

WeaponSocket.rotation:
  (0,0,0), (-0.20,0.55,-0.12), (0.25,-0.35,0.15),
  (0.18,-0.25,0.10), (0,0,0)
```

- [ ] **Step 5: 使用 ResourceSaver 保存三个外部资源**

Godot Editor API 必须保存到精确路径：

```text
res://Item/Weapon/Bow/BowAnimationLibrary.res
res://Item/Weapon/Staff/StaffAnimationLibrary.res
res://Item/Weapon/MagicGlobe/MagicGlobeAnimationLibrary.res
```

每个 `ResourceSaver.save()` 返回值必须为 `OK`。

- [ ] **Step 6: 在外部动画库存在后创建三份 Data**

在动画库成功保存后创建三份 Data，避免 Data 在中间状态引用尚不存在的资源。

三份 Data 均使用：

```text
script = res://Item/Weapon/WeaponData.gd
attack_forward_distances = []
hitbox_sizes = []
hitbox_center_offsets = []
```

映射：

```text
BowData:
  display_name = "Bow"
  visual_scene = BowVisual.tscn
  animation_library = BowAnimationLibrary.res

StaffData:
  display_name = "Staff"
  visual_scene = StaffVisual.tscn
  animation_library = StaffAnimationLibrary.res

MagicGlobeData:
  display_name = "Magic Globe"
  visual_scene = MagicGlobeVisual.tscn
  animation_library = MagicGlobeAnimationLibrary.res
```

- [ ] **Step 7: 运行结构测试并确认通过**

Run:

```powershell
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' `
  --headless `
  --path 'G:\Godot\SipSip' `
  --script res://UnitSystem/Tests/RangedWeaponResourceMigrationTest.gd
```

Expected:

```text
RangedWeaponResourceMigrationTest: PASS
```

---

### Task 4: 回归与受保护文件验证

**Files:**
- Verify: all nine new resources
- Verify unchanged: protected old scenes

**Interfaces:**
- Consumes: Task 2 and 3 resources。
- Produces: Godot 4.7 load/run evidence and old-system isolation evidence。

- [ ] **Step 1: 比较受保护文件哈希**

Run:

```powershell
$before = Get-Content -Raw `
  -LiteralPath '.superpowers\weapon-migration-protected-hashes.json' |
  ConvertFrom-Json
$changed = @()
foreach ($entry in $before) {
  $relative = Resolve-Path -Relative -LiteralPath $entry.Path
  $current = (Get-FileHash -Algorithm SHA256 -LiteralPath $entry.Path).Hash
  if ($current -ne $entry.Hash) {
    $changed += $relative
  }
}
if ($changed.Count -gt 0) {
  throw "Protected files changed: $($changed -join ', ')"
}
'PROTECTED_FILES_UNCHANGED'
```

Expected: `PROTECTED_FILES_UNCHANGED`。

- [ ] **Step 2: 执行 Godot 编辑器扫描**

Run:

```powershell
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' `
  --headless `
  --editor `
  --path 'G:\Godot\SipSip' `
  --quit
```

Expected: exit code `0`，没有资源加载或脚本编译错误。

- [ ] **Step 3: 执行主场景无窗口启动**

Run:

```powershell
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' `
  --headless `
  --path 'G:\Godot\SipSip' `
  --quit-after 120
```

Expected: exit code `0`，无新增 error 或 warning。

- [ ] **Step 4: MCP 刷新与错误检查**

依次调用：

```text
reload_project
get_editor_errors
```

Expected: `get_editor_errors.count == 0`。

- [ ] **Step 5: 交付人工 Preview 指引**

不保存 Workbench 改动。分别临时把目标 Visual 放入 `WeaponSocket`、加载同目录 AnimationLibrary，然后播放：

```text
BowAnimationLibrary/basic_attack_1
StaffAnimationLibrary/basic_attack_1
MagicGlobeAnimationLibrary/basic_attack_1
```

请用户确认动作幅度；后续远程投射物和技能交付另行设计。
