extends SceneTree
## 真实数值/状态/仇恨与触发子技能；捕捉只放大基础值、漏传倍率或子技能复利。
var failures: Array[String] = []
var world: Node3D
var caster: UnitBase
var context: SkillContext
func _initialize() -> void: call_deferred("_run")
func _run() -> void:
	var probe := SkillEffectBase.new()
	var ready := probe.has_method("scale_effect_value") and probe.get("use_finisher_bonus") != null
	_expect(ready,"EffectBase exposes inherited opt-in and scaling method")
	probe.free()
	context = SkillContext.new()
	_expect(context.get("finisher_multiplier") != null,"request context carries default finisher multiplier")
	var round_script = load("res://UnitSystem/Components/Combat/Squad/SquadChainRoundController.gd")
	_expect(round_script.has_method("calculate_finisher_multiplier"),"round provider owns reward curve")
	if not ready or context.get("finisher_multiplier")==null or not round_script.has_method("calculate_finisher_multiplier"):
		_finish()
		return
	for row in [[100.0,1.0],[110.0,1.0906346235],[125.0,1.1967346701],[150.0,1.3160602794],[200.0,1.4323323584],[300.0,1.4908421806],[1000000.0,1.5]]:
		_expect(absf(round_script.calculate_finisher_multiplier(row[0])-row[1])<0.000001,"reward curve sample "+str(row[0]))
	for bad in [-1.0,NAN,INF]:
		_expect(round_script.calculate_finisher_multiplier(bad)==1.0,"invalid or subthreshold score is neutral")
	_expect(context.finisher_multiplier==1.0,"ordinary context is neutral")
	context.finisher_multiplier=1.5
	var copy = context.duplicate_context()
	context.finisher_multiplier=1.1
	_expect(copy.finisher_multiplier==1.5,"context copy freezes multiplier without sharing field")
	context=copy
	world=Node3D.new()
	root.add_child(world)
	current_scene=world
	caster=_unit(1,Vector3.ZERO)
	caster.attack_power=20.0
	context.caster=caster
	context.delivery_parent=world
	context.damage_context=CombatDamageContext.create(caster,world,CombatDamageContext.Origin.FINISHER)
	_test_health()
	_test_modifiers()
	_test_threat()
	await _test_trigger()
	world.free()
	current_scene=null
	await process_frame
	_finish()
func _test_health() -> void:
	var target := _unit(2,Vector3(30,0,0))
	target.defense=100
	var effect := HealthChangeSkillEffect.new()
	world.add_child(effect)
	effect.operation=HealthChangeSkillEffect.Operation.DAMAGE
	effect.base_amount=10
	effect.power_ratio=2
	var before := target.get_current_health()
	_expect(effect.apply(context,null,target),"default damage applies")
	_expect(is_equal_approx(before-target.get_current_health(),25.0),"off switch preserves base+power and armor")
	effect.use_finisher_bonus=true
	before=target.get_current_health()
	effect.apply(context,null,target)
	_expect(is_equal_approx(before-target.get_current_health(),37.5),"enabled damage scales full value once before original armor")
	effect.operation=HealthChangeSkillEffect.Operation.HEAL
	before=target.get_current_health()
	effect.apply(context,null,target)
	_expect(is_equal_approx(target.get_current_health()-before,62.5),"healing clamps to actual missing health")
	target.apply_damage(500,caster)
	before=target.get_current_health()
	effect.apply(context,null,target)
	_expect(is_equal_approx(target.get_current_health()-before,75.0),"healing scales full value once without armor")
	var ordinary := SkillContext.new()
	ordinary.caster=caster
	before=target.get_current_health()
	effect.apply(ordinary,null,target)
	_expect(is_equal_approx(target.get_current_health()-before,50.0),"enabled effect with ordinary context stays neutral")
	_expect(effect.base_amount==10 and effect.power_ratio==2,"runtime reward does not mutate static damage configuration")
	effect.free()
