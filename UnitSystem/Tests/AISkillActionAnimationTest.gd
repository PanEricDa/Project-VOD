extends SceneTree

## AI 外部技能动作与角色动画之间的契约测试。##
## 测试刻意只向战斗控制器传递有效施法时间，不引用 SkillBase 或具体动画名，##
## 用来保证 UnitSystem 与 SkillSystem 之间保持开放、可替换的适配边界。
const ALLY_SCENE_PATH := "res://UnitSystem/AI/Ally/AllyBase.tscn"
const UNIT_SCENE_PATH := "res://UnitSystem/Base/00_UnitBase.tscn"
const CONTROLLER_SCRIPT_PATH := \
	"res://UnitSystem/Components/Combat/AI/AIAttackController.gd"
const COMBAT_SCENE_PATH := \
	"res://UnitSystem/Components/Combat/AI/AICombatSystem.tscn"
const VISUAL_SCENE_PATH := \
	"res://UnitSystem/Visuals/Ally/AllyVisual.tscn"
const MAGIC_GLOBE_PATH := "res://Item/Weapon/MagicGlobe/MagicGlobeData.tres"

var _failures: Array[String] = []
var _world: Node3D


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	_world = Node3D.new()
	root.add_child(_world)
	var combat_contract := (
		load(COMBAT_SCENE_PATH) as PackedScene
	).instantiate()
	_expect(
		combat_contract.has_method(&"request_external_action")
		and combat_contract.has_method(&"cancel_external_action")
		and combat_contract.has_method(&"get_action_launch_transform"),
		"AICombatSystem exposes the type-independent external action API"
	)
	_expect(
		combat_contract.has_signal(&"external_action_released")
		and combat_contract.has_signal(&"external_action_finished")
		and combat_contract.has_signal(&"external_action_cancelled"),
		"AICombatSystem exposes generic external action signals"
	)
	combat_contract.free()
	var owner := (load(ALLY_SCENE_PATH) as PackedScene).instantiate() as AIUnitBase
	var enemy := (load(UNIT_SCENE_PATH) as PackedScene).instantiate() as UnitBase
	owner.team_id = 1
	enemy.team_id = 2
	_world.add_child(owner)
	_world.add_child(enemy)
	owner.set_physics_process(false)
	var visual := (load(VISUAL_SCENE_PATH) as PackedScene).instantiate() as Node3D
	owner.get_node(^"Visual").add_child(visual)

	var controller := (load(CONTROLLER_SCRIPT_PATH) as Script).new() as Node
	owner.add_child(controller)
	_expect(bool(controller.call("configure", owner)), "controller configures")
	var test_weapon := (
		(load(MAGIC_GLOBE_PATH) as WeaponData).duplicate(true)
		as WeaponData
	)
	_expect(
		bool(controller.call("equip_weapon", test_weapon)),
		"weapon supplies RESET and the sole valid basic_cast_1 animation"
	)
	var animation_player := visual.get_node(
		^"CharacterAnimationPlayer"
	) as CharacterAnimationEventPlayer
	_expect(
		animation_player.has_animation(&"weapon/basic_cast_1"),
		"weapon cast animation is registered"
	)
	var cast_animation := animation_player.get_animation(
		&"weapon/basic_cast_1"
	)
	var release_markers := controller.call(
		"_find_method_marker_times",
		cast_animation,
		&"release_action"
	) as Array
	_expect(
		release_markers.size() == 1,
		"controller recognizes exactly one release_action marker"
	)
	var release_time: float = float(release_markers[0]) if release_markers.size() == 1 else 0.0
	var effective_cast_time: float = release_time * 2.0

	var released: Array[int] = [0]
	var finished: Array[int] = [0]
	controller.external_action_released.connect(
		func() -> void:
			released[0] += 1
	)
	controller.external_action_finished.connect(
		func() -> void:
			finished[0] += 1
	)

	_expect(
		bool(controller.call(
			"request_external_action",
			effective_cast_time
		)),
		"valid weapon cast starts the external action"
	)
	_expect(
		animation_player.current_animation == &"weapon/basic_cast_1",
		"controller selects the weapon action that satisfies the marker contract"
	)
	_expect(
		is_equal_approx(animation_player.get_playing_speed(), 0.5),
		"weapon release marker scales correctly to twice its original release time"
	)
	_expect(
		not bool(controller.call("can_attack")),
		"basic attacks are blocked during an external action"
	)
	_expect(
		not bool(controller.call(
			"request_external_action",
			0.3
		)),
		"a second external action is blocked while one is active"
	)
	animation_player.advance(effective_cast_time - 0.01)
	_expect(released[0] == 0, "release does not occur before effective cast time")
	animation_player.advance(0.02)
	_expect(released[0] == 1, "release occurs at effective cast time")
	animation_player.advance(2.0)
	_expect(finished[0] == 1, "finish_action closes the external action")
	_expect(bool(controller.call("can_attack")), "basic attacks recover after finish")

	_expect(
		bool(controller.call(
			"request_external_action",
			effective_cast_time
		)),
		"the same action can be requested again"
	)
	_expect(
		is_equal_approx(animation_player.get_playing_speed(), 0.5),
		"the repeated weapon action preserves its scaled playback speed"
	)
	controller.call("cancel_external_action")
	_expect(
		animation_player.current_animation == &"weapon/RESET",
		"cancelling restores the equipped weapon RESET"
	)

	var origin := visual.get_node(
		^"CharacterRoot/WeaponSocket/ProjectileOrigin"
	) as Node3D
	_expect(
		controller.call("get_action_launch_transform") == origin.global_transform,
		"launch transform comes from the current visual ProjectileOrigin"
	)
	_finish()


func _replace_cast_animation(
	library: AnimationLibrary,
	animation: Animation
) -> void:
	if library.has_animation(&"basic_cast_1"):
		library.remove_animation(&"basic_cast_1")
	library.add_animation(&"basic_cast_1", animation)


func _create_method_animation(
	length: float,
	release_times: Array[float],
	include_finish: bool
) -> Animation:
	var animation := Animation.new()
	animation.length = length
	var track := animation.add_track(Animation.TYPE_METHOD)
	# CharacterAnimationPlayer 的 root_node 为角色 Visual，因此方法轨道必须明确
	# 指向播放器节点；这与编辑器中制作正式角色动画时的节点路径一致
	animation.track_set_path(track, NodePath("CharacterAnimationPlayer"))
	for release_time: float in release_times:
		animation.track_insert_key(
			track,
			release_time,
			{"method": &"release_action", "args": []}
		)
	if include_finish:
		animation.track_insert_key(
			track,
			length,
			{"method": &"finish_action", "args": []}
		)
	return animation


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if is_instance_valid(_world):
		_world.queue_free()
	if _failures.is_empty():
		print("AISkillActionAnimationTest: PASS")
		quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	quit(1)
