extends SceneTree
## 基础平衡验收：正式单位/技能实际扣血与治疗、武器隔离、整条专注的理想伤害预算。
## 不覆盖 TestScene 单位，不把理想全命中预算当作真实 AI 清场时间。
var failures: Array[String] = []
var world: Node3D
var party: Dictionary = {}

func _initialize() -> void:
	call_deferred(&"_run")

func _run() -> void:
	world = Node3D.new()
	root.add_child(world)
	for row: Array in [
		["Hero","res://UnitSystem/Player/Hero/Hero.tscn",300.0],
		["Guardian","res://UnitSystem/AI/Ally/Units/Guardian.tscn",650.0],
		["Archer","res://UnitSystem/AI/Ally/Units/Archer.tscn",240.0],
		["Caster","res://UnitSystem/AI/Ally/Units/Caster.tscn",220.0],
		["Priest","res://UnitSystem/AI/Ally/Units/Priest.tscn",260.0],
		["GoblinWarrior","res://UnitSystem/AI/Enemy/Units/GoblinWarrior.tscn",500.0],
		["GoblinArcher","res://UnitSystem/AI/Enemy/Units/GoblinArcher.tscn",350.0],
	]:
		var unit := (load(row[1]) as PackedScene).instantiate() as UnitBase
		unit.set_physics_process(false)
		world.add_child(unit)
		unit.set_physics_process(false)
		party[row[0]] = unit
		_expect(is_equal_approx(unit.get_current_health(),row[2]), "source scene initializes agreed health: "+row[0])
	var dummy := UnitBase.new()
	dummy.maximum_health = 10000.0
	dummy.team_id = 2
	world.add_child(dummy)
	for row: Array in [["Hero",6.0],["Guardian",4.0],["Archer",5.6],["Caster",6.0],["Priest",4.75],["GoblinWarrior",11.0],["GoblinArcher",7.0]]:
		var source: UnitBase = party[row[0]]
		var weapon: WeaponData = source.get("starting_weapon")
		var actual := CombatValueResolver.apply_damage(source,dummy,weapon.basic_attack_base_damage,weapon.basic_attack_power_ratio)
		_expect(is_equal_approx(actual,row[1]), "real basic damage follows role budget: "+row[0])
	var hero_weapon: WeaponData = party.Hero.get("starting_weapon")
	var enemy_weapon: WeaponData = party.GoblinWarrior.get("starting_weapon")
	_expect(hero_weapon != enemy_weapon and hero_weapon.resource_path != enemy_weapon.resource_path, "enemy basic damage is isolated from player sword tuning")
	var enemy_weapon_path := "res://Item/Weapon/Sword/GoblinSwordData.tres"
	_expect(ResourceLoader.exists(enemy_weapon_path) and ResourceLoader.get_resource_uid(enemy_weapon_path) != ResourceUID.INVALID_ID, "new enemy weapon has registered UID")
	if ResourceLoader.exists(enemy_weapon_path):
		_expect(load(enemy_weapon_path) is MeleeWeaponData, "enemy weapon remains Inspector-compatible MeleeWeaponData")
	for row: Array in [
		["Caster","FireboltSkill",40.0],["Caster","PyroblastSkill",65.0],
		["Caster","ComboFireboltSkill",48.0],["Archer","RapidShotSkill",10.5],
		["Archer","ComboRapidShotSkill",12.6],["Archer","ExplosiveArrowSkill",24.5],
		["Guardian","GuardianShieldSkill",20.0],["Guardian","ComboGuardianBashSkill",24.0],
	]:
		var source: UnitBase = party[row[0]]
		var skill: SkillBase = source.get_node("SkillHost/SkillSocket/"+row[1])
		var effect := skill.get_node("DamageEffect") as HealthChangeSkillEffect
		_expect(is_equal_approx(_apply_effect(effect,source,dummy),row[2]), "real skill damage: "+row[1])
	for row: Array in [["GuardianShieldSkill",24.0],["ComboGuardianBashSkill",28.8]]:
		var skill: SkillBase = party.Guardian.get_node("SkillHost/SkillSocket/"+row[0])
		var payload := skill.get_action_payload()
		var actual := CombatValueResolver.apply_damage(party.Guardian,dummy,payload.base_damage,payload.power_ratio,payload.damage_multiplier)
		_expect(is_equal_approx(actual,row[1]), "melee action damage included separately: "+row[0])
	for row: Array in [["Trig_ExplosiveFragment/ExplosiveFragmentSkill",7.0],["Trig_BurningSplash/BurningSplashSkill",3.5]]:
		var skill := (load("res://SkillSystem/00-Skills/"+row[0]+".tscn") as PackedScene).instantiate()
		world.add_child(skill)
		_expect(is_equal_approx(_apply_effect(skill.get_node("DamageEffect"),party.Archer,dummy),row[1]), "trigger damage keeps archer hit-count identity")
		skill.free()
	dummy.team_id = 1
	for row: Array in [["HolyLightSkill",38.2],["GreaterHealSkill",150.0],["ComboGreaterHealSkill",300.0]]:
		var skill: SkillBase = party.Priest.get_node("SkillHost/SkillSocket/"+row[0])
		var context := SkillContext.new()
		context.caster = party.Priest
		# 连携伤害下调后原累计缺血不足300；各治疗样例独立制造缺口，避免过量治疗截断断言。
		dummy.apply_damage(1000.0)
		var before := dummy.get_current_health()
		skill.get_node("HealEffect").apply(context,null,dummy)
		_expect(is_equal_approx(dummy.get_current_health()-before,row[1]), "real healing preserves sustained pressure: "+row[0])
	_test_chain_damage_ratio()
	_test_full_focus_damage_budget()
	_test_scene_overrides()
	world.free()
	await process_frame
	for failure: String in failures:
		push_error(failure)
	if failures.is_empty():
		print("CombatBalanceBaselineTest: PASS")
	quit(0 if failures.is_empty() else 1)

