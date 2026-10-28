extends SceneTree
## 防止新光矢改变单体伤害、方向丢失、蓄力脱离弩口或慢放后视觉不回收。
const BASE := "res://Effects/Skills/ArcherPowerShot/"
const PROJECTILE := "res://Item/Projectiles/ArcherPowerShotProjectile.tscn"
var failures: Array[String] = []
func _initialize() -> void: call_deferred("_run")
func _run() -> void:
	for part: String in ["Cast","Flight","Impact"]:
		_expect(ResourceLoader.exists(BASE+"ArcherPowerShot"+part+"Effect.tscn"),part+" visual exists")
		_expect(ResourceLoader.exists(BASE+"ArcherPowerShot"+part+"EffectPreview.tscn"),part+" independent preview exists")
	_expect(ResourceLoader.exists(PROJECTILE),"dedicated projectile exists")
	if not failures.is_empty():
		_finish()
		return
	var world := Node3D.new()
	root.add_child(world)
	current_scene = world
	var source := Node3D.new()
	world.add_child(source)
	var anchor := Marker3D.new()
	anchor.name = "ProjectileOrigin"
	source.add_child(anchor)
	anchor.position = Vector3(0.4,1.0,-0.4)
	var charge := load(BASE+"ArcherPowerShotCastEffect.tscn").instantiate() as Node3D
	charge.set("autoplay",false)
	world.add_child(charge)
	charge.call("configure_cast",source,anchor.global_transform,0.8)
	charge.call("play")
	charge.set_process(false)
	anchor.position += Vector3(0.2,0.4,-0.1)
	charge.call("advance_effect",0.2)
	_expect(charge.get_node("VisualRoot/Focus").global_position.is_equal_approx(anchor.global_position),"charge follows the actual moving muzzle")
	charge.call("stop")
	_expect(not charge.visible and not charge.call("is_playing"),"cancel hides every charge visual")
	var parent := Node3D.new()
	parent.rotation.y = 0.7
	world.add_child(parent)
	var target := load("res://UnitSystem/Base/00_UnitBase.tscn").instantiate() as UnitBase
	world.add_child(target)
	target.global_position = Vector3(4,0,0)
	var projectile := load(PROJECTILE).instantiate() as Node3D
	parent.add_child(projectile)
	var facts := {"hits":0,"prepared":0,"ended":0,"direction":Vector3.ZERO}
	projectile.connect("projectile_hit",func(_target, _point, direction):
		facts.hits += 1
		facts.direction = direction
	)
	projectile.connect("impact_presentation_prepared",func(effect):
		facts.prepared += 1
		effect.ready.connect(func():
			_expect((-effect.global_basis.z).dot(Vector3.RIGHT)>0.99,"impact faces world incoming direction under a rotated parent")
		,CONNECT_ONE_SHOT)
		effect.connect("effect_finished",func(): facts.ended += 1,CONNECT_ONE_SHOT)
	)
	_expect(is_zero_approx(projectile.get("arc_height")),"dedicated projectile has no arc")
	_expect(projectile.call("launch",target,Vector3(0,0.25,0)),"dedicated projectile follows the existing launch contract")
	projectile.set_physics_process(false)
	projectile.call("_physics_process",0.07)
	_expect(is_equal_approx(projectile.global_position.y,0.25),"flight stays on the straight trajectory")
	projectile.call("_physics_process",0.08)
	await process_frame
	await create_timer(0.6).timeout
	_expect(facts.hits == 1 and facts.prepared == 1 and facts.ended == 1,"one hit and one directional impact end naturally")
	_expect(target.get_current_health() == target.maximum_health,"visual projectile and scatter alone never apply damage")
	for part: String in ["Cast","Flight","Impact"]:
		var packed := load(BASE+"ArcherPowerShot"+part+"Effect.tscn") as PackedScene
		var fx := packed.instantiate()
		_expect(fx.find_children("*","Area3D",true,false).is_empty(),"visual does not create collision or damage areas")
		fx.free()
	for suffix: String in ["CastEffect","FlightEffect","ImpactEffect","Sequence"]:
		var path := BASE+"ArcherPowerShot"+suffix+"Preview.tscn"
		var preview := load(path).instantiate() as Node3D
		preview.set("auto_repeat",false)
		if suffix == "ImpactEffect": preview.get_node("TargetPoint").position = Vector3(0.4,0.4,-1.7)
		world.add_child(preview)
		if suffix == "Sequence":
			_expect((-preview.get_node("Actor/HeroVisual").global_basis.z).dot(Vector3.RIGHT)>0.99,"preview bow faces its target, not away from it")
		if suffix == "ImpactEffect":
			_expect((-preview.get("_impact").global_basis.z).dot(Vector3(2.4,-0.3,-1.7).normalized())>0.99,"moving preview target updates the exit scatter direction")
		preview.set_process(false)
		for tick: int in range(130):
			preview.call("_process",0.02)
			for fx: Node in preview.get_node("Transient").get_children():
				fx.set_process(false)
				fx.call("advance_effect",0.02)
		_expect(preview.get("_done") == true, suffix+" preview finishes a real playback without AI or damage")
		_expect(ResourceLoader.get_resource_uid(path) != ResourceUID.INVALID_ID,"preview scene has native registered UID")
		preview.free()
	world.free()
	current_scene = null
	await process_frame
	_finish()
func _expect(ok: bool,message: String) -> void:
	if not ok: failures.append(message)
func _finish() -> void:
	for message: String in failures: push_error(message)
	print("ArcherPowerShotVisualEffectTest: ","PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
