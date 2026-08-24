# PlayerBase 与 Hero 独立视觉插槽实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** 将 PlayerBase 的具体方盒视觉拆成独立 HeroVisual PackedScene，并通过新的 Hero 继承场景手动装配，同时保持 PlayerBase 所有控制行为不变。

**Architecture:** UnitBase 现有 `Visual` 节点保持原名并作为空视觉插槽。PlayerBase 只保留玩家控制、基础物理结构和 TargetingSystem；Hero 继承 PlayerBase，在 Visual 下实例化一个无玩法脚本的 HeroVisual，并覆盖 Hero 专用方盒碰撞体。

**Tech Stack:** Godot 4.7、GDScript、PackedScene、Godot 场景继承、SceneTree headless tests。

## Global Constraints

- 不修改 `UnitSystem/PlayerBase.gd` 和 `UnitSystem/00_UnitBase.gd` 的现有行为。
- 不修改旧 `Scenes/ObjectScenes/Hero.tscn` 或其战斗系统。
- 不修改 `Scenes/TestScene.tscn` 中任何单位实例。
- 不加入 Profile、Definition、Visual 自动加载脚本或嵌套 Resource。
- 不在本次加入 WeaponSocket、EffectSocket、AnimationPlayer、CameraAnchor 或战斗节点。
- 新增 GDScript 使用英文标识和简体中文注释。
- 项目不是 Git 仓库，不创建 worktree、分支或提交。

---

### Task 1: 用测试定义空 PlayerBase 视觉插槽

**Files:**
- Modify: `UnitSystem/Tests/PlayerBaseMovementTest.gd`
- Modify: `UnitSystem/PlayerBase.tscn`

**Interfaces:**
- Consumes: UnitBase 的 `Visual` 与 `CollisionShape3D`。
- Produces: 不包含任何具体角色视觉的 PlayerBase 场景。

- [x] **Step 1: 修改 PlayerBase 测试并验证 RED**

将原来要求 `Visual/CharacterActionRig/BodyRoot/BodyMesh` 存在的断言替换为：

```gdscript
var visual := player.get_node_or_null(^"Visual") as Node3D
_assert_true(visual != null, "PlayerBase keeps the stable Visual slot")
_assert_equal(visual.get_child_count(), 0, "PlayerBase Visual slot is empty")
var scene_text := FileAccess.get_file_as_string(PLAYER_SCENE_PATH)
for forbidden_text: String in [
    "CharacterActionRig",
    "BodyRoot",
    "BodyMesh",
    "WeaponSocket",
    "MatGridTiffanyBlue",
]:
    _assert_true(
        not scene_text.contains(forbidden_text),
        "PlayerBase excludes concrete visual: " + forbidden_text
    )
```

Run:

```powershell
Godot_v4.7-stable_win64_console.exe --headless --path . --script res://UnitSystem/Tests/PlayerBaseMovementTest.gd
```

Expected: FAIL because the current PlayerBase still contains the concrete visual hierarchy.

- [x] **Step 2: 最小化 PlayerBase 场景**

从 `PlayerBase.tscn` 删除：

- Tiffany Blue 材质 ext_resource。
- PlayerBase 专用 BoxShape3D sub_resource。
- CharacterActionRig、BodyRoot、BodyMesh 和 WeaponSocket。
- 对继承 CollisionShape3D 的 Hero 专用形状与位置覆盖。

保留：

```text
PlayerBase extends UnitBase
├── Visual
├── CollisionShape3D
└── TargetingSystem
```

PlayerBase 根节点继续设置原有 movement、dash、gravity、collision layer、faction 和 team 参数。

- [x] **Step 3: 验证 PlayerBase 测试 GREEN**

Run the same test command.

Expected: `PlayerBaseMovementTest: PASS`。

### Task 2: 创建 HeroVisual 与 Hero 继承场景

**Files:**
- Create: `UnitSystem/Tests/HeroVisualAssemblyTest.gd`
- Create: `UnitSystem/Players/Hero/HeroVisual.tscn`
- Create: `UnitSystem/Players/Hero/Hero.tscn`

**Interfaces:**
- Consumes: PlayerBase 的空 `Visual` 插槽和继承 CollisionShape3D。
- Produces: 可独立预览的 HeroVisual，以及完整可操控的 Hero 继承场景。

- [x] **Step 1: 编写 Hero 装配失败测试**

测试必须验证：

