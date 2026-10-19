# Caster终结技：装配、配置与验证

## 运行入口

- 正式完整战斗：F5启动 `res://Scenes/CombatRoom.tscn`（或打开它按F6），具体组装见同目录CombatRoomAssemblyGuide.md。沿用1—4连携与原评分，结算达分后选择窗口中按3使用Caster终结技。其余伙伴尚未装备终结技，灰显。
- 对照体验：打开 `res://Scenes/Previews/SquadFinisherComparisonPreview.tscn`，F6。右侧选择A/B，再点击“试放”；可重置、真暂停。这里冻结普通AI以隔离演出差异，但仍可用原1—4做真实连携。
- 单纯美术：`res://Effects/Skills/FlameBarrage/FlameBarrageVisualSequencePreview.tscn`，仍只展示视觉，不实施伤害。

比较模式只覆盖下一次请求的私有快照，不改共享技能。首版正式默认B。

## 技能配置入口

打开 `res://UnitSystem/AI/Ally/Units/Caster.tscn`：SkillHost的Finisher Skill引用其SkillSocket下的FlameBarrageFinisherSkill，与两个普通技能、连携技能分开实例。

打开 `res://SkillSystem/00-Skills/Finisher_FlameBarrage/FlameBarrageFinisherSkill.tscn`：

- Targeting分组：Cast Range=6米，Release Range Tolerance M=2米，Validate Target On Release开启。容差只用于释放帧，不扩大初始可用性和接近距离。
- 根节点仍为原SkillBase，套用原RangedSkillTemplate的三个基础节点，不建立终结技专用伤害体系。
- Delivery选通用ArcProjectileDeliveryConfig，Destination Mode=Random Ground Circle。Shot Count=5、Shot Interval Seconds=0.12、Scatter Radius M=3、Impact Radius M=1.5。
- DamageEffect为原HealthChangeSkillEffect，Base Amount=45，Power Ratio=1.25；沿用原防御和伤害算法。
- Cast Effect Scene、Release Visual Scene和投射物的Flight/Impact均为此前验收的新焰星连轰资产。
- Cinematic Profile选择同目录FlameBarrageCinematic.tres，仅三个主要配置：模式、动作Animation、世界速度（0.05）。
- Camera Effect Profile选择 `res://Effects/Camera/Presets/FlameBarrageCinematicCamera.tres`，可调整角色正面偏移、注视高度，以及Transition Timing下的三个真实活动秒数：Closeup Transition Seconds、Battle Transition Seconds、Player Return Seconds，默认均0.2。

外部资源已由Godot正式保存并登记UID。Cinematic与Camera分别为强类型资源，可以按相应字段Quick Load。

## 投射物与视觉

`res://Item/Projectiles/FlameBarrageProjectile.tscn`复用TrackingArcProjectile通用运动脚本：飞行0.5秒、弧高3米，引用独立Flight和Impact场景。地面爆炸半径由Delivery注入视觉，不手工同步两个半径。

落点在成功释放时围绕当时目标位置投影到World层地面并冻结，之后不追踪原目标。3米内均匀采样，最多5颗；每颗在1.5米内复用原Effects，可落空、可重复覆盖，查询不限制为32目标。

## 动作资产

FlameBarrageAction.tres是用户完成的finish_cast_1的独立正式快照：长度约1.333333秒、非循环、release为0.6秒、finish约0.766667秒。已同步原MagicGlobeAnimationLibrary.res中的finish_cast_1；没有修改工作台场景。身体与武器同时保持蓄力姿态约0.5秒，后续关键帧统一顺延约0.133333秒，动作值、插值与后续帧间隔不变。

继续调整正式终结动作时可编辑该Animation资源或在Cinematic Profile中换选动画。若继续通过Workbench修改MagicGlobeAnimationLibrary/finish_cast_1，须将新的片段同步到正式Action快照；当释放帧改变时，沿原有规则将Base Cast Time对齐该帧，避免动作被旧施法时间重新加速。动作占用等待片段自然结束和本次发射完成，避免早finish标记截断五发。

## A/B与控制权

进入特写：施法开始时从当前实际镜头平滑推进并转向角色正面，内部固定约0.2真实活动秒，使用缓入缓出；不受5%世界慢放拖慢，真暂停冻结。不增加Inspector参数；提前释放直接从当时画面进入后续阶段，不等待镜头到位。

A：前摇正面特写、5%世界；第一颗真正成功发出即恢复普通镜头和此前世界速度，剩余交付按世界时间。

B（当前正式流程）：动作装载并求值0帧后，自动真暂停并推进特写；到位解除自身暂停，世界5%、角色正常速度播放。release_action先检查并等待，真暂停退到目标区域的普通战斗视角；到位后解除自身暂停，下一物理帧走原释放管线，生成火球、播放成功特效并继续后摇。等待全部待发、在途和主要Impact结束后恢复世界速度，再按Player Return Seconds平滑交回玩家；最终归位不额外暂停。

