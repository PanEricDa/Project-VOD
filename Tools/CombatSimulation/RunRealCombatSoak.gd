extends SceneTree

const ROOM := preload("res://Scenes/TestCombatRoom.tscn")
const DRIVER := preload("res://Tools/CombatSimulation/IdealHeroCombatDriver.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var room := ROOM.instantiate() as Node3D
	root.add_child(room)
	await process_frame
	await process_frame
	var hero := room.get_node_or_null(^"Hero") as PlayerBase
	var driver := DRIVER.new() as IdealHeroCombatDriver
	room.add_child(driver)
	driver.configure(hero)
	for enemy_node: Node in room.get_node(^"EnemyContainer").get_children():
		for candidate: Node in enemy_node.get_children():
			var enemy := candidate as EnemyBase
			if enemy != null:
				enemy.get_targeting_component().call("_set_locked_target", hero)
				enemy.enter_combat()
	await create_timer(30.0).timeout
	var remaining := 0
	for node: Node in get_nodes_in_group(&"enemy_targets"):
		if node is EnemyBase and not (node as EnemyBase).is_dead():
			remaining += 1
	print("RealCombatSoak: remaining_enemies=", remaining)
	room.queue_free()
	quit(0)
