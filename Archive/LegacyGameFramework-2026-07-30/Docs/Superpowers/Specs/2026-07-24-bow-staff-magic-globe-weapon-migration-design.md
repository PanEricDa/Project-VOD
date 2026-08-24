# Bow、Staff、MagicGlobe 新武器资源迁移设计

## 目标

把旧 Ranger、Healer 和 Mage 中可复用的十字弩、法杖与法球视觉迁入新的 `Item/Weapon` 架构，并为每种武器建立一套可由 `PlayerAttackController` 装备和播放的外部动画库。

本阶段只迁移和制作武器视觉与攻击动作，不迁移旧 AI 攻击算法，不生成箭矢、法术、治疗或其他远程交付。

## 架构边界

每种武器只维护三个资源：

```text
WeaponData.tres
WeaponVisual.tscn
WeaponAnimationLibrary.res
```

资源不继承旧 `AttackModuleBase.tscn`，不引用旧 AI Profile，不增加武器专用脚本。旧 Ranger、Healer、Mage 场景及 `TestScene` 保持不变。

动画继续由 `HeroVisual/CharacterAnimationPlayer` 播放，只操作：

- `CharacterRoot:position`
- `CharacterRoot:rotation`
- `CharacterRoot/WeaponSocket:position`
- `CharacterRoot/WeaponSocket:rotation`

动画不得直接绑定武器视觉内部节点。三个 Visual 均以 `WeaponSocket` 为局部零点，避免重复带入旧角色场景中的位置偏移。

## 文件结构

```text
Item/Weapon/
├── Bow/
│   ├── BowData.tres
│   ├── BowVisual.tscn
│   └── BowAnimationLibrary.res
├── Staff/
│   ├── StaffData.tres
│   ├── StaffVisual.tscn
│   └── StaffAnimationLibrary.res
└── MagicGlobe/
    ├── MagicGlobeData.tres
    ├── MagicGlobeVisual.tscn
    └── MagicGlobeAnimationLibrary.res
```

每个动画库只包含：

```text
RESET
basic_attack_1
```

## Bow

新系统统一使用 `Bow` 命名，但当前视觉采用旧 `CrossbowAttack.tscn` 中的十字弩示例：

- Stock
- BowLimbs
- Grip
- LoadedBolt
- `MatGridYellow.tres`

`basic_attack_1` 总长约 `0.38s`：

1. 身体轻微抬弩并向目标方向压低重心。
2. 十字弩快速后坐并小幅抬高。
3. 身体与 WeaponSocket 平滑返回 RESET。

本阶段 LoadedBolt 持续显示，不触发 `_release_projectile()`，也不实例化 `Arrow.tscn`。

## Staff

视觉迁移旧 `Healer.tscn` 中的：

- StaffShaft
- FocusOrb
- FocusBar
- `MatGridYellow.tres`

旧 `StaffAttack.tscn` 目前没有实际攻击动画，因此新建 `basic_attack_1`，总长约 `0.55s`：

1. 身体侧转，法杖后收并抬起。
2. 身体向前转回，法杖向前上方点出。
3. 保持短暂施法终点后返回 RESET。

## MagicGlobe

视觉迁移旧 `Mage.tscn` 中的 `MagicFocus`：

- 球形 CSG 模型
- `MatGridBlue.tres`

模型转换为以 WeaponSocket 为局部零点的独立视觉场景。新建 `basic_attack_1`，总长约 `0.48s`：

1. 身体轻微后收，法球向身体侧上方绕起。
2. 身体前倾，法球向正前方推出。
3. 保持短暂动作终点后返回 RESET。

动作只需清楚可见，不加入复杂旋转、粒子或缩放表现。

## WeaponData 配置

三份 Data 分别引用同文件夹内的 Visual 与外部 AnimationLibrary。

当前阶段统一保持：

```text
attack_forward_distances = []
hitbox_sizes = []
hitbox_center_offsets = []
```

动画不创建 Method Track，因此不会触发真实攻击位移、近战 Hitbox 或远程 Delivery。

## Workbench 使用

不为三种武器新增独立 Workbench 场景，也不永久修改当前 Workbench 的盾牌配置。需要人工预览时，在 `HeroAnimationWorkbench.tscn` 中临时：

1. 将目标 Visual 实例放入 `WeaponSocket`。
2. 加载目标外部 AnimationLibrary。
3. 播放 `basic_attack_1`。
4. 预览结束后可移除临时绑定。

## 验证标准

- 三份 WeaponData 能够加载，且分别引用正确 Visual 和外部 AnimationLibrary。
- 三个 Visual 场景根节点均为 `Node3D`，且不包含旧 AI 脚本。
- 三个外部 AnimationLibrary 均包含且只包含 `RESET`、`basic_attack_1`。
- 两个动画均拥有四条规定的值轨道。
- `basic_attack_1` 最后一帧与同库 RESET 完全一致。
- `PlayerAttackController.equip_weapon()` 能接受三份 Data。
- 旧 Ranger、Healer、Mage、AI AttackModule 和 `TestScene` 不发生修改。
- Godot 4.7 编辑器扫描与主场景无窗口启动不产生新增错误。