执行组件只需引用本世界Selection Source和Camera Source，沿原选择源取得队伍、专注指令和暂停协调器。最终镜头仍由原CameraFollowController写入，不另造第二台运行相机。

取消/硬中断只停止未发，已发投射物继续按规则结算。真暂停冻结请求，不在恢复时补发。执行组件只释放自己的时间和输入token，其他慢放/菜单仍有效。终结伤害来源为既有FINISHER，不回专注、不进入连携评分。

## 文件复用

新增通用接口：SkillExecutionClock、SkillCinematicProfile、SkillCinematicCameraProfile、SquadFinisherExecutionController。Arc交付、SkillBase/Host、原AI动作与原相机只作兼容扩展；普通配置不需要选择演出资源。

后续地面多发技能可改Arc投射物/数量/间隔/半径和Effects；后续终结技可换Animation、四段视觉与Camera Profile，不必复制本技能的伤害、时间或目标算法。

## 实施裁决

- 原详细设计早期0.65/1.35秒参考已被用户验收的实际动画替代。
- 既有实施计划只覆盖选择窗口，因此本轮新增执行计划衔接已确认规格。
- 历史实施最初装配在SelectionPreview；2026-10-19完整组装后，正式入口为继承TestCombatRoom的CombatRoom，旧预览保持独立，不向基础房间重复添加组件，也不向TestScene添加单位。
- 比较预览嵌套Battle，沿原Host.configure_owner显式统一其作用域；不是第二套技能执行。

## 稳定性补充
发射与主要视觉超时预算由实际配置/素材推导，不要求额外调参。地面采样和同步命中统一在物理阶段；SkillBase自动承接来自渲染回调的释放。正式终结Delivery是静态配置，运行会话复制快照；角色和预览不再重复覆盖源技能参数。

## 2026-10-19 特写推进验证
进入特写已由直接切换改为约0.2真实活动秒平滑推进；默认0.35秒转区域、0.30秒归还玩家不变。定向测试覆盖起始画面不跳、5%速度下推进、真暂停冻结、提前释放继续后续阶段。真实运行采样：施法后约0.1秒尚在推进，约0.25秒已到正面机位，五发完整结束。全量151测试中150通过，唯一既有CameraFollowControllerTest导航网格未烘焙失败不变，无泄漏日志。

## 2026-10-19 新动作与特写停留同步
同步用户新finish_cast_1：1.2秒片长，0.466667秒释放、0.633333秒完成标记。Base Cast Time改为0.466667，默认1倍动作播放，不再压缩前摇。特写推进0.1真实活动秒，按默认动画时间轴，到位后约停留0.366667秒再首发（实际播放受既有施法速度与帧调度影响）；转区域和归还玩家参数保持原值。用户原库及工作台未写入，正式Action原UID保留。

本次同步验证：全量151测试中150通过，唯一旧导航网格失败不变、无泄漏日志；真实运行确认动作播放速度1倍，0.15及0.35秒采样仍处于到位后的特写且尚未首发，释放时动画位置约0.466667，最终五发/五落地并恢复。正式Animation已用ResourceSaver保存，UID保持不变。

## 2026-10-19 延长完整姿态保持
按用户调试要求，镜头推进恢复0.2真实活动秒。finish_cast_1的全身/武器共同静止段从约0.166667—0.533333秒延长为约0.166667—0.666667秒，达到0.5秒姿态保持。后续动作与方法轨道统一后移0.133333秒：release=0.6、finish≈0.766667、片长≈1.333333。正式Action与Base Cast Time=0.6同步，默认1倍播放；按动画时间轴镜头到位后到首发约0.4秒。原动作曲线值、插值及后段帧间隔不变，其他动画未变；A/B恢复规则不变。原生ResourceSaver保存动画库及正式Action，UID均有效且保持原值。

本次验证：装配、镜头及视觉测试通过（视觉165项断言）；原生读取确认源动画库与正式Action保存后所有关键帧时刻一致、UID有效，其他动画与工作台场景未变。真实预览0.1/0.3/0.5秒采样均处于特写、尚未首发、动作1倍播放，最终5发/5落地、主视觉清零并恢复。全量151脚本149通过：CameraFollowControllerTest仍为既有room navigation mesh is baked失败；SquadFinisherSelectionControllerTest在并行运行的30ms选择窗口压力用例出现一次stress selection失败，单独重跑通过，未调整其窗口或产品逻辑。并行计时稳定性仍需关注，不能据单次重跑视为修复。全部日志未发现ObjectDB泄漏或资源仍在使用报告。

## 2026-10-19 加快离开特写与归位
为减少镜头移动遮挡角色后续动作，特写转战斗区域从0.35缩短为0.2真实活动秒（约1.75倍速），演出结束交回玩家从0.30缩短为0.2真实活动秒（约1.5倍速）。进入特写仍0.2秒，姿态保持0.5秒、释放0.6秒、动画与方法轨道不变；A首发立即恢复规则不变。保留原有缓入缓出与暂停冻结，不增加Inspector参数。

