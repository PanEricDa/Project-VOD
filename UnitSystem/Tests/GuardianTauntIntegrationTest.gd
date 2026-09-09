extends SceneTree

## Guardian 范围仇恨技能的真实场景端到端验证：
## 装配契约（guardian_taunt 与 guardian_shield_bash 并存）、真实施放链路、
## 精确范围交付（0.6/5.0 命中、5.1 排除）、固定 200 仇恨、既有接管规则不被强制、
## 长冷却启动与既有 S 形衰减。
## Guardian 根物理被关闭以排除其近战与行为系统对仇恨表的污染；
## 技能施放与交付由 SkillBase 自身的施法计时器驱动，与根物理无关。

const GUARDIAN_SCENE_PATH := "res://UnitSystem/AI/Ally/Units/Guardian.tscn"
const ENEMY_SCENE_PATH := "res://UnitSystem/AI/Enemy/EnemyBase.tscn"
const UNIT_SCENE_PATH := "res://UnitSystem/Base/00_UnitBase.tscn"

var _failures: Array[String] = []


class CandidateProvider:
	extends Node

	var candidates: Array[Node3D] = []

	func get_perceived_candidates(
		_maximum_distance: float = -1.0
	) -> Array[Node3D]:
		return candidates.duplicate()


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	var guardian := (
		(load(GUARDIAN_SCENE_PATH) as PackedScene).instantiate() as AllyBase
	)
	_expect(guardian != null, "Guardian scene instantiates")
	if guardian == null:
		_finish()
		return
	guardian.gravity_multiplier = 0.0
	guardian.movement_speed = 0.0
	guardian.attack_power = 0.0
	# 普攻伤害仍来自武器基础值；换装零伤害武器副本（保留动画库，供 basic_cast_1 使用），
	# 使任何路径的普攻都结算为 0 伤害，其威胁事件因基础量非正被既有校验拒绝。
	if guardian.starting_weapon is WeaponData:
		var zero_damage_weapon := (guardian.starting_weapon as WeaponData).duplicate() as WeaponData
		zero_damage_weapon.basic_attack_base_damage = 0.0
		guardian.starting_weapon = zero_damage_weapon
	guardian.automatic_skill_cast_enabled = false
	guardian.position = Vector3.ZERO
	root.add_child(guardian)
	# Guardian 的保护/编队行为需要 Player 阵营锚点单位才会进入可自动施法的战斗状态。
	var player_anchor := (
		(load(UNIT_SCENE_PATH) as PackedScene).instantiate() as UnitBase
	)
	player_anchor.name = &"GuardianTauntPlayerAnchor"
	player_anchor.faction_id = "Player"
	player_anchor.team_id = 1
	# 全部夹具保持默认碰撞（敌方感知依赖物理层），但通过布局保证胶囊体互不重叠，
	# 避免物理推挤使施法距离与半径判定漂移。
	player_anchor.position = Vector3(-1.5, 0.0, 0.0)
	root.add_child(player_anchor)

	# EnemyA 是触发目标：0.75 米在 0.8 施法距离内且大于胶囊最小分离 0.7，不产生推挤。
	# EnemyB 用对角位 (3,4)：水平距离恰为 5.0 的同时与其他单位保持空间分离。
	var enemy_a := _make_enemy("EnemyA", Vector3(0.75, 0.0, 0.0))
	var enemy_b := _make_enemy("EnemyB", Vector3(3.0, 0.0, 4.0))
	var enemy_c := _make_enemy("EnemyC", Vector3(5.1, 0.0, 0.0))
	var enemy_d := _make_enemy("EnemyD", Vector3(0.0, 0.0, 2.5))
	var existing_source := (
		(load(UNIT_SCENE_PATH) as PackedScene).instantiate() as UnitBase
	)
	existing_source.team_id = 1
	# 保持在敌方感知范围内（作为既有仇恨的当前目标）同时与所有单位无胶囊重叠。
	existing_source.position = Vector3(0.0, 0.0, 3.5)
	root.add_child(existing_source)
	await physics_frame
	await physics_frame

	var host := guardian.get_node_or_null(^"SkillHost") as SkillHostComponent
	_expect(host != null, "Guardian exposes its SkillHost")
	if host == null:
		await _cleanup(guardian, [enemy_a, enemy_b, enemy_c, enemy_d], existing_source, player_anchor)
		return
	host.configure_owner(guardian, root)
	var skill := _find_registered_skill(host, &"guardian_taunt")
	_expect(skill != null, "Guardian registers the area threat skill")
	_expect(
		_find_registered_skill(host, &"guardian_shield_bash") != null,
		"Guardian keeps Shield Bash"
	)
	if skill == null:
		await _cleanup(guardian, [enemy_a, enemy_b, enemy_c, enemy_d], existing_source, player_anchor)
		return

	var provider := CandidateProvider.new()
	provider.candidates = [enemy_a, enemy_b, enemy_c, enemy_d]
	guardian.add_child(provider)
	host.set_target_candidate_provider(provider)

	var threat_a := enemy_a.get_threat_component()
	var threat_b := enemy_b.get_threat_component()
	var threat_c := enemy_c.get_threat_component()
	var threat_d := enemy_d.get_threat_component()
	_expect(
		threat_a != null and threat_b != null
			and threat_c != null and threat_d != null,
		"enemy fixtures expose their threat components"
	)
	if threat_a == null or threat_b == null or threat_c == null or threat_d == null:
		await _cleanup(guardian, [enemy_a, enemy_b, enemy_c, enemy_d], existing_source, player_anchor)
		return

	# 断言阶段冻结既有 S 形衰减，保证固定仇恨值可精确读出；衰减契约在末尾单独验证。
	for threat_component: Node in [threat_a, threat_b, threat_c, threat_d]:
		threat_component.set("threat_half_life", 1000000000.0)

	threat_a.call(
		"submit_threat",
		ThreatEvent.create_damage(existing_source, 150.0)
	)
	threat_b.call(
		"submit_threat",
		ThreatEvent.create_damage(existing_source, 150.0)
	)
	threat_d.call(
		"submit_threat",
		ThreatEvent.create_damage(existing_source, 250.0)
	)
	await physics_frame
	await physics_frame

	# 敌方索敌先按既有仇恨锁定来源单位，作为接管断言的非空洞前提。
	enemy_a.get_targeting_component().refresh_target()
	enemy_d.get_targeting_component().refresh_target()
	_expect(
		enemy_a.get_targeting_component().get_locked_target() == existing_source,
		"EnemyA initially locks the existing threat source"
	)
	_expect(
		enemy_d.get_targeting_component().get_locked_target() == existing_source,
		"EnemyD initially locks the higher existing threat source"
	)

	# 走与 Priest 自动化先例一致的完整自动链：策略切到“技能优先、技能可用期间不普攻”，
	# 行为机把动作请求转交 AICombatSystem 的真实动画标记完成交付；
	# 普攻伤害不会经结算器混入敌人的 Guardian 仇恨行。
	guardian.combat_action_policy = 2
	guardian.set_automatic_skill_cast_enabled(true)
	# 巨大半衰期下固定 200 仍会以每帧约 1e-9 的幅度缓慢衰减，
	# 检测阈值取 199.0 以覆盖浮点尾差，精确值由后续 is_equal_approx 断言把关。
	var delivered: bool = false
	for _frame: int in range(480):
		if float(threat_a.call(&"get_threat_for", guardian)) >= 199.0:
			delivered = true
			break
		await physics_frame
	_expect(delivered, "the skill delivers through the real automatic cast chain")
	# 交付后给敌人索敌一个确定的重解析点，接管断言不依赖索敌刷新节奏。
	await physics_frame
	await physics_frame
	enemy_a.get_targeting_component().refresh_target()
	enemy_d.get_targeting_component().refresh_target()

	_expect(
		is_equal_approx(
			float(threat_a.call(&"get_threat_for", guardian)),
			200.0
		),
		"EnemyA receives exactly 200 Guardian threat"
	)
	_expect(
		is_equal_approx(
			float(threat_b.call(&"get_threat_for", guardian)),
			200.0
		),
		"EnemyB at the boundary receives exactly 200 Guardian threat"
	)
	_expect(
		is_zero_approx(
			float(threat_c.call(&"get_threat_for", guardian))
		),
		"EnemyC outside the radius receives no Guardian threat"
	)
	_expect(
		is_equal_approx(
			float(threat_d.call(&"get_threat_for", guardian)),
			200.0
		),
		"EnemyD receives exactly 200 Guardian threat"
	)
	_expect(
		enemy_a.get_targeting_component() != null
			and enemy_a.get_targeting_component().get_locked_target() == guardian,
		"existing threat resolution can select Guardian after the burst"
	)
	_expect(
		enemy_d.get_targeting_component() != null
			and enemy_d.get_targeting_component().get_locked_target() != guardian,
		"a higher current target threat is not force-taken-over"
	)
	_expect(
		skill.get_cooldown_remaining() > 0.0,
		"successful delivery starts the long skill cooldown"
	)

	var decayed := float(threat_a.call(&"get_threat_for", guardian))
	threat_a.set("threat_half_life", 0.3)
	await create_timer(0.45).timeout
	await physics_frame
	var after_decay := float(threat_a.call(&"get_threat_for", guardian))
	_expect(
		after_decay > 0.0 and after_decay < 200.0,
		"Guardian threat decays through the existing curve (before=%s after=%s)"
		% [decayed, after_decay]
	)

	await _cleanup(guardian, [enemy_a, enemy_b, enemy_c, enemy_d], existing_source, player_anchor)


