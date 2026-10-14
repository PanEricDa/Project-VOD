extends SceneTree
## 验证类型配置被提示读取、全部正式技能分类，以及多个框体样式相互隔离。
const FRAME_PATH = "res://UnitSystem/Components/UI/UnitHealthFrame.tscn"
const BADGE_PATH = "FrameContent/CoreInfo/Header/SkillNoticeClip/SkillNotice"
const TYPES = {
	"GuardianShield/GuardianShieldSkill": 0,
	"GuardianTaunt/GuardianTauntSkill": 3,
	"Firebolt/FireboltSkill": 0,
	"Pyroblast/PyroblastSkill": 0,
	"ExplosiveArrow/ExplosiveArrowSkill": 0,
	"RapidShot/RapidShotSkill": 0,
	"HolyLight/HolyLightSkill": 1,
	"GreaterHeal/GreaterHealSkill": 1,
	"Trig_ExplosiveFragment/ExplosiveFragmentSkill": 0,
	"Trig_BurningSplash/BurningSplashSkill": 0,
	"Combo_GuardianBash/ComboGuardianBashSkill": 0,
	"Combo_GreaterHeal/ComboGreaterHealSkill": 1,
	"Combo_Firebolt/ComboFireboltSkill": 0,
	"Combo_RapidShot/ComboRapidShotSkill": 0,
}
var failures: Array[String] = []
func _initialize() -> void: call_deferred(&"_run")
func _run() -> void:
	var base = SkillBase.new()
	var has_type = false
	for property in base.get_property_list():
		if property.name == "skill_type":
			has_type = true
			_expect(bool(property.usage & PROPERTY_USAGE_EDITOR), "skill type configurable in Inspector")
			_expect(property.hint == PROPERTY_HINT_ENUM, "skill type is a dropdown not a raw number")
	_expect(has_type, "all skills expose a shared skill type")
	base.free()
	if not has_type:
		_finish()
		return
	for content in TYPES:
		var skill = load("res://SkillSystem/00-Skills/" + content + ".tscn").instantiate() as SkillBase
		_expect(skill.get("skill_type") == TYPES[content], content + " has correct primary purpose")
		skill.free()
	var caster = load("res://UnitSystem/AI/Ally/Units/Caster.tscn").instantiate() as AllyBase
	var priest = load("res://UnitSystem/AI/Ally/Units/Priest.tscn").instantiate() as AllyBase
	for actor in [caster, priest]:
		actor.automatic_skill_cast_enabled = false
		root.add_child(actor)
		actor.set_physics_process(false)
	var frames: Array[UnitHealthFrame] = []
	for actor in [caster, priest]:
		var frame = load(FRAME_PATH).instantiate() as UnitHealthFrame
		root.add_child(frame)
		frame.set_presentation_mode(UnitHealthFrame.PresentationMode.COMPACT_ALLY)
		frame.skill_notice_hold_duration = 2.0
		frame.bind_unit(actor)
		frames.append(frame)
	await process_frame
	await process_frame
	var host = caster.get_node("SkillHost") as SkillHostComponent
	var skill = host.get_regular_skill(0)
	var context = SkillContext.new()
	context.caster = caster
	context.host = host
	# 各色必须可区分且保持深色文字可读；不绑死美术色值。
	var colors: Array[Color] = []
	for type in range(4):
		skill.set("skill_type", type)
		skill.cast_started.emit(context)
		var badge = frames[0].get_node(BADGE_PATH) as Panel
		_expect(badge.visible, "type %d shows notice" % type)
		var color = (badge.get_theme_stylebox("panel") as StyleBoxFlat).bg_color
		for previous in colors:
			_expect(Vector3(color.r, color.g, color.b).distance_to(Vector3(previous.r, previous.g, previous.b)) > 0.1, "different skill types have distinct backgrounds")
		colors.append(color)
		_expect(color.get_luminance() > 0.3, "background keeps dark label readable")
	_expect(colors[0].r > colors[0].g and colors[0].r > colors[0].b, "damage background red")
	_expect(colors[1].g > colors[1].r and colors[1].g > colors[1].b, "healing background green")
	_expect(colors[2].b > colors[2].r, "buff background blue")
	_expect(colors[3].r > colors[3].g and colors[3].b > colors[3].g, "debuff background purple")
	skill.set("skill_type", 0)
	skill.cast_started.emit(context)
	var priest_host = priest.get_node("SkillHost") as SkillHostComponent
	var healing = priest_host.get_regular_skill(1)
	var heal_context = SkillContext.new()
	heal_context.caster = priest
	heal_context.host = priest_host
	healing.cast_started.emit(heal_context)
	var damage_style = (frames[0].get_node(BADGE_PATH) as Panel).get_theme_stylebox("panel") as StyleBoxFlat
	var heal_style = (frames[1].get_node(BADGE_PATH) as Panel).get_theme_stylebox("panel") as StyleBoxFlat
	_expect(damage_style.bg_color.is_equal_approx(colors[0]), "healer cast does not recolor caster frame")
	_expect(heal_style.bg_color.is_equal_approx(colors[1]), "healing skill reads configured type without inspecting effects")
	_expect(damage_style != heal_style, "each frame owns its background style")
	for frame in frames: frame.free()
	caster.free()
	priest.free()
	await process_frame
	_finish()
func _expect(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
func _finish() -> void:
	for message in failures: push_error(message)
	if failures.is_empty(): print("SkillTypeNoticeTest: PASS")
	quit(0 if failures.is_empty() else 1)
