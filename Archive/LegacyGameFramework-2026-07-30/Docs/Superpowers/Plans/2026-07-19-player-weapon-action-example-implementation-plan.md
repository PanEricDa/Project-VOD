# PlayerBase Weapon Action Example Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 创建一把默认装备到 PlayerBase 的 CSG 单手剑，并通过可复用动作资源和独立玩家攻击组件播放一段鼠标左键基础攻击动画。

**Architecture:** 武器视觉、武器定义、动作定义和 AnimationLibrary 分离保存。PlayerBase 持有稳定 `CharacterActionRig`，装备组件实例化武器视觉，动画控制器动态装载动作库，玩家攻击组件只读取 `player_attack` 并请求播放动作。

**Tech Stack:** Godot 4.7、GDScript、Resource、AnimationLibrary、AnimationPlayer、InputMap、SceneTree headless 测试。

## Global Constraints

- 不修改 `Scenes/TestScene.tscn`，不向其中添加任何单位实例。
- 不修改旧 Hero、旧 `MeleeAttackModule`、AI AttackModule 或 SkillSystem。
- 攻击只读取现有 `player_attack` InputMap；项目当前将其绑定为鼠标左键。
- 本阶段只有一个动作，不加入连击、Hitbox、伤害、命中反馈、攻击前移或 GCD。
- 所有字段和方法使用英文标识，新增代码提供详细简体中文注释。
- 删除 `PlayerCombatSystem` 后，PlayerBase 移动、冲刺、锁定和重力必须继续运行。
- 项目不是 Git 仓库，因此使用测试结果代替提交步骤。

---

### Task 1: 武器与动作资源契约

**Files:**
- Create: `WeaponCombatSystem/02-Core/AttackActionDefinition.gd`
- Create: `WeaponCombatSystem/02-Core/WeaponActionSet.gd`
- Create: `WeaponCombatSystem/02-Core/WeaponDefinition.gd`
- Create: `WeaponCombatSystem/04-Tests/WeaponResourceContractsTest.gd`

**Interfaces:**
- Produces:
  - `AttackActionDefinition`
  - `WeaponActionSet.get_action(action_id: StringName) -> AttackActionDefinition`
  - `WeaponActionSet.is_compatible_with(rig_profile: StringName) -> bool`
  - `WeaponDefinition` 的视觉、动作集和插槽偏移字段。

- [ ] **Step 1: 编写失败测试**

测试加载三个脚本，实例化资源并断言默认值和查询行为：

```gdscript
var attack := AttackActionDefinition.new()
attack.action_id = &"basic_attack"
attack.animation_name = &"basic_attack"
var action_set := WeaponActionSet.new()
action_set.rig_profile = &"csg_box"
action_set.attack_actions = [attack]
_assert_equal(action_set.get_action(&"basic_attack"), attack, "action lookup")
_assert_true(action_set.is_compatible_with(&"csg_box"), "rig compatibility")
_assert_equal(WeaponDefinition.new().visual_scene, null, "visual defaults empty")
```

- [ ] **Step 2: 运行并确认 RED**

```powershell
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' --headless --path 'G:\Godot\SipSip' --script res://WeaponCombatSystem/04-Tests/WeaponResourceContractsTest.gd
```

Expected: FAIL，因为资源脚本尚不存在。

- [ ] **Step 3: 实现最小资源类型**

按设计文档实现强类型导出。`get_action()` 忽略 null 和空 ID，找不到时返回 null；兼容性只比较非空 `rig_profile`。

- [ ] **Step 4: 运行并确认 GREEN**

运行 Step 2 命令。

Expected: `WeaponResourceContractsTest: PASS`，退出码 0。

---

### Task 2: 动画、装备与玩家输入组件

**Files:**
- Create: `WeaponCombatSystem/03-Components/CharacterAnimationController.gd`
- Create: `WeaponCombatSystem/03-Components/WeaponEquipmentComponent.gd`
- Create: `WeaponCombatSystem/03-Components/PlayerAttackController.gd`
- Create: `WeaponCombatSystem/04-Tests/WeaponCombatComponentsTest.gd`

