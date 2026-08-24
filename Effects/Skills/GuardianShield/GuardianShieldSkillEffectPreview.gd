extends Node3D

## Guardian 盾击特效的独立循环预览控制器；不连接正式技能、命中或单位逻辑。

## 使用 Node3D 接口而非新建 class_name 静态类型，确保 Godot 首次扫描脚本时 Preview 也可稳定加载。
@onready var effect: Node3D = $PreviewGuardian/GuardianShieldSkillEffect
@onready var preview_camera: Camera3D = $Camera3D


## 固定构图并在每轮特效结束后等待短暂间隔再重播，方便观察完整起止过程。
func _ready() -> void:
	preview_camera.look_at_from_position(
		Vector3(2.25, 1.35, 3.0),
		Vector3(0.0, 0.35, -0.15),
		Vector3.UP
	)
	if (
		effect.has_signal(&"effect_finished")
		and not effect.is_connected(&"effect_finished", _on_effect_finished)
	):
		effect.connect(&"effect_finished", _on_effect_finished)


## 等待 0.65 秒后重播，保留足够的空档观察下一次盾击起始位置。
func _on_effect_finished() -> void:
	await get_tree().create_timer(0.65).timeout
	if is_instance_valid(effect):
		if effect.has_method(&"play"):
			effect.call(&"play")
