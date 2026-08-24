# Pack 遭遇控制器设计

## 目标

为 `TestCombatRoom` 中已手动摆放的敌群提供轻量的遭遇生命周期汇总：自动识别每个 Pack 的开战、脱战重置、清除与整房间清除。控制器不承担索敌、移动、攻击、单位生成、奖励、门、玩家失败或血量恢复。

## 现有前置与修正

`UnitBase` 已提供 `combat_state_changed`、`died` 与 `is_in_combat()`，但 Enemy 行为状态机尚未把 `CHASE / ATTACK / RETURN_HOME / IDLE` 同步到该公共状态。

先在 `EnemyBehaviorStateMachine` 的状态转换中建立唯一映射：

```text
CHASE / ATTACK       -> owner.enter_combat()
RETURN_HOME / IDLE   -> owner.exit_combat()
死亡                 -> UnitBase.apply_damage() 已先执行 exit_combat()，随后发出 died
```

`EncounterController` 只订阅 `UnitBase.combat_state_changed` 与 `UnitBase.died`，不读取敌人状态机枚举；因此它不与敌人具体 AI、武器或攻击方式耦合。

## 场景约定与自动登记

控制器作为 `TestCombatRoom` 的根节点直接子节点。它使用同级固定节点 `EnemyContainer`，并将其每一个直接 `Node3D` 子节点视为一个 Pack；每个 Pack 内递归查找 `EnemyBase`。

```text
TestCombatRoom
├── EncounterController
└── EnemyContainer
    ├── Pack_A
    │   └── EnemyBase …
    ├── Pack_B
    └── Pack_C
```

- 不使用 Inspector NodePath，不需要逐只敌人登记。
- 控制器在场景树稳定后延迟一次完成初始扫描，确保所有敌人均已 `_ready()`。
- 运行中新增、移动到其他 Pack 或移除敌人不自动重算；未来生成系统通过明确的 `register_enemy()` / `refresh_packs()` 扩展，避免本版出现隐式统计变化。
- 空 Pack 不参与 `room_cleared` 判定，并输出一次配置警告。

## Pack 状态模型

```text
DORMANT --(任一存活敌人进入战斗)--> ENGAGED
ENGAGED --(所有存活敌人脱战)-------> RESETTING
RESETTING --(任一存活敌人再进战斗)--> ENGAGED
RESETTING --(缓冲结束)--------------> DORMANT
DORMANT / ENGAGED / RESETTING --(全部敌人死亡)--> CLEARED
```

`CLEARED` 是本轮终态。全体非空 Pack 都达到 `CLEARED` 时，房间发出一次 `room_cleared`。

## 脱战与死亡结算

- 每名敌人依旧由其自身 AI leash 规则决定何时归位。控制器不移动、取消攻击或强制脱战。
- Pack 内所有**存活**敌人都变为 `OUT_OF_COMBAT` 后，进入 `RESETTING`，并使用默认 `1.0s` 的脱战重置缓冲。
- 缓冲期间任何存活敌人再次进入战斗，立即取消重置、回到 `ENGAGED`；不会重复发出 `pack_started`。
- 缓冲结束，发送 `pack_reset` 并回到 `DORMANT`。本版不回血、不复活，未来可由独立监听者处理该信号。
- `UnitBase.apply_damage()` 在致死时先发 `exit_combat` 再发 `died`。控制器将事件结算延迟到当前帧末，确保同帧死亡优先于脱战重置：所有敌人死亡必定进入 `CLEARED`，不会错误进入 `RESETTING`。
- 注册敌人未经过 `died` 即离开场景树时，Pack 进入 `TRACKING_INVALID` 调试状态并发送一次警告；它不会自动算作死亡、更不会触发 `pack_cleared` 或 `room_cleared`。

## 对外接口

公共信号（都带 Pack 节点与本包已登记敌人数量，便于 UI/门/奖励系统后续消费）：

```gdscript
signal pack_started(pack: Node3D, registered_enemy_count: int)
signal pack_reset(pack: Node3D, registered_enemy_count: int)
signal pack_cleared(pack: Node3D, registered_enemy_count: int)
signal room_cleared()
signal pack_tracking_invalid(pack: Node3D, removed_enemy: EnemyBase)
```

只提供调试查询：

```gdscript
func get_pack_state(pack: Node3D) -> PackState
func get_registered_enemy_count(pack: Node3D) -> int
func get_alive_enemy_count(pack: Node3D) -> int
```

默认 `reset_delay = 1.0` 作为唯一可配置参数，并在 Inspector 写明其单位、范围、默认行为和影响范围。

`debug_log_enabled` 是默认关闭的房间调试开关；`TestCombatRoom` 的控制器实例显式开启它，以便在 Output 观察 `started`、`reset`、`cleared`、`room cleared` 与异常追踪事件。该开关不改变任何信号、AI 或结算逻辑。

## 验收

- 三个现有 Pack 自动被登记，不需要路径或逐敌配置。
- 任一敌人进战斗时只发一次 `pack_started`。
- 所有存活敌人脱战后，缓冲完成才发一次 `pack_reset`；缓冲内重拉会取消重置。
- 最后一个敌人死亡时只发一次 `pack_cleared`，且死亡不会被同帧脱战误判为 reset。
- 全部非空 Pack 清除时只发一次 `room_cleared`。
- 空 Pack 与异常移除的敌人绝不触发错误的完成事件。
- Godot 4.7 headless 测试、既有敌人行为测试、编辑器扫描与 MCP 错误面板均无新增错误。

## 实施记录（2026-08-01）

- `EnemyBehaviorStateMachine` 已在唯一状态转换入口同步 `UnitBase` 公共战斗状态：CHASE/ATTACK 进入战斗，RETURN_HOME/IDLE 离开战斗。
- `UnitSystem/Encounter/EncounterController.tscn` 已作为独立通用组件实例化到 `TestCombatRoom` 根节点；仅扫描既有 `EnemyContainer/Pack_A~C`，未移动、删除或新增任何用户摆放的单位实例。
- 运行中完整房间卸载不再被误判为敌人异常离树；只有房间正常运行期间未发出 `died` 的独立敌人离树才会标记追踪失效。
- `TestCombatRoom` 已启用 Encounter 调试日志，且导航网格的四角数据直接保存在场景中，避免编辑器缓存的临时导航编辑无法持久化。
- 敌人登记时会同时保存稳定的实例 ID 快照。死亡特效结束并释放节点后，后续 Pack 轮询只读取该快照再检查节点有效性，因此不会对已释放实例调用方法；该情形已加入 `EncounterControllerTest` 回归覆盖。