**Interfaces:**
- Consumes: Task 1 的三个 Resource。
- Produces:
  - 动画库装卸与动作播放接口。
  - 武器视觉装备/卸下接口。
  - `request_basic_attack()` 与攻击状态信号。

- [ ] **Step 1: 编写组件失败测试**

构造真实 `Node3D + AnimationPlayer` 测试树，创建内存 AnimationLibrary 和武器视觉 PackedScene，验证：

```gdscript
_assert_true(animator.configure(animation_player), "animator configures")
_assert_true(animator.load_action_set(action_set), "library loads")
_assert_true(equipment.equip_weapon(weapon), "weapon equips")
_assert_equal(weapon_socket.get_child_count(), 1, "one visual instance")
_assert_true(attacker.request_basic_attack(), "attack starts")
_assert_false(attacker.request_basic_attack(), "repeated active request rejected")
```

等待动画结束后断言攻击状态恢复，卸下武器后视觉和动画库均被清理。

- [ ] **Step 2: 运行并确认 RED**

```powershell
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' --headless --path 'G:\Godot\SipSip' --script res://WeaponCombatSystem/04-Tests/WeaponCombatComponentsTest.gd
```

Expected: FAIL，因为三个组件尚不存在。

- [ ] **Step 3: 实现 CharacterAnimationController**

固定动作库名称为 `weapon_actions`。装载前停止动作并移除旧库；验证动作集骨架、AnimationLibrary 和动画名称。通过 `animation_finished` 转发稳定动作完成信号。

- [ ] **Step 4: 实现 WeaponEquipmentComponent**

组件保存 `starting_weapon`，在配置后才装备。视觉始终实例化为 `WeaponSocket` 的唯一受管子节点，并应用定义中的位置和角度偏移。装备失败不残留半配置视觉或动作库。

- [ ] **Step 5: 实现 PlayerAttackController**

只响应导出的 `attack_action=&"player_attack"`。输入与公开请求共用 `request_basic_attack()`；动作未结束前拒绝第二次请求，没有武器或动作时安全返回 false。

- [ ] **Step 6: 运行并确认 GREEN**

运行 Step 2 命令。

Expected: `WeaponCombatComponentsTest: PASS`，无 warning/error。

---

### Task 3: 单手剑示例资产

**Files:**
- Create: `WeaponCombatSystem/00-Weapons/IronSword/IronSwordVisual.tscn`
- Create: `WeaponCombatSystem/00-Weapons/IronSword/IronSwordDefinition.tres`
- Create: `WeaponCombatSystem/01-ActionSets/Sword/CSGBox/SwordAnimations.tres`
- Create: `WeaponCombatSystem/01-ActionSets/Sword/CSGBox/SwordActionSet.tres`
- Create: `WeaponCombatSystem/04-Tests/IronSwordExampleTest.gd`

**Interfaces:**
- Consumes: Task 1 的资源类型。
- Produces: 可由玩家或未来 AI 共用的单手剑定义与 CSGBox 动作集。

- [ ] **Step 1: 编写资产失败测试**

断言四个资源存在并可加载；剑场景不包含 AnimationPlayer 或攻击脚本；动作库包含 `basic_attack` 且轨道只指向 `BodyRoot` 和 `WeaponSocket`；动画长度约 `0.45s`。

- [ ] **Step 2: 运行并确认 RED**

```powershell
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' --headless --path 'G:\Godot\SipSip' --script res://WeaponCombatSystem/04-Tests/IronSwordExampleTest.gd
```

Expected: FAIL，因为示例资产尚不存在。

- [ ] **Step 3: 创建 CSG 单手剑视觉**

场景根节点为 Node3D；子节点仅包含剑刃、护手和剑柄 CSG。使用现有项目材质资源，不附加攻击脚本或 AnimationPlayer。

