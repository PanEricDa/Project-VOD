extends SceneTree

## 验证 Guardian 嘲讽只在作用范围内有敌人锁定其他任意友方时允许 AI 施放。

const SKILL_SCENE_PATH := \
	"res://SkillSystem/00-Skills/GuardianTaunt/GuardianTauntSkill.tscn"
const UNIT_SCENE_PATH := "res://UnitSystem/Base/00_UnitBase.tscn"
const PLAYER_SCENE_PATH := "res://UnitSystem/Player/PlayerBase.tscn"
const ENEMY_SCENE_PATH := "res://UnitSystem/AI/Enemy/EnemyBase.tscn"
const CONDITION_SCENE_PATH := (
	"res://SkillSystem/03-Extensions/Conditions/GuardianTauntNeededCondition.tscn"
)

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	_expect(
		ResourceLoader.get_resource_uid(CONDITION_SCENE_PATH)
			!= ResourceUID.INVALID_ID,
		"Guardian Taunt condition scene has an editor-indexed UID"
	)
	var world := Node3D.new()
	root.add_child(world)
	var guardian := (
		(load(UNIT_SCENE_PATH) as PackedScene).instantiate() as UnitBase
	)
	var ally := (
		(load(UNIT_SCENE_PATH) as PackedScene).instantiate() as UnitBase
	)
	var player := (
		(load(PLAYER_SCENE_PATH) as PackedScene).instantiate() as PlayerBase
	)
	var enemy := (
		(load(ENEMY_SCENE_PATH) as PackedScene).instantiate() as EnemyBase
	)
	guardian.team_id = 1
	ally.team_id = 1
	player.team_id = 1
	enemy.team_id = 2
	world.add_child(guardian)
	world.add_child(ally)
	world.add_child(player)
	world.add_child(enemy)
	await process_frame
	var skill := (
		(load(SKILL_SCENE_PATH) as PackedScene).instantiate() as SkillBase
	)
	world.add_child(skill)
	skill.configure_owner(guardian, null, world)
	var condition := skill.get_node_or_null(^"GuardianTauntNeededCondition")
	_expect(condition is SkillConditionBase, "Guardian Taunt mounts its needed condition")
	if not condition is SkillConditionBase:
		world.queue_free()
		await process_frame
		_finish()
		return
	var context := SkillContext.new()
	context.delivery_parent = world
	context.request_source = SkillContext.RequestSource.AI_AUTOMATIC
	context.candidate_targets.assign([enemy])
	enemy.global_position = guardian.global_position + Vector3(4.0, 0.0, 0.0)
	var targeting := enemy.get_targeting_component()
	targeting.call(&"_set_locked_target", guardian)
	_expect(not skill.can_request(context), "Enemy already targeting Guardian does not trigger Taunt")
	targeting.call(&"_set_locked_target", ally)
	_expect(skill.can_request(context), "Enemy targeting an AI ally triggers Taunt")
	targeting.call(&"_set_locked_target", player)
	_expect(skill.can_request(context), "Enemy targeting the player also triggers Taunt")
	ally.apply_damage(ally.maximum_health, enemy)
	targeting.call(&"_set_locked_target", ally)
	_expect(not skill.can_request(context), "Enemy retaining a dead ally target does not trigger Taunt")
	targeting.call(&"_set_locked_target", player)
	enemy.global_position = guardian.global_position + Vector3(5.1, 0.0, 0.0)
	_expect(not skill.can_request(context), "Enemy outside Delivery radius does not trigger Taunt")
	enemy.global_position = guardian.global_position + Vector3(4.0, 0.0, 0.0)
	targeting.call(&"_set_locked_target", null)
	_expect(not skill.can_request(context), "Enemy without a locked friendly does not trigger Taunt")
	world.queue_free()
	await process_frame
	_finish()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("GuardianTauntConditionTest: PASS")
		quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	quit(1)
