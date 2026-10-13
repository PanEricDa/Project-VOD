extends SceneTree

## 真实 Caster 施放炎爆：释放前锁定目标、同帧齐射、每枚单体命中并消耗灼烧。

const CASTER_SCENE := preload("res://UnitSystem/AI/Ally/Units/Caster.tscn")
const UNIT_SCENE := preload("res://UnitSystem/Base/00_UnitBase.tscn")
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var caster := CASTER_SCENE.instantiate() as UnitBase
	caster.set("automatic_skill_cast_enabled", false)
	world.add_child(caster)
	var primary := _enemy(world, Vector3(4, 0, 0))
	var marked_a := _enemy(world, Vector3(4, 0, 1))
	var marked_b := _enemy(world, Vector3(4, 0, -1))
	var unmarked := _enemy(world, Vector3(5, 0, 1))
	for _frame in range(3):
		await physics_frame
	var host := caster.get_node(^"SkillHost") as SkillHostComponent
	host.configure_owner(caster, world)
	var skill := host.get_node_or_null(^"SkillSocket/PyroblastSkill") as SkillBase
	if skill == null:
		_expect(false, "Caster equips Pyroblast")
		world.free()
		_finish()
		return
	var ai_context := SkillContext.new()
	ai_context.caster = caster
	ai_context.requested_target = primary
	ai_context.candidate_targets = [primary, marked_a, marked_b]
	ai_context.delivery_parent = world
	ai_context.request_source = SkillContext.RequestSource.AI_AUTOMATIC
	_expect(not skill.can_request(ai_context), "AI cannot use Pyroblast without burning targets")
	marked_a.get_status_effect_component().apply_named_status(&"burning", 8.0)
	_expect(not skill.can_request(ai_context), "AI still waits with one burning target")
	marked_b.get_status_effect_component().apply_named_status(&"burning", 8.0)
	_expect(skill.can_request(ai_context), "AI may use Pyroblast with two burning targets")
	marked_a.get_status_effect_component().remove_named_status(&"burning")
	marked_b.get_status_effect_component().remove_named_status(&"burning")
	_expect(host.request_skill(&"pyroblast", primary), "explicit single-target request succeeds without burning")
	if skill.get_state() == SkillBase.SkillState.ACTION_REQUESTED:
		skill.confirm_action_started(Transform3D(Basis.IDENTITY, Vector3.UP))
	marked_a.get_status_effect_component().apply_named_status(&"burning", 8.0)
	marked_b.get_status_effect_component().apply_named_status(&"burning", 8.0)
	if skill.get_state() == SkillBase.SkillState.CASTING:
		_expect(skill.release_action(Transform3D(Basis.IDENTITY, Vector3.UP)), "Pyroblast releases after targets gain burning during cast")
	var launched_targets: Array[UnitBase] = []
	for node: Node in world.get_children():
		if node is AITrackingArcProjectile:
			launched_targets.append((node as AITrackingArcProjectile).tracked_target)
	_expect(launched_targets.size() == 3, "three projectiles spawn together at release")
	_expect(launched_targets.has(primary) and launched_targets.has(marked_a) and launched_targets.has(marked_b), "primary and both burning targets each receive a projectile")
	_expect(not launched_targets.has(unmarked), "unmarked secondary is not selected")
	for _frame in range(75):
		await physics_frame
	_expect(primary.get_current_health() < primary.maximum_health, "nonburning primary takes one direct hit")
	_expect(marked_a.get_current_health() < marked_a.maximum_health and marked_b.get_current_health() < marked_b.maximum_health, "marked secondaries each take one direct hit")
	_expect(is_equal_approx(unmarked.get_current_health(), unmarked.maximum_health), "unmarked neighbor takes no splash damage")
	_expect(not marked_a.get_status_effect_component().has_named_status(&"burning") and not marked_b.get_status_effect_component().has_named_status(&"burning"), "successful hits consume burning")
	world.free()
	_finish()


func _enemy(world: Node3D, at: Vector3) -> UnitBase:
	var unit := UNIT_SCENE.instantiate() as UnitBase
	unit.team_id = 2
	unit.collision_layer = 4
	world.add_child(unit)
	unit.position = at
	unit.add_to_group(&"enemy_targets")
	return unit


func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)


func _finish() -> void:
	for failure: String in failures:
		push_error(failure)
	if failures.is_empty():
		print("PyroblastIntegrationTest: PASS")
	quit(0 if failures.is_empty() else 1)
