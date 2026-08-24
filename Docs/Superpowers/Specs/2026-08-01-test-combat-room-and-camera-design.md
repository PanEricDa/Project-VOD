# 最小测试战斗房间与自动摄像机设计

## 目标

将 `TestCombatRoom` 作为独立的战斗空间测试场，并让 `CameraFollowController` 自动寻找唯一的玩家阵营单位，不再依赖场景内手写 NodePath。

## 自动摄像机绑定

`CameraFollowController` 继续只承担镜头位置、预留与平滑跟随，不承担玩家控制或场景加载。

### 目标识别规则

- 在当前场景树递归查找 `UnitBase`。
- 只接受 `faction_id == "Player"` 的单位。
- 找到唯一候选时，缓存为运行时跟随目标，记录锁定高度并立即调用 `snap_to_target()`。
- 未找到时保持运行并以内部固定间隔重试；这是房间先加载、玩家后加入时的正常状态，不输出错误。
- 已绑定目标离开场景树或失效时，清空缓存并恢复搜索。
- 找到多个玩家候选时不任意选择，输出一次明确警告并等待恢复唯一候选。

### Inspector 与接口

- 删除 `target_path` 及所有场景中的手写路径配置。
- 保留既有相机偏移、平滑、预留和垂直锁定参数。
- 添加只读 `debug_resolved_target`，仅显示当前自动识别到的目标，不保存到场景文件。
- 不添加新 Resource、组或第二份阵营配置；复用 `UnitBase.faction_id` 的 Player 枚举值。

## TestCombatRoom

在已有地面、环境、光照、CameraRig 和导航区域基础上，补齐无逻辑的组织节点：

```text
TestCombatRoom
├─ Ground
├─ WorldEnvironment
├─ DirectionalLight3D
├─ NavigationRegion3D
├─ CameraRig
│  └─ Camera3D
├─ PlayerSpawn
├─ PartySpawn
└─ EnemyContainer
   ├─ Pack_A
   ├─ Pack_B
   └─ Pack_C
```

- `PlayerSpawn`、`PartySpawn` 使用 `Marker3D`，只表示未来场景入口位置。
- `EnemyContainer` 与 `Pack_*` 使用 `Node3D`，仅为场景树整理，不附脚本、不表示波次。
- 不加入 `EncounterController`、敌人生成器、奖励、门或完成判定。
- 不自动向房间添加 Hero、伙伴或敌人实例；用户在编辑器中手动放入并设置初始位置。

## 导航验证

- `NavigationRegion3D` 必须包含覆盖平坦地面的有效导航网格。
- 测试场景中的 AI 可在导航区内追击与脱战归位，不产生导航相关错误。
- 如当前导航网格未烘焙，实施时只烘焙该房间已存在的地面；不改动单位实例。

## 验收条件

- Hero 改名、改变层级或在 CameraRig 后加入场景时，CameraRig 都能自动绑定唯一 Player 阵营单位。
- 没有玩家、多个玩家、玩家被删除时，CameraRig 不抛出持续错误，不保留失效引用。
- `TestCombatRoom` 具备出生点和三组敌人容器，且不含由 Codex 自动添加的单位。
- 房间在编辑器和 headless 扫描中加载成功；相关摄像机与 AI 回归测试通过。

## 实施验证记录（2026-08-01）

- `CameraFollowController` 已移除手写 `target_path`，改为递归识别唯一的 `faction_id == "Player"` 的 `UnitBase`；重命名、改变层级、后加入和失效后重新加入都由 `CameraFollowControllerTest` 覆盖。
- 多个 Player 候选时控制器保持未绑定，并只输出一次明确警告；无 Player 时保持可恢复等待，不再关闭处理循环或报告路径错误。
- `TestCombatRoom` 已加入 `PlayerSpawn`、`PartySpawn`、`EnemyContainer/Pack_A`、`Pack_B`、`Pack_C`，全部为空组织节点；未添加任何单位、波次、生成或结算逻辑。
- 原 CSGBox3D 不是导航烘焙器可直接采集的几何来源；MCP 烘焙调用虽成功但未生成多边形。因此改为在现有 `NavigationRegion3D` 中保存覆盖 Ground 的显式四角导航面，且将 cell size/height 对齐项目默认 0.25，避免导航网格失配警告。
- 验证通过：`CameraFollowControllerTest.gd`、`EnemyBehaviorStateMachineTest.gd`、Godot headless 编辑器扫描；MCP 刷新后的编辑器错误数为 0。
