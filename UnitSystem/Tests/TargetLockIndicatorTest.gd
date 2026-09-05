extends SceneTree

## 验证 TargetLockIndicator 三状态（进入/维持/退出）与位置语义的独立行为契约，
## 以及正式圆环场景、shader 材质与状态驱动的视觉装配契约。
## 测试直接实例化脚本节点与正式场景，不加载玩家、敌人或测试房间。
## 状态断言使用 EffectState 的声明顺序数值（ENTER=0, MAINTAIN=1, EXIT=2），
## 与计划锁定的稳定接口一致；所有交互通过公开方法完成，不访问私有字段。

const INDICATOR_SCRIPT_PATH := (
	"res://UnitSystem/Visuals/Targeting/TargetLockIndicator.gd"
)
const INDICATOR_SCENE_PATH := (
	"res://UnitSystem/Visuals/Targeting/TargetLockIndicator.tscn"
)
const INDICATOR_SHADER_PATH := (
	"res://UnitSystem/Visuals/Targeting/TargetLockIndicator.gdshader"
)
## 无头环境下推进动画的计时安全余量，单位为秒。
const TIME_MARGIN := 0.08
## 与 EffectState 枚举声明顺序一一对应的状态数值。
const STATE_ENTER := 0
const STATE_MAINTAIN := 1
const STATE_EXIT := 2

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	await _test_state_controller_contract()
	await _test_scene_visual_contract()
	await _test_enter_exit_scale_continuity()
	await _test_scene_instance_material_isolation()
	_finish()


func _test_state_controller_contract() -> void:
	var indicator_script := load(INDICATOR_SCRIPT_PATH) as GDScript
	_expect(indicator_script != null, "TargetLockIndicator script exists")
	if indicator_script == null:
		return
	var indicator := indicator_script.new() as Node3D
	_expect(indicator != null, "TargetLockIndicator instantiates as Node3D")
	if indicator == null:
		return
	root.add_child(indicator)
	await process_frame

	_expect(not indicator.visible, "fresh indicator stays hidden")
	_expect(
		not bool(indicator.call(&"is_effect_visible")),
		"hidden indicator reports no visible effect"
	)

	var maintain_opacity := float(indicator.get("maintain_opacity"))
	var breathe_amplitude := float(indicator.get("breathe_amplitude"))
	var enter_duration := float(indicator.get("enter_duration"))
	var exit_duration := float(indicator.get("exit_duration"))

	indicator.call(&"play_enter", Vector3(2.0, 0.03, -3.0))
	_expect(
		indicator.visible and bool(indicator.call(&"is_effect_visible")),
		"play_enter makes the effect visible immediately"
	)
	_expect(
		int(indicator.call(&"get_effect_state")) == STATE_ENTER,
		"play_enter enters the ENTER state"
	)
	_expect(
		indicator.global_position.is_equal_approx(Vector3(2.0, 0.03, -3.0)),
		"play_enter places the effect at the requested world position"
	)
	_expect(
		float(indicator.call(&"get_presentation_alpha")) < maintain_opacity,
		"ENTER starts below the maintain opacity"
	)
	_expect(
		indicator.scale.x < 1.0,
		"ENTER starts smaller than the maintain scale"
	)

	await _wait_seconds(enter_duration + TIME_MARGIN)
	_expect(
		int(indicator.call(&"get_effect_state")) == STATE_MAINTAIN,
		"ENTER transitions to MAINTAIN after the enter duration"
	)
	_expect(
		is_equal_approx(indicator.scale.x, 1.0),
		"MAINTAIN restores the uniform scale to one"
	)
	_expect(
		absf(
			float(indicator.call(&"get_presentation_alpha")) - maintain_opacity
		) <= breathe_amplitude + 0.02,
		"MAINTAIN base opacity reaches the maintain value within breathing"
	)
	_expect(
		indicator.visible,
		"MAINTAIN keeps the effect visible"
	)

	indicator.call(&"update_world_position", Vector3(3.5, 0.03, -1.0))
	indicator.call(&"update_world_position", Vector3(-1.0, 0.03, 4.0))
	_expect(
		int(indicator.call(&"get_effect_state")) == STATE_MAINTAIN,
		"position updates do not replay the ENTER state"
	)
	_expect(
		indicator.global_position.is_equal_approx(Vector3(-1.0, 0.03, 4.0)),
		"the effect follows the latest world position"
	)

	var exit_position := indicator.global_position
	indicator.call(&"play_exit")
	_expect(
		int(indicator.call(&"get_effect_state")) == STATE_EXIT,
		"play_exit enters the EXIT state"
	)
	_expect(
		indicator.visible and bool(indicator.call(&"is_effect_visible")),
		"EXIT remains visible until the exit duration elapses"
	)
	await _wait_seconds(exit_duration + TIME_MARGIN)
	_expect(
		not indicator.visible and not bool(indicator.call(&"is_effect_visible")),
		"finished EXIT hides the effect"
	)
	_expect(
		indicator.global_position.is_equal_approx(exit_position),
		"EXIT keeps the last valid world position without touching the target"
	)

	indicator.call(&"play_enter", Vector3(0.5, 0.03, 0.5))
	await _wait_seconds(enter_duration + TIME_MARGIN)
	_expect(
		int(indicator.call(&"get_effect_state")) == STATE_MAINTAIN,
		"a fresh lock reaches MAINTAIN before interruption testing"
	)
	indicator.call(&"play_exit")
	await _wait_seconds(exit_duration * 0.4)
	indicator.call(&"play_enter", Vector3(-4.0, 0.03, 2.0))
	_expect(
		int(indicator.call(&"get_effect_state")) == STATE_ENTER,
		"a new lock interrupts the running EXIT immediately"
	)
	_expect(
		indicator.visible,
		"an interrupted EXIT becomes visible again"
	)
	_expect(
		indicator.global_position.is_equal_approx(Vector3(-4.0, 0.03, 2.0)),
		"the interrupted exit moves to the new target position"
	)
	await _wait_seconds(enter_duration + TIME_MARGIN)
	_expect(
		int(indicator.call(&"get_effect_state")) == STATE_MAINTAIN,
		"the interrupted exit settles into MAINTAIN normally"
	)

	indicator.call(&"hide_immediately")
	_expect(
		not indicator.visible and not bool(indicator.call(&"is_effect_visible")),
		"hide_immediately hides without playing the exit"
	)
	indicator.call(&"play_exit")
	_expect(
		not indicator.visible,
		"play_exit on a hidden effect stays a no-op"
	)
	indicator.call(&"hide_immediately")
	_expect(
		not indicator.visible,
		"repeated hide_immediately stays safe"
	)
	indicator.call(&"update_world_position", Vector3(7.0, 0.03, 7.0))
	_expect(
		not indicator.visible
		and not bool(indicator.call(&"is_effect_visible")),
		"updating the waiting position does not show the effect"
	)
	_expect(
		int(indicator.call(&"get_effect_state")) == STATE_EXIT,
		"updating the waiting position does not change the effect state"
	)
	_expect(
		indicator.global_position.is_equal_approx(Vector3(7.0, 0.03, 7.0)),
		"the waiting position is stored for later use"
	)

	indicator.queue_free()
	await process_frame


