# 玩家技能阶段三：实现与验证记录

日期：2026-10-21。用户已确认阶段三计划；阶段三已完成实现、原生运行、独立review修正与最终全量回归，等待用户体验验收。阶段四、五未实施，不提交Git/上传。

## 交付与配置

- 正式新增：SkillSystem/00-Skills/Player_ThreatMark/ThreatMarkSkill.tscn（原生继承SkillBase，UID已登记）。根节点Delivery配置World Scope/Caster Radius/Hostile，半径5米，偏移0；施法0.15秒，源CD12秒。ThreatChangeSkillEffect子节点配置threat_amount=2000、duration_seconds=8。测试实例CD2秒。
- 正式脚本复用：EnemyThreatComponent临时贡献账本、StatusEffectComponent带来源状态/单一时钟、ThreatChangeSkillEffect可选限时分支、WorldHealthBar玫红状态点。duration默认0，Guardian普通仇恨400配置和普通伤害/治疗仇恨不改。没有新增正式.gd/.tres/.res。
- 新增测试：UnitSystem/Tests/TemporaryThreatLifecycleTest.gd、SkillSystem/05-Tests/TemporaryThreatSkillEffectTest.gd；扩展既有PlayerSkillTestSceneTest与WorldHealthBarDebuffTest。Godot生成.gd.uid。
- 专用场景/Harness：替换E探针为正式ThreatMark；增加Training/Threat Combat切换按钮、只读状态与仇恨观察；Guardian仅在本专用场景验证，默认Training会移除验证实例，不干扰Q。没有更改受保护Scenes/TestScene.tscn、正式Hero/EnemyBase装配或CombatRoom。

## F6操作

1. 打开Scenes/Tests/PlayerSkills/PlayerSkillsTest.tscn并F6。默认Training，WASD移动，Q拉拽，E施加标记；只有Q青蓝示意圈，E圈仍关闭。
2. E命中时敌人血条上方出现玫红小点，右侧Mark ON、Player约2000；静止靶不追击属于训练设置。8秒后状态点消失、临时贡献归零。重复E只刷新，不叠加。
3. 点击Switch to Threat Combat，场景重新建立、启用真实敌人AI与ValidationGuardian；E后观察目标和追击，到期后按原仇恨倍率/感知/攻击规则竞争接管。远程原射程不变。Switch to Training返回静止靶，Reset Test Scene重置当前模式。
4. 不做强制Guardian接管；若其普通仇恨不足或目标不合法，继续遵循原规则。

## Q参数保护

- 当前基准：作用半径3.5米、中心前移3米、拉动0.12秒、落点身前1.5米/圆盘0.6米、施法0.2秒；源CD10秒、测试2秒。
- Gather源场景SHA256=7799775c42be08682f41a9612aff61fe0531a6539b49f56575415f6259494fa2，与实施前原生快照一致。示意圈读取Q Delivery，不复制参数。

## 自动验证

- 生命周期测试先RED（无临时账本接口）再GREEN：普通100+临时2000=2100，新增50=2150，撤销后150；独立S形衰减对照、同源刷新不叠加、多效果/多来源、比例/snapshot统一。
- 状态绑定先RED再GREEN：8秒到期、4秒刷新延寿、多源部分到期仍有状态；状态创建失败保留旧记录；移除/死亡/来源退出/清表双侧同步；Effect销毁不影响已提交状态到期。
- 来源tree_exiting时is_inside_tree仍true，新增失败测试捕获清理回调重建；修复为离树闸门直到tree_exited，旧代通知不能删新代。
- 当前Godot版本实测不同bind参数的同方法Callable比较相等；初实现刷新产生重复连接ERROR，改为每记录独立lambda并保存精确回调断连，测试无引擎错误。
- WorldHealthBarDebuffTest验证玫红点与灼烧/降防并存及移除，不增加独立UI计时。PlayerSkillTestSceneTest验证真实Q/E输入、CD、无伤害/专注/连携事件和真实感知目标接续。
- 所有Task相关旧回归已通过；全量最终结果稍后追加。

## 原生运行数据

