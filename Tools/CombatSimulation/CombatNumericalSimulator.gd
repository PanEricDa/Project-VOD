class_name CombatNumericalSimulator
extends RefCounted

## 离线数值模拟器：用于快速比较当前房间敌群强度，不替代真实 AI、导航或命中检测。

const TIME_STEP: float = 0.1
const MAX_DURATION: float = 180.0

## 运行指定数量近战与远程哥布林对理想玩家队伍的蒙特卡洛模拟。
## warrior_count 与 archer_count 是同时激活的敌人数量；trials 至少为 1；seed 保证相同输入得到相同统计。
func run_scenario(warrior_count: int, archer_count: int, trials: int, seed: int = 20260804) -> Dictionary:
	var random := RandomNumberGenerator.new()
	random.seed = seed
	var wins: int = 0
	var total_duration: float = 0.0
	var total_ot: int = 0
	var total_healing: float = 0.0
	var ally_deaths := {"Guardian": 0, "Archer": 0, "Caster": 0, "Priest": 0}
	for trial_index: int in range(maxi(trials, 1)):
		var outcome := _run_trial(warrior_count, archer_count, random)
		if bool(outcome.won):
			wins += 1
		total_duration += float(outcome.duration)
		total_ot += int(outcome.ot_count)
		total_healing += float(outcome.healing)
		for name: String in ally_deaths.keys():
			if bool(outcome.deaths.get(name, false)):
				ally_deaths[name] = int(ally_deaths[name]) + 1
	var safe_trials: float = float(maxi(trials, 1))
	var death_rates := {}
	for name: String in ally_deaths.keys():
		death_rates[name] = float(ally_deaths[name]) / safe_trials
	return {
		"trials": maxi(trials, 1),
		"warriors": maxi(warrior_count, 0),
		"archers": maxi(archer_count, 0),
		"win_rate": float(wins) / safe_trials,
		"average_duration": total_duration / safe_trials,
		"average_ot_count": float(total_ot) / safe_trials,
		"average_healing": total_healing / safe_trials,
		"ally_death_rates": death_rates,
	}


