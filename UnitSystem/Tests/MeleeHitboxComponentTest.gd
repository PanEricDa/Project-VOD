extends SceneTree

const UNIT_SCENE_PATH: String = "res://UnitSystem/Base/00_UnitBase.tscn"
const HITBOX_SCENE_PATH: String = (
	"res://UnitSystem/Components/Combat/Common/"
	+ "MeleeHitboxComponent.tscn"
)

var _failures: Array[String] = []
var _world: Node3D
var _hit_count: int = 0
var _last_target: UnitBase


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_world = Node3D.new()
	_world.name = "MeleeHitboxComponentTestWorld"
	root.add_child(_world)

	var hitbox_scene := load(HITBOX_SCENE_PATH) as PackedScene
	_expect(hitbox_scene != null, "common melee hitbox scene loads")
	if hitbox_scene == null:
		_finish()
		return

	# 使用非原点 AI 持有者，覆盖“调试盒回到世界原点”的回归场景。
	var owner := _create_unit("EnemyOwner", 2, 4, Vector3(5.0, 0.0, 3.0))
	var enemy := _create_unit(
		"HostileAlly",
		1,
		2,
		Vector3(5.0, 0.0, 2.35)
	)
	var friendly := _create_unit(
		"EnemyTeammate",
		2,
		2,
		Vector3(5.25, 0.0, 2.35)
	)
	var combat_parent := Node.new()
	combat_parent.name = "CombatSystem"
	owner.add_child(combat_parent)
	var hitbox := hitbox_scene.instantiate()
	combat_parent.add_child(hitbox)
	# 模拟场景继承/编辑器中可能残留的固定 Hitbox 局部位置。
	# 正常实现不能让这个位置影响调试盒的世界坐标。
	hitbox.position = Vector3(7.0, 0.0, -4.0)
	hitbox.call("configure_owner", owner)
	hitbox.connect(&"attack_hit", _on_attack_hit)
	var debug_hitbox := hitbox.get_node_or_null(^"DebugHitbox") as MeshInstance3D
	_expect(
		debug_hitbox != null and not debug_hitbox.top_level,
		"debug hitbox uses the owner-local transform path"
	)
	if debug_hitbox != null:
		_expect(
			debug_hitbox.global_position.is_equal_approx(owner.global_position),
			"debug hitbox is initialized at the owner before the first attack"
		)

	var weapon_data := MeleeWeaponData.new()
	weapon_data.hitbox_sizes = [Vector3(1.2, 0.8, 1.0)]
	weapon_data.hitbox_center_offsets = [Vector3(0.0, 0.4, 0.65)]
	var opened: bool = bool(
		hitbox.call(
			"begin_detection",
			weapon_data,
			1,
			Vector3.FORWARD
		)
	)
	_expect(opened, "valid weapon hitbox profile opens detection")
	await _wait_for_physics()
	_expect(_hit_count == 1, "one hostile target emits once per window")
	_expect(_last_target == enemy, "the hostile unit is reported as the hit target")
	if debug_hitbox != null:
		var expected_debug_position := owner.global_position + Vector3(0.0, 0.4, -0.65)
		_expect(
			debug_hitbox.global_position.is_equal_approx(expected_debug_position),
			"debug hitbox follows the AI owner query position"
		)
		var last_valid_debug_position := debug_hitbox.global_position
		hitbox.call("end_detection")
		_expect(
			debug_hitbox.global_position.is_equal_approx(last_valid_debug_position),
			"ending a window preserves the last valid hidden debug transform"
		)

	await _wait_for_physics()
	_expect(_hit_count == 1, "the same target is deduplicated within one window")
	_expect(
		friendly != _last_target,
		"same-team units are filtered even on the queried collision layer"
	)

	hitbox.call("end_detection")
	_expect(
		not bool(hitbox.call("is_detecting")),
		"ending the window disables detection"
	)
	_finish()


func _create_unit(
	unit_name: String,
	unit_team_id: int,
	unit_collision_layer: int,
	unit_position: Vector3
) -> UnitBase:
	var unit := (load(UNIT_SCENE_PATH) as PackedScene).instantiate() as UnitBase
	unit.name = unit_name
	unit.team_id = unit_team_id
	unit.collision_layer = unit_collision_layer
	unit.collision_mask = 0
	unit.position = unit_position
	_world.add_child(unit)
	return unit


func _wait_for_physics() -> void:
	await physics_frame
	await physics_frame


func _on_attack_hit(
	target: UnitBase,
	_hit_position: Vector3,
	_hit_direction: Vector3,
	_attack_index: int
) -> void:
	_hit_count += 1
	_last_target = target


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if is_instance_valid(_world):
		_world.queue_free()
	if _failures.is_empty():
		print("MeleeHitboxComponentTest: PASS")
		quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	print("MeleeHitboxComponentTest: FAIL (%d)" % _failures.size())
	quit(1)
