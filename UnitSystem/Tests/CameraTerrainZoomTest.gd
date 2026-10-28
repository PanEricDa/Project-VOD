extends SceneTree
## 地形高度跟随、变焦俯角和既有特写/反馈合成的行为回归。
const CONTROLLER = preload("res://UnitSystem/Components/Camera/CameraFollowController.gd")
const UNIT = preload("res://UnitSystem/Base/00_UnitBase.tscn")
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var exported_script: Script = load("res://UnitSystem/Components/Camera/CameraFollowController.gd")
	var defaults: Variant = exported_script.get_property_default_value("zoom_distances")
	_expect((defaults is PackedFloat32Array or defaults is Array) and defaults.size() == 4, "Inspector exposes the four editable default zoom distances before runtime")
	var f := _fixture()
	await _height_follows_by_default(f)
	var supported: bool = f.rig.get("zoom_pitch_enabled") != null
	_expect(supported, "Inspector exposes zoom-linked pitch controls")
	if supported:
		_zoom_orbit(f)
		_feedback_and_cinematic(f)
		_configuration_edges()
	current_scene = null
	f.world.free()
	for message: String in failures:
		push_error(message)
	print("CameraTerrainZoomTest: PASS" if failures.is_empty() else "CameraTerrainZoomTest: FAIL (%d)" % failures.size())
	quit(0 if failures.is_empty() else 1)

## config 在节点入树前设置，测试真实初始化；每个夹具只包含一个存活玩家。
func _fixture(config: Dictionary = {}) -> Dictionary:
	var world := Node3D.new()
	root.add_child(world)
	current_scene = world
	var player := UNIT.instantiate() as UnitBase
	player.faction_id = &"Player"
	player.position = Vector3(5, 2, -3)
	world.add_child(player)
	player.set_physics_process(false)
	var rig := Node3D.new()
	rig.set_script(CONTROLLER)
	rig.set("initial_zoom_step", 0)
	rig.set("look_ahead_distance", 0.0)
	for key: String in config:
		rig.set(key, config[key])
	var camera := Camera3D.new()
	camera.name = "Camera3D"
	camera.rotation_degrees.x = -50.0
	camera.fov = 45.0
	rig.add_child(camera)
	world.add_child(rig)
	rig.set_process(false)
	camera.make_current()
	return {"world": world, "player": player, "rig": rig, "camera": camera}

## 玩家上升、下降和显式锁定分别验证；米制误差阈值不依赖实现的平滑公式。
func _height_follows_by_default(f: Dictionary) -> void:
	_expect(not bool(f.rig.get("lock_vertical_follow")), "terrain follow is enabled by default")
	f.player.position.y += 4.0
	f.player.reset_physics_interpolation()
	await physics_frame
	await physics_frame
	f.rig.call("_process", 2.0)
	_expect(absf(f.rig.global_position.y - f.player.global_position.y - 9.0) < 0.05, "camera rig rises with player on a higher terrace")
	f.player.position.y -= 10.0
	f.player.reset_physics_interpolation()
	await physics_frame
	await physics_frame
	f.rig.call("_process", 2.0)
	_expect(absf(f.rig.global_position.y - f.player.global_position.y - 9.0) < 0.05, "camera rig descends with player toward a lower terrace")
	f.rig.set("lock_vertical_follow", true)
	var locked_y: float = f.rig.global_position.y
	f.player.position.y += 3.0
	f.player.reset_physics_interpolation()
	f.rig.call("snap_to_target")
	_expect(absf(f.rig.global_position.y - float(f.rig.get("locked_target_height")) - 9.0) < 0.01, "explicit vertical lock remains available")
	f.rig.set("lock_vertical_follow", false)
	f.rig.call("snap_to_target")