func _test_modifiers() -> void:
	var target := _unit(2,Vector3(35,0,0))
	target.defense=100
	var effect := StatModifierSkillEffect.new()
	world.add_child(effect)
	effect.target_mode=StatModifierSkillEffect.TargetMode.DELIVERY_TARGET
	effect.modifier_mode=StatModifierSkillEffect.ModifierMode.PERCENT
	effect.amount=-25
	effect.duration_seconds=5
	effect.apply(context,null,target)
	_expect(is_equal_approx(target.get_defense(),75.0),"modifier switch off remains independent of damage")
	target.get_status_effect_component().advance_effects(5.1)
	effect.use_finisher_bonus=true
	effect.apply(context,null,target)
	_expect(is_equal_approx(target.get_defense(),62.5),"negative modifier preserves sign and scales magnitude")
	target.get_status_effect_component().advance_effects(5.1)
	_expect(is_equal_approx(target.get_defense(),100.0),"duration stays five seconds and cleanup restores base")
	effect.modifier_stat=StatModifierSkillEffect.ModifierStat.OUTGOING_DAMAGE
	effect.amount=30
	effect.apply(context,null,target)
	_expect(is_equal_approx(target.get_outgoing_damage_multiplier(),1.45),"positive blessing scales percentage points")
	_expect(effect.amount==30 and effect.duration_seconds==5,"modifier configuration stays unchanged")
	effect.free()
func _test_threat() -> void:
	var enemy := load("res://UnitSystem/AI/Enemy/Units/GoblinWarrior.tscn").instantiate() as EnemyBase
	world.add_child(enemy)
	enemy.set_physics_process(false)
	enemy.position=Vector3(40,0,0)
	var effect := ThreatChangeSkillEffect.new()
	world.add_child(effect)
	effect.threat_amount=100
	effect.use_finisher_bonus=true
	var threat := enemy.get_threat_component() as EnemyThreatComponent
	_expect(effect.apply(context,null,enemy),"scaled permanent threat applies")
	_expect(is_equal_approx(threat.get_threat_for(caster),150.0),"permanent threat scales once")
	effect.duration_seconds=3
	_expect(effect.apply(context,null,enemy),"scaled temporary contribution applies")
	_expect(is_equal_approx(threat.get_threat_for(caster),300.0),"temporary contribution scales without multiplying existing pool")
	enemy.get_status_effect_component().advance_effects(3.1)
	_expect(is_equal_approx(threat.get_threat_for(caster),150.0),"expiry removes scaled contribution only and keeps original duration")
	_expect(effect.threat_amount==100,"threat source amount is not overwritten")
	effect.free()
	enemy.free()
func _test_trigger() -> void:
	var hit := _unit(2,Vector3(2,0,0))
	var nearby := _unit(2,Vector3(3,0,0))
	await physics_frame
	await physics_frame
	var trigger := TriggerSkillEffect.new()
	world.add_child(trigger)
	trigger.max_targets=1
	trigger.radius_m=2
	var result := SkillDeliveryResult.new()
	result.current_hit=SkillHitOutcome.new()
	result.current_hit.target=hit
	result.current_hit.impact_position=hit.global_position
	result.current_hit.actual_damage=10
	trigger.child_skill_scene=_child_scene(true)
	var before := nearby.get_current_health()
	_expect(trigger.apply(context,result,hit),"trigger passes through reward context")
	_expect(is_equal_approx(before-nearby.get_current_health(),6.0),"child inherits1.5 once even though child purpose is REGULAR")
	await process_frame
	trigger.use_finisher_bonus=true
	trigger.child_skill_scene=_child_scene(false)
	before=nearby.get_current_health()
	trigger.apply(context,result,hit)
	_expect(is_equal_approx(before-nearby.get_current_health(),4.0),"child opt-out remains independent of parent trigger switch")
	await process_frame
	trigger.free()
func _child_scene(enabled: bool) -> PackedScene:
	var skill := load("res://SkillSystem/01-Core/SkillBase.tscn").instantiate() as SkillBase
	skill.skill_id=&"reward_child_probe"
	skill.skill_cooldown=0
	skill.cast_range=10
	skill.delivery=InstantTargetDeliveryConfig.new()
	var damage := HealthChangeSkillEffect.new()
	damage.operation=HealthChangeSkillEffect.Operation.DAMAGE
	damage.base_amount=4
	damage.use_finisher_bonus=enabled
	skill.add_child(damage)
	damage.owner=skill
	var packed := PackedScene.new()
	_expect(packed.pack(skill)==OK,"child packs with inherited switch")
	skill.free()
	return packed
func _unit(team: int, at: Vector3) -> UnitBase:
	var unit := load("res://UnitSystem/Base/00_UnitBase.tscn").instantiate() as UnitBase
	unit.team_id=team
	unit.maximum_health=10000
	unit.collision_layer=2 if team==1 else 4
	world.add_child(unit)
	unit.position=at
	unit.defense=0
	return unit
func _expect(ok: bool,message: String) -> void:
	if not ok: failures.append(message)
func _finish() -> void:
	for message in failures: printerr("FAIL: ",message)
	print("FinisherRewardEffectTest: ","PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