```gdscript
const HERO_PATH := "res://UnitSystem/Players/Hero/Hero.tscn"
const VISUAL_PATH := "res://UnitSystem/Players/Hero/HeroVisual.tscn"

_assert_true(ResourceLoader.exists(HERO_PATH), "Hero scene exists")
_assert_true(ResourceLoader.exists(VISUAL_PATH), "HeroVisual scene exists")

var visual := (load(VISUAL_PATH) as PackedScene).instantiate() as Node3D
_assert_true(visual != null, "HeroVisual root is Node3D")
_assert_true(visual.get_script() == null, "HeroVisual has no gameplay script")
var mesh := visual.get_node_or_null(^"BodyMesh") as CSGBox3D
_assert_equal(mesh.size, Vector3(0.5, 0.5, 0.5), "Hero mesh size")
_assert_near(mesh.position.y, 0.25, 0.001, "Hero origin is at foot center")

var hero := (load(HERO_PATH) as PackedScene).instantiate() as PlayerBase
_assert_true(hero != null, "Hero inherits PlayerBase")
_assert_equal(hero.get_node(^"Visual").get_child_count(), 1, "one visual instance")
_assert_true(hero.get_node_or_null(^"Visual/HeroVisual") != null, "HeroVisual mounted")
var collision := hero.get_node(^"CollisionShape3D") as CollisionShape3D
var box := collision.shape as BoxShape3D
_assert_equal(box.size, Vector3(0.6, 0.5, 0.6), "Hero collision size")
```

Run:

```powershell
Godot_v4.7-stable_win64_console.exe --headless --path . --script res://UnitSystem/Tests/HeroVisualAssemblyTest.gd
```

Expected: FAIL because both scenes are missing.

- [x] **Step 2: 创建 HeroVisual.tscn**

场景内容：

```text
HeroVisual (Node3D, no script)
└── BodyMesh (CSGBox3D)
    size = Vector3(0.5, 0.5, 0.5)
    position = Vector3(0, 0.25, 0)
    material = MatGridTiffanyBlue.tres
```

- [x] **Step 3: 创建 Hero.tscn**

Hero 继承 `UnitSystem/PlayerBase.tscn`，并完成：

```text
Visual/HeroVisual = instance of HeroVisual.tscn
CollisionShape3D.shape = BoxShape3D(0.6, 0.5, 0.6)
CollisionShape3D.position = Vector3(0, 0.25, 0)
```

不附加 Hero 专用脚本，不重复创建 TargetingSystem。

- [x] **Step 4: 验证 Hero 装配测试 GREEN**

Run the same Hero test command.

Expected: `HeroVisualAssemblyTest: PASS`。

### Task 3: 回归验证与冻结边界

**Files:**
- Update: `Docs/Superpowers/Plans/2026-07-21-playerbase-hero-visual-slot-implementation-plan.md`

**Interfaces:**
- Consumes: Tasks 1-2 的最终场景。
- Produces: Godot 4.7 可加载且不影响旧系统的视觉拆分结果。

- [x] **Step 1: 运行全部 UnitSystem 测试**

逐个运行 `UnitSystem/Tests/*.gd`。

Expected: 所有测试输出 `PASS`，退出码为 0。

- [x] **Step 2: 运行 Godot 4.7 完整导入**

```powershell
Godot_v4.7-stable_win64_console.exe --headless --path . --import
```

Expected: exit code 0，且无 `ERROR`、`SCRIPT ERROR` 或 `WARNING`。

- [x] **Step 3: 复核冻结文件哈希**

Expected SHA-256：

```text
Scenes/ObjectScenes/Hero.tscn
A00DE9820394CA6702615C5905CE5E637D42727273910E6ECDF823D0832E9F38

Scenes/TestScene.tscn
ED61E6208F63EAB5FF28EEA2D6142BD321A13B5A077D87E28DBC4DBFA0C723A1

UnitSystem/PlayerBase.gd
B004A09757A21B281ACBB6B6B64E370E464B7E2ADB9F4CF9C1F54547F2966F24

UnitSystem/00_UnitBase.gd
8C2E80A12A5621F5CE599CA068D7B026FF46808F827522C6AA47AEB6D6DCA16D
```

- [x] **Step 4: 路径与职责扫描**

验证 PlayerBase 不再包含 `CharacterActionRig`、`BodyRoot`、`BodyMesh`、`WeaponSocket`
或 Tiffany Blue 材质引用；HeroVisual 不包含脚本、碰撞或玩法节点。

- [x] **Step 5: 标记计划完成并交付**

将本计划所有 checkbox 更新为 `[x]`，报告测试数量、导入结果和冻结哈希结果。
