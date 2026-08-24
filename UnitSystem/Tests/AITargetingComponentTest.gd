extends SceneTree

const UNIT_SCENE_PATH: String = "res://UnitSystem/Base/00_UnitBase.tscn"
const COMPONENT_SCENE_PATH: String = (
	"res://UnitSystem/Components/Targeting/AI/AITargetingComponent.tscn"
)
const THREAT_COMPONENT_SCENE_PATH: String = (
	"res://UnitSystem/Components/Threat/EnemyThreatComponent.tscn"
)
const THREAT_EVENT_SCRIPT_PATH: String = (
	"res://UnitSystem/Components/Threat/ThreatEvent.gd"
)

var _failures: Array[String] = []
var _world: Node3D


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_world = Node3D.new()
	_world.name = "AITargetingComponentTestWorld"
	root.add_child(_world)

	var owner: UnitBase = _create_unit(
		"Owner",
		1,
		2,
		Vector3.ZERO
	)
	var component_scene := load(COMPONENT_SCENE_PATH) as PackedScene
	_expect(component_scene != null, "AI targeting component scene loads")
	if component_scene == null:
		_finish()
		return
	var component := component_scene.instantiate() as AITargetingComponent
	owner.add_child(component)
	_expect(
		component.configure(owner, 6.0),
		"component accepts a UnitBase owner and targeting radius"
	)
	_expect(
		is_equal_approx(component.get_targeting_radius(), 6.0),
		"component uses the configured acquisition radius"
	)
	_expect(
		is_equal_approx(component.get_retention_radius(), 7.0),
		"component calculates a fixed one-metre retention buffer"
	)
	var debug_ring := component.get_node_or_null(
		^"DebugRangeRing"
	) as MeshInstance3D
	_expect(debug_ring != null, "component owns a debug range ring")
	if debug_ring != null:
		_expect(debug_ring.visible, "debug range ring is visible by default")
		var debug_torus := debug_ring.mesh as TorusMesh
		_expect(
			debug_torus != null
			and is_equal_approx(debug_torus.outer_radius, 6.0),
			"debug ring displays the configured targeting radius"
		)
		_expect(
			debug_torus != null
			and is_equal_approx(
				debug_torus.outer_radius - debug_torus.inner_radius,
				0.025
			),
			"debug ring keeps a thin fixed line width"
		)
		var idle_material := (
			debug_ring.material_override as StandardMaterial3D
		)
		_expect(
			idle_material != null
			and idle_material.albedo_color.is_equal_approx(
				Color(0.72, 0.75, 0.80, 0.32)
			),
			"debug ring is translucent light gray without a target"
		)

	var first_enemy: UnitBase = _create_unit(
		"FirstEnemy",
		2,
		4,
		Vector3(0.0, 0.0, -6.5)
	)
	await _wait_for_physics()
	component.refresh_target()
	_expect(
		component.get_locked_target() == null,
		"target between acquisition and retention radii is not acquired"
	)

	first_enemy.global_position = Vector3(0.0, 0.0, -5.0)
	await _wait_for_physics()
	component.refresh_target()
	_expect(
		component.get_locked_target() == first_enemy,
		"enemy inside acquisition radius is acquired"
	)
	if debug_ring != null:
		var locked_material := (
			debug_ring.material_override as StandardMaterial3D
		)
		_expect(
			locked_material != null
			and locked_material.albedo_color.is_equal_approx(
				Color(1.0, 0.24, 0.08, 0.48)
			),
			"debug ring becomes orange-red after locking a target"
		)

	first_enemy.global_position = Vector3(0.0, 0.0, -6.5)
	await _wait_for_physics()
	component.refresh_target()
	_expect(
		component.get_locked_target() == first_enemy,
		"locked target remains valid inside retention radius"
	)

	var nearer_enemy: UnitBase = _create_unit(
		"NearerEnemy",
		2,
		4,
		Vector3(0.0, 0.0, -1.0)
	)
	await _wait_for_physics()
	component.refresh_target()
	_expect(
		component.get_locked_target() == first_enemy,
		"a nearer newcomer does not replace a valid locked target"
	)

	first_enemy.targetable = false
	component.refresh_target()
	_expect(
		component.get_locked_target() == nearer_enemy,
		"invalid current target is replaced by the next valid candidate"
	)

	component.clear_locked_target()
	if debug_ring != null:
		var cleared_material := (
			debug_ring.material_override as StandardMaterial3D
		)
		_expect(
			cleared_material != null
			and cleared_material.albedo_color.is_equal_approx(
				Color(0.72, 0.75, 0.80, 0.32)
			),
			"debug ring returns to gray after clearing the target"
		)
	nearer_enemy.global_position = Vector3(0.0, 0.0, -6.5)
	await _wait_for_physics()
	component.refresh_target()
	_expect(
		component.get_locked_target() == null,
		"cleared target cannot be reacquired outside acquisition radius"
	)

	nearer_enemy.global_position = Vector3(0.0, 0.0, -4.0)
	await _wait_for_physics()
	component.refresh_target()
	component.refresh_target()
	_expect(
		component.get_locked_target() == nearer_enemy,
		"repeated refresh discovers an enemy that remains overlapping"
	)
	component.suspend_detection(0.05)
	_expect(
		component.get_locked_target() == null,
		"temporary suspension clears the current target"
	)
	_expect(
		component.detection_enabled,
		"temporary suspension does not change the persistent detection switch"
	)
	component.refresh_target()
	_expect(
		component.get_locked_target() == null,
		"manual refresh cannot bypass active suspension"
	)
	_expect(
		component.is_detection_suspended(),
		"component reports that temporary suspension is active"
	)
	_expect(
		component.get_perceived_candidates().is_empty(),
		"suspended detection exposes no skill candidates"
	)
	if debug_ring != null:
		var suspended_material := (
			debug_ring.material_override as StandardMaterial3D
		)
		_expect(
			suspended_material != null
			and suspended_material.albedo_color.is_equal_approx(
				Color(0.72, 0.75, 0.80, 0.32)
			),
			"debug ring uses its idle color during suspension"
		)
	await _wait_for_detection_resume(component)
	component.refresh_target()
	_expect(
		component.get_locked_target() == nearer_enemy,
		"normal targeting resumes without an extra target filter"
	)
	_expect(
		not component.is_detection_suspended(),
		"component reports suspension complete after its timer expires"
	)
	component.debug_range_visible = false
	component.refresh_target()
	if debug_ring != null:
		_expect(
			not debug_ring.visible,
			"debug range switch hides only the visual ring"
		)
	_expect(
		component.get_locked_target() == nearer_enemy,
		"targeting continues while the debug ring is hidden"
	)
	component.debug_range_visible = true

	component.detection_enabled = false
	component.refresh_target()
	_expect(
		component.get_locked_target() == null,
		"disabling detection clears the current lock"
	)
	_expect(
		component.get_perceived_candidates().is_empty(),
		"disabled detection exposes no skill candidates"
	)

	component.detection_enabled = true
	_expect(
		component.monitoring,
		"re-enabling detection immediately restores Area3D monitoring"
	)
	var query_enemy: UnitBase = _create_unit(
		"QueryEnemy",
		2,
		4,
		Vector3(0.0, 0.0, -4.0)
	)
	var retention_only_enemy: UnitBase = _create_unit(
		"RetentionOnlyEnemy",
		2,
		4,
		Vector3(0.0, 0.0, -6.5)
	)
	var friendly_unit: UnitBase = _create_unit(
		"FriendlyCandidate",
		1,
		2,
		Vector3(0.0, 0.0, -2.0)
	)
	var player_unit: UnitBase = _create_unit(
		"PlayerCandidate",
		1,
		1,
		Vector3(1.0, 0.0, -2.0)
	)
	await _wait_for_physics()
	var locked_before_query: UnitBase = component.get_locked_target()
	var perceived: Array[Node3D] = component.get_perceived_candidates()
	_expect(
		friendly_unit in perceived,
		"candidate provider returns a friendly-layer overlap"
	)
	_expect(
		player_unit in perceived,
		"candidate provider returns a player-layer overlap"
	)
	_expect(
		query_enemy in perceived,
		"candidate provider returns an enemy inside acquisition radius"
	)
	_expect(
		retention_only_enemy not in perceived,
		"candidate provider excludes a unit only inside retention radius"
	)
	_expect(
		owner not in perceived,
		"candidate provider excludes its owner"
	)
	_expect(
		perceived.count(query_enemy) == 1,
		"candidate provider does not duplicate the same body"
	)
	var short_range_candidates: Array[Node3D] = (
		component.get_perceived_candidates(3.0)
	)
	_expect(
		friendly_unit in short_range_candidates
		and query_enemy not in short_range_candidates,
		"custom maximum distance filters the same perception snapshot"
	)
	_expect(
		component.get_locked_target() == locked_before_query,
		"reading candidates does not mutate the persistent lock"
	)
	var friendly_policy := (
		component.selection_policy.duplicate() as TargetSelectionPolicy
	)
	friendly_policy.target_relation = (
		TargetSelectionPolicy.TargetRelation.FRIENDLY
	)
	component.set_selection_policy(friendly_policy)
	_expect(
		component.get_locked_target() == friendly_unit,
		"runtime policy replacement immediately refreshes the locked target"
	)

	var second_owner: UnitBase = _create_unit(
		"SecondOwner",
		1,
		2,
		Vector3(20.0, 0.0, 0.0)
	)
	var second_component := component_scene.instantiate() as AITargetingComponent
	second_owner.add_child(second_component)
	_expect(
		second_component.configure(second_owner, 8.0),
		"second component accepts its own owner and radius"
	)
	_expect(
		is_equal_approx(second_component.get_targeting_radius(), 8.0),
		"each component keeps an independent targeting radius"
	)
	_expect(
		is_equal_approx(second_component.get_retention_radius(), 9.0),
		"each component calculates its own retention radius"
	)
	var first_shape: SphereShape3D = (
		component.get_node(^"DetectionShape") as CollisionShape3D
	).shape as SphereShape3D
	var second_shape: SphereShape3D = (
		second_component.get_node(^"DetectionShape") as CollisionShape3D
	).shape as SphereShape3D
	_expect(
		first_shape != null and second_shape != null and first_shape != second_shape,
		"each component owns an independent sphere shape resource"
	)
	if first_shape != null and second_shape != null:
		first_shape.radius = 12.0
		_expect(
			not is_equal_approx(first_shape.radius, second_shape.radius),
			"changing one detection shape does not affect another instance"
		)

	await _verify_optional_threat_decision_provider(component_scene)

	_finish()


