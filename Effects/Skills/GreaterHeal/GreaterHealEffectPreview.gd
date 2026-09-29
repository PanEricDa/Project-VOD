extends Node3D

## 强效治疗圣印特效的独立循环预览；不连接技能、单位或生命系统。

@onready var effect: Node3D = $PreviewTarget/GreaterHealEffect
@onready var preview_camera: Camera3D = $Camera3D


## 设置固定观察构图，并连接每轮自然结束事件。
func _ready() -> void:
	preview_camera.look_at_from_position(
		Vector3(3.2, 2.5, 3.2),
		Vector3(0.0, 0.75, 0.0),
		Vector3.UP
	)
	if (
		effect.has_signal(&"effect_finished")
		and not effect.is_connected(&"effect_finished", _on_effect_finished)
	):
		effect.connect(&"effect_finished", _on_effect_finished)


## 每轮结束后等待0.7秒再重播，便于观察圣印出现、下降和脉冲三个阶段。
func _on_effect_finished() -> void:
	await get_tree().create_timer(0.7).timeout
	if is_instance_valid(effect) and effect.has_method(&"play"):
		effect.call(&"play")
