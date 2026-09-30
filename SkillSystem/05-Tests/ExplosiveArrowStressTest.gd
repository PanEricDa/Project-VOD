extends SceneTree

## 十组同时触发连锁，记录活跃实例/投射物峰值与帧间耗时，验证回收而非预设性能阈值。

const ARCHER_PATH := "res://UnitSystem/AI/Ally/Units/Archer.tscn"
const UNIT_PATH := "res://UnitSystem/Base/00_UnitBase.tscn"
const GROUP_COUNT := 10
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var total_hits: Array[int] = [0]
	for group_index in range(GROUP_COUNT):
		var base := Vector3(float(group_index) * 20.0, 0, 0)
		var archer := (load(ARCHER_PATH) as PackedScene).instantiate() as UnitBase
		archer.set("automatic_skill_cast_enabled", false)
		world.add_child(archer)
		archer.global_position = base
		var primary := _enemy(world, base + Vector3(5, 0, 0), total_hits)
		for offset: Vector3 in [Vector3(5.8, 0, 0), Vector3(5, 0, 1), Vector3(4.2, 0, 0)]:
			var fragment := _enemy(world, base + offset, total_hits)
			fragment.get_status_effect_component().apply_named_status(&"burning", 4.0)
	for _frame in range(3):
		await physics_frame
	for node: Node in world.get_children():
		if not node is UnitBase or node.team_id != 1:
			continue
		var host := node.get_node(^"SkillHost") as SkillHostComponent
		host.configure_owner(node as UnitBase, world)
		var skill := host.get_node(^"SkillSocket/ExplosiveArrowSkill") as SkillBase
		var primary: UnitBase
		for candidate: Node in world.get_children():
			if candidate is UnitBase and candidate.team_id == 2 and candidate.global_position.distance_to(node.global_position + Vector3(5, 0, 0)) < 0.1:
				primary = candidate
				break
		_expect(host.request_skill(&"explosive_arrow", primary), "stress Archer accepts skill request")
		if skill.get_state() == SkillBase.SkillState.ACTION_REQUESTED:
			skill.confirm_action_started(Transform3D(Basis.IDENTITY, node.global_position + Vector3.UP))
		if skill.get_state() == SkillBase.SkillState.CASTING:
			skill.release_action(Transform3D(Basis.IDENTITY, node.global_position + Vector3.UP))
	var peak_skills := 0
	var peak_projectiles := 0
	var peak_frame_gap_ms := 0.0
	var last_ticks := Time.get_ticks_usec()
	for _frame in range(150):
		await physics_frame
		var current_ticks := Time.get_ticks_usec()
		peak_frame_gap_ms = maxf(peak_frame_gap_ms, float(current_ticks - last_ticks) / 1000.0)
		last_ticks = current_ticks
		var skill_count := 0
		var projectile_count := 0
		for node: Node in world.get_children():
			if node is SkillBase:
				skill_count += 1
			elif node is AITrackingArcProjectile:
				projectile_count += 1
		peak_skills = maxi(peak_skills, skill_count)
		peak_projectiles = maxi(peak_projectiles, projectile_count)
	_expect(total_hits[0] == GROUP_COUNT * 13, "ten concurrent chains produce 130 actual damage events")
	_expect(peak_skills > 0 and peak_projectiles > 0, "stress sampler observes real in-flight child skills and projectiles")
	_expect(world.get_children().filter(func(node: Node) -> bool: return node is SkillBase or node is AITrackingArcProjectile).is_empty(), "all triggered skill and projectile nodes return to baseline")
	print("ExplosiveArrowStressTest: peak_skills=%d peak_projectiles=%d peak_frame_gap_ms=%.3f" % [peak_skills, peak_projectiles, peak_frame_gap_ms])
	world.free()
	await process_frame
	_finish()


func _enemy(world: Node3D, at: Vector3, hit_events: Array[int]) -> UnitBase:
	var unit := (load(UNIT_PATH) as PackedScene).instantiate() as UnitBase
	unit.team_id = 2
	unit.collision_layer = 4
	world.add_child(unit)
	unit.global_position = at
	unit.health_changed.connect(func(_before: float, _after: float, _maximum: float, _source: Node) -> void: hit_events[0] += 1)
	return unit


func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)


func _finish() -> void:
	for failure: String in failures:
		push_error(failure)
	if failures.is_empty():
		print("ExplosiveArrowStressTest: PASS")
	quit(0 if failures.is_empty() else 1)