## 验证索敌组件仍是唯一锁定目标持有者，但可向外部优先级组件询问一次决策。
func _verify_optional_threat_decision_provider(
	component_scene: PackedScene
) -> void:
	var owner := _create_unit(
		"ThreatDecisionOwner",
		2,
		4,
		Vector3(40.0, 0.0, 0.0)
	)
	var near_target := _create_unit(
		"ThreatDecisionNearTarget",
		1,
		2,
		Vector3(40.0, 0.0, -2.0)
	)
	var far_target := _create_unit(
		"ThreatDecisionFarTarget",
		1,
		2,
		Vector3(40.0, 0.0, -5.0)
	)
	var component := component_scene.instantiate() as AITargetingComponent
	owner.add_child(component)
	_expect(component.configure(owner, 8.0), "threat decision targeting configures")

	var threat_scene := load(THREAT_COMPONENT_SCENE_PATH) as PackedScene
	var event_script := load(THREAT_EVENT_SCRIPT_PATH) as Script
	_expect(threat_scene != null, "threat component scene loads for targeting integration")
	_expect(event_script != null, "threat event script loads for targeting integration")
	if threat_scene == null or event_script == null:
		return
	var threat_component: Node = threat_scene.instantiate()
	owner.add_child(threat_component)
	_expect(
		bool(threat_component.call("configure", owner)),
		"threat decision provider configures"
	)
	var damage_event: Variant = event_script.call(
		"create_damage",
		far_target,
		20.0
	)
	_expect(
		bool(threat_component.call("submit_threat", damage_event)),
		"far target receives a local threat record"
	)
	_expect(
		component.has_method(&"set_target_decision_provider"),
		"targeting exposes an optional target decision provider interface"
	)
	if not component.has_method(&"set_target_decision_provider"):
		return
	component.call("set_target_decision_provider", threat_component)
	await _wait_for_physics()
	component.refresh_target()
	_expect(
		component.get_locked_target() == far_target,
		"provider chooses the valid higher-threat target instead of the nearer target"
	)
	component.call("set_target_decision_provider", null)
	component.clear_locked_target()
	component.refresh_target()
	_expect(
		component.get_locked_target() == near_target,
		"clearing provider restores the original nearest-policy fallback"
	)


func _create_unit(
	unit_name: String,
	unit_team_id: int,
	unit_collision_layer: int,
	unit_position: Vector3
) -> UnitBase:
	var scene := load(UNIT_SCENE_PATH) as PackedScene
	var unit := scene.instantiate() as UnitBase
	unit.name = unit_name
	unit.team_id = unit_team_id
	unit.collision_layer = unit_collision_layer
	unit.collision_mask = 1
	unit.position = unit_position
	_world.add_child(unit)
	return unit


func _wait_for_physics() -> void:
	await physics_frame
	await physics_frame


## 等待以物理帧递减的感知暂停结束。
## 不能使用空闲帧 Timer 代替物理等待，否则 headless 环境中可能尚未推进 AITargetingComponent 的 _physics_process()。
func _wait_for_detection_resume(component: AITargetingComponent) -> void:
	for _frame_index: int in range(8):
		if not component.is_detection_suspended():
			return
		await physics_frame


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if is_instance_valid(_world):
		_world.queue_free()
	if _failures.is_empty():
		print("AITargetingComponentTest: PASS")
		quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	print(
		"AITargetingComponentTest: FAIL (%d)"
		% _failures.size()
	)
	quit(1)
