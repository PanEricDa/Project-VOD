class_name SkillReleasePresentationPlayer
extends Node
## 技能成功释放的一次性表现播放器；挂在基础技能已有 RuntimeEffects，配置只在技能根节点。
## 请求镜头侧解释只读 profile；source/target 可为空或随后失效，world_transform 是本次有限世界快照。
signal camera_effect_requested(profile: CameraEffectProfile, source: Node3D, target: Node3D, world_transform: Transform3D)
## instance尚未进树，订阅者只登记纯表现时钟；presentation可空以兼容旧工具。
signal release_instance_prepared(presentation: SkillPresentationContext, instance: Node)
## 本次成功释放的各通道已启动；不表示命中，空美术但有表现身份仍通知。
signal release_presentation_started(presentation: SkillPresentationContext)
const SAFETY_SECONDS: float = 30.0

## 只读准备本次资产、世界位置和附着意图，返回独立临时字典；不创建节点或播放。
## context 只在本调用读取，不保存其费用/指令生命周期；anchor 使用 SkillBase.PresentationAnchor。
## action_transform 是本次有限世界发射变换；三个资产均可空，全部为空或世界无效时返回空。
func prepare_release(context: SkillContext, action_transform: Transform3D,
		visual_scene: PackedScene, anchor: int, audio_stream: AudioStream,
		camera_profile: CameraEffectProfile, presentation_context: SkillPresentationContext = null) -> Dictionary:
	if context == null or not action_transform.is_finite() or not _live(context.delivery_parent):
		return {}
	if visual_scene == null and audio_stream == null and camera_profile == null and presentation_context == null:
		return {}
	var source := context.caster if _live(context.caster) else null
	var target := context.resolved_target if _live(context.resolved_target) else null
	var parent: Node3D
	var pose := action_transform
	match anchor:
		SkillBase.PresentationAnchor.CASTER_FEET:
			if source != null:
				parent = source
				var direction: Vector3 = target.global_position - source.global_position if target != null else Vector3.ZERO
				direction.y = 0.0
				if direction.length_squared() <= 0.0001:
					direction = -action_transform.basis.z
					direction.y = 0.0
				var facing := Basis.IDENTITY
				if direction.length_squared() > 0.0001:
					facing = Basis(Vector3.UP, atan2(-direction.x, -direction.z))
				pose = Transform3D(facing, source.global_position)
		SkillBase.PresentationAnchor.RESOLVED_TARGET:
			if target != null:
				parent = target
				pose = target.global_transform
		SkillBase.PresentationAnchor.TARGET_POSITION:
			if context.target_position.is_finite():
				pose = Transform3D(Basis.IDENTITY, context.target_position)
	return {"execution_clock":context.execution_clock, "presentation": presentation_context.for_release(context, pose) if presentation_context != null else null,
		"visual_scene": visual_scene, "audio_stream": audio_stream, "camera_profile": camera_profile,
		"world_transform": pose, "world_parent_ref": weakref(context.delivery_parent),
		"attach_parent_ref": weakref(parent) if parent != null else null,
		"source_ref": weakref(source) if source != null else null,
		"target_ref": weakref(target) if target != null else null}

## 播放已经准备的本次快照；不重新读取技能/目标配置，每个通道可独立留空。
## 所有实例挂在世界或附着单位下，技能/播放器结束不撤回已释放表现；空快照无操作。
func play_release(snapshot: Dictionary) -> void:
	if snapshot.is_empty() or _from_ref(snapshot.get("world_parent_ref")) == null:
		return
	var pose: Transform3D = snapshot.get("world_transform", Transform3D(Basis.IDENTITY, Vector3.INF))
	if not pose.is_finite():
		return
	_play_visual(snapshot)
	if not is_instance_valid(self) or _from_ref(snapshot.get("world_parent_ref")) == null:
		return
	_play_audio(snapshot)
	if not is_instance_valid(self) or _from_ref(snapshot.get("world_parent_ref")) == null:
		return
	var profile := snapshot.get("camera_profile") as CameraEffectProfile
	if profile != null:
		camera_effect_requested.emit(profile, _from_ref(snapshot.get("source_ref")) as Node3D,
			_from_ref(snapshot.get("target_ref")) as Node3D, pose)

	if is_instance_valid(self) and _from_ref(snapshot.get("world_parent_ref")) != null:
		var presentation := snapshot.get("presentation") as SkillPresentationContext
		if presentation != null: release_presentation_started.emit(presentation)

