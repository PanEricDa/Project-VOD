# 炎爆术视觉组件

沿用 Fireball 的组织方式：独立蓄力、飞行、命中特效，各自的 Preview，以及完整流程 Preview。正式战斗仅引用特效组件，不引用 Preview。

## 预览入口

在 Godot 中打开对应场景并按 F6：

| 场景 | 用途 |
| --- | --- |
| `PyroblastCastChargeEffectPreview.tscn` | 脚下圆环、火星上升、后半段汇聚施法点 |
| `PyroblastFlightEffectPreview.tscn` | 圆形火球与短粗尾焰 |
| `PyroblastImpactEffectPreview.tscn` | 金白闪光与紧凑红橙爆燃 |
| `PyroblastVisualSequencePreview.tscn` | 完整蓄力—飞行—命中，交替展示单发与三目标同时齐射 |

Preview 使用几何体、地面、灯光、相机和标题；只演示视觉，不执行 AI、伤害、灼烧或选目标逻辑。四个场景共用 `PyroblastEffectPreview.gd`，通过 Inspector 的 `preview_mode` 区分。

## 正式组件和配置位置

- `PyroblastCastChargeEffect.tscn`：根节点使用 `PyroblastCastChargeEffect.gd`。通过 Inspector 调整圆环半径、火星数量、上升高度、尺寸、颜色和独立预览时长。火星使用一个 MultiMesh，播放时不为每粒火星创建节点。
- `PyroblastFlightEffect.tscn`：复用 `FireballFlightEffect.gd`。调整火核与外壳半径、颜色、尾迹粒子数量和寿命；尾迹默认 0.14 秒。粒子材质使用内嵌的圆形透明渐变，不需要外部贴图。
- `PyroblastImpactEffect.tscn`：复用 `FireballExplosionEffect.gd`。默认视觉半径 0.55 米，播放 0.38 秒；这些参数仅影响画面，不产生范围伤害。正式命中特效自行播放、结束后销毁。

技能接线：

1. `res://SkillSystem/00-Skills/Pyroblast/PyroblastSkill.tscn` 根节点的 `cast_effect_scene` 引用蓄力场景。
2. `res://Item/Projectiles/PyroblastProjectile.tscn` 下实例化飞行场景，根节点的 `impact_effect_scene` 引用命中场景。
3. Preview 和投射物均直接继承正式特效场景参数；Preview 仅覆盖自动播放和命中特效自动销毁开关，避免重复维护美术参数。

## 生命周期与通用接口

`SkillBase` 对可选实现 `configure_cast(source, world_origin, duration)` 的蓄力组件传入施法者、世界发射变换和实际施法秒数，并调用 `play()`。成功释放、取消、失败或重置时调用 `stop()` 并清理该组件。未实现接口的已有特效保持原有播放方式。

炎爆圆环跟随施法者脚下，火星优先汇聚到角色既有 `ProjectileOrigin` 节点；缺少该节点时，使用传入世界发射点相对施法者的局部偏移。独立预览使用 `preview_cast_offset` 作为回退位置。

`TrackingArcProjectile.impact_effect_scene` 是通用的可选 PackedScene 参数。有效抵达目标时在世界命中位置创建独立特效；投射物随后销毁，特效自行完成生命周期。目标失效、死亡或投射物超时不会生成命中特效。默认空值维持其他弧线投射物的现有行为。

所有视觉网格和粒子关闭投影，局部灯光关闭阴影；不改变炎爆选目标、同帧齐射、单体伤害、冷却或灼烧消耗规则。

## 验证

`PyroblastVisualEffectTest.gd` 验证七个场景的有效 UID、预览装配、施法时长同步、圆环跟随、停止与重播、真实 Caster 的释放与打断清理、命中特效独立存活和销毁，以及超时投射物不产生命中特效。
