extends SceneTree

func _init() -> void:
	var scene := load("res://SkillSystem/00-Skills/GuardianShield/GuardianShieldSkill.tscn") as PackedScene
	var skill := scene.instantiate() as SkillBase
	var action := skill.get_node_or_null(^"MeleeAction")
	print("skill=", skill, " action=", action, " payload=", action.get_action_payload(skill.threat_multiplier) if action != null and action.has_method(&"get_action_payload") else {})
	skill.free()
	quit()