func _test_scene_visual_contract() -> void:
	_expect(
		ResourceLoader.exists(INDICATOR_SCENE_PATH),
		"formal indicator scene exists"
	)
	_expect(
		ResourceLoader.exists(INDICATOR_SHADER_PATH),
		"formal indicator shader exists"
	)
	if (
		not ResourceLoader.exists(INDICATOR_SCENE_PATH)
		or not ResourceLoader.exists(INDICATOR_SHADER_PATH)
	):
		return
	var scene := load(INDICATOR_SCENE_PATH) as PackedScene
	var shader_resource := load(INDICATOR_SHADER_PATH) as Shader
	_expect(
		scene != null and shader_resource != null,
		"formal indicator resources load"
	)
	if scene == null or shader_resource == null:
		return

	var shader_text := FileAccess.get_file_as_string(INDICATOR_SHADER_PATH)
	_expect(
		not shader_text.contains("disable_depth_test"),
		"the ring shader keeps normal depth occlusion"
	)

	var indicator := scene.instantiate() as TargetLockIndicator
	_expect(indicator != null, "scene root is a TargetLockIndicator")
	if indicator == null:
		return
	root.add_child(indicator)
	await process_frame
	_expect(not indicator.visible, "scene root stays hidden by default")
	_expect(indicator.top_level, "scene root uses a top-level world transform")

	var ring_root := indicator.get_node_or_null(^"RingRoot")
	var ring_mesh := (
		indicator.get_node_or_null(^"RingRoot/RingMesh") as MeshInstance3D
	)
	_expect(
		ring_root != null and ring_mesh != null,
		"stable RingRoot/RingMesh path exists"
	)
	if ring_mesh == null:
		indicator.queue_free()
		await process_frame
		return

	_expect(
		_count_mesh_instances(indicator) == 1,
		"the scene assembles exactly one formal ring layer"
	)
	_expect(
		not _subtree_has_collision(indicator),
		"the effect subtree contains no collision or pickable nodes"
	)
	var quad := ring_mesh.mesh as QuadMesh
	_expect(quad != null, "RingMesh draws a QuadMesh")
	if quad != null:
		_expect(
			is_equal_approx(quad.size.x, 1.2)
			and is_equal_approx(quad.size.y, 1.2),
			"the ring quad is about 1.2 by 1.2 meters"
		)
	_expect(
		absf(ring_mesh.global_transform.basis.x.dot(Vector3.UP)) < 0.01
			and absf(ring_mesh.global_transform.basis.y.dot(Vector3.UP)) < 0.01,
		"the ring quad lies horizontally"
	)
	_expect(
		ring_mesh.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
		"the ring mesh casts no shadows"
	)

	var material := ring_mesh.get_active_material(0) as ShaderMaterial
	_expect(material != null, "RingMesh uses a ShaderMaterial")
	if material == null:
		indicator.queue_free()
		await process_frame
		return
	_expect(
		material.shader == shader_resource,
		"RingMesh material uses the formal ring shader"
	)
	_expect(
		shader_text.contains("uniform vec4 ring_color")
			and shader_text.contains("uniform float outer_radius")
			and shader_text.contains("uniform float inner_radius")
			and shader_text.contains("uniform float edge_smooth")
			and shader_text.contains("uniform float emission_strength")
			and shader_text.contains("uniform float overall_alpha"),
		"the shader declares ring color, radii, softening and overall alpha uniforms"
	)

	var maintain_opacity := indicator.maintain_opacity
	var breathe_amplitude := indicator.breathe_amplitude
	indicator.play_enter(Vector3(0.0, 0.03, -2.0))
	await _wait_seconds(indicator.enter_duration * 0.5)
	var entering_alpha := float(material.get_shader_parameter("overall_alpha"))
	_expect(
		entering_alpha > 0.0
			and entering_alpha <= maintain_opacity + 0.01,
		"ENTER pushes a rising alpha into the material"
	)
	await _wait_seconds(indicator.enter_duration + TIME_MARGIN)
	_expect(
		int(indicator.get_effect_state()) == STATE_MAINTAIN,
		"the scene instance reaches MAINTAIN"
	)
	var maintain_alpha := float(material.get_shader_parameter("overall_alpha"))
	_expect(
		absf(maintain_alpha - maintain_opacity) <= breathe_amplitude + 0.02,
		"MAINTAIN pushes the breathing base alpha into the material"
	)

	indicator.play_exit()
	await _wait_seconds(indicator.exit_duration + TIME_MARGIN)
	_expect(not indicator.visible, "finished EXIT hides the scene root")
	_expect(
		is_zero_approx(float(material.get_shader_parameter("overall_alpha"))),
		"finished EXIT zeroes the material alpha"
	)

	indicator.queue_free()
	await process_frame


