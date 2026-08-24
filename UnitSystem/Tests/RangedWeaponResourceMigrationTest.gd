extends SceneTree

const HERO_PATH: String = "res://UnitSystem/Player/Hero/Hero.tscn"
const DEFINITIONS: Array[Dictionary] = [
	{
		"name": "Bow",
		"data": "res://Item/Weapon/Bow/BowData.tres",
		"visual": "res://Item/Weapon/Bow/BowVisual.tscn",
		"library": (
			"res://Item/Weapon/Bow/BowAnimationLibrary.res"
		),
		"length": 0.38,
	},
]

const TRACK_PATHS: Array[NodePath] = [
	^"CharacterRoot:position",
	^"CharacterRoot:rotation",
	^"CharacterRoot/WeaponSocket:position",
	^"CharacterRoot/WeaponSocket:rotation",
]

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for definition: Dictionary in DEFINITIONS:
		_validate_definition(definition)
	await process_frame
	await _validate_equipment()
	if failures.is_empty():
		print("RangedWeaponResourceMigrationTest: PASS")
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	print(
		"RangedWeaponResourceMigrationTest: FAIL (%d)"
		% failures.size()
	)
	quit(1)


func _validate_definition(definition: Dictionary) -> void:
	var weapon_name: String = definition["name"]
	var data_path: String = definition["data"]
	_expect(
		ResourceLoader.get_resource_uid(data_path) != ResourceUID.INVALID_ID,
		"%s data must have a valid resource UID" % weapon_name
	)
	var data: RangedWeaponData = load(data_path) as RangedWeaponData
	_expect(data != null, "%s data must load" % weapon_name)
	if data == null:
		return
	_expect(
		data.visual_scene != null,
		"%s visual_scene must be assigned" % weapon_name
	)
	_expect(
		data.animation_library != null,
		"%s animation_library must be assigned" % weapon_name
	)
	if data.visual_scene != null:
		_expect(
			data.visual_scene.resource_path == definition["visual"],
			"%s data references the wrong visual" % weapon_name
		)
	if data.animation_library != null:
		_expect(
			data.animation_library.resource_path == definition["library"],
			"%s data references the wrong animation library"
			% weapon_name
		)

	var visual_scene: PackedScene = load(
		definition["visual"]
	) as PackedScene
	_expect(
		visual_scene != null,
		"%s visual scene must load" % weapon_name
	)
	if visual_scene != null:
		var visual: Node = visual_scene.instantiate()
		_expect(
			visual is Node3D,
			"%s visual root must be Node3D" % weapon_name
		)
		_expect(
			visual.get_script() == null,
			"%s visual must not contain a root script" % weapon_name
		)
		visual.free()

	var library: AnimationLibrary = load(
		definition["library"]
	) as AnimationLibrary
	_expect(
		library != null,
		"%s animation library must load" % weapon_name
	)
	if library == null:
		return
	var animation_names: Array[StringName] = (
		library.get_animation_list()
	)
	var expected_names: Array[StringName] = [
		&"RESET",
		&"basic_attack_1",
	]
	_expect(
		animation_names == expected_names,
		"%s library must contain RESET and basic_attack_1 only"
		% weapon_name
	)
	var reset: Animation = library.get_animation(&"RESET")
	var attack: Animation = library.get_animation(&"basic_attack_1")
	if reset == null or attack == null:
		return
	_expect(
		is_equal_approx(
			attack.length,
			float(definition["length"])
		),
		"%s attack length is incorrect" % weapon_name
	)
	_expect(
		attack.get_track_count() == 5,
		"%s attack must contain four value tracks and one release event" % weapon_name
	)
	for track_path: NodePath in TRACK_PATHS:
		var attack_track: int = attack.find_track(
			track_path,
			Animation.TYPE_VALUE
		)
		var reset_track: int = reset.find_track(
			track_path,
			Animation.TYPE_VALUE
		)
		_expect(
			attack_track >= 0,
			"%s missing attack track %s" % [
				weapon_name,
				track_path,
			]
		)
		_expect(
			reset_track >= 0,
			"%s missing RESET track %s" % [
				weapon_name,
				track_path,
			]
		)
		if attack_track < 0 or reset_track < 0:
			continue
		var final_value: Vector3 = attack.track_get_key_value(
			attack_track,
			attack.track_get_key_count(attack_track) - 1
		)
		var reset_value: Vector3 = reset.track_get_key_value(
			reset_track,
			0
		)
		_expect(
			final_value.is_equal_approx(reset_value),
			"%s does not return %s to RESET" % [
				weapon_name,
				track_path,
			]
		)
	var release_track: int = attack.find_track(
		^"CharacterAnimationPlayer",
		Animation.TYPE_METHOD
	)
	_expect(release_track >= 0, "%s must contain a release method track" % weapon_name)
	if release_track >= 0:
		var release_key: Dictionary = attack.track_get_key_value(release_track, 0)
		_expect(
			release_key.get("method", &"") == &"release_projectile",
			"%s release event must call release_projectile" % weapon_name
		)


func _validate_equipment() -> void:
	var hero_scene: PackedScene = load(HERO_PATH) as PackedScene
	_expect(hero_scene != null, "Hero scene must load")
	if hero_scene == null:
		return
	var hero: Node = hero_scene.instantiate()
	root.add_child(hero)
	await process_frame
	var controller: Node = hero.get_node("AttackController")
	for definition: Dictionary in DEFINITIONS:
		var data: RangedWeaponData = load(definition["data"]) as RangedWeaponData
		if data == null:
			continue
		_expect(
			controller.call("equip_weapon", data) == true,
			"%s must equip through PlayerAttackController"
			% definition["name"]
		)
	controller.call("unequip_weapon")
	hero.queue_free()
	await process_frame


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
