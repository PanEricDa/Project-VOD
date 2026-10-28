extends "res://Effects/Combat/RadiusReleaseEffectPlayer.gd"
## 临时仇恨释放脉冲：半径复用既有接口，根节点使用实际释放脚下快照，世界固定。
## presentation为成功释放只读快照；入树前注入，不重读单位姿态或改变技能几何。
func configure_release(presentation: SkillPresentationContext) -> void:
	var pose := presentation.release_caster_transform
	if not pose.is_finite(): return
	pose.origin += -pose.basis.z * presentation.effect_center_forward_offset_m
	transform = pose
