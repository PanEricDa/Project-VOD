extends Node3D
## Q独立视觉预览：直接读取正式技能配置，不运行AI/伤害/拉拽，不复制玩法参数。
## 预览所用技能PackedScene，默认旧身前Gather；只读取配置，不启动Gameplay。新目标技能可直接更换本字段复用预览。
@export var skill_scene: PackedScene = preload("res://SkillSystem/00-Skills/Player_Gather/GatherSkill.tscn")
## 是否在一轮演示后自动重播；默认开启，仅控制本预览场景。
@export var auto_repeat: bool = true
var _age: float = 0.0
var _cast_seconds: float = 0.2
var _released: bool = false
var _skill: SkillBase
var _cast: Node3D
var _fact: SkillPresentationContext
var _ctx: SkillContext

func _ready() -> void:
	$UI/Panel/VBox/Replay.pressed.connect(restart_preview)
	_skill = skill_scene.instantiate() as SkillBase
	add_child(_skill)
	restart_preview()

## 清除上轮临时表现并从正式Q参数重新开始；不调用技能释放管线或修改共享资源。
func restart_preview() -> void:
	for node: Node in $Transient.get_children(): node.free()
	_age = 0.0
	_released = false
	_cast_seconds = _skill.get_effective_cast_time()
	_ctx = SkillContext.new()
	_ctx.caster = $Actor
	_ctx.resolved_target = $Actor if _skill.target_relations == TargetResolver.TargetRelationFlag.SELF else get_node("Target")
	_ctx.target_position = _ctx.resolved_target.global_position
	_ctx.delivery_parent = $Transient
	_ctx.release_caster_position = $Actor.global_position
	_ctx.release_facing_direction = Vector3.FORWARD
	var origin: Transform3D = $Actor/Focus.global_transform
	_fact = SkillPresentationContext.create(_skill,_ctx,origin)
	_cast = _skill.cast_effect_scene.instantiate() as Node3D
	_cast.autoplay = false
	$Transient.add_child(_cast)
	_cast.configure_cast($Actor,origin,_cast_seconds)
	_cast.play()
	var data := _fact.get_effect_data(&"pull")
	if bool(data.get("center_on_target",false)):
		$UI/Panel/VBox/Status.text = "Target circle %.1fm / gather at target\nCast %.2fs / pull %.2fs" % [_fact.effect_radius,_cast_seconds,float(data.duration_seconds)]
		return
	$UI/Panel/VBox/Status.text = "Selection %.1fm / offset %.1fm · Gather %.1fm / disk %.1fm\nCast %.2fs · Pull %.2fs · Silver-cyan wind" % [_fact.effect_radius,_fact.effect_center_forward_offset_m,float(data.front_distance_m),float(data.gather_radius_m),_cast_seconds,float(data.duration_seconds)]

func _process(delta: float) -> void:
	_age += delta
	if not _released and _age >= _cast_seconds:
		_released = true
		if is_instance_valid(_cast): _cast.queue_free()
		var player := _skill.get_node("RuntimeEffects") as SkillReleasePresentationPlayer
		player.play_release(player.prepare_release(_ctx,$Actor/Focus.global_transform,_skill.release_effect_scene,_skill.release_effect_anchor,null,null,_fact))
	if auto_repeat and _age > _cast_seconds + 1.5:
		restart_preview()
