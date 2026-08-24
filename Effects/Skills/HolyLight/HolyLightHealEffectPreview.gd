extends Node3D

## 独立预览场景中的特效实例，只用于循环观察，不参与正式治疗逻辑。
@onready var effect: Node3D = $PreviewTarget/HolyLightHealEffect

## 预览摄像机使用固定构图对准原型角色中心。
@onready var preview_camera: Camera3D = $Camera3D


func _ready() -> void:
	preview_camera.look_at_from_position(
		Vector3(1.8, 1.25, 2.4),
		Vector3(0.0, 0.38, 0.0),
		Vector3.UP
	)
	if not effect.effect_finished.is_connected(_on_effect_finished):
		effect.effect_finished.connect(_on_effect_finished)


## 每次自然结束后等待 0.7 秒再重播，使 0.5 秒效果具有清晰的观察间隔。
func _on_effect_finished() -> void:
	await get_tree().create_timer(0.7).timeout
	if is_instance_valid(effect):
		effect.play()
