extends SceneTree

## Guardian 嘲讽释放视觉契约：可加载、可重播，并明确显示五米瞬时作用范围。

const EFFECT_PATH := (
	"res://Effects/Skills/GuardianTaunt/GuardianTauntReleaseEffect.tscn"
)
const PREVIEW_PATH := (
	"res://Effects/Skills/GuardianTaunt/GuardianTauntReleaseEffectPreview.tscn"
)

var _failures: PackedStringArray = []


func _initialize() -> void:
	var scene := load(EFFECT_PATH) as PackedScene
	_expect(scene != null, "Guardian Taunt release effect scene loads")
	if scene == null:
		_finish()
		return
	_expect(
		ResourceLoader.get_resource_uid(EFFECT_PATH) != ResourceUID.INVALID_ID,
		"Guardian Taunt release effect has an editor-indexed UID"
	)
	var effect := scene.instantiate() as Node3D
	effect.set("autoplay", false)
	root.add_child(effect)
	await process_frame
	_expect(effect.has_node(^"ThreatRing"), "Effect owns the expanding ThreatRing")
	_expect(effect.has_node(^"CoreBurst"), "Effect owns the central CoreBurst")
	_expect(effect.has_node(^"BurstParticles"), "Effect owns one-shot BurstParticles")
	_expect(effect.has_node(^"AnimationPlayer"), "Effect owns AnimationPlayer")
	_expect(effect.has_method(&"play"), "Effect exposes replayable play")
	_expect(effect.has_method(&"stop"), "Effect exposes stop")
	_expect(
		is_equal_approx(float(effect.get("effect_radius")), 5.0),
		"Effect communicates the five-meter Delivery radius"
	)
	var ring := effect.get_node_or_null(^"ThreatRing") as MeshInstance3D
	var ring_mesh := ring.mesh as TorusMesh if ring != null else null
	_expect(
		ring_mesh != null and is_equal_approx(ring_mesh.outer_radius, 5.0),
		"ThreatRing geometry reaches five meters at full scale"
	)
	var ring_material := ring.material_override as StandardMaterial3D
	_expect(
		ring_material != null and ring_material.emission_enabled,
		"ThreatRing retains emissive readability"
	)
	effect.call(&"play")
	_expect(effect.call(&"is_playing"), "Effect enters its active playback state")
	await create_timer(0.8).timeout
	_expect(not is_instance_valid(effect), "Effect frees itself after natural playback")
	var preview_scene := load(PREVIEW_PATH) as PackedScene
	_expect(preview_scene != null, "Guardian Taunt visual preview scene loads")
	if preview_scene != null:
		_expect(
			ResourceLoader.get_resource_uid(PREVIEW_PATH)
				!= ResourceUID.INVALID_ID,
			"Guardian Taunt preview has an editor-indexed UID"
		)
		var preview := preview_scene.instantiate() as Node3D
		root.add_child(preview)
		await process_frame
		_expect(preview.has_node(^"Ground"), "Preview owns a large ground plane")
		_expect(preview.has_node(^"RangeReference"), "Preview shows a five-meter reference")
		_expect(preview.has_node(^"Camera3D"), "Preview owns an active camera")
		_expect(
			preview.has_node(
				^"PreviewGuardian/GuardianTauntReleaseEffect"
			),
			"Preview instantiates the real release effect"
		)
		preview.queue_free()
		await process_frame
	_finish()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("GuardianTauntReleaseEffectTest: PASS")
		quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	quit(1)
