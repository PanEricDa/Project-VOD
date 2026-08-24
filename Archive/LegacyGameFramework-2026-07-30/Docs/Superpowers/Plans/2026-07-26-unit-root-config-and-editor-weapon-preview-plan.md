# Unit Root Configuration and Editor Weapon Preview Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 将武器和阵型配置提升到单位根节点，并提供不保存的编辑器武器视觉预览。

**Architecture:** 根节点保存设计师配置，启动时通过明确的 setter 转交给内部 CombatSystem/BehaviorStateMachine。编辑器预览是独立的 `@tool` 逻辑，只在编辑器树中维护临时 Visual 实例，不参与运行时装配。

**Tech Stack:** Godot 4.7、GDScript、PackedScene、WeaponData、FormationPositionData。

## Global Constraints

- 不自动添加或修改 `Scenes/TestScene.tscn` 中的单位实例。
- 正式外部 `.tres/.res` 必须由 Godot 正式保存并验证 UID；本任务不新增外部资源。
- 不改变现有攻击、动画、Hitbox、AI 状态机的运行时行为。

---

### Task 1: 根节点配置接口

**Files:**
- Modify: `UnitSystem/Base/AIUnitBase.gd`
- Modify: `UnitSystem/Base/PlayerBase.gd`
- Modify: `UnitSystem/AI/Ally/AllyBase2.gd`
- Modify: `UnitSystem/Components/Combat/AI/AICombatSystem.gd`
- Modify: `UnitSystem/Components/Behavior/AllyBehaviorStateMachine.gd`

**Interfaces:**
- `AIUnitBase.starting_weapon: WeaponData`
- `AIUnitBase.set_starting_weapon(weapon_data: WeaponData) -> void`
- `PlayerBase.starting_weapon: WeaponData`
- `PlayerBase.set_starting_weapon(weapon_data: WeaponData) -> void`
- `AllyBase2.formation_position: FormationPositionData`
- `AllyBase2.set_formation_position(data: FormationPositionData) -> void`

- [ ] **Step 1: Add failing contract assertions**

在 `UnitSystem/Tests/AIUnitBaseLocomotionMigrationTest.gd` 或新增 `UnitSystem/Tests/UnitRootConfigurationTest.gd` 中实例化 AI、Ally 和 Player，断言根节点存在上述属性，并断言 Ally 的根节点配置最终进入状态机。

- [ ] **Step 2: Run the contract test and verify it fails**

Run: `Godot_v4.7-stable_win64_console.exe --headless --path G:\Godot\SipSip --script res://UnitSystem/Tests/UnitRootConfigurationTest.gd`

Expected: FAIL because root-level properties and forwarding setters do not exist.

- [ ] **Step 3: Implement root-level forwarding**

根节点字段只在 `AIUnitBase`、`PlayerBase`、`AllyBase2` 暴露；`_ready()` 中把已经配置的资源转交给内部节点。转交方法必须安全处理缺失节点和空资源，不修改子节点 Inspector 配置定义。

- [ ] **Step 4: Remove duplicate child Inspector exports**

将 `AICombatSystem.starting_weapon` 和 `AllyBehaviorStateMachine.formation_position` 改为内部运行字段，保留 getter/setter 或内部赋值接口，但不再使用 `@export`。

- [ ] **Step 5: Run the contract test and related tests**

Run: `... --script res://UnitSystem/Tests/UnitRootConfigurationTest.gd` and `... --script res://UnitSystem/Tests/AllyBehaviorStateMachineTest.gd`.

Expected: PASS; existing behavior tests remain unchanged.

### Task 2: 编辑器专用武器预览

**Files:**
- Create: `UnitSystem/Components/Combat/EditorWeaponPreview.gd`
- Modify: `UnitSystem/Base/AIUnitBase.tscn`
- Modify: `UnitSystem/Base/PlayerBase.tscn`
- Modify: `UnitSystem/Base/AIUnitBase.gd`
- Modify: `UnitSystem/Base/PlayerBase.gd`

**Interfaces:**
- `EditorWeaponPreview.set_weapon(weapon_data: WeaponData) -> void`
- `EditorWeaponPreview.clear_preview() -> void`

- [ ] **Step 1: Add failing preview assertions**

在 `UnitRootConfigurationTest.gd` 中以编辑器工具场景方式检查预览组件可加载、能够读取 `WeaponData.visual_scene`，并且运行时不留下预览节点。

- [ ] **Step 2: Run the test and verify the preview contract fails**

Expected: FAIL because the editor preview component does not exist.

- [ ] **Step 3: Implement editor-only preview**

使用 `@tool` 脚本监听 `starting_weapon` 的变化，在具体 Visual 的 `CharacterRoot/WeaponSocket` 创建临时视觉实例。预览节点设置 `owner = null` 或等效“不保存”状态，不添加动画库、不连接控制器；清空或替换武器时释放旧预览。

- [ ] **Step 4: Guard runtime behavior**

运行时不执行编辑器预览分支；正式运行仍由 `CombatSystem`/`AttackController` 装配武器，避免重复模型。

- [ ] **Step 5: Run visual and scene-load tests**

Run the preview contract, `AIAttackControllerTest.gd`, `AICombatSystemTest.gd`, and a headless editor scan.

Expected: preview contract and existing scene-load tests pass; no TestScene unit instance changes.

### Task 3: Documentation and verification

**Files:**
- Modify: `Docs/CurrentImplementationSummary.md`
- Modify: `UnitSystem/Tests/UnitDirectoryLayoutTest.gd`

- [ ] **Step 1: Add the new test and canonical paths to the directory contract**
- [ ] **Step 2: Document root configuration and editor-only preview workflow**
- [ ] **Step 3: Run the full relevant headless test set and editor scan**

Run: all `UnitSystem/Tests/*.gd` scripts that load AI/Player combat, plus `--headless --editor --quit`.

- [ ] **Step 4: Verify no TestScene instance was modified**

Check that no unit instance was added or changed in `Scenes/TestScene.tscn`.
