extends Node3D
## 状态视觉的纯动画生命周期；gain/idle由场景维护，状态结束只触发out，不读取增益数值或时长。
var _ending: bool = false

func _ready() -> void:
	$AnimationPlayer.animation_finished.connect(_on_animation_finished)

## 状态已经移除后调用，清空待播并播放有限非循环out；缺少合法out时立即回收。重复调用无效。
func finish_presentation() -> void:
	if _ending: return
	_ending = true
	var player := $AnimationPlayer as AnimationPlayer
	player.clear_queue()
	var animation := player.get_animation(&"out") if player.has_animation(&"out") else null
	if animation == null or animation.loop_mode != Animation.LOOP_NONE or animation.length <= 0:
		queue_free()
		return
	player.play(&"out")

func _on_animation_finished(animation_name: StringName) -> void:
	if _ending:
		if animation_name == &"out": queue_free()
	elif animation_name == &"gain" and $AnimationPlayer.has_animation(&"idle"):
		$AnimationPlayer.play(&"idle")
