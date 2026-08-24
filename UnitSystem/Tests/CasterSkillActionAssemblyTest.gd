extends SceneTree

## 验证 Caster 以新 UnitSystem 方式装配技能：技能必须位于 UnitBase 的 SkillSocket，
## 且行为状态机的策略应为“技能可用时只施法、技能禁用后才回退普攻”。
const CASTER_SCENE_PATH := "res://UnitSystem/AI/Ally/Units/Caster.tscn"
const MAGIC_GLOBE_ANIMATION_LIBRARY_PATH := "res://Item/Weapon/MagicGlobe/MagicGlobeAnimationLibrary.res"

var failures: Array[String] = []


func _initialize() -> void:
	_expect(
		ResourceLoader.get_resource_uid(MAGIC_GLOBE_ANIMATION_LIBRARY_PATH) != ResourceUID.INVALID_ID,
		"MagicGlobeAnimationLibrary.res has a valid Godot resource UID"
	)
	var caster_scene := load(CASTER_SCENE_PATH) as PackedScene
	_expect(caster_scene != null, "Caster scene loads")
	if caster_scene == null:
		_finish()
		return

	var caster := caster_scene.instantiate() as Node3D
	_expect(caster != null, "Caster scene instantiates")
	if caster == null:
		_finish()
		return
	root.add_child(caster)
	await process_frame

	var skill_host: Node = caster.get_node_or_null(^"SkillHost")
	_expect(skill_host != null, "Caster provides SkillHost")
	if skill_host != null:
		var socket: Node = skill_host.get_node_or_null(^"SkillSocket")
		_expect(socket != null, "Caster SkillHost provides SkillSocket")
		_expect(
			socket != null and socket.get_node_or_null(^"FireboltSkill") != null,
			"FireboltSkill is a direct SkillSocket child"
		)
		var firebolt := socket.get_node_or_null(^"FireboltSkill") as SkillBase
		_expect(
			firebolt != null
			and firebolt.skill_id == &"firebolt",
			"Caster mounts the one-scene Firebolt skill without animation coupling"
		)
		_expect(
			(skill_host.call("get_registered_skills") as Array).size() == 1,
			"Caster registers exactly one skill"
		)
		_expect(
			skill_host.call("get_skill_owner") == caster,
			"Caster SkillHost configures Caster as owner"
		)

	var animation_player := caster.get_node_or_null(
		^"Visual/CasterVisual/CharacterAnimationPlayer"
	) as CharacterAnimationEventPlayer
	_expect(
		animation_player != null
		and animation_player.has_animation(&"unit/Die"),
		"CasterVisual inherits the shared unit/Die animation from AllyVisual"
	)
	_expect(
		animation_player != null
		and animation_player.has_animation(&"weapon/basic_cast_1"),
		"Caster receives generic basic_cast_1 exclusively from Magic Globe"
	)
	_expect(
		animation_player != null
		and not animation_player.has_animation(&"character/basic_cast_1"),
		"CasterVisual does not carry a unit-specific character cast library"
	)
	var combat_system: Node = caster.get_node_or_null(^"CombatSystem")
	_expect(
		combat_system != null
		and combat_system.has_method(&"request_external_action"),
		"Caster combat system exposes the generic skill action driver"
	)

	_expect(
		int(caster.get("combat_action_policy")) == 2,
		"Caster uses skill-only policy with basic fallback when casting is disabled"
	)
	_expect(
		bool(caster.get("automatic_skill_cast_enabled")),
		"Caster enables automatic skill casting"
	)
	_expect(
		is_equal_approx(float(caster.get("shared_action_cooldown_duration")), 1.0),
		"Caster uses one-second shared action cooldown"
	)
	var behavior: Node = caster.get_node_or_null(^"BehaviorStateMachine")
	_expect(
		behavior != null
		and bool(behavior.call("_should_block_basic_attack_for_skills")),
		"enabled skill priority suppresses ordinary basic attacks"
	)
	caster.call("set_skill_casting_enabled", false)
	_expect(
		behavior != null
		and not bool(behavior.call("_should_block_basic_attack_for_skills")),
		"disabling skill casting enables the existing basic-attack fallback"
	)

	caster.queue_free()
	await process_frame
	_finish()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("CasterSkillActionAssemblyTest: PASS")
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	quit(1)
