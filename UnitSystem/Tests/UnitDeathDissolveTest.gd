extends SceneTree

## 验证死亡溶解效果的资源契约与 UnitState 的公开控制接口。

const UNIT_SCENE_PATH := "res://UnitSystem/AI/Enemy/EnemyBase.tscn"
const UNIT_BASE_SCENE_PATH := "res://UnitSystem/Base/00_UnitBase.tscn"
const DISSOLVE_SHADER_PATH := "res://Effects/Death/UnitDissolve.gdshader"
const DEFAULT_DEATH_EFFECT_PATH := "res://Effects/Death/DefaultDeathEffect.tscn"
const PREVIEW_SCENE_PATH := "res://Effects/Death/UnitDissolvePreview.tscn"

var _failures: Array[String] = []
var _world: Node3D


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	_world = Node3D.new()
	root.add_child(_world)
	_test_effect_assets()
	_test_dissolve_defaults()
	await _test_dissolve_lifecycle()
	_finish()


func _test_effect_assets() -> void:
	_expect(
		ResourceLoader.exists(DISSOLVE_SHADER_PATH),
		"Unit dissolve shader exists in Effects/Death"
	)


func _test_dissolve_defaults() -> void:
	var scene := load(UNIT_BASE_SCENE_PATH) as PackedScene
	_expect(scene != null, "UnitBase scene loads for dissolve default verification")
	if scene == null:
		return
	var unit := scene.instantiate() as UnitBase
	_expect(unit != null, "UnitBase instantiates for dissolve default verification")
	if unit == null:
		return
	var state := unit.get_node_or_null(^"UnitState") as UnitStateComponent
	_expect(state != null, "UnitBase exposes UnitState for dissolve defaults")
	if state == null:
		return
	_expect(
		is_equal_approx(state.dissolve_duration, 1.5)
		and is_equal_approx(state.dissolve_edge_emission_energy, 50.0)
		and is_equal_approx(state.dissolve_edge_width, 0.06)
		and is_equal_approx(state.dissolve_noise_scale, 3.0),
		"UnitState uses the approved dissolve appearance defaults"
	)
	unit.free()
	_expect(
		load(DEFAULT_DEATH_EFFECT_PATH) is PackedScene,
		"default supplementary death effect scene is loadable"
	)
	_expect(
		load(PREVIEW_SCENE_PATH) is PackedScene,
		"Unit dissolve preview scene is loadable"
	)


func _test_dissolve_lifecycle() -> void:
	var scene := load(UNIT_SCENE_PATH) as PackedScene
	_expect(scene != null, "EnemyBase scene loads")
	if scene == null:
		return
	var unit := scene.instantiate() as UnitBase
	_expect(unit != null, "EnemyBase instantiates as UnitBase")
	if unit == null:
		return
	unit.name = "DissolveLifecycleUnit"
	_world.add_child(unit)
	await process_frame

	var state := unit.get_node_or_null(^"UnitState") as UnitStateComponent
	_expect(state != null, "EnemyBase exposes UnitState")
	if state == null:
		return
	state.death_mode = UnitStateComponent.DeathMode.REMOVE_AFTER_DELAY
	state.remove_after_seconds = 0.0
	state.dissolve_duration = 2.0
	_expect(state.dissolve_duration > 0.0, "dissolve duration has a positive default")

	unit.apply_damage(unit.maximum_health)
	await process_frame
	_expect(
		not state.is_dissolving(),
		"death begins with the character death animation before dissolution"
	)
	await create_timer(1.1).timeout
	_expect(state.is_dissolving(), "dissolve starts after the death presentation")
	_expect(state.has_dissolve_materials(), "dissolve applies per-instance shader materials")
	var dissolve_entries: Array = state.get("_dissolve_materials") as Array
	var first_material := (
		dissolve_entries[0].get("material") as ShaderMaterial
		if not dissolve_entries.is_empty()
		else null
	)
	_expect(
		first_material != null
		and first_material.get_shader_parameter(&"base_texture") != null,
		"dissolve shader retains the source material albedo texture"
	)
	var emission_energy: Variant = state.get("dissolve_edge_emission_energy")
	var noise_offset: Variant = (
		first_material.get_shader_parameter(&"noise_offset")
		if first_material != null
		else null
	)
	var shader_emission_energy: Variant = (
		first_material.get_shader_parameter(&"edge_emission_energy")
		if first_material != null
		else null
	)
	_expect(
		emission_energy is float
		and shader_emission_energy is float
		and is_equal_approx(
			shader_emission_energy as float,
			emission_energy as float
		),
		"dissolve shader receives UnitState edge emission energy"
	)
	_expect(
		noise_offset is Vector3 and noise_offset != Vector3.ZERO,
		"dissolve shader receives a per-death random noise offset"
	)
	var original_material := (
		dissolve_entries[0].get("original_material") as BaseMaterial3D
		if not dissolve_entries.is_empty()
		else null
	)
	_expect(
		first_material != null
		and original_material != null
		and first_material.get_shader_parameter(&"base_uv_scale") == original_material.uv1_scale
		and first_material.get_shader_parameter(&"base_uv_offset") == original_material.uv1_offset
		and first_material.get_shader_parameter(&"use_triplanar") == original_material.uv1_triplanar,
		"dissolve shader retains source UV and triplanar mapping settings"
	)
	unit.revive(1.0)
	await process_frame
	_expect(not state.is_dissolving(), "revive cancels an unfinished dissolve")
	_expect(not state.has_dissolve_materials(), "revive restores source materials")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if is_instance_valid(_world):
		_world.queue_free()
	if _failures.is_empty():
		print("UnitDeathDissolveTest: PASS")
		quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	print("UnitDeathDissolveTest: FAIL (%d)" % _failures.size())
	quit(1)