- [ ] **Step 4: 创建动作库和定义**

`basic_attack` 长度 `0.45s`，为 BodyRoot 和 WeaponSocket 的 position/rotation 建立蓄力、挥砍和复位关键帧。资源定义引用该库和剑视觉。

- [ ] **Step 5: 运行并确认 GREEN**

运行 Step 2 命令。

Expected: `IronSwordExampleTest: PASS`。

---

### Task 4: PlayerBase 装配

**Files:**
- Modify: `UnitSystem/PlayerBase.tscn`
- Modify: `UnitSystem/Tests/PlayerBaseMovementTest.gd`
- Create: `WeaponCombatSystem/04-Tests/PlayerWeaponExampleAssemblyTest.gd`

**Interfaces:**
- Consumes: 前三项组件和示例资源。
- Produces: 默认装备单手剑并可通过左键动作播放的 PlayerBase。

- [ ] **Step 1: 编写 PlayerBase 装配失败测试**

验证稳定节点路径、默认装备、动作库、公开请求与可拆装行为：

```gdscript
_assert_true(player.has_node(^"Visual/CharacterActionRig/BodyRoot/BodyMesh"), "stable body path")
_assert_true(player.has_node(^"Visual/CharacterActionRig/WeaponSocket"), "weapon socket")
_assert_true(player.has_node(^"PlayerCombatSystem/PlayerAttackController"), "attack controller")
_assert_true(attacker.call("request_basic_attack"), "default sword attack starts")
```

移除 `PlayerCombatSystem` 后重新运行移动、冲刺和锁定测试。

- [ ] **Step 2: 运行并确认 RED**

```powershell
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' --headless --path 'G:\Godot\SipSip' --script res://WeaponCombatSystem/04-Tests/PlayerWeaponExampleAssemblyTest.gd
```

Expected: FAIL，因为 PlayerBase 尚未装配动作层级与组件。

- [ ] **Step 3: 重组 PlayerBase 视觉层级**

只移动源场景中的 BodyMesh 到 `CharacterActionRig/BodyRoot`，保持原材质、尺寸和离地高度。新增 WeaponSocket、角色动画播放器和 PlayerCombatSystem。

- [ ] **Step 4: 配置组件路径和默认单手剑**

在 Inspector 数据中设置组件 NodePath、`rig_profile=&"csg_box"` 和 `starting_weapon=IronSwordDefinition.tres`。不向 PlayerBase.gd 添加攻击代码。

- [ ] **Step 5: 运行新旧 PlayerBase 测试**

运行装配测试与 `res://UnitSystem/Tests/PlayerBaseMovementTest.gd`。

Expected: 两者 PASS；PlayerBase 原有移动、冲刺、锁定测试不回退。

---

### Task 5: 完整验证

**Files:**
- Verify only.

- [ ] **Step 1: 运行 WeaponCombatSystem 全部测试**

遍历 `WeaponCombatSystem/04-Tests/*.gd`，要求全部退出码 0。

- [ ] **Step 2: 运行 UnitSystem 全部测试**

遍历 `UnitSystem/Tests/*.gd`，要求全部退出码 0。

- [ ] **Step 3: 运行项目既有 Tests 与 SkillSystem 测试**

记录所有通过数和任何既有失败；不得为了本功能修改无关 Mage、AI 或 SkillSystem 配置。

- [ ] **Step 4: Godot 4.7 编辑器扫描和无窗口启动**

```powershell
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' --headless --editor --path 'G:\Godot\SipSip' --quit
& 'G:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe' --headless --path 'G:\Godot\SipSip' --quit-after 10
```

- [ ] **Step 5: MCP 刷新与错误检查**

刷新项目文件系统，加载新脚本、资源和 PlayerBase，清空 Output 后确认编辑器错误数为零。确认 `Scenes/TestScene.tscn` 未修改。

