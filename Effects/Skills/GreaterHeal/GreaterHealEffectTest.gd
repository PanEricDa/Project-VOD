extends SceneTree

## 圣印降临特效契约：下降圣印融入目标后产生球形恢复脉冲，且不复用 HolyLight 轮廓。

const EFFECT_PATH := "res://Effects/Skills/GreaterHeal/GreaterHealEffect.tscn"
const PREVIEW_PATH := "res://Effects/Skills/GreaterHeal/GreaterHealEffectPreview.tscn"

var _failures: PackedStringArray = []


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	_expect(ResourceLoader.exists(EFFECT_PATH), "Greater Heal effect scene exists")
	if not ResourceLoader.exists(EFFECT_PATH):
		_finish()
		return
	_expect(
		ResourceLoader.get_resource_uid(EFFECT_PATH) != ResourceUID.INVALID_ID,
		"Greater Heal effect has an editor-indexed UID"
	)
	var scene := load(EFFECT_PATH) as PackedScene
	var effect := scene.instantiate() as Node3D if scene != null else null
	_expect(effect != null, "Greater Heal effect scene instantiates")
	if effect == null:
		_finish()
		return
	effect.set("autoplay", false)
	root.add_child(effect)
	await process_frame

	_expect(effect.has_node(^"DescendingSeal"), "Effect owns the descending holy seal")
	_expect(effect.has_node(^"RecoveryPulse"), "Effect owns the spherical recovery pulse")
	_expect(effect.has_node(^"BlessingMotes"), "Effect owns the trailing blessing motes")
	_expect(effect.has_node(^"AnimationPlayer"), "Effect owns its animation timeline")
	_expect(not effect.has_node(^"GroundRing"), "Effect does not reuse Holy Light's ground ring")
	_expect(not effect.has_node(^"LightColumn"), "Effect does not reuse Holy Light's light column")
	_expect(effect.has_method(&"play") and effect.has_method(&"stop"), "Effect is replayable")

	effect.call(&"play")
	_expect(effect.call(&"is_playing"), "Effect enters active playback")
	var animation_player := effect.get_node(^"AnimationPlayer") as AnimationPlayer
	animation_player.advance(0.12)
	var recovery_pulse := effect.get_node(^"RecoveryPulse") as MeshInstance3D
	_expect(
		not recovery_pulse.visible,
		"Recovery pulse leaves rendering completely while the overhead seal appears"
	)
	animation_player.advance(0.35)
	await process_frame
	_expect(
		recovery_pulse.visible,
		"Recovery pulse enters rendering when the seal reaches the target"
	)
	await create_timer(1.0).timeout
	_expect(not is_instance_valid(effect), "Effect frees itself after natural playback")

	_expect(ResourceLoader.exists(PREVIEW_PATH), "Greater Heal preview scene exists")
	if ResourceLoader.exists(PREVIEW_PATH):
		_expect(
			ResourceLoader.get_resource_uid(PREVIEW_PATH) != ResourceUID.INVALID_ID,
			"Greater Heal preview has an editor-indexed UID"
		)
		var preview_scene := load(PREVIEW_PATH) as PackedScene
		var preview := preview_scene.instantiate() as Node3D if preview_scene != null else null
		_expect(preview != null, "Greater Heal preview instantiates")
		if preview != null:
			root.add_child(preview)
			await process_frame
			_expect(preview.get_script() != null, "Preview controller script loads")
			_expect(preview.has_node(^"PreviewTarget"), "Preview owns a visible target")
			_expect(
				preview.get_node_or_null(^"PreviewTarget/Body") is GeometryInstance3D,
				"Preview target body is a real renderable geometry node"
			)
			_expect(preview.has_node(^"Camera3D"), "Preview owns an active camera")
			_expect(
				preview.has_node(^"PreviewTarget/GreaterHealEffect"),
				"Preview instantiates the real effect"
			)
			preview.queue_free()
			await process_frame
	_finish()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("GreaterHealEffectTest: PASS")
		quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	quit(1)
