extends SceneTree

## 验证 Caster 使用现有自主索敌、行为状态机、SkillHost 与内嵌交付配置完成真实施法。
## 测试场景完全在运行时构建，不读取或修改 TestScene。
const CASTER_SCENE_PATH := "res://UnitSystem/AI/Ally/Units/Caster.tscn"
const PLAYER_UNIT_SCENE_PATH := "res://UnitSystem/Base/00_UnitBase.tscn"
const ENEMY_SCENE_PATH := "res://UnitSystem/AI/Enemy/EnemyBase.tscn"

var failures: Array[String] = []
var _delivery_launched: bool = false
var _projectile_launch_position: Vector3 = Vector3.INF
var _expected_launch_position: Vector3 = Vector3.INF
var _runtime_caster: AllyBase
var _cooldown_at_cast_start: float = -1.0
var _cooldown_at_delivery_start: float = -1.0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var player := (load(PLAYER_UNIT_SCENE_PATH) as PackedScene).instantiate() as UnitBase
	var caster := (load(CASTER_SCENE_PATH) as PackedScene).instantiate() as AllyBase
	var enemy := (load(ENEMY_SCENE_PATH) as PackedScene).instantiate() as AIUnitBase
	_expect(player != null and caster != null and enemy != null, "runtime fixtures instantiate")
	if player == null or caster == null or enemy == null:
		_finish()
		return

	player.name = &"RuntimePlayer"
	player.faction_id = "Player"
	player.team_id = 1
	caster.movement_speed = 0.0
	caster.gravity_multiplier = 0.0
	enemy.gravity_multiplier = 0.0
	player.position = Vector3(10.0, 0.0, 6.0)
	caster.position = Vector3(10.0, 0.0, 4.0)
	enemy.position = Vector3(10.0, 0.0, 1.0)
	root.add_child(player)
	root.add_child(caster)
	root.add_child(enemy)
	_runtime_caster = caster
	await physics_frame
	var host: Node = caster.get_node_or_null(^"SkillHost")
	_expect(host != null, "Caster provides SkillHost")
	if host != null:
		## 隔离 SceneTree 没有 current_scene；显式注入运行时世界根，等价于正式 TestScene 的交付父节点。
		host.configure_owner(caster, root)
	## 索敌组件已由自身测试覆盖；这里直接注入已锁定结果，专注验证状态机之后的施法链路。
	var targeting: AITargetingComponent = caster.get_targeting_component()
	targeting.call("_set_locked_target", enemy)
	## 无地面的隔离物理世界不会持续报告 Area3D 重叠；暂停其下一帧刷新以保留该测试输入。
	targeting.set_physics_process(false)

	var skill: Node = caster.get_node_or_null(
		^"SkillHost/SkillSocket/FireboltSkill"
	)
	_expect(skill != null, "Caster owns FireboltSkill")
	if skill != null:
		skill.cast_started.connect(_on_cast_started)
		skill.delivery_started.connect(_on_delivery_started)

	## Firebolt 保留设计中的 0.3–3 秒常规决策延迟，以及最多 5 秒的低概率额外犹豫。
	## 因此测试覆盖完整最长等待、施法时间和一小段交付启动余量。
	for _frame: int in range(720):
		if _delivery_launched:
			break
		await physics_frame

	_expect(caster.get_locked_target() == enemy, "Caster accepts the hostile lock")
	_expect(_delivery_launched, "Caster launches Firebolt delivery after casting")
	_expect(
		is_zero_approx(_cooldown_at_cast_start),
		"shared cooldown does not start when casting begins"
	)
	_expect(
		is_equal_approx(_cooldown_at_delivery_start, 1.0),
		"shared cooldown starts only after successful delivery begins"
	)
	if _delivery_launched:
		_expect_vector_near(
			_projectile_launch_position,
			_expected_launch_position,
			0.0001,
			"Firebolt projectile starts from Caster Visual ProjectileOrigin"
		)

	player.queue_free()
	caster.queue_free()
	enemy.queue_free()
	await process_frame
	_finish()


func _on_delivery_started(_context: RefCounted) -> void:
	_delivery_launched = true
	_cooldown_at_delivery_start = float(
		_runtime_caster.get_behavior_state_machine().get(
			"_shared_action_cooldown_remaining"
		)
	)
	if is_instance_valid(_runtime_caster):
		_expected_launch_position = (
			_runtime_caster.get_node(
				^"Visual/CasterVisual/CharacterRoot/WeaponSocket/ProjectileOrigin"
			) as Marker3D
		).global_position
	var projectile := root.get_node_or_null(^"FireBall") as Node3D
	if projectile != null:
		_projectile_launch_position = projectile.global_position


func _on_cast_started(_context: RefCounted) -> void:
	_cooldown_at_cast_start = float(
		_runtime_caster.get_behavior_state_machine().get(
			"_shared_action_cooldown_remaining"
		)
	)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _expect_vector_near(
	value: Vector3,
	expected: Vector3,
	tolerance: float,
	message: String
) -> void:
	if value.distance_to(expected) > tolerance:
		failures.append(
			message + ": expected " + str(expected) + ", got " + str(value)
		)


func _finish() -> void:
	if failures.is_empty():
		print("CasterFireboltRuntimeTest: PASS")
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	quit(1)