## 验证进入尚未完成时开始退出会从当前缩放继续，不会先跳回完整尺寸。
func _test_enter_exit_scale_continuity() -> void:
	var indicator_script := load(INDICATOR_SCRIPT_PATH) as GDScript
	var indicator := indicator_script.new() as Node3D if indicator_script != null else null
	_expect(indicator != null, "scale-continuity indicator instantiates")
	if indicator == null:
		return
	root.add_child(indicator)
	await process_frame
	indicator.call(&"play_enter", Vector3.ZERO)
	await _wait_seconds(float(indicator.get("enter_duration")) * 0.35)
	var scale_before_exit: float = indicator.scale.x
	indicator.call(&"play_exit")
	await process_frame
	await process_frame
	_expect(
		indicator.scale.x <= scale_before_exit + 0.02,
		"EXIT during ENTER continues from the current scale without enlarging"
	)
	indicator.queue_free()
	await process_frame


## 验证每个正式场景实例独占运行时修改的 ShaderMaterial，透明度不会串扰。
func _test_scene_instance_material_isolation() -> void:
	var scene := load(INDICATOR_SCENE_PATH) as PackedScene
	_expect(scene != null, "material-isolation scene loads")
	if scene == null:
		return
	var first := scene.instantiate() as TargetLockIndicator
	var second := scene.instantiate() as TargetLockIndicator
	_expect(first != null and second != null, "two formal indicator instances instantiate")
	if first == null or second == null:
		if is_instance_valid(first):
			first.free()
		if is_instance_valid(second):
			second.free()
		return
	root.add_child(first)
	root.add_child(second)
	await process_frame
	var first_mesh := first.get_node_or_null(^"RingRoot/RingMesh") as MeshInstance3D
	var second_mesh := second.get_node_or_null(^"RingRoot/RingMesh") as MeshInstance3D
	var first_material := (
		first_mesh.get_active_material(0) as ShaderMaterial
		if first_mesh != null else null
	)
	var second_material := (
		second_mesh.get_active_material(0) as ShaderMaterial
		if second_mesh != null else null
	)
	_expect(
		first_material != null and second_material != null,
		"both indicator instances expose a ShaderMaterial"
	)
	if first_material != null and second_material != null:
		_expect(
			first_material != second_material,
			"formal indicator instances do not share their mutable material"
		)
		first.play_enter(Vector3.ZERO)
		await process_frame
		_expect(
			float(first_material.get_shader_parameter("overall_alpha")) > 0.0
				and is_zero_approx(
					float(second_material.get_shader_parameter("overall_alpha"))
				),
			"changing one indicator alpha does not affect another instance"
		)
	first.queue_free()
	second.queue_free()
	await process_frame


func _count_mesh_instances(node: Node) -> int:
	var count := 1 if node is MeshInstance3D else 0
	for child: Node in node.get_children():
		count += _count_mesh_instances(child)
	return count


func _subtree_has_collision(node: Node) -> bool:
	if node is CollisionObject3D or node is CollisionShape3D:
		return true
	for child: Node in node.get_children():
		if _subtree_has_collision(child):
			return true
	return false


func _wait_seconds(seconds: float) -> void:
	await create_timer(seconds).timeout


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("TargetLockIndicatorTest: PASS")
		quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	print("TargetLockIndicatorTest: FAIL (%d)" % _failures.size())
	quit(1)
