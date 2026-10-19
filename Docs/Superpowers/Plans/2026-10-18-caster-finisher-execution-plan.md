# Caster终结技组装与A/B演出 Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans，按任务测试先行执行。用户已授权接续实施，不另起设计确认循环。

**Goal:** 将已验收的终结动画与焰星连轰四段视觉接入同一套 SkillBase，支持真实选择施放及A/B两种镜头时间体验。
**Architecture:** 扩展现有Arc交付为可配置地面散布，复用原Effects和数值归属；请求级时钟提供正常演出速度。执行组件只协调镜头、慢速和主爆炸完成，不实施伤害。
**Tech Stack:** Godot 4.7、GDScript、强类型Resource、PackedScene、现有InputMap。
**Spec:** Docs/Superpowers/Specs/2026-10-18-caster-finisher-barrage-comparison-design.md；最新动画/美术基线见 Effects/Skills/FlameBarrage/README.md。

## Global Constraints

- 保留当前目录、当前分支及既有未提交修改，不创建新工作树，不自动提交或推送。
- Godot MCP Pro优先编辑，资源必须原生保存、验证UID；所有可配置参数和公开接口具中文说明。
- 不修改用户工作台或动画库。使用用户finish_cast_1：长度0.95s，release≈0.333333s，finish≈0.433333s，非循环。独立正式动作资产从用户片段保存，不重新制作曲线。
- 不向 Scenes/TestScene.tscn 添加或修改单位。
- 五发、间隔0.12s、飞行0.5s、落点半径5m、爆炸半径3m，允许落空及重复覆盖。
- A首颗成功发出恢复；B首颗后恢复战斗角度并移往固定区域，5%世界慢放保持至全部交付及主要爆炸完成。
- 普通技能默认行为不变；伤害、专注、连携评分仍使用现有规则。

## Review Focus

1. 同步释放/完成/退出回调下请求身份不串线，不误释放其他系统token。
2. 菜单真暂停及恢复不补发，B只有本次动画/交付/视觉正常推进。
3. 早finish标记不截断五发；后续普通动作不继承演出速度。
4. 原目标死亡、空地落点、施法者硬中断及控制器删除均可终结。
5. Inspector配置可读，A/B切换只改下次；正式资源UID、原用户动画不变。

## Task 1：请求级时钟与地面弧线交付

**Files:** 新增 SkillSystem/01-Core/SkillExecutionClock.gd、SkillSystem/05-Tests/GroundArcDeliveryTest.gd、SkillExecutionClockTest.gd；修改 SkillContext.gd、ArcProjectileDeliveryConfig.gd、ArcProjectileDeliverySession.gd、SkillDeliveryRunner.gd、Item/Projectiles/TrackingArcProjectile.gd、Effects/Skills/FlameBarrage/FlameBarrageEffectPlayer.gd。
**Interfaces:** SkillContext.execution_clock共享请求级时钟；SkillExecutionClock.get_delta(world_delta, physics=true)和get_presentation_delta提供秒数，use_world_time()安全回退；Arc配置destination_mode、scatter_radius_m、impact_radius_m；投射物launch_point(destination,start_position)，保留launch(unit,start)。Runner emission_finished(context)、impact_presentation_prepared(context,instance)、projectile_launched(context,index,point)、projectile_landed(context,index,point)；stop_pending_emission(request_id)只停未发。
- [x] 写测试并运行确认RED：无地面拒绝；有效地面5点在5米内；空地成功；每颗3米内执行同一DamageEffect；点快照不追原目标；时钟0.05世界下读0.016667而非0.0008333，真暂停为0，副本共享。
- [x] 实现：新增配置默认单位模式，有限次World层垂直投影及sqrt均匀采样，命中使用NearbySkillTargetQuery不限人数、独立SkillHitOutcome。
- [x] 运行新测试及 ArcProjectileDeliveryTest、MultiShotArcDeliveryTest、MultiShotSkillAssemblyTest、PyroblastIntegrationTest，Expected PASS。记录不提交。

