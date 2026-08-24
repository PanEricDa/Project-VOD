extends SceneTree

## 验证 Priest 只通过 SkillHost 请求数据与 Staff 通用施法动画完成 HolyLight。##
## 此测试显式提供友方候选目标，刻意不覆盖尚未实施的自动友方索敌逻辑
const PRIEST_SCENE_PATH := "res://UnitSystem/AI/Ally/Units/Priest.tscn"
const UNIT_SCENE_PATH := "res://UnitSystem/Base/00_UnitBase.tscn"
const STAFF_ANIMATION_LIBRARY_PATH := "res://Item/Weapon/Staff/StaffAnimationLibrary.res"

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	_expect(
		ResourceLoader.get_resource_uid(STAFF_ANIMATION_LIBRARY_PATH) != ResourceUID.INVALID_ID,
		"StaffAnimationLibrary.res has a valid Godot resource UID"
	)
	var priest := (
		load(PRIEST_SCENE_PATH) as PackedScene
	).instantiate() as AllyBase
	var player := (
		load(UNIT_SCENE_PATH) as PackedScene
	).instantiate() as UnitBase
	var target := (
		load(UNIT_SCENE_PATH) as PackedScene
	).instantiate() as UnitBase
	_expect(
		priest != null and player != null and target != null,
		"Priest action fixtures instantiate"
	)
	if priest == null or player == null or target == null:
		_finish()
		return

	player.faction_id = "Player"
	player.team_id = 1
	priest.team_id = 1
	# 本测试只验证显式 Host 请求与动画事件交付；关闭新的自动决策入口
	# 避免场景进入树后的真实 AI 抢先占用 active_skill
	priest.automatic_skill_cast_enabled = false
	target.team_id = 1
	player.position = Vector3(0.0, 0.0, 2.0)
	priest.position = Vector3.ZERO
	target.position = Vector3.RIGHT
	root.add_child(player)
	root.add_child(priest)
	root.add_child(target)
	await process_frame

	var host := priest.get_node_or_null(^"SkillHost") as SkillHostComponent
	var animation_player := priest.get_node_or_null(
		^"Visual/AllyVisual/CharacterAnimationPlayer"
	) as CharacterAnimationEventPlayer
	_expect(host != null, "Priest provides SkillHost")
	_expect(animation_player != null, "Priest provides CharacterAnimationPlayer")
	if host == null or animation_player == null:
		_cleanup(player, priest, target)
		return
	host.configure_owner(priest, root)

	_expect(
		animation_player.has_animation(&"weapon/basic_cast_1"),
		"Staff provides weapon/basic_cast_1"
	)
	var cast_animation := animation_player.get_animation(
		&"weapon/basic_cast_1"
	)
	var release_markers := (
		priest.get_combat_system().get_attack_controller().call(
			"_find_method_marker_times",
			cast_animation,
			&"release_action"
		) as Array
	)
	_expect(
		release_markers.size() == 1,
		"Staff basic_cast_1 contains exactly one release_action marker"
	)

	target.apply_damage(50.0, priest)
	var candidates: Array[Node3D] = [target]
	_expect(
		host.request_skill(&"holy_light", target, candidates),
		"Priest accepts an explicitly supplied HolyLight target set"
	)
	animation_player.advance(5.0)
	_expect(
		is_equal_approx(target.get_current_health(), 75.0),
		"Staff animation release marker delivers HolyLight once"
	)

	_cleanup(player, priest, target)


func _cleanup(player: Node, priest: Node, target: Node) -> void:
	player.queue_free()
	priest.queue_free()
	target.queue_free()
	await process_frame
	_finish()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("PriestHolyLightActionAssemblyTest: PASS")
		quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	quit(1)
