extends Node3D

@export_category("Preview Loop")
## 每轮爆炸自然结束后等待多久再重新播放，单位为秒。
@export_range(0.1, 3.0, 0.05) var replay_delay: float = 0.75

@onready var effect: Node3D = $ImpactPoint/FireballExplosionEffect
@onready var preview_camera: Camera3D = $Camera3D


## 设置固定构图并监听效果完成信号，Preview 不参与正式爆炸查询。
func _ready() -> void:
	preview_camera.look_at_from_position(
		Vector3(2.8, 2.0, 3.6),
		Vector3(0.0, 0.38, 0.0),
		Vector3.UP
	)
	if not effect.effect_finished.is_connected(_on_effect_finished):
		effect.effect_finished.connect(_on_effect_finished)


## 保留清晰空白间隔后重播同一个可复用效果实例。
func _on_effect_finished() -> void:
	await get_tree().create_timer(replay_delay).timeout
	if is_instance_valid(effect):
		effect.call("play")
