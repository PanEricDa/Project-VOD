extends SceneTree

const LIBRARY_PATH: String = (
	"res://Item/Weapon/Shield/ShieldAnimationLibrary.res"
)
const REQUIRED_ANIMATIONS: Array[StringName] = [
	&"RESET",
	&"basic_attack_1",
	&"basic_attack_2",
]

var failures: Array[String] = []


func _initialize() -> void:
	var library: AnimationLibrary = load(LIBRARY_PATH) as AnimationLibrary
	_expect(library != null, "ShieldAnimationLibrary.res must load")
	if library == null:
		_finish()
		return

	for animation_name: StringName in REQUIRED_ANIMATIONS:
		_expect(
			library.has_animation(animation_name),
			"Missing animation: %s" % animation_name
		)

	var attack_1: Animation = library.get_animation(&"basic_attack_1")
	var attack_2: Animation = library.get_animation(&"basic_attack_2")
	var reset: Animation = library.get_animation(&"RESET")
	if attack_1 == null or attack_2 == null or reset == null:
		_finish()
		return

	_expect(
		is_equal_approx(attack_1.length, 0.46),
		"basic_attack_1 length must be 0.46s"
	)
	_expect(
		is_equal_approx(attack_2.length, 0.52),
		"basic_attack_2 length must be 0.52s"
	)

	var required_paths: Array[NodePath] = [
		^"CharacterRoot:position",
		^"CharacterRoot:rotation",
		^"CharacterRoot/WeaponSocket:position",
		^"CharacterRoot/WeaponSocket:rotation",
	]
	var attacks: Array[Animation] = [attack_1, attack_2]
	for animation: Animation in attacks:
		for track_path: NodePath in required_paths:
			_expect(
				animation.find_track(
					track_path,
					Animation.TYPE_VALUE
				) >= 0,
				"%s missing track %s" % [
					animation.resource_name,
					track_path,
				]
			)

	var attack_1_socket_position_track: int = attack_1.find_track(
		^"CharacterRoot/WeaponSocket:position",
		Animation.TYPE_VALUE
	)
	if attack_1_socket_position_track >= 0:
		var first_position: Vector3 = attack_1.track_get_key_value(
			attack_1_socket_position_track,
			0
		)
		var minimum_z: float = INF
		for key_index: int in range(
			attack_1.track_get_key_count(
				attack_1_socket_position_track
			)
		):
			var value: Vector3 = attack_1.track_get_key_value(
				attack_1_socket_position_track,
				key_index
			)
			minimum_z = minf(minimum_z, value.z)
		_expect(
			first_position.z - minimum_z >= 0.35,
			"basic_attack_1 must visibly thrust forward"
		)

	var attack_2_socket_position_track: int = attack_2.find_track(
		^"CharacterRoot/WeaponSocket:position",
		Animation.TYPE_VALUE
	)
	if attack_2_socket_position_track >= 0:
		var minimum_x: float = INF
		var maximum_x: float = -INF
		for key_index: int in range(
			attack_2.track_get_key_count(
				attack_2_socket_position_track
			)
		):
			var value: Vector3 = attack_2.track_get_key_value(
				attack_2_socket_position_track,
				key_index
			)
			minimum_x = minf(minimum_x, value.x)
			maximum_x = maxf(maximum_x, value.x)
		_expect(
			maximum_x - minimum_x >= 0.45,
			"basic_attack_2 must have a readable left-to-right arc"
		)

	# PlayerAttackController 会在连击等待或整轮结束时显式播放 RESET。
	# 因此攻击动画不需要自行回到初始姿势，但 RESET 必须为所有受控路径提供基准键。
	for track_path: NodePath in required_paths:
		var reset_track: int = reset.find_track(
			track_path,
			Animation.TYPE_VALUE
		)
		_expect(
			reset_track >= 0 and reset.track_get_key_count(reset_track) > 0,
			"RESET must define a baseline key for %s" % track_path
		)

	_finish()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("ShieldAnimationLibraryTest: PASS")
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	print(
		"ShieldAnimationLibraryTest: FAIL (%d)" % failures.size()
	)
	quit(1)
