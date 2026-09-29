extends Node3D

## Guardian 嘲讽特效的独立循环预览；不连接技能、单位或仇恨系统。

@onready var effect: Node3D = (
	$PreviewGuardian/GuardianTauntReleaseEffect
)
@onready var preview_camera: Camera3D = $Camera3D


## 设置可完整观察五米范围的固定构图，并连接每轮播放完成事件。
func _ready() -> void:
	preview_camera.look_at_from_position(
		Vector3(7.8, 6.4, 7.8),
		Vector3(0.0, 0.25, 0.0),
		Vector3.UP
	)
	if (
		effect.has_signal(&"effect_finished")
		and not effect.is_connected(&"effect_finished", _on_effect_finished)
	):
		effect.connect(&"effect_finished", _on_effect_finished)


## 每轮自然结束后等待0.8秒再重播，方便观察冲击环起点和完整扩张过程。
func _on_effect_finished() -> void:
	await get_tree().create_timer(0.8).timeout
	if is_instance_valid(effect) and effect.has_method(&"play"):
		effect.call(&"play")
