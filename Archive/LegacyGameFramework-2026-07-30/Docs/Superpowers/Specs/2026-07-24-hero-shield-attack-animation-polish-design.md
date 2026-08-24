# Hero 盾牌两段普通攻击动画优化设计

## 目标

在不修改剑动画库、玩家攻击控制器、盾牌模型和其他战斗逻辑的前提下，优化 `IronShield` 的两段普通攻击动画。动作需要摆脱只有武器插槽移动造成的僵硬感，通过 `CharacterRoot` 与 `WeaponSocket` 的协同运动，让攻击方向和力量更容易辨认。

运行时与 Workbench 必须共同使用唯一的外部动画资源：

`res://Item/Weapon/IronShield/ShieldAnimationLibrary.res`

## 资源边界

- 只调整 `ShieldAnimationLibrary.res` 中的 `basic_attack_1` 和 `basic_attack_2`。
- `HeroAnimationWorkbench.tscn` 继续通过 `ExtResource` 引用该动画库，仅作为编辑和预览环境。
- 保留 `RESET` 的当前盾牌基础持握姿势。
- 不修改 `IronSwordAnimationLibrary.res`。
- 不修改盾牌材质或 `IronShieldVisual.tscn`。
- 本次不调整伤害、攻击距离、真实位移距离或 Hitbox 数值。

## 第一段：举盾前顶

动画总长约 `0.46s`，分为四个阶段：

1. `0.00–0.10s`：身体轻微后仰和转肩，盾牌抬高并小幅后收。
2. `0.10–0.20s`：身体快速向前压，盾牌沿角色正前方向顶出。
3. `0.20–0.26s`：保持极短的冲击姿势，使动作具有明确命中点。
4. `0.26–0.46s`：身体与盾牌平滑返回 `RESET`。

`CharacterRoot` 使用约 `8–15°` 的俯仰和转肩动作。`WeaponSocket` 主要表现盾牌抬起、前顶和轻微倾斜，不再依赖大幅水平转向假装前进。

## 第二段：左向右横扫

动画总长约 `0.52s`，分为四个阶段：

1. `0.00–0.12s`：身体向左侧蓄力，盾牌移动到左前方。
2. `0.12–0.25s`：身体快速向右转动，盾牌沿宽弧线由左向右扫过正前方。
3. `0.25–0.32s`：保持短暂随动，明确表现挥击终点。
4. `0.32–0.52s`：降低速度并回到 `RESET`。

`CharacterRoot` 左右转体总变化约 `30–40°`。盾牌扫击角度约 `110–130°`，并通过横向位置变化形成可读的运动弧线。

## 动画轨道

两段动画都使用以下值轨道：

- `CharacterRoot:position`
- `CharacterRoot:rotation`
- `CharacterRoot/WeaponSocket:position`
- `CharacterRoot/WeaponSocket:rotation`

动画仍以 `HeroVisual/CharacterAnimationPlayer` 为播放节点，因此轨道路径必须相对 `HeroVisual` 保持有效。轨道不直接绑定 `IronShieldVisual`，以后替换盾牌视觉时不需要重做动作。

## 节奏与插值

- 蓄力阶段较慢。
- 出击阶段明显加速。
- 冲击姿势只短暂停留。
- 复位阶段慢于出击阶段。
- 使用平滑插值和额外关键姿势形成节奏，不依赖匀速直线移动。

## 验证标准

- Workbench 对盾动画库的绑定为 `ExtResource`，不存在第二份内嵌盾动画库。
- 外部动画库能够加载，且包含连续命名的 `RESET`、`basic_attack_1`、`basic_attack_2`。
- 两段攻击都包含 `CharacterRoot:rotation` 轨道。
- 第一段具有可辨认的抬盾、前顶和冲击停留。
- 第二段具有可辨认的左侧蓄力、穿过正前方的右向横扫及随动。
- 两段最后都精确返回 `RESET`，连续攻击不会积累位置或旋转偏差。
- Godot 4.7 编辑器扫描和无窗口项目启动不产生新增错误。
