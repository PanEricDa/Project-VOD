# 敌人 AI 基础框架设计

## 目标

在不复制 Ally 的移动、索敌、武器或攻击实现的前提下，为 `EnemyBase` 建立可扩展的自主索敌、追击、攻击和归位行为。

## 继承结构

```text
UnitBase
└── AIUnitBase
    ├── AllyBase
    │   └── AllyBehaviorStateMachine
    └── EnemyBase
        └── EnemyBehaviorStateMachine
```

- `UnitBase` 继续提供阵营、队伍、生命、可选中性和死亡事件。
- `AIUnitBase` 是所有自动单位唯一的物理与移动执行者；它继续负责导航、重力、朝向、冲刺、攻击位移和 `CombatSystem` 装配。
- `AllyBase` 保留其专属编队、跟随玩家和归队行为。
- `EnemyBase` 只添加敌方行为所需的出生点与状态机装配，不复制移动和战斗代码。

## 目标锁定

敌我双方共用现有的 `AITargetingComponent` 和 `TargetSelectionPolicy`：

- 敌人配置现有 `DefaultNearestEnemy.tres`。
- 它从敌人视角选择最近的、有效的敌对 `UnitBase`；玩家和伙伴均为候选。
- 获取半径、保持半径、扫描频率、锁定稳定性、调试范围圈和目标有效性检查完全沿用现有实现。
- `AITargetingComponent` 是唯一的锁定目标所有者。敌人状态机不保存第二份目标，只在每帧读取 `get_locked_target()`。
- 未来“优先玩家”“最低生命”等规则通过新增或替换 `TargetSelectionPolicy` 资源实现，当前不改变策略架构。

## 敌人行为状态

`EnemyBehaviorStateMachine` 是独立于 Ally 状态机的组件，不继承其具体实现，以免引入玩家编队参数。第一版只有四个状态：

```text
IDLE
  └─ 获得有效锁定目标 → CHASE

CHASE
  ├─ 进入武器攻击距离 → ATTACK
  └─ 超出出生点脱战半径 / 目标失效 → RETURN_HOME

ATTACK
  ├─ 目标离开攻击距离 → CHASE
  └─ 超出出生点脱战半径 / 目标失效 → RETURN_HOME

RETURN_HOME
  └─ 回到出生点 → IDLE
```

### 状态职责

- `IDLE`：停在出生点附近，不主动移动；索敌组件继续扫描。
- `CHASE`：朝锁定目标移动，移动速度由 `AIUnitBase` 执行；进入 `AICombatSystem` 的武器攻击距离后切换攻击。
- `ATTACK`：保持面向目标，使用现有 `AICombatSystem.request_basic_attack(target)`。冷却、武器动画、近战 Hitbox、远程投射物、伤害与命中反馈均由既有战斗系统处理。
- `RETURN_HOME`：立刻清除锁定目标并取消当前攻击，再返回运行时记录的出生位置；到达后才恢复正常索敌。

## 脱战与出生点

- `EnemyBehaviorStateMachine` 在配置时记录持有者的初始世界坐标为 `home_position`，不要求设计师手填世界坐标。
- 暴露 `leash_distance` 和 `home_arrival_distance`，便于各敌人场景独立调整。
- `leash_distance` 以敌人与出生点的水平距离判定。无论当前处于追击还是攻击，越界即进入 `RETURN_HOME`。
- 归位期间临时暂停 `AITargetingComponent`，避免敌人在返程时反复锁定同一目标。
- 返回出生点后恢复索敌；第一版不实现巡逻、仇恨表、组链接战或回血重置。

## 配置与节点

`EnemyBase.tscn` 将由现有节点加装两个可复用组件：

```text
EnemyBase
├── CombatSystem                 # 已有，近战或远程战斗子场景
├── AITargetingComponent         # 复用现有组件和 DefaultNearestEnemy.tres
└── BehaviorStateMachine         # EnemyBehaviorStateMachine.tscn
```

具体敌人只需继承 `EnemyBase`，设置武器、战斗组件、索敌半径和脱战半径；不需要写新脚本。

## 命名还原范围

旧系统已归档，因此新系统中仅为规避旧名称而存在的名称将还原：

- `AllyBase2` → `AllyBase`
- `EnemyBase2` → `EnemyBase`

会同步更新 `class_name`、场景文件名、继承和测试引用。归档内容保持原状。

## 边界与安全性

- 不修改 `Scenes/TestScene.tscn`，任何敌人实例仍由用户手动添加。
- 不更改玩家和伙伴现有行为逻辑；只复用其公共组件。
- 目标失效、死亡、归位或组件配置失败时，敌人取消移动/攻击请求并安全回到待机或归位，不保留悬挂目标。
- 本阶段不连接 `UnitBase` 的全局战斗状态，也不实现房间完成、敌人群体唤醒、经验/掉落或复活重置。

## 验收条件

- 敌人在目标进入其获取半径后，锁定最近的玩家或伙伴并追击。
- 到达武器距离后使用已装配的近战或远程 `CombatSystem` 攻击。
- 目标死亡、不可选中或敌人越过脱战半径时，攻击停止并返回出生点。
- 返回出生点后敌人能再次正常扫描与锁定。
- Ally 与 Enemy 均通过同一 `AITargetingComponent` / `TargetSelectionPolicy` 工作。
- `AllyBase`、`EnemyBase` 命名还原后，相关测试、编辑器扫描和运行输出无错误。

## 实施验证（2026-08-01）

- 已还原 `AllyBase2` / `EnemyBase2` 为 `AllyBase` / `EnemyBase`，并更新当前新系统的继承场景与测试引用。
- `EnemyBase` 已装配现有 `AITargetingComponent`、`DefaultNearestEnemy.tres` 和新的 `EnemyBehaviorStateMachine`。
- 已通过 `UnitDirectoryLayoutTest`、`EnemyBehaviorStateMachineTest`、`AITargetingComponentTest`、`AICombatSystemTest`、`AIUnitBaseLocomotionMigrationTest`、`AllyInheritedRootRenameTest` 及 Godot headless 编辑器扫描。
- Godot MCP Pro 刷新后，编辑器错误数为零。
