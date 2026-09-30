extends SceneTree

## 真实 Archer 技能槽到 A→B→C 的端到端命中测试；不以文件内容代替运行行为。

const ARCHER_PATH := "res://UnitSystem/AI/Ally/Units/Archer.tscn"
const UNIT_PATH := "res://UnitSystem/Base/00_UnitBase.tscn"
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	await _run_case(false, 4)
	await _run_case(true, 13)
	await _run_case(false, 0, true)
	await _run_target_loss_case()
	_finish()


func _run_case(burning: bool, expected_hits: int, zero_damage: bool = false) -> void:
	var world := Node3D.new()
	root.add_child(world)
	var archer := (load(ARCHER_PATH) as PackedScene).instantiate() as UnitBase
	archer.automatic_skill_cast_enabled = false
	world.add_child(archer)
	archer.global_position = Vector3.ZERO
	var primary := _enemy(world, Vector3(5, 0, 0))
	var fragments: Array[UnitBase] = [
		_enemy(world, Vector3(5.8, 0, 0)),
		_enemy(world, Vector3(5, 0, 1.0)),
		_enemy(world, Vector3(4.2, 0, 0)),
	]
	if zero_damage:
		primary.can_die = false
		primary.apply_damage(primary.get_current_health() - 1.0, archer)
	for enemy: UnitBase in fragments:
		if burning:
			enemy.get_status_effect_component().apply_named_status(&"burning", 4.0)
	var hit_events: Array[int] = [0]
	for enemy: UnitBase in [primary] + fragments:
		enemy.health_changed.connect(func(_before: float, _after: float, _maximum: float, _source: Node) -> void: hit_events[0] += 1)
	for _frame in range(3):
		await physics_frame
	var host := archer.get_node(^"SkillHost") as SkillHostComponent
	host.configure_owner(archer, world)
	var skill := host.get_node(^"SkillSocket/ExplosiveArrowSkill") as SkillBase
	var main_finished: Array[int] = [0]
	skill.delivery_finished.connect(func(_context: SkillContext, _result: SkillDeliveryResult) -> void: main_finished[0] += 1)
	_expect(host.request_skill(&"explosive_arrow", primary), "Archer SkillHost accepts equipped explosive arrow")
	if skill.get_state() == SkillBase.SkillState.ACTION_REQUESTED:
		_expect(skill.confirm_action_started(Transform3D(Basis.IDENTITY, archer.global_position + Vector3.UP)), "animation-equivalent action start accepted")
	if skill.get_state() == SkillBase.SkillState.CASTING:
		_expect(skill.release_action(Transform3D(Basis.IDENTITY, archer.global_position + Vector3.UP)), "animation-equivalent release accepted")
	for _frame in range(120):
		await physics_frame
	_expect(main_finished[0] == 1, "main arrow delivery finishes exactly once")
	_expect(hit_events[0] == expected_hits, "chain damage event count equals %d with burning=%s, actual %d" % [expected_hits, burning, hit_events[0]])
	_expect(world.get_children().filter(func(node: Node) -> bool: return node is SkillBase or node is AITrackingArcProjectile).is_empty(), "all triggered skills and projectiles are reclaimed")
	world.free()
	await process_frame


func _run_target_loss_case() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var archer := (load(ARCHER_PATH) as PackedScene).instantiate() as UnitBase
	archer.set("automatic_skill_cast_enabled", false)
	world.add_child(archer)
	var target := _enemy(world, Vector3(5, 0, 0))
	for _frame in range(3):
		await physics_frame
	var host := archer.get_node(^"SkillHost") as SkillHostComponent
	host.configure_owner(archer, world)
	var skill := host.get_node(^"SkillSocket/ExplosiveArrowSkill") as SkillBase
	var failed: Array[int] = [0]
	skill.skill_failed.connect(func(_context: SkillContext, _reason: StringName) -> void: failed[0] += 1)
	_expect(host.request_skill(&"explosive_arrow", target), "target-loss skill request accepted")
	if skill.get_state() == SkillBase.SkillState.ACTION_REQUESTED:
		skill.confirm_action_started(Transform3D(Basis.IDENTITY, Vector3.UP))
	if skill.get_state() == SkillBase.SkillState.CASTING:
		skill.release_action(Transform3D(Basis.IDENTITY, Vector3.UP))
	target.free()
	for _frame in range(50):
		await physics_frame
	_expect(failed[0] == 1, "target lost during flight ends main delivery once")
	_expect(world.get_children().filter(func(node: Node) -> bool: return node is SkillBase or node is AITrackingArcProjectile).is_empty(), "target-loss flight releases projectile and has no child branches")
	world.free()
	await process_frame


func _enemy(world: Node3D, at: Vector3) -> UnitBase:
	var unit := (load(UNIT_PATH) as PackedScene).instantiate() as UnitBase
	unit.team_id = 2
	unit.collision_layer = 4
	world.add_child(unit)
	unit.global_position = at
	return unit


func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)


func _finish() -> void:
	for failure: String in failures:
		push_error(failure)
	if failures.is_empty():
		print("ExplosiveArrowChainIntegrationTest: PASS")
	quit(0 if failures.is_empty() else 1)
