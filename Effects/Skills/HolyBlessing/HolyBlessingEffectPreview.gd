extends Node3D
## 独立纯视觉预览：使用正式动作/特效，不运行AI、伤害、增益或终结资格判定。
enum PreviewMode { CAST, RELEASE, BUFF, SEQUENCE }
## 本预览展示的段落；默认完整序列，仅影响预览，不影响正式技能。
@export var preview_mode: PreviewMode = PreviewMode.SEQUENCE
## 是否在结束后自动重播，默认开启；可关闭后用界面按钮手动重播。
@export var auto_repeat: bool = true
const BASE = "res://Effects/Skills/HolyBlessing/"
var _animation: CharacterAnimationEventPlayer
var _cast: Node3D
var _release: Node3D
var _elapsed: float = 0
var _done: bool = false
var _released: bool = false
var _release_radius: float = 1.0

func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	if preview_mode in [PreviewMode.RELEASE,PreviewMode.SEQUENCE]:
		# 只预览含范围段落时读取正式技能；镜头与地板随范围适配，避免8米环被近景裁掉。
		var skill = load("res://SkillSystem/00-Skills/Finisher_HolyBlessing/HolyBlessingFinisherSkill.tscn").instantiate()
		_release_radius = skill.delivery.effect_radius
		skill.free()
		$Camera3D.position = Vector3(1.2,1.4,1.8) * _release_radius
		$Camera3D.look_at(Vector3.ZERO)
		$Floor.mesh = $Floor.mesh.duplicate()
		$Floor.mesh.size = Vector2.ONE * _release_radius * 2.6
	_animation = $Actor/HeroVisual/CharacterAnimationPlayer
	_animation.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	_animation.callback_mode_method = AnimationMixer.ANIMATION_CALLBACK_MODE_METHOD_IMMEDIATE
	_animation.action_release_requested.connect(_release_marker)
	$UI/Panel/VBox/Replay.pressed.connect(restart_preview)
	restart_preview()

## 清空本轮视觉并从头重播；不修改正式场景、动画库或任何战斗数据。
func restart_preview() -> void:
	for child: Node in $Transient.get_children(): child.free()
	_cast = null
	_release = null
	_elapsed = 0
	_done = false
	_released = false
	_animation.stop()
	$Actor.visible = preview_mode != PreviewMode.RELEASE
	$UI/Panel/VBox/Title.text = ["蓄力 · 圣辉回旋","释放 · 杵地赐福","增益 · 圣辉光印","终结 · 圣辉祝福"][preview_mode]
	if preview_mode in [PreviewMode.CAST,PreviewMode.SEQUENCE]:
		_animation.play("Finisher/action")
		_animation.advance(0)
		_cast = _spawn("Cast")
		var profile = load("res://SkillSystem/00-Skills/Finisher_HolyBlessing/HolyBlessingCinematic.tres")
		_cast.configure_cast($Actor,Transform3D(Basis.IDENTITY,Vector3.ZERO),profile.marker_times(&"release_action")[0])
		_cast.play()
	elif preview_mode == PreviewMode.RELEASE:
		_release = _spawn("Release")
	else:
		_spawn("Buff")

func _process(delta: float) -> void:
	_elapsed += delta
	if _done:
		if auto_repeat and _elapsed >= 1: restart_preview()
		return
	if preview_mode in [PreviewMode.CAST,PreviewMode.SEQUENCE]:
		_animation.advance(delta)
		var duration := _animation.get_animation("Finisher/action").length
		if _elapsed >= duration+1.2: _complete()
	elif preview_mode == PreviewMode.RELEASE:
		if not is_instance_valid(_release) or not _release.is_playing(): _complete()
	elif _elapsed >= 3:
		_complete()

func _release_marker() -> void:
	if _released: return
	_released = true
	if is_instance_valid(_cast): _cast.free()
	_cast = null
	if preview_mode == PreviewMode.SEQUENCE:
		_release = _spawn("Release")
		_spawn("Buff")

func _spawn(part: String) -> Node3D:
	var effect := load(BASE+"HolyBlessing"+part+"Effect.tscn").instantiate() as Node3D
	if part != "Buff":
		effect.set("autoplay",false)
		effect.set("auto_free_on_finished",false)
	if part == "Release":
		effect.configure_effect_radius(_release_radius)
	$Transient.add_child(effect)
	if part != "Buff": effect.call("play")
	return effect

func _complete() -> void:
	_done = true
	_elapsed = 0
