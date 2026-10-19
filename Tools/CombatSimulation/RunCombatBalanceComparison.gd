extends SceneTree
## 正式房间的临时七敌实战对照；只改运行副本的摆放，不保存场景或修改AI/数值。
## --mode=auto/basic/chain，--seconds=45；自动驱动玩家并保留可死亡，结果不是人类操作胜率。
const DRIVER := preload("res://Tools/CombatSimulation/IdealHeroCombatDriver.gd")
var mode := "auto"
var duration := 45.0
var room: Node3D
var heroes: Array[UnitBase] = []
var enemies: Array[UnitBase] = []
var stats: Dictionary = {"ordinary_damage":0.0,"chain_damage":0.0,"incoming_damage":0.0,"healing":0.0,"first_ally_death":-1.0,"chain_requests":[],"chain_releases":[],"rejections":[],"command_failures":[],"by_skill":{},"lowest_hp_ratio":{}}
var elapsed := 0.0

func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--mode="): mode = arg.get_slice("=",1)
		if arg.begins_with("--seconds="): duration = maxf(1.0,arg.get_slice("=",1).to_float())
	call_deferred(&"_run")

func _run() -> void:
	var path := "res://Scenes/Previews/SquadChainRoundPreview.tscn" if mode == "chain" else "res://Scenes/TestCombatRoom.tscn"
	room = (load(path) as PackedScene).instantiate() as Node3D
	var discarded := room.get_node("EnemyContainer/Pack_C")
	discarded.get_parent().remove_child(discarded)
	discarded.free()
	var positions := {"Hero":Vector3.ZERO,"Guardian":Vector3(-0.6,0,-0.7),"Priest":Vector3(-1.5,0,1.5),"Caster":Vector3(0,0,1.7),"Archer":Vector3(1.5,0,1)}
	for unit_name: String in positions:
		var unit := room.get_node(unit_name) as UnitBase
		unit.position = positions[unit_name]
		if unit is AllyBase and mode == "basic":
			unit.automatic_skill_cast_enabled = false

	var index := 0
	for pack: Node3D in room.get_node("EnemyContainer").get_children():
		pack.position = Vector3.ZERO
		for unit: UnitBase in pack.get_children():
			unit.position = Vector3(float(index%3-1)*0.8,0,-3.0-floorf(float(index)/3.0)*0.8)
			index += 1
	# 使用真实 SceneTree 场景切换，保证所有 SkillHost 在 ready 时绑定正确世界。
	var prepared := PackedScene.new()
	prepared.pack(room)
	room.free()
	change_scene_to_packed(prepared)
	await scene_changed
	room = current_scene as Node3D
	for unit_name: String in positions:
		var unit := room.get_node(unit_name) as UnitBase
		unit.damage_resolved.connect(_on_damage)
		unit.healed.connect(_on_healed)
		unit.died.connect(_on_party_death)
		heroes.append(unit)
		stats.lowest_hp_ratio[unit_name] = 1.0
	for pack: Node3D in room.get_node("EnemyContainer").get_children():
		for unit: UnitBase in pack.get_children():
			unit.damage_resolved.connect(_on_damage)
			enemies.append(unit)
	for _step: int in range(4): await physics_frame
	var hero := room.get_node("Hero") as PlayerBase
	var driver := DRIVER.new()
	room.add_child(driver)
	var original_can_die := hero.can_die
	driver.configure(hero)
	hero.can_die = original_can_die
	var commander := room.get_node_or_null("SquadChainCommandController") as SquadChainCommandController
	if commander != null:
		commander.command_failed.connect(func(slot: int, id: int, reason: StringName): stats.command_failures.append({"slot":slot,"id":id,"reason":reason,"time":elapsed}))
		commander.command_rejected.connect(func(slot: int, reason: StringName): stats.rejections.append({"slot":slot,"reason":reason,"time":elapsed}))
		commander.command_released.connect(func(id: int, cost: float): stats.chain_releases.append({"id":id,"cost":cost,"time":elapsed}))
	var schedule := [[1.0,2],[1.5,3],[3.0,2],[3.5,3]]
	var next_request := 0
	var wall_deadline := Time.get_ticks_msec()+int((duration+20.0)*1000)
	var outcome := "time_limit"
	while elapsed < duration and Time.get_ticks_msec() < wall_deadline:
		await physics_frame
		if hero.is_dead():
			outcome = "hero_dead"
			break
		if _enemy_hp() <= 0.0:
			outcome = "cleared"
			break
		if paused: continue
		elapsed += 1.0/float(Engine.physics_ticks_per_second)
		for unit: UnitBase in heroes:
			stats.lowest_hp_ratio[unit.name] = minf(stats.lowest_hp_ratio[unit.name],unit.get_health_ratio())
		if mode == "chain" and next_request < schedule.size() and elapsed >= schedule[next_request][0]:
			var slot: int = schedule[next_request][1]
			var accepted := commander.submit_slot(slot)
			stats.chain_requests.append({"slot":slot,"time":elapsed,"accepted":accepted,"status":commander.get_slot_status(slot)})
			next_request += 1
	stats["mode"] = mode
	stats["duration"] = elapsed
	stats["outcome"] = outcome
	stats["enemy_hp_start"] = 3200.0
	stats["enemy_hp_remaining"] = _enemy_hp()
	stats["chain_hp_fraction"] = stats.chain_damage/3200.0
	stats["party_final"] = {}
	for unit: UnitBase in heroes:
		stats.party_final[unit.name] = unit.get_current_health()
	var focus := room.get_node("SquadFocusComponent") as SquadFocusComponent
	stats["focus_final"] = focus.get_current_focus()
	if commander != null:
		stats["round"] = room.get_node("SquadChainRoundController").get_round_status()
	print("CombatBalanceComparison: "+JSON.stringify(stats))
	paused = false
	driver.set_physics_process(false)
	room.get_node("EncounterController").begin_scene_unload()
	current_scene = null
	room.queue_free()
	for _step: int in range(4): await process_frame
	quit(0)

## event 为单位统一发布的实际扣血快照；只统计来源，不推测当前活动技能。
func _on_damage(event: CombatDamageEvent) -> void:
	if event.target_team_id == 2 and event.source_team_id == 1:
		if event.origin == CombatDamageContext.Origin.CHAIN:
			stats.chain_damage += event.actual_damage
		else:
			stats.ordinary_damage += event.actual_damage
		var key := String(event.skill_id) if not event.skill_id.is_empty() else "basic"
		stats.by_skill[key] = float(stats.by_skill.get(key,0.0))+event.actual_damage
	elif event.target_team_id == 1 and event.source_team_id == 2:
		stats.incoming_damage += event.actual_damage

## amount 为实际恢复生命；source 仅为统一信号约定，不参与推测治疗技能。
func _on_healed(amount: float, _source: Node) -> void:
	stats.healing += amount

## source 为致死来源；仅记录首次队伍死亡时间。
func _on_party_death(_source: Node) -> void:
	if stats.first_ally_death < 0.0:
		stats.first_ally_death = elapsed

func _enemy_hp() -> float:
	var total := 0.0
	for unit: UnitBase in enemies:
		if is_instance_valid(unit):
			total += unit.get_current_health()
	return total