本次归位调速验证：定向测试先复现旧时长无法在0.2秒到位，再验证两段新时长通过；覆盖5%世界速度与平滑归位、镜头原配置恢复。全量151项中150通过（选择压力测试单独执行以避免上一轮并行计时干扰），唯一失败为既有CameraFollowControllerTest导航网格未烘焙检查，无泄漏日志。

## 2026-10-19 终结技释放射程容差
用户已选定B为后续唯一正式方案，A保留到统一清理，本次不改演出模式。
新增SkillBase通用Targeting字段Release Range Tolerance M（release_range_tolerance_m），默认0保持其他技能行为；当前焰星连轰配置2米，Cast Range仍为6米。终结预检、真实启动与动作排队均按原6米检查，只有release_action的复核使用6+2=8米。沿用原0.05米数值容差和水平距离口径，不识别击飞或走动的来源，不新增位移状态；超过释放射程则沿原失败管线取消，恢复世界速度/镜头/输入，死亡、失效、施法封锁仍按原规则执行。成功释放后仍以目标当时位置采样并冻结全部落点，不在容差改动中提前冻结中心或改变散布、伤害范围。
配置入口：FlameBarrageFinisherSkill.tscn根节点 → Targeting → Release Range Tolerance M。后续其他技能需要相同宽限时可自行配置，无须新增脚本。
定向测试覆盖初始超距拒绝、漂移至7.9/8米成功、超过8米与20米位移失败、零容差保留旧行为；真实B演出验证7米不能入场、前摇后7.9米仍完成五发、8.2米取消且没有遗留镜头/时间/输入/动作锁。

容差交付验证：生命周期测试先在旧实现中复现7.9/8米释放失败，再于通用容差与正式配置接入后通过；真实B演出边界测试通过。全量151项中150通过（短时限选择压力测试单独运行），唯一既有CameraFollowControllerTest导航网格检查失败，无ObjectDB/资源泄漏日志。Inspector原生查询确认正式技能Cast Range=6、Release Range Tolerance M=2，新增字段有浮点范围约束，默认0不影响其他技能。

## 2026-10-19 镜头过渡门闩（当前流程）
本节覆盖前面的历史调试记录。无新增动画方法帧，仍只使用release_action与finish_action；自动进入特写停在0帧，退镜停在释放帧。镜头移动不消耗角色动画；第一颗火球从原动画0.6秒延至约0.2+0.6+0.2=1.0真实活动秒，具体受帧调度影响。镜头到位由带请求身份的完成通知驱动，不等待暂停中的动画继续执行。

配置：技能根节点的Camera Effect Profile引用FlameBarrageCinematicCamera.tres；Transition Timing三项分别为进入特写、退至目标区域、轰炸后归还玩家的真实活动秒数，默认0.2，允许0，范围0—3。不同技能可选不同资源，共用同一资源的技能会共同改变。动画时长、释放标记和Base Cast Time仍沿原契约，不在镜头等待中缩放或改写。

架构：GamePauseCoordinator新增镜头过渡暂停凭证；只有本凭证且无菜单/其他暂停时，CameraFollowController可在真暂停中推进，战斗和SkillExecutionClock仍冻结。Host增加可选终结释放门闩，未装配执行协调器的技能继续原流程。AIAttackController只消费请求时钟并精确截到释放标记，不反向查询镜头或技能；镜头结束后Host从原SkillBase提交，目标/2米容差、费用与效果再次验证。支持非Arc技能，未提供范围时保持普通战斗镜头距离。

新的可测试阶段：enter_closeup → windup → exit_closeup → release_pending → bombardment → returning → idle。菜单暂停优先；取消、角色/世界退出只释放本方token，迟到到位通知不能恢复旧动作或再次发射。A模式兼容入口本轮不扩展，后续统一清理。

本轮最终验证：152个脚本中151通过，唯一失败仍为CameraFollowControllerTest的既有导航网格未烘焙检查；无ObjectDB或资源泄漏日志。新增FinisherCinematicPauseGateTest覆盖零帧进镜冻结、释放帧精确截断、镜头到位前零投射物、菜单优先、两段取消、零时长、非Arc交付、可选镜头缺失及暂停中卸载。FinisherCinematicExecutionTest验证0.3/0.4/0.5秒三个独立时长；首发硬中断测试按真实发射事件等待，不再依赖旧1秒假设。原生运行追踪确认0帧/0.6秒冻结、镜头到位后首发、五发五落地并恢复。配置资源原生保存、UID有效，工作台与源/正式动画均未改动。本轮为实现者自审，未进行独立代理评审。

## 2026-10-19 缩小轰炸范围
仅修改正式焰星连轰Delivery：落点散布半径3米，单颗伤害半径1.5米，理论最外围可波及距目标中心4.5米；不保证整个圆内都命中。爆炸视觉沿既有半径注入同步缩放至原来的一半，镜头区域沿既有散布+爆炸半径自动推导。未修改Arc通用默认5/3米、伤害数值、发射数量或动作时序。
