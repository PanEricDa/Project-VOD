extends Node3D

## Preview 只负责展示和循环，不会被正式技能、投射物或战斗系统引用。
@onready var effect: Node3D = $PreviewCaster/CastAnchor/FireballCastChargeEffect
## 固定相机对准施法者手前的 CastAnchor，便于比较尺寸和亮度。
@onready var preview_camera: Camera3D = $Camera3D


func _ready() -> void:
	preview_camera.look_at_from_position(
		Vector3(2.1, 1.35, 2.8),
		Vector3(0.15, 0.55, -0.12),
		Vector3.UP
	)
	if not effect.effect_finished.is_connected(_on_effect_finished):
		effect.effect_finished.connect(_on_effect_finished)


## 每轮自然结束后保留清晰的空白间隔，再启动下一轮蓄力观察。
func _on_effect_finished() -> void:
	await get_tree().create_timer(0.65).timeout
	if is_instance_valid(effect):
		effect.play()
