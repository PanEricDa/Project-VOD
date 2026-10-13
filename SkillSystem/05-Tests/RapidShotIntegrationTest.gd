extends SceneTree

## 从 Archer 技能槽释放连射，验证同一次施放产生三次实际扣血。

const ARCHER_SCENE := preload("res://UnitSystem/AI/Ally/Units/Archer.tscn")
const UNIT_SCENE := preload("res://UnitSystem/Base/00_UnitBase.tscn")
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var archer := ARCHER_SCENE.instantiate() as UnitBase
	archer.automatic_skill_cast_enabled = false
	world.add_child(archer)
	var target := UNIT_SCENE.instantiate() as UnitBase
	target.team_id = 2
	world.add_child(target)
	target.global_position = Vector3(5, 0, 0)
	for _frame in range(3):
		await physics_frame
	var host := archer.get_node(^"SkillHost") as SkillHostComponent
	host.configure_owner(archer, world)
	var skill := host.get_regular_skill(1)
	var outcomes: Array[SkillHitOutcome] = []
	var finished_count: Array[int] = [0]
	var health_events: Array[int] = [0]
	target.health_changed.connect(func(_before: float, _after: float, _maximum: float, _source: Node) -> void: health_events[0] += 1)
	if skill != null:
		skill.delivery_finished.connect(func(_context: SkillContext, result: SkillDeliveryResult) -> void:
			finished_count[0] += 1
			outcomes.assign(result.hit_outcomes)
		)
	var before := target.get_current_health()
	_expect(host.request_skill(&"rapid_shot", target), "Archer accepts equipped rapid shot")
	if skill != null and skill.get_state() == SkillBase.SkillState.ACTION_REQUESTED:
		_expect(skill.confirm_action_started(Transform3D(Basis.IDENTITY, archer.global_position + Vector3.UP)), "rapid-shot cast starts")
	if skill != null and skill.get_state() == SkillBase.SkillState.CASTING:
		_expect(skill.release_action(Transform3D(Basis.IDENTITY, archer.global_position + Vector3.UP)), "one release starts the volley")
	for _frame in range(80):
		await physics_frame
	_expect(health_events[0] == 3, "three independent damage events reach target")
	_expect(outcomes.size() == 3 and finished_count[0] == 1, "one skill delivery reports three distinct hit outcomes")
	_expect(target.get_current_health() < before, "rapid shot actually reduces target health")
	world.free()
	for failure: String in failures:
		push_error(failure)
	if failures.is_empty():
		print("RapidShotIntegrationTest: PASS")
	quit(0 if failures.is_empty() else 1)


func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
