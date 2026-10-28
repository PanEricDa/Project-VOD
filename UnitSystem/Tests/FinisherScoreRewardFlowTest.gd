extends SceneTree
## 真实闭窗与选择快照、正式终结接线和重新开始；不伪造达分/资格信号。
const F = preload("res://UnitSystem/Tests/SquadFinisherSelectionControllerTest.gd")
const W = preload("res://UnitSystem/Tests/SquadChainRoundWindowTest.gd")
var failures: Array[String] = []
func _initialize() -> void: call_deferred("_run")
func _run() -> void:
	await _test_closed_snapshot()
	await _test_real_execution()
	for message in failures: printerr("FAIL: ",message)
	print("FinisherScoreRewardFlowTest: ","PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
func _test_closed_snapshot() -> void:
	var f := F.make_selection_fixture(root)
	f.round.hit_score_scale=1
	f.round.damage_score_scale=500
	f.round.score_difficulty=10.0/3.0
	await physics_frame
	var request := W.start_released(f)
	W.deal(f,request,500)
	_expect(is_equal_approx(f.round.get_round_status().score,150.0),"fixture reaches150 from real damage and configured H/D")
	W.advance(f,2.000001)
	var result: Dictionary = f.round.get_round_status().last_result
	_expect(absf(float(result.get("finisher_multiplier",1))-1.3160602794)<0.000001,"closed result carries150-score reward")
	var status: Dictionary = f.selection.get_selection_status()
	_expect(absf(float(status.get("finisher_multiplier",1))-1.3160602794)<0.000001,"selection freezes original round multiplier")
	result["finisher_multiplier"]=999.0
	f.round.score_difficulty=0.1
	var chosen: Array = []
	f.selection.finisher_selected.connect(func(value): chosen.append(value))
	_expect(f.selection.try_select_slot(0),"real qualified choice accepted")
	_expect(chosen.size()==1 and absf(float(chosen[0].get("finisher_multiplier",1))-1.3160602794)<0.000001,"choice keeps closed snapshot despite later edits")
	f.selection.cancel_selection(&"reward_cleanup")
	_expect(f.selection.get_selection_status().get("finisher_multiplier",1)==1.0,"closing clears reward snapshot")
	f.world.free()
	await process_frame
func _test_real_execution() -> void:
	var scene := load("res://Scenes/Previews/SquadFinisherComparisonPreview.tscn").instantiate() as Node3D
	root.add_child(scene)
	current_scene=scene
	for i in range(4): await process_frame
	await physics_frame
	var actor := scene.get_node("Battle/Caster") as AllyBase
	var host := actor.get_node("SkillHost") as SkillHostComponent
	var command := scene.get_node("Battle/SquadChainCommandController") as SquadChainCommandController
	var evaluator := scene.get_node("Battle/SquadChainRoundController") as SquadChainRoundController
	var selection := scene.get_node("Battle/SquadFinisherSelectionController") as SquadFinisherSelectionController
	var execution := scene.get_node("Battle/SquadFinisherExecutionController") as SquadFinisherExecutionController
	var focus := scene.get_node("Battle/SquadFocusComponent") as SquadFocusComponent
	scene.reset_preview()
	focus.initial_focus=100
	focus.reset_focus()
	evaluator.score_difficulty=0.1
	evaluator.damage_score_scale=1
	_expect(command.submit_slot(2),"real Caster combo admitted")
	await _wait(func(): return selection.get_selection_status().phase in [1,2],6.0)
	var result: Dictionary=evaluator.get_round_status().last_result
	_expect(result.get("qualified",false),"real combo damage closes qualified round")
	var reward: float=result.get("finisher_multiplier",1.0)
	_expect(reward>1.49 and reward<=1.5,"high score safely approaches1.5 instead of unlimited reward")
	var captures: Array[float]=[]
	var skill := host.get_finisher_skill()
	skill.delivery_started.connect(func(ctx): captures.append(float(ctx.get("finisher_multiplier") if ctx.get("finisher_multiplier")!=null else 1.0)))
	_expect(selection.try_select_slot(2),"actual choice hands off to finisher execution")
	var pending := execution.get("_pending_context") as SkillContext
	_expect(pending!=null and is_equal_approx(float(pending.get("finisher_multiplier") if pending.get("finisher_multiplier")!=null else 1.0),reward),"selection reward enters prepared execution context")
	await _wait(func(): return execution.get_execution_status().phase==&"idle",6.0)
	_expect(captures.size()==1 and is_equal_approx(captures[0],reward),"Host/SkillBase copies preserve reward until actual delivery")
	_expect(execution.get_execution_status().launched==5 and execution.get_execution_status().landed==5,"reward does not change projectile count or delivery completion")
	scene.reset_preview()
	_expect(execution.begin_finisher(actor,171018,1),"direct preview remains callable without extra parameters")
	pending=execution.get("_pending_context") as SkillContext
	_expect(pending!=null and pending.get("finisher_multiplier")==1.0,"next direct preview starts neutral instead of leaking previous reward")
	execution.cancel_execution(&"reward_preview_cleanup")
	for entry in [
		["res://SkillSystem/00-Skills/Finisher_FlameBarrage/FlameBarrageFinisherSkill.tscn","DamageEffect"],
		["res://SkillSystem/00-Skills/Finisher_ArcherPowerShot/ArcherPowerShotFinisherSkill.tscn","DamageEffect"],
		["res://SkillSystem/00-Skills/Finisher_GuardianArmorBreak/GuardianArmorBreakFinisherSkill.tscn","DamageEffect"],
		["res://SkillSystem/00-Skills/Finisher_GuardianArmorBreak/GuardianArmorBreakFinisherSkill.tscn","ArmorBreakEffect"],
		["res://SkillSystem/00-Skills/Finisher_HolyBlessing/HolyBlessingFinisherSkill.tscn","DamageBlessingEffect"]]:
		var configured = load(entry[0]).instantiate()
		_expect(configured.get_node(entry[1]).get("use_finisher_bonus")==true,"formal main effect opts in: "+entry[1]+" "+entry[0])
		configured.free()
	scene.free()
	current_scene=null
	await process_frame
	_expect(Engine.time_scale==1.0 and not paused,"cleanup leaves normal time and no pause")
func _wait(predicate: Callable, seconds: float) -> void:
	var end := Time.get_ticks_usec()+int(seconds*1000000)
	while not predicate.call() and Time.get_ticks_usec()<end: await process_frame
func _expect(ok: bool,message: String) -> void:
	if not ok: failures.append(message)