func _run_trial(warrior_count: int, archer_count: int, random: RandomNumberGenerator) -> Dictionary:
	var party := {
		"Hero": _unit(300.0, 12.0, 10.0, 1.0, 5.0, 0.05),
		"Guardian": _unit(450.0, 10.0, 35.0, 1.0, 5.0, 0.05),
		"Archer": _unit(150.0, 17.0, 3.0, 1.0, 5.0, 0.20),
		"Caster": _unit(90.0, 16.0, 2.0, 3.75, 10.0, 0.0),
		"Priest": _unit(250.0, 11.0, 5.0, 999.0, 0.0, 0.0),
	}
	var enemies: Array[Dictionary] = []
	for count: int in range(maxi(warrior_count, 0)):
		enemies.append(_unit(200.0, 5.0, 2.0, 1.3, 5.0, 0.05))
	for count: int in range(maxi(archer_count, 0)):
		enemies.append(_unit(150.0, 3.0, 1.0, 2.0, 3.0, 0.20))
	var threat := {"Hero": 0.0, "Guardian": 0.0, "Archer": 0.0, "Caster": 0.0}
	var enemy_targets: Array[String] = []
	for enemy: Dictionary in enemies:
		enemy_targets.append("Guardian")
	var time := 0.0
	var healing: float = 0.0
	var ot_count: int = 0
	var previous_non_guardian_target: bool = false
	while time < MAX_DURATION and not enemies.is_empty() and _has_living_ally(party):
		var target_enemy := _first_living_enemy(enemies)
		if target_enemy >= 0:
			for attacker_name: String in ["Hero", "Guardian", "Archer", "Caster"]:
				var attacker: Dictionary = party[attacker_name]
				if float(attacker.hp) <= 0.0 or time + 0.0001 < float(attacker.next_attack):
					continue
				var multiplier: float = 1.0
				if attacker_name == "Guardian":
					multiplier = 1.6
				var dealt := _damage(attacker, enemies[target_enemy], random)
				enemies[target_enemy].hp -= dealt
				threat[attacker_name] = float(threat[attacker_name]) + dealt * multiplier
				attacker.next_attack = time + float(attacker.cooldown)
				party[attacker_name] = attacker
				if attacker_name == "Guardian" and time + 0.0001 >= float(attacker.next_skill):
					var skill_damage := _raw_damage(16.0 + float(attacker.attack), enemies[target_enemy], 0.0, random)
					enemies[target_enemy].hp -= skill_damage
					threat.Guardian = float(threat.Guardian) + skill_damage * 1.2
					attacker.next_skill = time + 5.1 + random.randf_range(0.0, 2.0)
					party.Guardian = attacker
				if float(enemies[target_enemy].hp) <= 0.0:
					enemies.remove_at(target_enemy)
					if target_enemy < enemy_targets.size():
						enemy_targets.remove_at(target_enemy)
					break
		var priest: Dictionary = party.Priest
		if float(priest.hp) > 0.0 and time + 0.0001 >= float(priest.next_skill):
			var heal_target := _lowest_living_ally(party)
			if not heal_target.is_empty():
				var receiver: Dictionary = party[heal_target]
				var amount := minf(36.0, float(receiver.max_hp) - float(receiver.hp))
				receiver.hp += amount
				party[heal_target] = receiver
				healing += amount
			priest.next_skill = time + 1.8 + random.randf_range(0.0, 2.0)
			party.Priest = priest
		for index: int in range(enemies.size()):
			var enemy: Dictionary = enemies[index]
			if time + 0.0001 < float(enemy.next_attack):
				continue
			var selected := _highest_threat_living_target(threat, party)
			if selected != "Guardian":
				ot_count += 1
				previous_non_guardian_target = true
			var victim: Dictionary = party[selected]
			victim.hp -= _damage(enemy, victim, random)
			party[selected] = victim
			enemy.next_attack = time + float(enemy.cooldown)
			enemies[index] = enemy
		time += TIME_STEP
	var deaths := {}
	for name: String in ["Guardian", "Archer", "Caster", "Priest"]:
		deaths[name] = float((party[name] as Dictionary).hp) <= 0.0
	return {"won": enemies.is_empty(), "duration": time, "ot_count": ot_count, "healing": healing, "deaths": deaths}


func _unit(max_hp: float, attack: float, defense: float, cooldown: float, base_damage: float, variance: float) -> Dictionary:
	return {"max_hp": max_hp, "hp": max_hp, "attack": attack, "defense": defense, "cooldown": cooldown, "base_damage": base_damage, "variance": variance, "next_attack": 0.0, "next_skill": 0.0}


func _damage(source: Dictionary, target: Dictionary, random: RandomNumberGenerator) -> float:
	return _raw_damage(float(source.base_damage) + float(source.attack), target, float(source.variance), random)


func _raw_damage(raw_damage: float, target: Dictionary, variance: float, random: RandomNumberGenerator) -> float:
	return raw_damage * 100.0 / (100.0 + float(target.defense)) * random.randf_range(1.0 - variance, 1.0 + variance)


func _first_living_enemy(enemies: Array[Dictionary]) -> int:
	for index: int in range(enemies.size()):
		if float(enemies[index].hp) > 0.0:
			return index
	return -1


func _has_living_ally(party: Dictionary) -> bool:
	for name: String in party.keys():
		if name == "Hero" or float((party[name] as Dictionary).hp) > 0.0:
			return true
	return false


func _lowest_living_ally(party: Dictionary) -> String:
	var selected := ""
	var ratio := INF
	for name: String in party.keys():
		var unit: Dictionary = party[name]
		if float(unit.hp) <= 0.0:
			continue
		var value := float(unit.hp) / float(unit.max_hp)
		if value < ratio:
			ratio = value
			selected = name
	return selected


func _highest_threat_living_target(threat: Dictionary, party: Dictionary) -> String:
	var selected := "Guardian"
	var value := -1.0
	for name: String in threat.keys():
		if float((party[name] as Dictionary).hp) <= 0.0:
			continue
		if float(threat[name]) > value:
			value = float(threat[name])
			selected = name
	return selected
