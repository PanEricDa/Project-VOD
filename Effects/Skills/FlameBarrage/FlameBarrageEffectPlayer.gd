extends Node3D

## 四个新终结技视觉组件共用的纯表现生命周期；不参与技能、目标、伤害或世界时间调度。
## 主视觉自然结束时通知一次；取消不发出，飞行循环由持有方 stop()。
signal effect_finished()
## 从头开始一次视觉播放时通知；无战斗语义。
signal effect_started()

## 是否进入场景后自动播放；默认开启，受技能托管的实例应在入树前关闭。
@export var autoplay: bool = true
## 自然结束后是否销毁本实例；默认关闭，独立命中特效开启。取消由持有方清理。
@export var auto_free_on_finished: bool = false

var _execution_clock: SkillExecutionClock
var _visual_radius_scale: float = 1.0
var _playing: bool = false
var _speed: float = 1.0
var _source: WeakRef
var _fixed_basis: Basis = Basis.IDENTITY
@onready var _animation: AnimationPlayer = $AnimationPlayer

func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_animation.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	_animation.animation_finished.connect(_on_animation_finished)
	visible = false
	if autoplay:
		play()

## 与现有施法视觉契约一致：source 为施法者，world_origin 为世界发射变换，duration 为实际施法秒数。
## 冠环跟随角色位置但保留起始朝向；发射点偏移用于冠环末端聚光，最短时长0.001秒。
func configure_cast(source: Node3D, world_origin: Transform3D, duration: float) -> void:
	_source = weakref(source) if is_instance_valid(source) else null
	_fixed_basis = Basis(Vector3.UP, world_origin.basis.get_euler().y)
	global_basis = _fixed_basis
	if is_instance_valid(source):
		global_position = source.global_position
	var focus := get_node_or_null("VisualRoot/Focus")
	if focus is Node3D:
		focus.position = _fixed_basis.inverse() * (world_origin.origin - global_position)
	var clip: Animation = $AnimationPlayer.get_animation("effect")
	_speed = clip.length / maxf(duration, 0.001)

## 从头播放场景中的 effect 动画；可在取消后重播，不改变外部世界速度。
func play() -> void:
	_playing = true
	visible = true
	_animation.stop()
	_animation.play("effect")
	_animation.advance(0.0)
	effect_started.emit()

## 立即隐藏并停止；不会发出成功完成通知，也不会销毁由外部持有的对象。
func stop() -> void:
	_playing = false
	_animation.stop()
	visible = false

## 返回当前主视觉是否仍在播放；循环飞行会持续为 true，直至外部停止。
func is_playing() -> bool:
	return _playing

## 注入本实例的请求时钟，null使用原Godot秒数；不登记为战斗投射物或改变世界速度。
func set_execution_clock(clock: SkillExecutionClock) -> void:
	_execution_clock = clock

## 将3米基准爆炸适配本次实际范围；只缩放本实例根节点，不改场景和共享网格。
func configure_impact_radius(radius_m: float) -> void:
	if not is_finite(radius_m) or radius_m <= 0: return
	scale /= _visual_radius_scale
	_visual_radius_scale = radius_m / 3.0
	scale *= _visual_radius_scale

## 返回主视觉剩余秒数，已停止为0，循环飞行为INF；供持有者对齐出生、抵达和完成的时间边界。
func get_remaining_seconds() -> float:
	if not _playing:
		return 0.0
	var clip: Animation = _animation.get_animation("effect")
	if clip.loop_mode != Animation.LOOP_NONE:
		return INF
	return maxf(0.0, clip.length - _animation.current_animation_position) / _speed

## 以秒推进纯视觉；默认由 _process 调用，接入独立表现时钟时先 set_process(false)，避免双重推进。
func advance_effect(delta: float) -> void:
	if not _playing or delta <= 0.0:
		return
	if _source != null:
		var source := _source.get_ref() as Node3D
		if is_instance_valid(source) and source.is_inside_tree():
			global_position = source.global_position
			global_basis = _fixed_basis
	_animation.advance(delta * _speed)

func _process(delta: float) -> void:
	if _execution_clock != null:
		delta = _execution_clock.get_delta(delta, false)
	advance_effect(delta)

func _on_animation_finished(animation_name: StringName) -> void:
	if animation_name != &"effect" or not _playing:
		return
	_playing = false
	visible = false
	effect_finished.emit()
	if auto_free_on_finished:
		queue_free()