## effect/source/target 为已装配的真实效果与单位；返回实际生命差，不读取面板作为断言结果。
func _apply_effect(effect: HealthChangeSkillEffect, source: UnitBase, target: UnitBase) -> float:
	var context := SkillContext.new()
	context.caster = source
	var before := target.get_current_health()
	effect.apply(context,null,target)
	return before-target.get_current_health()

## 不同攻击力/防御下验证连携实际扣血恒为对应普通伤害1.2倍，避免只调平当前面板。
func _test_chain_damage_ratio() -> void:
	var target := UnitBase.new()
	target.team_id = 2
	target.maximum_health = 100000.0
	world.add_child(target)
	for row: Array in [
		["Caster","FireboltSkill","ComboFireboltSkill"],
		["Archer","RapidShotSkill","ComboRapidShotSkill"],
		["Guardian","GuardianShieldSkill","ComboGuardianBashSkill"],
	]:
		var actor: UnitBase = party[row[0]]
		var original_attack := actor.attack_power
		var normal: SkillBase = actor.get_node("SkillHost/SkillSocket/"+row[1])
		var combo: SkillBase = actor.get_node("SkillHost/SkillSocket/"+row[2])
		for attack: float in [0.0,10.0,60.0]:
			actor.attack_power = attack
			for defense: float in [0.0,35.0,100.0]:
				target.defense = defense
				var normal_damage := _apply_effect(normal.get_node("DamageEffect"),actor,target)
				var chain_damage := _apply_effect(combo.get_node("DamageEffect"),actor,target)
				_expect(is_equal_approx(chain_damage,normal_damage*1.2), "damage effect ratio stays1.2 through attack/armor changes: "+row[2])
				if row[0] == "Guardian":
					var normal_action := normal.get_action_payload()
					var combo_action := combo.get_action_payload()
					normal_damage = CombatValueResolver.apply_damage(actor,target,normal_action.base_damage,normal_action.power_ratio,normal_action.damage_multiplier)
					chain_damage = CombatValueResolver.apply_damage(actor,target,combo_action.base_damage,combo_action.power_ratio,combo_action.damage_multiplier)
					_expect(is_equal_approx(chain_damage,normal_damage*1.2), "melee action damage ratio stays1.2 through attack/armor changes")
		actor.attack_power = original_attack
	target.free()

func _test_full_focus_damage_budget() -> void:
	var total := 0.0
	for index: int in range(7):
		var target := UnitBase.new()
		target.team_id = 2
		target.defense = 2.0 if index < 5 else 1.0
		target.maximum_health = 500.0 if index < 5 else 350.0
		world.add_child(target)
		var fire: HealthChangeSkillEffect = party.Caster.get_node("SkillHost/SkillSocket/ComboFireboltSkill/DamageEffect")
		total += _apply_effect(fire,party.Caster,target)
		total += _apply_effect(fire,party.Caster,target)
		# 两次连射选择不同的近战目标，排除过量伤害；每次仍为原三箭，不虚增命中。
		if index < 2:
			var arrow: HealthChangeSkillEffect = party.Archer.get_node("SkillHost/SkillSocket/ComboRapidShotSkill/DamageEffect")
			for _shot: int in range(3):
				total += _apply_effect(arrow,party.Archer,target)
		target.free()
	_expect(is_equal_approx(total,734.8048922539), "full-focus budget uses ordinary damage times1.2 rather than obsolete70-80% target")
	print("CombatBalanceBudget: damage=",total," percent=",100.0*total/3200.0)

func _test_scene_overrides() -> void:
	var scene := (load("res://Scenes/Previews/SquadChainRoundPreview.tscn") as PackedScene).instantiate()
	_expect(is_equal_approx(scene.get_node("Hero").maximum_health,300.0), "preview player HP remains consistent")
	var focus := scene.get_node("SquadFocusComponent") as SquadFocusComponent
	_expect(is_equal_approx(focus.focus_gain_difficulty,3.0), "preview preserves current player-authored focus difficulty3")
	var score := scene.get_node("SquadChainRoundController") as SquadChainRoundController
	_expect(is_equal_approx(score.score_difficulty,2.0) and score.hit_score_scale == 20, "player-authored score difficulty and hit scale preserved")
	_expect(is_equal_approx(score.damage_score_scale,2000.0) and is_equal_approx(score.damage_interval_seconds,2.5), "score damage scale follows higher chain damage without changing window")
	scene.free()

## ok 为真实行为是否满足约束；message 只用于失败定位。
func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
