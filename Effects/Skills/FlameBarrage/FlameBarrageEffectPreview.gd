extends Node3D

## 纯视觉预览，使用现有角色外观和用户制作的动画；不调用战斗系统，不改动画库。
## 第 index 颗（从0计数）在 point 世界坐标落点发射，供预览状态显示和验证。
signal shot_emitted(index: int, point: Vector3)
## 第 index 颗的主爆炸已完成；余烬不参与等待。
signal impact_completed(index: int)
## 本轮预览全部主视觉播放结束；不会因角色完成动作而提前结束五发。
signal preview_finished()

enum PreviewMode { CAST, RELEASE, FLIGHT, IMPACT, SEQUENCE }
## 选择本场景展示的视觉段；完整流程包含用户动画、一次主释放、五发飞行及五次命中。
@export var preview_mode: PreviewMode = PreviewMode.SEQUENCE
## 是否在本轮结束后自动重播；默认开启，仅影响预览，不是技能参数。
@export var auto_repeat: bool = true

const BASE := "res://Effects/Skills/FlameBarrage/"
const PARTS := ["Cast", "Release", "Flight", "Impact"]
const FLIGHT_SECONDS := 0.5
const SHOT_INTERVAL := 0.12
const CENTER := Vector3(0, 0, -6.0)
# 固定采样仅用于可重复地观察构图；正式技能日后按圆形区域随机采样。
const OFFSETS := [Vector3(-1.8, 0, 0.7), Vector3(1.6, 0, -0.9), Vector3(0.1, 0, 1.6), Vector3(-1.1, 0, -1.7), Vector3(1.4, 0, 1.0)]
var _elapsed: float = 0.0
var _release_time: float = 1.0 / 3.0
var _next_shot: int = 0
var _released: bool = false
var _done: bool = false
var _effects: Array[Node3D] = []
var _flights: Array[Dictionary] = []
var _finished_impacts: int = 0
var _animation: AnimationPlayer
var _cast_effect: Node3D
var _origin: Node3D

func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_animation = $CasterVisual/CharacterAnimationPlayer
	_animation.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	_animation.callback_mode_method = AnimationMixer.ANIMATION_CALLBACK_MODE_METHOD_IMMEDIATE
	_animation.action_release_requested.connect(_on_release_marker)
	_origin = $CasterVisual/CharacterRoot/WeaponSocket/ProjectileOrigin
	$UI/Panel/Replay.pressed.connect(restart_preview)
	$UI/Panel/Pause.pressed.connect(_toggle_pause)
	var clip := _animation.get_animation("MagicGlobeAnimationLibrary/finish_cast_1")
	for track: int in range(clip.get_track_count()):
		if clip.track_get_type(track) != Animation.TYPE_METHOD:
			continue
		for key: int in range(clip.track_get_key_count(track)):
			if clip.method_track_get_name(track, key) == &"release_action":
				_release_time = clip.track_get_key_time(track, key)
	restart_preview()

## 清理本轮临时对象并从头展示；可在飞行或爆炸中点击，不会遗留上轮火球。
func restart_preview() -> void:
	_animation.stop()
	for child: Node in $Transient.get_children():
		child.free()
	_effects.clear()
	_flights.clear()
	_elapsed = 0.0
	_released = false
	_next_shot = 0
	_finished_impacts = 0
	_done = false
	_cast_effect = null
	$CasterVisual.visible = preview_mode in [PreviewMode.CAST, PreviewMode.SEQUENCE]
	$UI/Panel/Title.text = ["蓄力 · 破碎焰冠", "释放 · 红金火环", "飞行 · 金核短焰", "命中 · 火柱冲击", "终结技 · 五连焰星"][preview_mode]
	if preview_mode in [PreviewMode.CAST, PreviewMode.SEQUENCE]:
		_cast_effect = _spawn_effect("Cast", $CasterVisual.global_position)
		_cast_effect.call("configure_cast", $CasterVisual, _origin.global_transform, _release_time)
		_animation.play("MagicGlobeAnimationLibrary/finish_cast_1")
		_animation.advance(0.0)
	elif preview_mode == PreviewMode.RELEASE:
		_spawn_effect("Release", Vector3(0, 0.8, -3))
	elif preview_mode == PreviewMode.FLIGHT:
		_emit_shot(0, Vector3(-2, 1.0, -3), Vector3(2, 0, -3), false)
	else:
		_spawn_effect("Impact", Vector3(0, 0, -3))
	_update_status()

