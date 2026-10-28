# TestLevel01 区域1怪群配置
日期：2026-10-28  
配置场景：`res://Scenes/TestLevel01.tscn`。仅配置已确认的区域1，区域2/3不放怪。

## 场景与生成点结构

```text
TestLevel01
├─ EnemyContainer
│  ├─ Pack_A1                         4 GoblinWarrior
│  │  └─ Spawn_01_Melee … Spawn_04_Melee   Marker3D
│  │     └─ Enemy                    现有敌人场景实例
│  ├─ Pack_A2                         3 GoblinWarrior + 1 GoblinArcher
│  │  └─ Spawn_01_Melee … Spawn_04_Ranged
│  │     └─ Enemy
│  └─ Pack_A3                         3 GoblinWarrior + 2 GoblinArcher
│     └─ Spawn_01_Melee … Spawn_05_Ranged
│        └─ Enemy
├─ EncounterController               已有场景实例，Debug Log开启
├─ Region01Navigation                已烘焙的 NavigationRegion3D
└─ LevelMarkers/Region01/K1_GatherPoint
```

项目现有管理方式是场景预摆固定单位，不存在独立的波次刷怪器。本次用Godot原生Marker3D表达固定生成点，单位进入关卡即存在，不按计时生成、不自动补怪或复活。EncounterController仍只负责Pack生命周期。

EnemyContainer必须与EncounterController同级；其直接Node3D子节点为Pack，控制器递归收集各Pack下的EnemyBase。不要在EnemyContainer与Pack之间插入区域分组，否则会改变现有登记语义。以后区域2/3的Pack可继续增加为该容器的直接子节点。

## 点位和编辑入口

| 怪群 | 世界中心 X,Y,Z（米） | 配比 |
|---|---|---|
| Pack_A1 | 3.000, 13.042, 10.000 | 4近战 |
| Pack_A2 | 15.000, 12.506, 0.000 | 3近战＋1远程 |
| Pack_A3 | 9.000, 12.724, -16.000 | 3近战＋2远程 |

K1参考点：3.000, 12.670, 0.000米。K1只是编辑标记，不是波次触发器、传送点或强制集火指令。

- 修改单只怪位置：选择其Spawn Marker，调整Transform；Y应重新贴地。Marker的朝向控制初始朝向。
- 更换怪种：在相同Marker下替换Enemy场景实例，保持该Enemy初始局部Transform为单位变换（位置、旋转为0，Scale为1）。
- 修改全堆位置：可移动Pack，但各生成点需要重新贴地，并复测警戒、导航和归位余量。
- 修改单位能力：沿用已有单位、武器与技能配置入口；本次未修改单位源场景、AI脚本或战斗数值。
- 原有待机游荡被保留，因此运行后敌人可能在出生点附近轻微移动；Marker代表初始归位基准，不要求单位始终停在Marker正上方。
- 调试怪群生命周期：选择EncounterController，Debug Log Enabled目前开启，Output显示started/reset/cleared；发布前可按需要关闭。

实例通过Godot编辑器实例状态创建，保留原场景引用。GoblinArcher源场景本身带有非零根位移，关卡实例显式覆盖为单位变换，保存并重新实例化后已核验，避免弓手出生于地表下方。源场景未改动。

## 区域1导航

Region01Navigation复用默认导航层1，使用World物理层的静态碰撞进行烘焙。

几何源持久分组：`testlevel01_navigation_geometry`，添加于现有的：
- testscenebase/TerrainCollision
- TerrainBarriers
- MapBoundary

NavigationMesh通过Groups With Children读取几何，Bake AABB限定区域1上层：
- 起点：(-18,10,-29)米；大小：(46,8,58)米。
- Cell Size：0.25米；Cell Height：0.05米。
- Agent Height：1米；Agent Radius：0.45米；Max Climb：0.3米；Max Slope：45度。

高度采样采用0.05米以匹配已有NavigationAgent3D的0.2米到点距离。此前较粗的高度采样使首个导航点略高于角色脚底，到点判断无法推进；通过区域导航精度修正，未改动AI源脚本或单位场景参数。

地形、实体围挡或空气墙改变后：选Region01Navigation检查Shape来源和AABB，再Bake并保存场景。仅完成区域1导航，不表示区域2/3、跨区拉怪或断崖单向链接已配置。导航资源保存在场景内，本轮不创建外部.tres/.res。

## 实际验证记录

1. 已有EncounterControllerTest运行通过；该测试中空Pack与异常删怪的警告是测试夹具预期行为。
2. 保存后以全新PackedScene重读，13个Enemy实例初始局部Transform全部为单位变换，源场景引用保留。
3. 运行时控制器正确登记A1=4、A2=4、A3=5，初始均为DORMANT；13只均正常站立，并存在至K1的导航路径。
4. 运行时依次移动测试玩家到各组警戒范围，交战数实际为4→8→13；不是只检查节点数量。
5. 调整导航高度精度后，观察到实际追击移动；回K1阶段13只仍交战且全部站立，观测到距出生点最大位移约16.58米。
6. 清除锁定目标后执行已有归位逻辑，三组均回到DORMANT，存活数仍为4/4/5，距生成点误差约0.39～0.68米（含默认待机游荡）。
7. 以上连续接怪测试仅在运行实例临时关闭Hero死亡，避免场景中没有伙伴时验证被提前终止；已恢复并停止运行，没有保存不死或血量改动。
8. 原有Hero、CameraRig、地形、围挡与空气墙的节点变换保持不变。

本次不增加伙伴、区域2/3单位、战斗结算界面、自动刷怪、奖励或另一套遭遇系统。现有场景只有Hero，因此不把上述配置验收等同于五人队伍的战斗难度、完整手动跑图或全关卡平衡验收。