## 创建静止敌方夹具：无重力、零移速，保留物理与索敌以驱动真实威胁结算。
func _make_enemy(enemy_name: String, enemy_position: Vector3) -> EnemyBase:
	var enemy := (
		(load(ENEMY_SCENE_PATH) as PackedScene).instantiate() as EnemyBase
	)
	enemy.name = enemy_name
	enemy.team_id = 2
	enemy.gravity_multiplier = 0.0
	enemy.movement_speed = 0.0
	enemy.position = enemy_position
	root.add_child(enemy)
	return enemy


## 在 SkillHost 已注册技能中按 id 查找；不扩展 SkillHost 公开接口。
func _find_registered_skill(
	host: SkillHostComponent,
	skill_id: StringName
) -> SkillBase:
	for registered: SkillBase in host.get_registered_skills():
		if registered.skill_id == skill_id:
			return registered
	return null


func _cleanup(
	guardian: Node,
	enemies: Array,
	source: Node,
	anchor: Node
) -> void:
	guardian.queue_free()
	for enemy in enemies:
		if is_instance_valid(enemy):
			(enemy as Node).queue_free()
	if is_instance_valid(source):
		source.queue_free()
	if is_instance_valid(anchor):
		anchor.queue_free()
	await process_frame
	_finish()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("GuardianTauntIntegrationTest: PASS")
		quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	print("GuardianTauntIntegrationTest: FAIL (%d)" % _failures.size())
	quit(1)
