extends SceneTree

## 敌人本地仇恨组件的基础契约测试。
## 本测试只通过公开接口交互，确保后续技能、治疗或嘲讽也必须复用同一结算入口。

const UNIT_SCENE_PATH := "res://UnitSystem/Base/00_UnitBase.tscn"
const EVENT_SCRIPT_PATH := "res://UnitSystem/Components/Threat/ThreatEvent.gd"
const COMPONENT_SCENE_PATH := (
	"res://UnitSystem/Components/Threat/EnemyThreatComponent.tscn"
)
const NEAREST_POLICY_PATH := (
	"res://UnitSystem/Components/Targeting/AI/Policies/DefaultNearestEnemy.tres"
)

var _failures: Array[String] = []
var _world: Node3D
var _threat_cleared_count: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_world = Node3D.new()
	_world.name = "EnemyThreatComponentTestWorld"
	root.add_child(_world)

	var event_script := load(EVENT_SCRIPT_PATH) as Script
	var component_scene := load(COMPONENT_SCENE_PATH) as PackedScene
	_expect(event_script != null, "ThreatEvent script exists")
	_expect(component_scene != null, "EnemyThreatComponent scene exists")
	if event_script == null or component_scene == null:
		_finish()
		return

	var owner := _create_unit("ThreatOwner", 2, Vector3.ZERO)
	var near_source := _create_unit("NearSource", 1, Vector3(0.0, 0.0, 2.0))
	var far_source := _create_unit("FarSource", 1, Vector3(0.0, 0.0, 5.0))
	var component := component_scene.instantiate()
	owner.add_child(component)
	_expect(
		bool(component.call("configure", owner)),
		"component accepts one valid enemy owner"
	)

	var near_event: Variant = event_script.call("create_damage", near_source, 12.0)
	_expect(
		bool(component.call("submit_threat", near_event)),
		"valid damage event is accepted by the single submission interface"
	)
	_expect(
		is_equal_approx(float(component.call("get_threat_for", near_source)), 12.0),
		"component stores the accepted applied damage as local threat"
	)
	_expect(
		bool(component.call("submit_threat", event_script.call("create_damage", near_source, 3.0))),
		"same source can submit a later damage event"
	)
	_expect(
		is_equal_approx(float(component.call("get_threat_for", near_source)), 15.0),
		"same source accumulates through the same submission interface"
	)
	_expect(
		bool(component.call("submit_threat", event_script.call("create_damage", near_source, 12.0, 3.0))),
		"weighted damage event is accepted by the single submission interface"
	)
	_expect(
		is_equal_approx(float(component.call("get_threat_for", near_source)), 51.0),
		"weighted damage contributes applied damage multiplied by its threat multiplier"
	)
	_expect(
		not bool(component.call("submit_threat", event_script.call("create_damage", near_source, 0.0))),
		"zero-threat event is rejected"
	)

	_expect(
		bool(component.call("submit_threat", event_script.call("create_damage", far_source, 20.0))),
		"second valid source is accepted"
	)
	var has_relative_threat_ratio := component.has_method(
		&"get_threat_ratio_against_highest_competitor"
	)
	_expect(
		has_relative_threat_ratio,
		"ThreatComponent exposes a relative-threat query for action decisions"
	)
	if has_relative_threat_ratio:
		_expect(
			is_equal_approx(
				float(
					component.call(
						"get_threat_ratio_against_highest_competitor",
						near_source
					)
				),
				2.55
			),
			"relative threat compares the source against the highest other source"
		)

	# --- SKILL_BONUS acceptance ---
	component.call("clear_threat")
	var skill_bonus_event: Variant = event_script.new()
	skill_bonus_event.source = near_source
	skill_bonus_event.kind = 1  # Kind.SKILL_BONUS
	skill_bonus_event.base_amount = 30.0
	skill_bonus_event.threat_multiplier = 1.0
	_expect(
		bool(component.call("submit_threat", skill_bonus_event)),
		"SKILL_BONUS event is accepted by the single submission interface"
	)
	_expect(
		is_equal_approx(float(component.call("get_threat_for", near_source)), 30.0),
		"SKILL_BONUS stores its base amount as local threat"
	)
	_expect(
		bool(component.call("submit_threat", skill_bonus_event)),
		"same SKILL_BONUS source can submit again"
	)
	_expect(
		is_equal_approx(float(component.call("get_threat_for", near_source)), 60.0),
		"SKILL_BONUS accumulates through the same interface as DAMAGE"
	)
	# TAUNT still rejected
	var taunt_event: Variant = event_script.new()
	taunt_event.source = near_source
	taunt_event.kind = 2  # Kind.TAUNT
	taunt_event.base_amount = 100.0
	taunt_event.threat_multiplier = 1.0
	_expect(
		not bool(component.call("submit_threat", taunt_event)),
		"TAUNT event is still rejected until its design is finalized"
	)

	component.call("clear_threat")
	_expect(
		bool(component.call("submit_threat", event_script.call("create_damage", near_source, 20.0))),
		"single-source ratio fixture submits one valid threat event"
	)
	if has_relative_threat_ratio:
		_expect(
			is_zero_approx(
				float(
					component.call(
						"get_threat_ratio_against_highest_competitor",
						near_source
					)
				)
			),
			"a source without another valid competitor has no relative threat risk"
		)
	component.call("clear_threat")
	_expect(
		bool(component.call("submit_threat", event_script.call("create_damage", near_source, 120.0)))
		and bool(component.call("submit_threat", event_script.call("create_damage", far_source, 100.0))),
		"relative-ratio fixture submits both threat sources"
	)
	if has_relative_threat_ratio:
		_expect(
			is_equal_approx(
				float(
					component.call(
						"get_threat_ratio_against_highest_competitor",
						near_source
					)
				),
				1.2
			),
			"120 threat against a 100-threat competitor returns a 120 percent ratio"
		)
	var policy := load(NEAREST_POLICY_PATH) as TargetSelectionPolicy
	var candidates: Array[UnitBase] = [near_source, far_source]
	_expect(
		component.call(
			"resolve_target",
			owner,
			null,
			candidates,
			policy,
			6.0,
			7.0
	) == near_source,
		"weighted local threat overrides a lower unweighted threat candidate"
	)

	_expect(
		component.has_method(&"get_threat_snapshot"),
		"component exposes a read-only threat snapshot for presentation systems"
	)
	_expect(
		component.has_signal(&"threat_cleared"),
		"component notifies read-only consumers when its local table is cleared"
	)
	if component.has_signal(&"threat_cleared"):
		component.connect(&"threat_cleared", _on_threat_cleared)

	component.call("clear_threat")
	_expect(
		_threat_cleared_count == 1,
		"clearing a populated local table broadcasts exactly one clear notification"
	)
	var snapshot: Array = component.call("get_threat_snapshot") as Array
	_expect(
		snapshot.is_empty(),
		"cleared local table produces an empty presentation snapshot"
	)

	_expect(
		bool(component.call("submit_threat", event_script.call("create_damage", near_source, 100.0)))
		and bool(component.call("submit_threat", event_script.call("create_damage", far_source, 125.0))),
		"threshold test sources submit valid local threat"
	)
	_expect(
		component.call(
			"resolve_target",
			owner,
			near_source,
			candidates,
			policy,
			6.0,
			7.0
		) == near_source,
		"a challenger at exactly 125 percent retains the current target"
	)
	_expect(
		bool(component.call("submit_threat", event_script.call("create_damage", far_source, 0.1))),
		"threshold challenger can exceed the retained target by a positive amount"
	)
	_expect(
		component.call(
			"resolve_target",
			owner,
			near_source,
			candidates,
			policy,
			6.0,
			7.0
		) == far_source,
		"a challenger above 125 percent becomes the new target"
	)

	component.call("clear_threat")
	_expect(
		bool(component.call("submit_threat", event_script.call("create_damage", near_source, 100.0)))
		and bool(component.call("submit_threat", event_script.call("create_damage", far_source, 106.0))),
		"takeover-ratio sources submit their independent local threat values"
	)
	_expect(
		component.call(
			"resolve_target",
			owner,
			near_source,
			candidates,
			policy,
			6.0,
			7.0
		) == near_source,
		"a default challenger at 106 percent still respects the 125 percent protection"
	)
	var has_takeover_ratio := _has_property(far_source, &"threat_takeover_ratio")
	_expect(has_takeover_ratio, "UnitBase exposes a per-unit threat takeover ratio")
	if has_takeover_ratio:
		far_source.set("threat_takeover_ratio", 1.05)
		_expect(
			component.call(
				"resolve_target",
				owner,
				near_source,
				candidates,
				policy,
				6.0,
				7.0
			) == far_source,
			"a 105 percent challenger reclaims the target after exceeding its own threshold"
		)

	component.call("clear_threat")
	_expect(
		is_zero_approx(float(component.call("get_threat_for", near_source)))
		and is_zero_approx(float(component.call("get_threat_for", far_source))),
		"clearing threat removes every local source record"
	)
	_expect(
		component.call(
			"resolve_target",
			owner,
			null,
			candidates,
			policy,
			6.0,
			7.0
		) == near_source,
		"empty table falls back to the existing nearest selection policy"
	)

	# --- decay test ---
	_expect(
		component.call("submit_threat", event_script.call("create_damage", near_source, 100.0)),
		"decay precondition: source starts at 100 threat"
	)
	component.set("threat_half_life", 0.0)
	component.call("_process", 10.0)
	_expect(
		is_equal_approx(float(component.call("get_threat_for", near_source)), 100.0),
		"with zero half-life, no decay occurs"
	)
	component.set("threat_half_life", 1.0)
	for _i: int in range(60):
		component.call("_process", 1.0 / 60.0)
	_expect(
		float(component.call("get_threat_for", near_source)) < 90.0,
		"with 1s half-life, 1 second of decay reduces threat below 90"
	)
	_expect(
		component.call("submit_threat", event_script.call("create_damage", near_source, 50.0)),
		"fresh threat refreshes the reference peak"
	)
	_expect(
		float(component.call("get_threat_for", near_source)) > 95.0,
		"after new contribution, value is above post-decay level"
	)
	component.call("clear_threat")

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


func _on_threat_cleared() -> void:
	_threat_cleared_count += 1


## 检查对象是否暴露指定 Inspector 属性；用于保证仇恨倍率是可由单位源场景独立覆盖的配置，而不是敌方组件内的职业特判。
func _has_property(target: Object, property_name: StringName) -> bool:
	for property_info: Dictionary in target.get_property_list():
		if property_info.get("name") == property_name:
			return true
	return false


func _finish() -> void:
	if is_instance_valid(_world):
		_world.queue_free()
	if _failures.is_empty():
		print("EnemyThreatComponentTest: PASS")
		quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	print("EnemyThreatComponentTest: FAIL (%d)" % _failures.size())
	quit(1)
