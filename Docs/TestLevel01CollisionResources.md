# TestLevel01 地形碰撞资源

更新日期：2026-10-27。

## 装配位置

地图场景：`res://Scenes/TestLevel01.tscn`。

碰撞节点位于 `testscenebase/TerrainCollision`。五个节点的 Shape 分别引用以下外部二进制资源：

| 节点 | 资源文件（位于 Assets/3d/Collisions/TestLevel01/） |
|---|---|
| Route_23Collision | Route_23_Collision.res |
| Route_23_1Collision | Route_23_1_Collision.res |
| Terrain_01Collision | Terrain_01_Collision.res |
| Terrain_02Collision | Terrain_02_Collision.res |
| Terrain_03Collision | Terrain_03_Collision.res |

场景继续采用可查看差异的 `.tscn` 格式；三角形碰撞数组保存到压缩二进制 `.res`，避免地图每次保存时把大数组写进文本场景。资源可直接在对应 CollisionShape3D 的 Shape 字段或 FileSystem 中查看。

## 后续编辑

- 修改地图节点、位置或碰撞引用，正常保存场景。
- 编辑外部碰撞资源的内容时，确认资源本身也已保存；仅修改节点变换不需要重新生成碰撞数据。
- 如果重新生成了碰撞形状，将新形状另存并替换到对应 `.res`，再保存地图，避免新数据重新内嵌。
- 地形模型变化后，旧碰撞不会因本次外置自动重新生成，仍须按需要更新碰撞。
- 复制、移动或重新生成资源时使用 Godot 编辑器资源工具，检查引用与有效 UID。

## 本次验证

- 地图由 1,325,904 字节缩小为 81,632 字节，保留原场景 UID。
- 五份资源均使用 ResourceSaver 正式保存，具有有效 UID，类型为 ConcavePolygonShape3D。
- 逐一校验顶点数量、顶点字节哈希、背面碰撞、margin 和资源名称一致。
- 排除五份碰撞数据块及其引用格式变化后，场景其他文本完全一致。
- 这是存储格式优化；没有减少碰撞三角形、改变地形或改写游戏逻辑。
