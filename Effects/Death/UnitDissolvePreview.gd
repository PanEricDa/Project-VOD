extends Node3D

## 独立预览场景的循环驱动器，用于在编辑器运行场景时观察溶解节奏与边缘高光。

@export_range(0.1, 10.0, 0.05, "or_greater") var cycle_duration: float = 1.2
@export_range(0.0, 5.0, 0.05, "or_greater") var restart_delay: float = 0.5

@onready var _preview_mesh: MeshInstance3D = $PreviewMesh
var _material: ShaderMaterial


func _ready() -> void:
	_material = _preview_mesh.material_override as ShaderMaterial
	if _material == null:
		_material = _preview_mesh.get_active_material(0) as ShaderMaterial
	if _material == null:
		push_warning("UnitDissolvePreview requires a ShaderMaterial on PreviewMesh.")
		return
	_play_loop()


func _play_loop() -> void:
	while is_inside_tree() and _material != null:
		_material.set_shader_parameter(&"dissolve_progress", 0.0)
		var tween := create_tween()
		tween.tween_method(_set_dissolve_progress, 0.0, 1.0, cycle_duration)
		await tween.finished
		await get_tree().create_timer(restart_delay).timeout


func _set_dissolve_progress(progress: float) -> void:
	if _material != null:
		_material.set_shader_parameter(&"dissolve_progress", progress)