## 以秒推进预览时间轴；测试或独立驱动时先 set_process(false)，禁止与自动推进重复调用。
func advance_preview(delta: float) -> void:
	if delta <= 0 or not is_finite(delta):
		return
	var remaining := delta
	while remaining > 0.0000001:
		if _done:
			_elapsed += remaining
			if auto_repeat and _elapsed > 2.0:
				restart_preview()
			break
		# 按真正的发射/抵达/主视觉完成时间切分，出生对象不消费出生前的时间。
		var step := minf(remaining, maxf(_seconds_to_boundary(), 0.0000001))
		_elapsed += step
		for fx: Node3D in _effects.duplicate():
			if is_instance_valid(fx):
				fx.call("advance_effect", step)
		_effects = _effects.filter(func(fx: Node3D) -> bool: return is_instance_valid(fx))
		if preview_mode in [PreviewMode.CAST, PreviewMode.SEQUENCE]:
			_animation.advance(step)
		_advance_flights(step)
		if preview_mode == PreviewMode.SEQUENCE and _released:
			while _next_shot < 5 and _elapsed + 0.0000001 >= _release_time + _next_shot * SHOT_INTERVAL:
				_emit_shot(_next_shot, _origin.global_position, CENTER + OFFSETS[_next_shot], true)
				_next_shot += 1
		var finished := false
		if preview_mode == PreviewMode.SEQUENCE:
			finished = _finished_impacts == 5
		elif preview_mode == PreviewMode.FLIGHT:
			finished = _flights.is_empty()
		else:
			finished = _effects.is_empty()
		if finished:
			_done = true
			_elapsed = 0.0
			preview_finished.emit()
		remaining -= step
	_update_status()

func _seconds_to_boundary() -> float:
	var next := INF
	if preview_mode in [PreviewMode.CAST, PreviewMode.SEQUENCE] and not _released:
		next = minf(next, _release_time - _elapsed)
	if preview_mode == PreviewMode.SEQUENCE and _released and _next_shot < 5:
		next = minf(next, _release_time + _next_shot * SHOT_INTERVAL - _elapsed)
	for shot: Dictionary in _flights:
		next = minf(next, FLIGHT_SECONDS - float(shot.age))
	for fx: Node3D in _effects:
		if is_instance_valid(fx) and fx.call("is_playing"):
			next = minf(next, float(fx.call("get_remaining_seconds")))
	return next

func _process(delta: float) -> void:
	if not $UI/Panel/Pause.button_pressed:
		advance_preview(delta)

func _toggle_pause() -> void:
	$UI/Panel/Pause.text = "继续" if $UI/Panel/Pause.button_pressed else "暂停"

func _on_release_marker() -> void:
	if _released:
		return
	_released = true
	if is_instance_valid(_cast_effect):
		_effects.erase(_cast_effect)
		_cast_effect.free()
	_cast_effect = null
	if preview_mode == PreviewMode.SEQUENCE:
		var release := _spawn_effect("Release", _origin.global_position)
		release.global_basis = Basis(Vector3.UP, $CasterVisual.rotation.y)

func _spawn_effect(part: String, point: Vector3) -> Node3D:
	var fx := (load(BASE + "FlameBarrage" + part + "Effect.tscn") as PackedScene).instantiate() as Node3D
	fx.set("autoplay", false)
	fx.set("auto_free_on_finished", false)
	$Transient.add_child(fx)
	fx.global_position = point
	fx.set_process(false)
	if part != "Flight":
		fx.connect("effect_finished", func() -> void:
			_effects.erase(fx)
			fx.queue_free()
		)
	_effects.append(fx)
	fx.call("play")
	return fx

func _emit_shot(index: int, start: Vector3, point: Vector3, with_impact: bool) -> void:
	var carrier := Node3D.new()
	carrier.name = "PreviewShot%d" % index
	$Transient.add_child(carrier)
	carrier.global_position = start
	var visual := (load(BASE + "FlameBarrageFlightEffect.tscn") as PackedScene).instantiate() as Node3D
	visual.set("autoplay", false)
	carrier.add_child(visual)
	visual.set_process(false)
	visual.call("play")
	_flights.append({"carrier": carrier, "visual": visual, "start": start, "end": point, "age": 0.0, "index": index, "impact": with_impact})
	shot_emitted.emit(index, point)

func _advance_flights(delta: float) -> void:
	for shot: Dictionary in _flights.duplicate():
		var old: Vector3 = shot.carrier.global_position
		shot.age += delta
		var t: float = clampf(shot.age / FLIGHT_SECONDS, 0.0, 1.0)
		if FLIGHT_SECONDS - float(shot.age) < 0.0000001:
			t = 1.0
		var point: Vector3 = shot.start.lerp(shot.end, t) + Vector3.UP * sin(PI * t) * 1.6
		shot.carrier.global_position = point
		if old.distance_squared_to(point) > 0.00001:
			shot.carrier.look_at(point + (point - old), Vector3.UP)
		shot.visual.call("advance_effect", delta)
		if t >= 1.0:
			if shot.impact:
				var impact := _spawn_effect("Impact", shot.end)
				impact.connect("effect_finished", _on_impact_completed.bind(int(shot.index)), CONNECT_ONE_SHOT)
			shot.carrier.free()
			_flights.erase(shot)

func _on_impact_completed(index: int) -> void:
	_finished_impacts += 1
	impact_completed.emit(index)

func _update_status() -> void:
	var stage := "完成" if _done else "%.2fs" % _elapsed
	var progress: String = "发射 %d / 5    主爆炸 %d / 5" % [_next_shot, _finished_impacts] if preview_mode == PreviewMode.SEQUENCE else ["蓄力", "主释放", "单发飞行", "主爆炸"][preview_mode]
	$UI/Panel/Status.text = "纯视觉预览 · 无伤害 / AI / 时停\n%s    %s" % [progress, stage]
