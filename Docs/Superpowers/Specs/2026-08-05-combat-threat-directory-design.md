<!-- @@ spec @@ -->

# 战斗威胁目录设计

## 目标

建立一个轻量的事件驱动查询目录，让友方 AI（坦克等）可以高效获知"哪些敌人正在攻击队友"，而不需要逐帧轮询全场敌人。

## 动机

当前友方索敌完全依赖 `TargetSelectionPolicy.NEAREST`，坦克无法感知远处正在攻击队友的敌人（如 goblin archer）。敌人在魔兽风格副本玩法中应由坦克优先接手，但这需要坦克知道哪些敌人正在打别人。

轮询方案（每 0.2 秒遍历所有敌机读其当前目标）在 10-15 只怪合波时 O(n) 开销虽不大，但语义上不自然。事件目录方案：敌人在锁定目标变更时主动推送，目录内部维护预计算的哈希表，查表即得结果。

## 数据流

- 敌人锁定目标变更 → `locked_target_changed` 信号 → 目录更新 `enemy_id → target_id` 和 `target_id → [enemy_id_list]`。
- 敌人死亡或离树 → 自身信号 → 目录清理该敌人的所有记录。
- 坦克 AI 查询 → `directory.get_enemies_targeting_others(owner)` → 遍历目标侧哈希表，排除 `owner` 自身，展平结果返回。

## 组件：CombatThreatDirectory

### 位置
`UnitSystem/Components/Threat/CombatThreatDirectory.gd`，`class_name CombatThreatDirectory extends Node`。

### 内部数据
- `_enemy_by_target: Dictionary[int, Array[int]]` — 目标 instance_id → 正在打它的敌人 instance_id 列表。
- `_target_by_enemy: Dictionary[int, int]` — 敌人 instance_id → 当前目标 instance_id。
- `_enemy_node_by_id: Dictionary[int, EnemyBase]` — instance_id → EnemyBase 弱引用。
- `_unit_node_by_id: Dictionary[int, UnitBase]` —instance_id → UnitBase 弱引用。

### 公开接口

```
func register_enemy(enemy: EnemyBase) -> void
```
连接 `locked_target_changed`、`died`、`tree_exiting`，写入初始记录。注销由内部信号自动完成，调用方无需调 `unregister`。

```
func get_enemies_targeting_others(owner: UnitBase) -> Array[EnemyBase]
```
O(k)，k = 目标总数，通常远小于敌人数。返回所有当前目标不是 `owner` 的敌机节点列表。

```
func get_target_of(enemy: EnemyBase) -> UnitBase
```
查表返回敌人当前锁定目标，无记录返回 null。

```
func get_enemy_count() -> int
```
调试用，返回已注册敌人数。

目录在 `_ready` 中 `add_to_group("combat_threat_directory")`。

### 内部信号处理
- `_on_enemy_target_changed(enemy, previous, current)`：更新两张字典。
- `_on_enemy_died(source)`：清理该敌机的所有记录，断开信号。
- `_on_enemy_tree_exiting()`：同死亡处理。

### 注册入口
`EncounterController._register_pack` 中，在遍历敌人的循环里，对每个敌机调用 `directory.register_enemy(enemy)`。目录在首次需要时懒创建为 EncounterController 的子节点。

## 边界与安全
- 目录不写仇恨值、不修改 `locked_target`、不驱动移动和攻击。
- 敌人死亡或离树时目录自动清理，不保留悬挂引用。
- 目录节点独立于具体遭遇，可在任何场景中单独测试。
- 不使用全局单例/autoload；查找通过 group `"combat_threat_directory"`。

## 不在本阶段实现
- Guardian AI 的决策逻辑（查询后如何行动）。
- 任何与战斗数值（伤害、仇恨量）相关的逻辑。
- 新的 `TargetSelectionPolicy` 模式。

## 验收条件
- 注册敌机后，`get_target_of` 返回当前锁定目标。
- 敌机切换目标后，`get_enemies_targeting_others` 返回正确列表。
- 敌机死亡后，目录自动清理，查询不含已死亡敌机。
- 敌机离树后同理。
- 目录自身在 group 中可查询。
- Godot headless 测试及编辑器扫描通过。
