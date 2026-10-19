# 焰星连轰：终结技独立视觉资产

初次交付仅含视觉组件；目前已完成真实技能与A/B演出接线，参见 SkillSystem/04-Docs/FlameBarrageFinisherConfigurationGuide.md。以下独立美术预览仍不执行伤害。角色动画由用户制作；最新节奏调试仅延长finish_cast_1的姿态保持并顺延后段及方法轨道，不修改工作台或其他动画。所有新增脚本与场景均使用 Godot MCP Pro 创建，并通过 Godot ResourceSaver 原生保存场景。

## 如何查看

在 Godot 打开 `FlameBarrageVisualSequencePreview.tscn`，按 F6。预览循环展示一次蓄力、一次主释放、五颗弧线火球和五次独立爆炸；界面可暂停、继续和重播。地面细线是5米落点参考区，不是技能特效。预览落点固定，便于重复比较，不代表正式技能选点算法。

四个独立检查入口：

| 场景 | 内容 |
| --- | --- |
| FlameBarrageCastEffectPreview.tscn | 破碎竖直焰冠、火星汇聚与施法点亮核 |
| FlameBarrageReleaseEffectPreview.tscn | 0.14秒向前扩张的红金圆环与锥形火舌 |
| FlameBarrageFlightEffectPreview.tscn | 0.5秒弧线飞行，金白火核、红橙外壳、约1米短尾 |
| FlameBarrageImpactEffectPreview.tscn | 接触闪光、3米冲击环、短火柱、碎屑；0.35秒主视觉完成 |

## 实际编辑入口

四个不带 Preview 后缀的 `FlameBarrage{Cast,Release,Flight,Impact}Effect.tscn` 是正式视觉资产。选择 `VisualRoot` 下的网格，可在 Inspector 编辑尺寸、材质和位置；时间变化在 `AnimationPlayer → effect` 的轨道中编辑。所有网格关闭投影，不会增加黑影。

根节点仅暴露两个生命周期选项：

- `Autoplay`：独立放置时自动播放；技能托管时入树前关闭，再调用 `play()`。
- `Auto Free On Finished`：自然结束是否销毁。Release / Impact 开启；Cast 由技能持有方清理；Flight 循环，由投射物清理。

不是再建四套技能脚本。四段共用一个新的 `FlameBarrageEffectPlayer.gd`，画面和曲线保存在各自场景中；不引用旧 Fireball / Pyroblast 的视觉内容、脚本或曲线。预览共用另一个脚本。没有新增外部 .tres / .res，所有新网格、材质、动画是场景内嵌资源。

## 生命周期和接线契约

`play()` 从头播放；`stop()` 立即隐藏且不发送完成信号；取消后可重播。`effect_finished` 仅在主视觉自然结束时发出一次。Flight 为循环，不自行完成。Impact 的0.35秒完成信号可供后续 B 模式统计，当前不控制世界速度。

`configure_cast(source, world_origin, duration)` 沿用现有施法视觉接口。冠环跟随施法者位置，保留起始朝向，不跟角色旋转一圈。传入实际施法时长会同步调整整段表现速度。

默认使用场景处理帧；技能托管可直接set_execution_clock接入请求时钟，无须关闭处理。若外部手动推进，则先 `set_process(false)`，再每帧调用 `advance_effect(delta_seconds)`，避免重复推进。脚本和网格不读取全局 shader TIME，不包含世界时停实现。

## 动画基线

引用用户的 `Item/Weapon/MagicGlobe/MagicGlobeAnimationLibrary.res → finish_cast_1`：

- 片段长度约1.333333秒，不循环。
- `release_action` 0.6秒，触发主释放并开始五发。
- `finish_action` 约0.766667秒；随姿态保持段延长一并后移，仍不移动到末尾。
- 后续火球由预览时间轴推进，不受角色动作完成影响。间隔0.12秒，每颗飞行0.5秒，最后一颗主爆炸理论在约1.93秒完成。

这里只验证视觉，不对正式 AI 动作完成后的控制权恢复作结论。后续真正接入时仍复用 SkillBase / Delivery，不使用预览脚本作为战斗管线。

## 文件职责和数量

- 9个 .tscn：4段正式特效 + 4个独立预览 + 1个完整预览。
- 本目录3个 .gd：纯视觉播放器、预览播放器、视觉测试。
- `Tools/Effects/BuildFlameBarrageAssets.gd`：原生资产初始生成工具，不参与运行。公开 build() 遇到任一已有输出拒绝覆盖，后续日常调整直接编辑场景；不要删除资产后重新生成来替代人工美术编辑。
- 各脚本的 .uid 由 Godot 生成，需和脚本一同版本管理。

验证命令：Godot --headless --path 项目路径 --script res://Effects/Skills/FlameBarrage/FlameBarrageVisualEffectTest.gd。覆盖有效 UID、独立依赖、取消与重播、施法时长适配、冠环稳定朝向、命中完成与自动清理、五发不被角色动作截断、预览销毁无孤儿节点。
