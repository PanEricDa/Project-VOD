extends SceneTree

## 契约：脚底锚定的定向技能特效必须位于施法者脚底，并以场景中的目标方向为正前方。
const SKILL_SCENE_PATH := "res://SkillSystem/01-Core/SkillBase.tscn"
const UNIT_SCENE_PATH := "res://UnitSystem/Base/00_UnitBase.tscn"

var _world: Node3D


class TestDeliveryEffect extends SkillEffectBase:
	func apply(
		_context: SkillContext,
		_result: SkillDeliveryResult,
		_target: Node3D
	) -> bool:
		return true


func _init() -> void:
	call_deferred(&"_run")


func _run() -> void:
	_world = Node3D.new()
	root.add_child(_world)
	var caster := (load(UNIT_SCENE_PATH) as PackedScene).instantiate() as UnitBase
	var target := (load(UNIT_SCENE_PATH) as PackedScene).instantiate() as UnitBase
	caster.team_id = 1
	target.team_id = 2
	_world.add_child(caster)
	_world.add_child(target)
	caster.global_position = Vector3(2.0, 0.0, 3.0)
	target.global_position = Vector3(7.0, 0.0, 3.0)
	await process_frame

	var effect_template := Node3D.new()
	effect_template.name = &"FacingEffect"
	var effect_scene := PackedScene.new()
	if effect_scene.pack(effect_template) != OK:
		_fail("Failed to pack directional test effect")
		return
	effect_template.free()

	var skill := (load(SKILL_SCENE_PATH) as PackedScene).instantiate() as SkillBase
	_world.add_child(skill)
	var skill_host := Node.new()
	_world.add_child(skill_host)
	skill.target_relations = TargetResolver.TargetRelationFlag.HOSTILE
	skill.cast_range = 10.0
	skill.delivery = InstantTargetDeliveryConfig.new()
	skill.release_effect_scene = effect_scene
	skill.release_effect_anchor = SkillBase.PresentationAnchor.CASTER_FEET
	skill.add_child(TestDeliveryEffect.new())
	await process_frame
	skill.configure_owner(caster, skill_host, _world)
	var context := SkillContext.new()
	context.requested_target = target
	context.explicit_target_requested = true
	context.delivery_parent = _world
	if not skill.request_skill(context):
		_fail("Skill request was rejected")
		return
	if not skill.confirm_action_started(Transform3D.IDENTITY):
		_fail("Skill action could not start")
		return
	if not skill.release_action(Transform3D.IDENTITY):
		_fail("Skill release was rejected")
		return

	var effect := caster.get_node_or_null(^"FacingEffect") as Node3D
	if effect == null:
		_fail("Caster-feet effect was not attached to the caster")
		return
	var expected_forward := (target.global_position - caster.global_position)
	expected_forward.y = 0.0
	expected_forward = expected_forward.normalized()
	var actual_forward := -effect.global_basis.z
	actual_forward.y = 0.0
	actual_forward = actual_forward.normalized()
	if actual_forward.dot(expected_forward) < 0.999:
		_fail("Caster-feet effect forward direction does not face the scene target")
		return
	print("PASS: Caster-feet presentation faces the scene target")
	quit()


func _fail(message: String) -> void:
	push_error("FAIL: " + message)
	quit(1)
