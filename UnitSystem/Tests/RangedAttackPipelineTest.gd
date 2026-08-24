class_name RangedAttackPipelineTest
extends RefCounted

## 验证动画事件到远程战斗组件和投射物的第一版装配契约。
func collect_failures() -> Array[String]:
	var failures: Array[String] = []
	var bow: RangedWeaponData = ResourceLoader.load(
		"res://Item/Weapon/Bow/BowData.tres",
		"",
		ResourceLoader.CACHE_MODE_REPLACE
	) as RangedWeaponData
	if bow == null:
		failures.append("BowData must load as RangedWeaponData")
	else:
		if bow.projectile_scene == null:
			failures.append("BowData must reference Arrow.tscn")
		elif bow.projectile_scene.resource_path != "res://Item/Projectiles/Arrow.tscn":
			failures.append("BowData references the wrong projectile scene")

	var events: CharacterAnimationEventPlayer = CharacterAnimationEventPlayer.new()
	if not events.has_method(&"release_projectile"):
		failures.append("CharacterAnimationEventPlayer must expose release_projectile()")
	events.free()

	var visual_scene: PackedScene = ResourceLoader.load(
		"res://UnitSystem/Visuals/Ally/AllyVisual.tscn",
		"",
		ResourceLoader.CACHE_MODE_REPLACE
	) as PackedScene
	var visual: Node = visual_scene.instantiate() if visual_scene != null else null
	if visual == null or visual.get_node_or_null(^"CharacterRoot/WeaponSocket/ProjectileOrigin") == null:
		failures.append("Ally visual must provide WeaponSocket/ProjectileOrigin")
	if visual != null:
		visual.free()

	var arrow_scene: PackedScene = ResourceLoader.load(
		"res://Item/Projectiles/Arrow.tscn",
		"",
		ResourceLoader.CACHE_MODE_REPLACE
	) as PackedScene
	var arrow: Node = arrow_scene.instantiate() if arrow_scene != null else null
	if arrow == null or not arrow.has_method(&"launch"):
		failures.append("Arrow must expose launch()")
	elif not _has_property(arrow, &"hit_rule"):
		failures.append("Arrow must expose an Inspector hit_rule")
	if arrow != null:
		arrow.free()
	return failures


func _has_property(object: Object, property_name: StringName) -> bool:
	for property: Dictionary in object.get_property_list():
		if property.get("name", &"") == property_name:
			return true
	return false
