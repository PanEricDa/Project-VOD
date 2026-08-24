extends SceneTree

## 验证 CombatActionPolicy 的名称与真实运行语义一致，并锁定 TestScene2 中
## Priest 实例不得再保存会导致技能冷却期间普攻的旧 BASIC_ONLY 覆盖。
const PRIEST_SCENE := "res://UnitSystem/AI/Ally/Units/Priest.tscn"
const UNIT_SCENE := "res://UnitSystem/Base/00_UnitBase.tscn"

var _failures: Array[String] = []
var _delivery_started: bool = false


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	_verify_priest_source_scene_policy()
	await _verify_basic_only_does_not_cast()
	_finish()


func _verify_priest_source_scene_policy() -> void:
	var packed := load(PRIEST_SCENE) as PackedScene
	var priest := packed.instantiate() as AllyBase if packed != null else null
	_expect(priest != null, "Priest source scene instantiates")
	_expect(
		priest != null
		and priest.combat_action_policy
			== AllyBehaviorStateMachine.CombatActionPolicy.SKILL_ONLY_WITH_BASIC_WHEN_DISABLED,
		"Priest source scene uses skill-only policy while skills are enabled"
	)
	if priest != null:
		priest.free()


func _verify_basic_only_does_not_cast() -> void:
	var player := (
		load(UNIT_SCENE) as PackedScene
	).instantiate() as UnitBase
	var priest := (
		load(PRIEST_SCENE) as PackedScene
	).instantiate() as AllyBase
	var friendly := (
		load(UNIT_SCENE) as PackedScene
	).instantiate() as UnitBase
	player.faction_id = "Player"
	player.team_id = 1
	priest.team_id = 1
	friendly.team_id = 1
	priest.combat_action_policy = \
		AllyBehaviorStateMachine.CombatActionPolicy.BASIC_ONLY
	priest.gravity_multiplier = 0.0
	priest.movement_speed = 0.0
	priest.position = Vector3.ZERO
	friendly.position = Vector3.RIGHT
	player.position = Vector3(2.0, 0.0, 0.0)
	root.add_child(player)
	root.add_child(priest)
	root.add_child(friendly)
	await physics_frame

	var host := priest.get_node(^"SkillHost") as SkillHostComponent
	var skill := priest.get_node(
		^"SkillHost/SkillSocket/HolyLightSkill"
	) as SkillBase
	host.configure_owner(priest, root)
	skill.decision_delay_min = 0.0
	skill.decision_delay_max = 0.0
	skill.extra_hesitation_chance = 0.0
	skill.delivery_started.connect(
		func(_context: SkillContext) -> void:
			_delivery_started = true
	)
	friendly.apply_damage(50.0, priest)
	for _frame: int in range(90):
		await physics_frame

	_expect(
		not _delivery_started,
		"BASIC_ONLY policy never requests an automatic skill"
	)
	_expect(
		is_equal_approx(friendly.get_current_health(), 50.0),
		"BASIC_ONLY leaves the friendly target untouched"
	)
	player.queue_free()
	priest.queue_free()
	friendly.queue_free()
	await process_frame


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("AllySkillCombatPolicyTest: PASS")
		quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	quit(1)
