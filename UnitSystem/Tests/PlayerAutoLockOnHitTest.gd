extends SceneTree
## 捕捉首击不锁定、后续命中抢目标、非法命中清除手动锁定及监听未解除等回归。
const HERO_PATH := "res://UnitSystem/Player/Hero/Hero.tscn"
const UNIT_PATH := "res://UnitSystem/Base/00_UnitBase.tscn"
var _failures: Array[String] = []
var _world: Node3D

func _initialize() -> void:
	call_deferred(&"_run")

func _run() -> void:
	_world = Node3D.new()
	root.add_child(_world)
	var hero: PlayerBase = load(HERO_PATH).instantiate() as PlayerBase
	_world.add_child(hero)
	hero.set_physics_process(false)
	await process_frame
	await process_frame
	var targeting: PlayerTargetingComponent = hero.get_node(^"TargetingSystem") as PlayerTargetingComponent
	if not "auto_lock_on_hit_enabled" in targeting:
		_expect(false, "targeting exposes the optional auto-lock-on-hit switch")
		_world.queue_free()
		await process_frame
		_finish()
		return
	_expect(bool(targeting.get("auto_lock_on_hit_enabled")), "current Hero enables the test feature")
	var controller: PlayerAttackController = hero.get_node(^"AttackController") as PlayerAttackController
	var first := _target("First", Vector3(0.3,0,-1))
	var second := _target("Second", Vector3(-0.3,0,-1.5))
	var events: Array = []
	targeting.locked_target_changed.connect(func(target: UnitBase) -> void: events.append(target))
	var hp: float = first.get_current_health()
	_hit(controller, first)
	_expect(first.get_current_health() < hp, "real attack damage pipeline was exercised")
	_expect(targeting.get_locked_target() == first, "first valid basic-attack hit locks its enemy")
	_hit(controller, second)
	_expect(targeting.get_locked_target() == first and events.size() == 1, "subsequent hits never overwrite the existing first lock")
	targeting.request_lock(second)
	_hit(controller, first)
	_expect(targeting.get_locked_target() == second, "manual target selection stays authoritative")
	targeting.clear_locked_target()
	_hit(controller, second)
	_expect(targeting.get_locked_target() == second, "next hit relocks after explicit unlock")
	targeting.clear_locked_target()
	targeting.set("auto_lock_on_hit_enabled",false)
	_hit(controller, first)
	_expect(targeting.get_locked_target() == null, "disabled feature does not lock")
	targeting.set("auto_lock_on_hit_enabled",true)
	targeting.set_input_enabled(false)
	_hit(controller, first)
	_expect(targeting.get_locked_target() == null, "result/input lock prevents a new automatic target")
	targeting.set_input_enabled(true)
	var friendly := _target("Friendly",Vector3(0,0,-1))
	friendly.team_id = 1
	var far := _target("Far",Vector3(20,0,0))
	var ungrouped := _target("Ungrouped",Vector3(0,0,-1))
	ungrouped.remove_from_group(&"enemy_targets")
	for invalid: UnitBase in [friendly,far,ungrouped]:
		_hit(controller,invalid)
		_expect(targeting.get_locked_target() == null, "invalid enemy candidate cannot become automatic lock")
	var fragile := _target("Fragile",Vector3(0,0,-1))
	fragile.apply_damage(fragile.get_current_health()-1.0)
	_hit(controller,fragile)
	_expect(fragile.is_dead() and targeting.get_locked_target() == null, "lethal first hit skips the now-dead target")
	_hit(controller,first)
	_expect(targeting.get_locked_target() == first, "next living hit can lock after a lethal candidate")
	first.apply_damage(first.get_current_health())
	_hit(controller,second)
	_expect(targeting.get_locked_target() == second, "same-frame dead lock is replaced by the next valid hit")
	# 重新配置不能重复监听；失败配置和拆卸都解除旧连接。
	targeting.configure(hero)
	targeting.configure(hero)
	var owned_connections: int = 0
	for connection: Dictionary in controller.attack_hit.get_connections():
		var callback: Callable = connection.callable
		if callback.get_object() == targeting:
			owned_connections += 1
	_expect(owned_connections == 1, "repeated configuration keeps exactly one hit listener")
	targeting.configure(null)
	_hit(controller,second)
	_expect(targeting.get_locked_target() == null, "invalid owner configuration disconnects automatic targeting")
	targeting.configure(hero)
	targeting.clear_locked_target()
	controller.unequip_weapon()
	controller.equip_weapon(load("res://Item/Weapon/Shield/IronShieldData.tres"))
	_hit(controller,second)
	_expect(targeting.get_locked_target() == second, "automatic targeting survives a weapon change")
	hero.remove_child(targeting)
	targeting.queue_free()
	await process_frame
	_hit(controller,second)
	for connection: Dictionary in controller.attack_hit.get_connections():
		var callback: Callable = connection.callable
		_expect(callback.get_object() != targeting, "removed targeting component leaves no hit listener")
	_world.queue_free()
	await process_frame
	_finish()

func _target(node_name: String, position_value: Vector3) -> UnitBase:
	var unit: UnitBase = load(UNIT_PATH).instantiate() as UnitBase
	unit.name = node_name
	unit.team_id = 2
	unit.maximum_health = 5000
	unit.position = position_value
	unit.add_to_group(&"enemy_targets")
	_world.add_child(unit)
	return unit

func _hit(controller: PlayerAttackController, target: UnitBase) -> void:
	controller.call("_on_melee_hitbox_attack_hit",target,target.global_position,Vector3.FORWARD,1)

func _expect(ok: bool, message: String) -> void:
	if not ok:
		_failures.append(message)
		push_error("PlayerAutoLockOnHitTest: " + message)

func _finish() -> void:
	if _failures.is_empty():
		print("PlayerAutoLockOnHitTest: PASS")
		quit(0)
	else:
		printerr("PlayerAutoLockOnHitTest: FAIL\n- " + "\n- ".join(_failures))
		quit(1)