- Training出生点E实际命中4个目标，OutsideRadius在5米外未标记。截图可见4个玫红点与唯一Q青蓝圈。
- Threat Combat真实运行：4个标记在34301—34302ms添加，在42348ms移除，约8.047秒；Ranged从Guardian转Hero，随后Melee/Ranged/Unsupported回ValidationGuardian，WallBlocked按原感知随后接续。
- 未伪造伤害/锁定：玩家健康300→276.713，Guardian650→644.883，均为原战斗管线结果。
- MCP临时查询脚本曾因float/-1的三元分支类型报警；不是生产脚本，将通过干净会话复测Debugger。插件未修改。

## 实施决定与验收边界

- 按用户现有选择在当前目录、MCP写入，使用.godot/player_skills_stage3/保存快照和过程记录，不自动创建工作树或Git版本。
- 计划Task3误写Context.skill_id，按正文使用已有damage_context.skill_id，不增Context字段。
- 新节点改变实例ID后Q圆盘采样位置改变，恢复碰撞时可能挤动缺接收器靶；自动测试仅将运行夹具Unsupported置(-1,0,-1.8)，仍在Q/E范围，远离落盘，不改场景摆放或Q玩法。
- 动态装卸、完整技能栏、Q/E正式释放特效、UnitBase被动位移迁移和正式场景装配均延后，不把阶段三验收扩成这些任务。

## 全量回归

- 新增两项SceneTree测试后共177项，175通过，2项既有失败：CameraFollowControllerTest正式房间导航未烘焙；SingleSceneFireboltTest旧断言6米与用户配置5米不一致。没有新增失败。
- Effect测试另验证真实状态容器拒绝prepare时，旧状态/2400合计不变，旧到期后仍只留400普通池。
- 干净原生会话重新按E验证后，get_editor_errors返回count=0、errors=[]；先前临时查询三元分支warning未再出现，未修改MCP插件。

## 最终独立review与修正

- 独立review只读对照实施前快照，提出3项Important，均已真实复现RED并修正至GREEN：
  1. 来源死亡误用离树闸门，原地revive后永久拒绝。分离死亡清理与tree_exiting闸门；revive后可重新施加。
  2. 刷新暂存旧状态在外部贡献终止时未登记，失败回滚可能恢复孤立Debuff。暂存旧代保留终止标识，已失效代不可恢复，合并状态通知与真实聚合状态一致。
  3. 回滚资格在清理回调前计算，回调清表后旧判断仍恢复状态。改为回调后重验epoch、来源与代际；清理幂等。
- 三条独立反例先全部失败，修复死亡路径后只剩后两条失败，修复回滚后全部通过；Lifecycle、Effect、Status与WorldHealthBar回归均PASS且无ERROR。
- 加入真实SceneTree暂停/5%慢放测试。最初短0.1秒状态在启动帧切换time_scale前已捕获的补帧delta里到期；夹具改为先越过切换帧再创建状态，12个5%物理帧仅消耗约0.01战斗秒，暂停不推进，恢复正常流速后到期。未改生产时钟或增加补偿规则。
- Reviewer未判断的原生画面/时序、UID和旧suite失败，均由本任务独立原生读取/运行/全量回归验证；不以review未运行当作已验证。没有其他被延后修复的review minor。
- 修正后最终全量177项：175通过，仅CameraFollowControllerTest导航未烘焙及SingleSceneFireboltTest旧距离断言两项既有失败，无新增失败。

## 最终交付确认

- 修正后新原生会话真实按E：accepted/start/release/finish均为1，cancel=0，affected=4，marked=4；Q圈存在、E圈不存在，get_editor_errors count=0/errors=[]。
- 最终Gather源场景与实施前SHA256仍一致。阶段三完成后停止，不推进阶段四、五；没有Git提交/上传，未改MCP插件。
- 执行决定：按既有授权原目录/MCP工作（不创建工作树；若需要隔离须另行指定）；沿用damage_context.skill_id而非不存在的Context字段（直接调用无快照时使用稳定Effect类别）；自动夹具Unsupported远离落盘以隔离普通碰撞（源场景摆放不变）；慢放测试在时间切换启动帧后建立状态（不验证或补偿切换前已捕获的delta）。这些决定不增加游戏规则或策划参数。
