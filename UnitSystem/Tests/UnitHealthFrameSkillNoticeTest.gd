extends SceneTree
## 普通技能真实开始→名称右侧提示→停留→右移消失，以及连携/子触发排除、解绑和多实例隔离。
const FRAME_PATH = "res://UnitSystem/Components/UI/UnitHealthFrame.tscn"
const CLIP_PATH = "FrameContent/CoreInfo/Header/SkillNoticeClip"
var failures: Array[String] = []
func _initialize() -> void: call_deferred(&"_run")
func _run() -> void:
	var frame = load(FRAME_PATH).instantiate() as UnitHealthFrame
	root.add_child(frame)
	if not frame.has_node(CLIP_PATH):
		_expect(false, "unit frame provides a skill notice beside name")
		frame.free()
		_finish()
		return
	frame.set_presentation_mode(UnitHealthFrame.PresentationMode.COMPACT_ALLY)
	frame.custom_minimum_size = Vector2(280, 60)
	frame.skill_notice_hold_duration = 0.25
	var actor = load("res://UnitSystem/AI/Ally/Units/Caster.tscn").instantiate() as AllyBase
	actor.automatic_skill_cast_enabled = false
	root.add_child(actor)
	actor.set_physics_process(false)
	var host = actor.get_node("SkillHost") as SkillHostComponent
	frame.bind_unit(actor)
	await process_frame
	await process_frame
	var clip = frame.get_node(CLIP_PATH) as Control
	var badge = clip.get_node("SkillNotice") as Control
	var label = badge.get_node("SkillName") as Label
	var original_width = frame.size.x
	var skill = host.get_regular_skill(0)
	var context = SkillContext.new()
	context.caster = actor
	context.host = host
	# 受理/排队并未开始，不应提示；只观察公开SkillBase开始信号。
	_expect(not badge.visible, "binding alone does not fake a cast")
	skill.cast_started.emit(context)
	_expect(badge.visible and label.text == "Firebolt", "real ordinary cast-start signal shows actual skill name")
	var entry_x = badge.position.x
	await create_timer(0.20).timeout
	_expect(badge.position.x > entry_x and absf(badge.position.x) < 1.0 and badge.visible, "notice enters quickly from left then holds")
	var name_label = frame.get_node("FrameContent/CoreInfo/Header/NameLabel") as Label
	_expect(clip.global_position.x >= name_label.global_position.x + name_label.size.x, "notice is after name not centered over frame")
	_expect(frame.size.x == original_width, "notice does not stretch health frame")
	await create_timer(0.28).timeout
	_expect(badge.position.x > 0.0, "notice exits continuing right")
	await create_timer(0.22).timeout
	_expect(not badge.visible, "notice disappears after hold and exit")
	var chain = context.duplicate_context() as SkillContext
	chain.purpose = SkillContext.Purpose.CHAIN
	host.get_combo_skill().cast_started.emit(chain)
	_expect(not badge.visible, "chain skill excluded")
	var triggered = context.duplicate_context() as SkillContext
	triggered.execution_mode = SkillContext.ExecutionMode.DIRECT_TRIGGER
	skill.cast_started.emit(triggered)
	_expect(not badge.visible, "triggered child excluded")
	var other = load(FRAME_PATH).instantiate() as UnitHealthFrame
	root.add_child(other)
	other.set_presentation_mode(UnitHealthFrame.PresentationMode.COMPACT_ALLY)
	skill.cast_started.emit(context)
	_expect(not other.get_node(CLIP_PATH + "/SkillNotice").visible, "unbound frame does not mirror another actor")
	await create_timer(0.22).timeout
	var second = host.get_regular_skill(1)
	second.cast_started.emit(context)
	_expect(label.text == "Pyroblast", "new ordinary cast replaces old notice without queue")
	await create_timer(0.42).timeout
	_expect(badge.visible, "replacement remains visible past older completion deadline")
	frame.unbind_unit()
	_expect(not badge.visible, "unbind clears notice and animation immediately")
	skill.cast_started.emit(context)
	_expect(not badge.visible, "old actor callback detached")
	frame.bind_unit(actor)
	frame.set_presentation_mode(UnitHealthFrame.PresentationMode.TARGET)
	skill.cast_started.emit(context)
	_expect(not badge.visible, "target layout is not expanded by ally cast display")
	frame.set_presentation_mode(UnitHealthFrame.PresentationMode.COMPACT_ALLY)
	skill.cast_started.emit(context)
	actor.name = "VeryLongCompanionIdentityForTesting"
	frame.refresh_immediately()
	frame.size = Vector2(280, 60)
	await process_frame
	await process_frame
	skill.cast_started.emit(context)
	await create_timer(0.20).timeout
	_expect(badge.visible and label.size.x >= 50.0, "long companion name retains readable skill notice")
	_expect(frame.size.x <= 280.1, "long companion name does not expand health frame")
	actor.apply_damage(99999.0)
	_expect(not badge.visible, "death clears notice")
	actor.free()
	frame.free()
	other.free()
	await process_frame
	_finish()
func _expect(ok: bool, label: String) -> void:
	if not ok: failures.append(label)
func _finish() -> void:
	for message in failures: push_error(message)
	if failures.is_empty(): print("UnitHealthFrameSkillNoticeTest: PASS")
	quit(0 if failures.is_empty() else 1)