func _play_visual(snapshot: Dictionary) -> void:
	var scene := snapshot.get("visual_scene") as PackedScene
	if scene == null:
		return
	var parent := _from_ref(snapshot.get("attach_parent_ref"))
	if parent == null:
		parent = _from_ref(snapshot.get("world_parent_ref"))
	if parent == null:
		return
	var node := scene.instantiate()
	if not node is Node3D:
		node.free()
		push_warning("Release visual must have a Node3D root; other channels remain enabled.")
		return
	var visual := node as Node3D
	# 与施法表现共用弱归属标记；世界锚点不代表无主，镜头不能误隐藏本人效果。
	if snapshot.get("source_ref") != null: visual.set_meta(&"presentation_source_ref",snapshot.get("source_ref"))
	if visual.has_method(&"set_execution_clock"):
		visual.call(&"set_execution_clock", snapshot.get("execution_clock"))
	var pose: Transform3D = snapshot["world_transform"]
	# 在add_child触发ready之前设置最终局部变换，正确处理带变换的世界/附着父节点。
	visual.transform = (parent as Node3D).global_transform.affine_inverse() * pose if parent is Node3D and not visual.top_level else pose
	if visual.has_signal(&"effect_finished"):
		visual.connect(&"effect_finished", visual.queue_free)
	if visual is GPUParticles3D and visual.one_shot:
		visual.finished.connect(visual.queue_free)
	if visual is CPUParticles3D and visual.one_shot:
		visual.finished.connect(visual.queue_free)
	_arm_watchdog(visual, SAFETY_SECONDS)
	# 可选纯表现接口：入树前消费独立快照，不再查询技能节点或可变施法者。
	var release_fact := snapshot.get("presentation") as SkillPresentationContext
	if release_fact != null and visual.has_method(&"configure_release"):
		visual.call(&"configure_release", release_fact)
	release_instance_prepared.emit(snapshot.get("presentation") as SkillPresentationContext, visual)
	if not is_instance_valid(visual): return
	if not _live(parent) or _from_ref(snapshot.get("world_parent_ref")) == null:
		visual.free()
		return
	# 可选纯视觉范围接口；不支持者保持原状，不改交付、命中或共享资产。
	var presentation := snapshot.get("presentation") as SkillPresentationContext
	if presentation != null and presentation.effect_radius > 0.0 and visual.has_method(&"configure_effect_radius"):
		visual.call(&"configure_effect_radius", presentation.effect_radius)
	parent.add_child(visual)
	if not _live(visual):
		return
	var auto := true
	for property in visual.get_property_list():
		if property.name == "autoplay":
			auto = bool(visual.get("autoplay"))
			break
	if not auto and visual.has_method(&"play"):
		visual.call(&"play")
	elif visual is GPUParticles3D or visual is CPUParticles3D:
		visual.restart()
		visual.emitting = true

func _play_audio(snapshot: Dictionary) -> void:
	var stream := snapshot.get("audio_stream") as AudioStream
	if stream == null:
		return
	if _is_looping_audio(stream):
		push_warning("Release audio must be one-shot; looping stream skipped without modifying the asset.")
		return
	var parent := _from_ref(snapshot.get("world_parent_ref"))
	if parent == null:
		return
	var voice := AudioStreamPlayer3D.new()
	voice.name = "ReleaseAudioVoice"
	voice.stream = stream
	voice.bus = &"SFX" if AudioServer.get_bus_index(&"SFX") >= 0 else &"Master"
	var pose: Transform3D = snapshot["world_transform"]
	voice.transform = (parent as Node3D).global_transform.affine_inverse() * Transform3D(Basis.IDENTITY, pose.origin) if parent is Node3D else Transform3D(Basis.IDENTITY, pose.origin)
	voice.finished.connect(voice.queue_free)
	_arm_watchdog(voice, _get_audio_watchdog_seconds(stream))
	release_instance_prepared.emit(snapshot.get("presentation") as SkillPresentationContext, voice)
	if not is_instance_valid(voice): return
	if not _live(parent) or _from_ref(snapshot.get("world_parent_ref")) == null:
		voice.free()
		return
	parent.add_child(voice)
	if _live(voice): voice.play()

func _is_looping_audio(stream: AudioStream) -> bool:
	return _contains_loop(stream, {})

# 检查资源引用栈而非改共享资源；重复候选不算循环，递归引用本身拒绝播放。
func _contains_loop(stream: AudioStream, stack: Dictionary) -> bool:
	if stream == null:
		return false
	if stream is AudioStreamWAV:
		return stream.loop_mode != AudioStreamWAV.LOOP_DISABLED
	if stream is AudioStreamOggVorbis or stream is AudioStreamMP3:
		return stream.loop
	if stream is AudioStreamRandomizer:
		var id := stream.get_instance_id()
		if stack.has(id):
			return true
		stack[id] = true
		for index in range(stream.get_streams_count()):
			if _contains_loop(stream.get_stream(index), stack):
				return true
		stack.erase(id)
	return false

func _get_audio_watchdog_seconds(stream: AudioStream) -> float:
	var duration := stream.get_length()
	return duration + 1.0 if is_finite(duration) and duration > 0.0 else SAFETY_SECONDS

# 回收定时器属于表现实例；回调仅绑定该实例，不依赖已销毁的技能或播放器。
func _arm_watchdog(instance: Node, duration_seconds: float) -> void:
	var timer := Timer.new()
	timer.name = "ReleaseWatchdog"
	timer.one_shot = true
	timer.wait_time = maxf(duration_seconds, 0.001)
	timer.autostart = true
	timer.timeout.connect(instance.queue_free)
	instance.add_child(timer)

func _live(node: Node) -> bool:
	return is_instance_valid(node) and node.is_inside_tree() and not node.is_queued_for_deletion()

func _from_ref(value: Variant) -> Node:
	if not value is WeakRef:
		return null
	var node := value.get_ref() as Node
	return node if _live(node) else null