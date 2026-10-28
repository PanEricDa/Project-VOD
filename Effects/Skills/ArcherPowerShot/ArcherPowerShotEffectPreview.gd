extends Node3D
## 独立纯视觉预览；复用正式特效和终结动作，不调用伤害、AI或终结资格系统。
enum PreviewMode { CAST, FLIGHT, IMPACT, SEQUENCE }
## 选择蓄力、飞行、命中或整段预览；只影响本预览，不是技能配置。
@export var preview_mode: PreviewMode = PreviewMode.SEQUENCE
## 默认自动重复播放；关闭后可点击重播按钮观察单轮。
@export var auto_repeat: bool = true
const BASE := "res://Effects/Skills/ArcherPowerShot/"
var _elapsed: float = 0.0
var _flight_age: float = 0.0
var _flight_seconds: float = 0.14
var _charge: Node3D
var _flight: Node3D
var _impact: Node3D
var _origin: Node3D
var _animation: AnimationPlayer
var _released: bool = false
var _action_done: bool = false
var _done: bool = false
var _launch_position := Vector3.ZERO

func _ready() -> void:
	_animation = $Actor/HeroVisual/CharacterAnimationPlayer
	_animation.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	_animation.callback_mode_method = AnimationMixer.ANIMATION_CALLBACK_MODE_METHOD_IMMEDIATE
	_animation.action_release_requested.connect(_on_release)
	_animation.action_finish_requested.connect(func(): _action_done = true)
	_origin = $Actor/HeroVisual/CharacterRoot/WeaponSocket/ProjectileOrigin
	$UI/Panel/VBox/Replay.pressed.connect(restart_preview)
	var projectile := load("res://Item/Projectiles/ArcherPowerShotProjectile.tscn").instantiate() as Node3D
	_flight_seconds = projectile.get("flight_duration")
	projectile.free()
	restart_preview()

## 清空本轮视觉并重播，允许随时点击，不累积飞行或命中实例。
func restart_preview() -> void:
	for child: Node in $Transient.get_children(): child.free()
	_charge = null
	_flight = null
	_impact = null
	_elapsed = 0.0
	_released = false
	_action_done = false
	_done = false
	_animation.stop()
	$Actor.visible = preview_mode in [PreviewMode.CAST,PreviewMode.SEQUENCE]
	$UI/Panel/VBox/Title.text = ["蓄力 · 翠光汇聚","飞行 · 翠光直射","命中 · 穿出散射","终结 · 蓄力重箭"][preview_mode]
	if preview_mode in [PreviewMode.CAST,PreviewMode.SEQUENCE]:
		_animation.play("Finisher/action")
		_animation.advance(0.0)
		_charge = _spawn("Cast")
		var profile = load("res://SkillSystem/00-Skills/Finisher_ArcherPowerShot/ArcherPowerShotCinematic.tres")
		_charge.call("configure_cast",$Actor,_origin.global_transform,float(profile.marker_times(&"release_action")[0]))
		_charge.call("play")
	elif preview_mode == PreviewMode.FLIGHT:
		_launch()
	else:
		_show_impact()

func _process(delta: float) -> void:
	_elapsed += delta
	if _done:
		if auto_repeat and _elapsed >= 1.0: restart_preview()
		return
	if preview_mode in [PreviewMode.CAST,PreviewMode.SEQUENCE] and not _action_done:
		_animation.advance(delta)
	if is_instance_valid(_flight):
		_flight_age += delta
		_flight.global_position = _launch_position.lerp($TargetPoint.global_position,clampf(_flight_age/_flight_seconds,0,1))
		if _flight_age >= _flight_seconds:
			_flight.free()
			_flight = null
			if preview_mode == PreviewMode.SEQUENCE: _show_impact()
			else: _complete()
	var visual_done: bool = not is_instance_valid(_impact) or not _impact.call("is_playing")
	if preview_mode == PreviewMode.IMPACT and visual_done: _complete()
	if preview_mode in [PreviewMode.SEQUENCE,PreviewMode.CAST] and _action_done and not is_instance_valid(_flight) and visual_done: _complete()

func _on_release() -> void:
	if _released: return
	_released = true
	if is_instance_valid(_charge):
		_charge.call("stop")
		_charge.queue_free()
	_charge = null
	if preview_mode == PreviewMode.SEQUENCE: _launch()

func _launch() -> void:
	_flight = _spawn("Flight")
	_launch_position = _origin.global_position if preview_mode == PreviewMode.SEQUENCE else Vector3(-2,0.7,0)
	_flight_age = 0.0
	_flight.global_position = _launch_position
	_flight.look_at($TargetPoint.global_position)

func _show_impact() -> void:
	_impact = _spawn("Impact")
	_impact.global_position = $TargetPoint.global_position
	var start := _launch_position if preview_mode == PreviewMode.SEQUENCE else Vector3(-2,0.7,0)
	_impact.call("configure_impact_direction",$TargetPoint.global_position-start)

func _spawn(part: String) -> Node3D:
	var fx := load(BASE+"ArcherPowerShot"+part+"Effect.tscn").instantiate() as Node3D
	fx.set("autoplay",false)
	fx.set("auto_free_on_finished",false)
	$Transient.add_child(fx)
	fx.call("play")
	return fx

func _complete() -> void:
	_done = true
	_elapsed = 0.0