## 四档从近到远使用30/45/50/50度；只在最近两档降低俯角，观测真实姿态、高度、视线与FOV。
func _zoom_orbit(f: Dictionary) -> void:
	var rig: Node3D = f.rig
	var camera: Camera3D = f.camera
	_expect(absf(_pitch(camera) - 30.0) < 0.01, "closest zoom has a 30 degree downward view")
	var near_height: float = camera.global_position.y - f.player.global_position.y
	var near_distance: float = camera.global_position.distance_to(f.player.global_position + Vector3.UP)
	_expect(near_height > 1.0 and near_height < 8.0, "close zoom lowers camera height instead of merely rotating in place")
	var last_height := near_height
	for step: int in [1, 2, 3]:
		rig.set("_zoom_step", step)
		rig.call("_process", 2.0)
		var height: float = camera.global_position.y - f.player.global_position.y
		var expected_pitch: float = [30.0, 45.0, 50.0, 50.0][step]
		_expect(absf(_pitch(camera) - expected_pitch) < 0.01, "only the closest two zoom steps flatten pitch: %d" % step)
		_expect(height > last_height, "camera height increases monotonically when zooming farther: %d" % step)
		last_height = height
	_expect(absf(_pitch(camera) - 50.0) < 0.01, "farthest zoom uses configured far pitch")
	_expect(camera.global_position.distance_to(f.player.global_position + Vector3.UP) > near_distance + 8.0, "zoom still increases distance as well as height")
	var far_height := last_height
	rig.set("_zoom_step", 2)
	rig.call("_process", 0.025)
	_expect(absf(_pitch(camera) - 50.0) < 0.01, "moving between distant zoom steps preserves the normal angle during transition")
	rig.call("_process", 2.0)
	rig.set("_zoom_step", 0)
	rig.call("_process", 0.025)
	_expect(_pitch(camera) > 30.0 and _pitch(camera) < 50.0, "pitch transitions smoothly alongside distance")
	_expect(camera.global_position.y - f.player.global_position.y < far_height, "camera begins lowering immediately when zooming in")
	for index: int in range(120):
		rig.call("_process", 1.0 / 60.0)
	_expect(absf(_pitch(camera) - 30.0) < 0.01, "zoom settles at near pitch without drift")
	_expect(absf(camera.global_position.y - f.player.global_position.y - near_height) < 0.01, "repeated zoom returns to the same close height")
	var direction: Vector3 = (f.player.global_position + Vector3.UP - camera.global_position).normalized()
	_expect((-camera.global_basis.z).dot(direction) > 0.999, "lowered camera keeps the player observation point in view")
	_expect(is_equal_approx(camera.fov, 45.0), "zoom pitch preserves authored FOV")
	rig.set("zoom_closest_pitch_degrees", 24.0)
	rig.call("_update_zoom", 0.0)
	_expect(absf(_pitch(camera) - 24.0) < 0.01, "Inspector near angle updates the live orbit")
	rig.set("zoom_closest_pitch_degrees", 30.0)
	rig.call("_update_zoom", 0.0)

## 真实控制器的反馈叠加及特写取消必须恢复当前缩放姿态，避免相机争写。
func _feedback_and_cinematic(f: Dictionary) -> void:
	var camera: Camera3D = f.camera
	var baseline: Transform3D = camera.transform
	var owner_node := Node.new()
	f.world.add_child(owner_node)
	f.rig.call("set_feedback_offset", owner_node, Vector3(0.1, 0.2, 0.0))
	_expect(camera.position.is_equal_approx(baseline.origin + Vector3(0.1, 0.2, 0.0)), "hit feedback composes on zoom orbit")
	f.rig.call("clear_feedback_offset", owner_node)
	_expect(camera.transform.is_equal_approx(baseline), "clearing feedback restores exact orbit pose")
	var clock := SkillExecutionClock.new()
	clock.configure(f.world)
	var profile := SkillCinematicCameraProfile.new()
	profile.hide_closeup_occluders = false
	_expect(f.rig.call("begin_cinematic", 77, f.player.global_transform, profile, clock, f.player), "cinematic can interrupt pitched zoom")
	f.rig.call("_process", 0.1)
	f.rig.call("end_cinematic", 77, true)
	_expect(camera.transform.is_equal_approx(baseline), "cinematic restores both pitch and position")
	owner_node.free()

## 关闭变俯角、空档位和单档配置均走真实初始化，保留旧相机与最小装配。
func _configuration_edges() -> void:
	var previous_scene: Node = current_scene
	var fixed := _fixture({"zoom_pitch_enabled": false})
	_expect(absf(_pitch(fixed.camera) - 50.0) < 0.01 and fixed.camera.position.is_zero_approx(), "disabling pitch preserves authored closest camera")
	fixed.rig.set("_zoom_step", 3)
	fixed.rig.call("_process", 2.0)
	_expect(fixed.camera.position.is_equal_approx(fixed.camera.basis.z * 9.0), "fixed-angle mode preserves original zoom path")
	fixed.world.free()
	var empty := _fixture({"zoom_distances": PackedFloat32Array()})
	_expect(empty.camera.position.is_zero_approx() and absf(_pitch(empty.camera) - 50.0) < 0.01, "empty zoom list preserves authored camera")
	empty.world.free()
	var one := _fixture({"zoom_distances": PackedFloat32Array([2.0])})
	one.rig.call("_process", 0.1)
	_expect(one.camera.transform.is_finite() and absf(_pitch(one.camera) - 30.0) < 0.01, "single zoom step has finite close-angle pose")
	one.world.free()
	# 更多且非等距的档位仍仅在最近两档降低俯角；手工期望值不引用实现公式。
	var many := _fixture({"zoom_distances": PackedFloat32Array([0.0, 2.0, 8.0, 20.0, 40.0])})
	for step: int in range(5):
		many.rig.set("_zoom_step", step)
		many.rig.call("_process", 2.0)
		var expected_pitch: float = [30.0, 45.0, 50.0, 50.0, 50.0][step]
		_expect(absf(_pitch(many.camera) - expected_pitch) < 0.01, "custom distances keep all farther steps at the normal angle: %d" % step)
	many.world.free()
	current_scene = previous_scene

## 实际光轴相对世界水平面的下视角，单位度。
func _pitch(camera: Camera3D) -> float:
	return rad_to_deg(asin(clampf(camera.global_basis.z.normalized().y, -1.0, 1.0)))

## condition 为外部可观测行为；message 说明该行为违反的用户约定。
func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
