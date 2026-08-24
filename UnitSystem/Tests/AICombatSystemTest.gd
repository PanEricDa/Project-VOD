extends SceneTree

const OWNER_SCENE_PATH: String = "res://UnitSystem/Base/AIUnitBase.tscn"
const ALLY_VISUAL_SCENE_PATH: String = (
	"res://UnitSystem/Visuals/Ally/AllyVisual.tscn"
)
const UNIT_SCENE_PATH: String = "res://UnitSystem/Base/00_UnitBase.tscn"
const COMBAT_SCENE_PATH: String = (
	"res://UnitSystem/Components/Combat/AI/AICombatSystem.tscn"
)
const IRON_SWORD_PATH: String = (
	"res://Item/Weapon/Sword/IronSwordData.tres"
)
const AI_FEEDBACK_PROFILE_PATH: String = (
	"res://Effects/Combat/DefaultAIHitFeedback.tres"
)

var _failures: Array[String] = []
var _world: Node3D
var _gcd_started_count: int = 0
var _gcd_finished_count: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_world = Node3D.new()
	_world.name = "AICombatSystemTestWorld"
	root.add_child(_world)

	var combat_scene := load(COMBAT_SCENE_PATH) as PackedScene
	_expect(combat_scene != null, "AI combat-system scene loads")
	if combat_scene == null:
		_finish()
		return

	var owner := (load(OWNER_SCENE_PATH) as PackedScene).instantiate() as AIUnitBase
	owner.name = "CombatOwner"
	owner.team_id = 1
	_world.add_child(owner)
	owner.set_physics_process(false)
	var ally_visual_scene := load(ALLY_VISUAL_SCENE_PATH) as PackedScene
	_expect(ally_visual_scene != null, "Ally base visual scene loads")
	if ally_visual_scene != null:
		var ally_visual := ally_visual_scene.instantiate() as Node3D
		owner.get_node(^"Visual").add_child(ally_visual)

	var enemy := _create_unit("Enemy", 2, Vector3(0.0, 0.0, -0.8))
	var friendly := _create_unit("Friendly", 1, Vector3(0.0, 0.0, -0.8))
	var sword := load(IRON_SWORD_PATH) as WeaponData

	var empty_owner := (
		load("res://UnitSystem/Base/AIUnitBase.tscn") as PackedScene
	).instantiate() as AIUnitBase
	empty_owner.name = "EmptyVisualOwner"
	_world.add_child(empty_owner)
	empty_owner.set_physics_process(false)
	var empty_combat := combat_scene.instantiate()
	empty_owner.add_child(empty_combat)
	_expect(
		bool(empty_combat.call("configure", empty_owner)),
		"an unarmed AIUnitBase without a concrete visual configures safely"
	)

	var combat := combat_scene.instantiate()
	combat.name = "CombatSystemUnderTest"
	combat.set("starting_weapon", sword)
	combat.set("base_global_cooldown_duration", 1.0)
	owner.add_child(combat)
	var feedback_bridge: Node = combat.get_node(^"HitFeedbackBridge")
	var attack_controller: Node = combat.get_node(^"AttackController")
	var feedback_profile := load(
		AI_FEEDBACK_PROFILE_PATH
	) as HitFeedbackProfile
	_expect(feedback_profile != null, "AI hit-feedback profile loads")
	if feedback_profile != null:
		_expect(
			is_equal_approx(feedback_profile.hit_stop_duration, 0.06),
			"AI hit stop uses the formal 0.06-second default"
		)
		_expect(
			not feedback_profile.camera_shake_enabled,
			"AI hit feedback does not shake the player camera"
		)
	_expect(
		ResourceLoader.get_resource_uid(AI_FEEDBACK_PROFILE_PATH)
			!= ResourceUID.INVALID_ID,
		"AI hit-feedback profile has an editor-indexed UID"
	)
	combat.connect(&"global_cooldown_started", _on_gcd_started)
	combat.connect(&"global_cooldown_finished", _on_gcd_finished)
	_expect(
		bool(combat.call("configure", owner)),
		"combat system configures with an AI owner"
	)
	_expect(
		combat.call("get_equipped_weapon") == sword,
		"starting weapon equips during configuration"
	)
	_expect(
		is_equal_approx(float(combat.call("get_attack_range")), 1.1),
		"combat system exposes the equipped weapon range"
	)

	_expect(
		not bool(combat.call("request_basic_attack", friendly)),
		"friendly targets are rejected"
	)
	_expect(
		is_equal_approx(
			float(combat.call("get_global_cooldown_remaining")),
			0.0
		),
		"a rejected request does not start GCD"
	)

	_expect(
		bool(combat.call("request_basic_attack", enemy)),
		"a valid hostile request starts an attack"
	)
	_expect(
		is_equal_approx(
			float(combat.call("get_global_cooldown_remaining")),
			1.0
		),
		"a successful attack immediately starts one-second GCD"
	)
	_expect(_gcd_started_count == 1, "GCD start signal emits once")
	feedback_bridge.call(
		"play_hit_feedback",
		enemy,
		enemy.global_position,
		Vector3.FORWARD,
		1
	)
	_expect(
		bool(attack_controller.call("is_hit_stop_active")),
		"AI feedback bridge pauses the active attack controller"
	)
	feedback_bridge.call("_process", 0.13)
	_expect(
		not bool(attack_controller.call("is_hit_stop_active")),
		"AI feedback bridge resumes the attack after the configured duration"
	)
	_expect(
		not bool(combat.call("request_basic_attack", enemy)),
		"GCD blocks a second request"
	)

	combat.call("cancel_current_action")
	_expect(
		float(combat.call("get_global_cooldown_remaining")) > 0.0,
		"cancelling the attack does not clear GCD"
	)
	combat.call("_process", 1.1)
	_expect(
		bool(combat.call("is_global_cooldown_ready")),
		"GCD becomes ready after its duration"
	)
	_expect(_gcd_finished_count == 1, "GCD finish signal emits once")

	var debug_properties: Dictionary = _index_properties(combat)
	for property_name: StringName in [
		&"debug_equipped_weapon",
		&"debug_current_attack_target",
		&"debug_current_attack_animation",
		&"debug_global_cooldown_remaining",
	]:
		_expect(
			debug_properties.has(property_name),
			"combat Inspector exposes %s" % property_name
		)
		if debug_properties.has(property_name):
			var usage: int = int(
				(debug_properties[property_name] as Dictionary).get(
					"usage",
					0
				)
			)
			_expect(
				(usage & PROPERTY_USAGE_READ_ONLY) != 0,
				"%s is read-only" % property_name
			)
			_expect(
				(usage & PROPERTY_USAGE_STORAGE) == 0,
				"%s is not stored" % property_name
			)

	combat.call("unequip_weapon")
	_expect(
		not bool(combat.call("request_basic_attack", enemy)),
		"an unequipped combat system rejects attacks"
	)
	_finish()


func _create_unit(
	unit_name: String,
	unit_team_id: int,
	unit_position: Vector3
) -> UnitBase:
	var unit := (load(UNIT_SCENE_PATH) as PackedScene).instantiate() as UnitBase
	unit.name = unit_name
	unit.team_id = unit_team_id
	unit.position = unit_position
	_world.add_child(unit)
	return unit


func _index_properties(object: Object) -> Dictionary:
	var indexed: Dictionary = {}
	for property_definition: Dictionary in object.get_property_list():
		indexed[StringName(property_definition.get("name", ""))] = (
			property_definition
		)
	return indexed


func _on_gcd_started(_duration: float) -> void:
	_gcd_started_count += 1


func _on_gcd_finished() -> void:
	_gcd_finished_count += 1


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if is_instance_valid(_world):
		_world.queue_free()
	if _failures.is_empty():
		print("AICombatSystemTest: PASS")
		quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	print("AICombatSystemTest: FAIL (%d)" % _failures.size())
	quit(1)
