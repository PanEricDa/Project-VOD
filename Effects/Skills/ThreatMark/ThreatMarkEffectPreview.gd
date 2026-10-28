extends Node3D
## E纯视觉预览：读正式技能半径与状态时长，不施加仇恨、不运行AI或伤害。
## 一轮展示结束后是否自动重播；默认开启，仅影响预览。
@export var auto_repeat: bool = true
var _skill: SkillBase
var _age: float = 0.0
var _duration: float = 8.0
var _ended: bool = false
var _marks: Array[Node3D] = []

func _ready() -> void:
	_skill = load("res://SkillSystem/00-Skills/Player_ThreatMark/ThreatMarkSkill.tscn").instantiate() as SkillBase
	add_child(_skill)
	$UI/Panel/VBox/Replay.pressed.connect(restart_preview)
	$UI/Panel/VBox/Remove.pressed.connect(end_marks)
	restart_preview()

## 清理上轮对象并以正式E当前参数重播释放/目标标记；预览计时不参与实际状态系统。
func restart_preview() -> void:
	for node: Node in $Transient.get_children(): node.free()
	_marks.clear()
	_age = 0.0
	_ended = false
	var effect := _skill.get_node("ThreatChangeSkillEffect") as ThreatChangeSkillEffect
	_duration = effect.duration_seconds
	var ctx := SkillContext.new()
	ctx.caster = $Actor
	ctx.resolved_target = $Actor
	ctx.delivery_parent = $Transient
	ctx.release_caster_position = $Actor.global_position
	ctx.release_facing_direction = Vector3.FORWARD
	var fact := SkillPresentationContext.create(_skill,ctx,$Actor.global_transform)
	var player := _skill.get_node("RuntimeEffects") as SkillReleasePresentationPlayer
	player.play_release(player.prepare_release(ctx,$Actor.global_transform,_skill.release_effect_scene,0,null,null,fact))
	for target: Node3D in $Targets.get_children():
		var mark := effect.status_visual_scene.instantiate() as Node3D
		$Transient.add_child(mark)
		mark.global_position += target.global_position
		_marks.append(mark)
	_update_status()

## 立即模拟状态已结束，只调用共享视觉out，不影响任何单位状态或游戏速度。
func end_marks() -> void:
	if _ended: return
	_ended = true
	for mark: Node3D in _marks:
		if is_instance_valid(mark): mark.finish_presentation()
	_update_status()

func _process(delta: float) -> void:
	_age += delta
	if not _ended and _age >= _duration: end_marks()
	if auto_repeat and _age >= _duration + 1.0:
		restart_preview()
	_update_status()

func _update_status() -> void:
	$UI/Panel/VBox/Status.text = "Range %.1fm · Duration %.1fs\n%s · Pure visual / no threat or AI" % [_skill.delivery.effect_radius,_duration,"Expired" if _ended else "%.1fs remaining" % maxf(_duration-_age,0.0)]
