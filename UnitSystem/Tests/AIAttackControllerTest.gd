extends SceneTree

const OWNER_SCENE_PATH: String = "res://UnitSystem/Base/AIUnitBase.tscn"
const UNIT_SCENE_PATH: String = "res://UnitSystem/Base/00_UnitBase.tscn"
const CONTROLLER_SCRIPT_PATH: String = (
	"res://UnitSystem/Components/Combat/AI/AIAttackController.gd"
)
const COMBAT_SCENE_PATH: String = (
	"res://UnitSystem/Components/Combat/AI/AICombatSystem.tscn"
)
const IRON_SWORD_PATH: String = (
	"res://Item/Weapon/Sword/IronSwordData.tres"
)

var _failures: Array[String] = []
var _world: Node3D


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_world = Node3D.new()
	_world.name = "AIAttackControllerTestWorld"
	root.add_child(_world)

	var controller_script := load(CONTROLLER_SCRIPT_PATH) as Script
	_expect(controller_script != null, "AI attack-controller script loads")
	var combat_scene := load(COMBAT_SCENE_PATH) as PackedScene
	var combat_instance := (
		combat_scene.instantiate() if combat_scene != null else null
	)
	_expect(
		combat_instance is Node3D,
		"AI combat system provides a stable Node3D transform parent for hitbox"
	)
	if combat_instance != null:
		combat_instance.free()
	if controller_script == null:
		_finish()
		return

	var owner := (load(OWNER_SCENE_PATH) as PackedScene).instantiate() as AIUnitBase
	owner.name = "AttackOwner"
	owner.team_id = 1
	_world.add_child(owner)
	owner.set_physics_process(false)
	# Visual 容器允许存在其他装饰/子视觉节点；攻击控制器应按端点识别正式 Visual。
	# 验证控制器会从 Visual 插槽中解析唯一的有效角色视觉，而不会误选无关子节点。
	var visual_decoy := Node3D.new()
	visual_decoy.name = "VisualDecoy"
	owner.get_node(^"Visual").add_child(visual_decoy)
	var visual_scene := load(
		"res://UnitSystem/Visuals/Ally/AllyVisual.tscn"
	) as PackedScene
	var runtime_visual := visual_scene.instantiate() as Node3D
	runtime_visual.name = "RuntimeAllyVisual"
	owner.get_node(^"Visual").add_child(runtime_visual)

	var enemy := (load(UNIT_SCENE_PATH) as PackedScene).instantiate() as UnitBase
	enemy.name = "Enemy"
	enemy.team_id = 2
	enemy.position = Vector3(0.0, 0.0, -0.8)
	_world.add_child(enemy)

	var controller := controller_script.new() as Node
	controller.name = "AttackController"
	owner.add_child(controller)
	_expect(
		bool(controller.call("configure", owner)),
		"controller configures with the AI owner without delivery dependency"
	)

	var sword := load(IRON_SWORD_PATH) as WeaponData
	_expect(
		bool(controller.call("equip_weapon", sword)),
		"controller equips IronSword WeaponData"
	)
	var weapon_socket := owner.get_node(
		^"Visual/RuntimeAllyVisual/CharacterRoot/WeaponSocket"
	)
	_expect(
		weapon_socket.get_child_count() == 2,
		"equipping creates one weapon visual under WeaponSocket"
	)
	var animation_player := owner.get_node(
		^"Visual/RuntimeAllyVisual/CharacterAnimationPlayer"
	) as CharacterAnimationEventPlayer
	var motion_event_count: Array[int] = [0]
	animation_player.attack_motion_requested.connect(
		func() -> void:
			motion_event_count[0] += 1
	)

	var first_bag: Array[int] = []
	for request_index: int in range(3):
		_expect(
			bool(controller.call("request_attack", enemy)),
			"controller accepts a valid hostile attack request"
		)
		first_bag.append(
			int(controller.call("get_current_attack_index"))
		)
		_expect(
			bool(controller.call("is_attacking")),
			"controller reports the active attack"
		)
		if request_index == 0:
			animation_player.request_attack_motion()
			_expect(
				motion_event_count[0] == 1,
				"AI weapon animation keeps emitting its attack-motion marker"
			)
			_expect(
				not owner.is_attack_motion_active(),
				"AI ignores attack-motion markers without moving the body"
			)
		controller.call("cancel_attack")
		_expect(
			not bool(controller.call("is_attacking")),
			"cancelling returns the controller to idle"
		)

	var sorted_bag: Array[int] = first_bag.duplicate()
	sorted_bag.sort()
	_expect(
		sorted_bag == [1, 2, 3],
		"one random bag consumes every sword attack exactly once"
	)
	var previous_index: int = first_bag.back()
	_expect(
		bool(controller.call("request_attack", enemy)),
		"a new bag can start after the first bag is exhausted"
	)
	_expect(
		int(controller.call("get_current_attack_index")) != previous_index,
		"a new bag does not repeat the previous bag's last attack"
	)

	controller.call("set_hit_stop_active", true)
	_expect(
		bool(controller.call("is_hit_stop_active")),
		"controller exposes local hit-stop state"
	)
	controller.call("cancel_attack")
	_expect(
		not bool(controller.call("is_hit_stop_active")),
		"cancelling clears local hit stop"
	)

	controller.call("unequip_weapon")
	_expect(
		weapon_socket.get_child_count() == 1,
		"unequipping removes the weapon visual"
	)
	_expect(
		not bool(controller.call("request_attack", enemy)),
		"an unequipped controller rejects attack requests"
	)
	_finish()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if is_instance_valid(_world):
		_world.queue_free()
	if _failures.is_empty():
		print("AIAttackControllerTest: PASS")
		quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	print("AIAttackControllerTest: FAIL (%d)" % _failures.size())
	quit(1)
