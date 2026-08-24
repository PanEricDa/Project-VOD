extends SceneTree

## 治疗仇恨端到端集成测试。
## 验证从技能 HEAL 效果到敌人 ThreatComponent 的完整链路。

const UNIT_SCENE_PATH := "res://UnitSystem/Base/00_UnitBase.tscn"
const ENEMY_SCENE_PATH := "res://UnitSystem/AI/Enemy/EnemyBase.tscn"
const SKILL_SCENE_PATH := (
	"res://SkillSystem/05-Tests/HealThreatTestSkill.tscn"
)

var _failures: Array[String] = []
var _world: Node3D


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_world = Node3D.new()
	_world.name = "HealingThreatIntegrationTestWorld"
	root.add_child(_world)

	# 1. 验证 SKILL_BONUS 事件可经 submit_threat 提交
	var event_script := load(
		"res://UnitSystem/Components/Threat/ThreatEvent.gd"
	) as Script
	var component_scene := load(
		"res://UnitSystem/Components/Threat/EnemyThreatComponent.tscn"
	) as PackedScene
	_expect(event_script != null, "ThreatEvent script loads")
	_expect(component_scene != null, "ThreatComponent scene loads")
	if event_script == null or component_scene == null:
		_finish()
		return

	var enemy_owner := _create_unit("HealThreatOwner", 2, Vector3.ZERO)
	var healer := _create_unit("Healer", 1, Vector3(0.0, 0.0, 3.0))
	var component := component_scene.instantiate()
	enemy_owner.add_child(component)
	_expect(
		bool(component.call("configure", enemy_owner)),
		"ThreatComponent configured with enemy owner"
	)

	var skill_event: Variant = event_script.new()
	skill_event.source = healer
	skill_event.kind = 1  # Kind.SKILL_BONUS
	skill_event.base_amount = 40.0
	skill_event.threat_multiplier = 0.5
	_expect(
		bool(component.call("submit_threat", skill_event)),
		"SKILL_BONUS event (40 heal * 0.5 multiplier) is accepted"
	)
	_expect(
		is_equal_approx(float(component.call("get_threat_for", healer)), 20.0),
		"heal threat = 40 * 0.5 = 20 stored correctly"
	)
	component.call("clear_threat")

	# 2. 验证 threat_multiplier=0 时 SKILL_BONUS 不产生仇恨
	var zero_threat_event: Variant = event_script.new()
	zero_threat_event.source = healer
	zero_threat_event.kind = 1
	zero_threat_event.base_amount = 40.0
	zero_threat_event.threat_multiplier = 0.0
	_expect(
		bool(component.call("submit_threat", zero_threat_event)),
		"zero-threat SKILL_BONUS is accepted (event validity is fine)"
	)
	_expect(
		is_zero_approx(float(component.call("get_threat_for", healer))),
		"zero-threat-multiplier skill bonus results in zero local threat"
	)
	component.call("clear_threat")

	# 3. 验证 SKILL_BONUS 参与目标选择
	var near_source := _create_unit("NearHealer", 1, Vector3(0.0, 0.0, 2.0))
	var far_source := _create_unit("FarDamager", 1, Vector3(0.0, 0.0, 5.0))
	var damage_event: Variant = event_script.new()
	damage_event.source = far_source
	damage_event.kind = 0  # Kind.DAMAGE
	damage_event.base_amount = 30.0
	damage_event.threat_multiplier = 1.0
	_expect(
		bool(component.call("submit_threat", damage_event)),
		"damager submits 30 threat via DAMAGE"
	)
	var heal_event: Variant = event_script.new()
	heal_event.source = near_source
	heal_event.kind = 1
	heal_event.base_amount = 80.0
	heal_event.threat_multiplier = 0.5
	_expect(
		bool(component.call("submit_threat", heal_event)),
		"healer submits 40 threat (80 * 0.5) via SKILL_BONUS"
	)
	var policy := load(
		"res://UnitSystem/Components/Targeting/AI/Policies/DefaultNearestEnemy.tres"
	) as TargetSelectionPolicy
	var candidates: Array[UnitBase] = [near_source, far_source]
	_expect(
		component.call(
			"resolve_target",
			enemy_owner,
			null,
			candidates,
			policy,
			10.0,
			11.0
		) == near_source,
		"healer (40 threat via SKILL_BONUS) out-prioritizes damager (30 threat via DAMAGE)"
	)

	_finish()


func _create_unit(
	unit_name: String,
	unit_team_id: int,
	unit_position: Vector3
) -> UnitBase:
	var scene := load(UNIT_SCENE_PATH) as PackedScene
	var unit := scene.instantiate() as UnitBase
	unit.name = unit_name
	unit.team_id = unit_team_id
	unit.position = unit_position
	_world.add_child(unit)
	return unit


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if is_instance_valid(_world):
		_world.queue_free()
	if _failures.is_empty():
		print("HealingThreatIntegrationTest: PASS")
		quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	print("HealingThreatIntegrationTest: FAIL (%d)" % _failures.size())
	quit(1)