## Task 2：统一终结入口与动作接管

**Files:** 新增 SkillCinematicProfile.gd、SkillSystem/05-Tests/FinisherSkillLifecycleTest.gd；修改 SkillContext、SkillBase、SkillHostComponent、SkillPresentationContext、SkillReleasePresentationPlayer、AIAttackController、AllyBehaviorStateMachine。
**Interfaces:** Purpose.FINISHER与FINISHER伤害来源；SkillBase.cinematic_profile可空，get_action_payload携带Animation和请求时钟；Host.prepare_finisher_context及request_finisher沿用目标/条件/范围，预检成功才抢占；带正请求ID的既有动作生命周期；发射完成事实用于动作门闩。
- [x] 测试RED：预检失败不打断原动作；成功终结可覆盖动作且不删旧投射物；FINISHER无专注收益；早finish不使AI插入未发阶段；取消只停未发；普通技能照旧。
- [x] 演出资源只暴露模式、Animation、world_time_scale三项；动作临时库、手动物理推进和deadline使用相同clock，结束恢复原模式。
- [x] 新测试及既有AISkillActionAnimationTest、SkillSlotRoutingTest、AllyChainCommandPriorityTest、SkillPresentationLifecycleTest Expected PASS。

## Task 3：镜头与选择到执行

**Files:** 新增 Effects/Camera/SkillCinematicCameraProfile.gd、SquadFinisherExecutionController.gd/.tscn、UnitSystem/Tests/FinisherCinematicExecutionTest.gd；修改 CameraFollowController.gd、SquadFinisherSelectionController.gd。
**Interfaces:** Camera begin_cinematic、show_cinematic_area、end_cinematic均带施放ID；Execution只引用selection_source和camera_source，从技能取得演出配置；Selection可选执行provider（旧选择接口预览不受影响），提供选择所有权交接方法。
- [x] 测试RED：A首发恢复原倍率与镜头；B首发只改镜头不恢复速度，交付与全部主爆炸结束后恢复；外部慢放/暂停仍持有；相机和组件卸载幂等。
- [x] 相机最终写入仍只在CameraFollowController；保留缩放与投影，区域从5+3半径推导，B返程0.3真实活动秒。
- [x] 新测试及 CameraSkillFocusTest、GameTimeScaleOwnershipTest、SquadFinisherSelectionControllerTest Expected PASS。

## Task 4：内容装配、比较预览与回归

**Files:** 新增 SkillSystem/00-Skills/Finisher_FlameBarrage/FlameBarrageFinisherSkill.tscn、FlameBarrageCinematic.tres、FlameBarrageAction.tres；Item/Projectiles/FlameBarrageProjectile.tscn；Effects/Camera/Presets/FlameBarrageCinematicCamera.tres；Scenes/Previews/SquadFinisherComparisonPreview.gd/.tscn；配置说明与测试。修改Caster源场景及正式测试房的执行组件装配（不修改TestScene单位）。
- [x] 测试RED：正式Caster终结槽有效、资源UID有效、与普通技能无实例共享，真实选择可执行。
- [x] 新投射物只复用通用运动脚本，装配已验收的全新Flight/Impact；DamageEffect初值45+1.25*攻击，沿用现有算法。
- [x] A/B使用同一技能与私有模式快照；比较预览试放走真实Host，局部固定种子、重置、状态计数，不硬编码技能按键。
- [x] 全测试、真实A/B运行、主爆炸完成、真暂停及反复施放检查。已知原有CameraFollowControllerTest因测试房导航网格未烘焙失败单列，不借本任务修改地形。
- [x] 一次独立整体审查，发现重要问题以RED→GREEN修正，记录最终可验证成果与未完成项。

## 完成记录
2026-10-19：四任务完成；完整回归150/151通过，唯一既有导航网格失败单列。独立审查问题已定向RED→GREEN；详见同目录execution-validation.md及技能配置指南。
