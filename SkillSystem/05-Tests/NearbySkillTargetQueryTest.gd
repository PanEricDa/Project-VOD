extends SceneTree

## 命中点附近筛选不使用施法者索敌范围，按水平距离稳定选出合法目标。

const QUERY_PATH := "res://SkillSystem/01-Core/NearbySkillTargetQuery.gd"
const UNIT_PATH := "res://UnitSystem/Base/00_UnitBase.tscn"
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	if not ResourceLoader.exists(QUERY_PATH):
		_expect(false, "nearby target query exists")
		_finish()
		return
	var world := Node3D.new()
	root.add_child(world)
	var caster := _unit(world, 1, Vector3.ZERO)
	var center := Vector3(20, 0, 0)
	var near := _unit(world, 2, center + Vector3(0.5, 0, 0))
	var second := _unit(world, 2, center + Vector3(1.2, 0, 0))
	var high := _unit(world, 2, center + Vector3(2.0, 1.4, 0))
	var friend := _unit(world, 1, center + Vector3(0, 0, 1.8))
	var untargetable := _unit(world, 2, center + Vector3(0, 0, 2.3))
	untargetable.targetable = false
	var dead := _unit(world, 2, center + Vector3(0, 0, -2.3))
	dead.apply_damage(dead.get_current_health(), caster)
	for _frame in range(3):
		await physics_frame
	var query_script := load(QUERY_PATH) as Script
	var world_3d := world.get_world_3d()
	var hostile := TargetResolver.TargetRelationFlag.HOSTILE
	var chosen: Array = query_script.call(&"select_targets", world_3d, caster, center, 3.0, 3, hostile, null)
	_expect(chosen.size() == 3, "three legal nearby hostiles chosen far from caster")
	if chosen.size() == 3:
		_expect(chosen[0] == near and chosen[1] == second and chosen[2] == high, "targets ordered by horizontal distance including different height")
	_expect((query_script.call(&"select_targets", world_3d, caster, center, 3.0, 1, hostile, near) as Array) == [second], "excluded hit target replaced by next nearest")
	_expect((query_script.call(&"select_targets", world_3d, caster, center, 3.0, 0, hostile, null) as Array).is_empty(), "zero capacity returns empty")
	_expect((query_script.call(&"select_targets", world_3d, caster, center, -1.0, 3, hostile, null) as Array).is_empty(), "invalid radius returns empty")
	_expect((query_script.call(&"select_targets", world_3d, caster, center, 3.0, 3, 0, null) as Array).is_empty(), "empty relation mask returns empty")

	# 物理查询默认容量为 32；先创建远处密集目标，再创建最近目标，防止截断把最近者漏掉。
	var crowd_center := Vector3(80, 0, 0)
	for i in range(40):
		var radians := float(i) * TAU / 40.0
		_unit(world, 2, crowd_center + Vector3(cos(radians) * 8.0, 0, sin(radians) * 8.0))
	var closest := _unit(world, 2, crowd_center + Vector3(0.6, 0, 0))
	for _frame in range(3):
		await physics_frame
	var crowded: Array = query_script.call(&"select_targets", world_3d, caster, crowd_center, 10.0, 1, hostile, null)
	_expect(crowded.size() == 1 and crowded[0] == closest, "more than 32 colliders still returns the nearest")
	world.free()
	_finish()


func _unit(world: Node3D, team: int, at: Vector3) -> UnitBase:
	var unit := (load(UNIT_PATH) as PackedScene).instantiate() as UnitBase
	unit.team_id = team
	unit.collision_layer = 2 if team == 1 else 4
	world.add_child(unit)
	unit.position = at
	return unit


func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)


func _finish() -> void:
	for failure: String in failures:
		push_error(failure)
	if failures.is_empty():
		print("NearbySkillTargetQueryTest: PASS")
	quit(0 if failures.is_empty() else 1)
