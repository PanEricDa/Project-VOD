extends Node3D

## 测试场景专用观察器；只读正式信号，不模拟技能成功、不推进或重置生产冷却。
var _host: SkillHostComponent
var _driver: PlayerAttackController
var _slots: Array[Dictionary] = [
	{"accepted":0,"started":0,"released":0,"finished":0,"cancelled":0,"affected":0},
	{"accepted":0,"started":0,"released":0,"finished":0,"cancelled":0,"affected":0},
]
var _action_slots: Dictionary = {}
var _last_reason: StringName = &""
var _feedback: String = "Ready. Press Q / E to test a real cast."
var _labels: Array[Label] = []
var _gather_range: MeshInstance3D
var _combat_mode: bool = false
var _test_mode: int = 0
const SQUAD_SYSTEMS: Array[String] = ["SquadFocusComponent","SquadChainCommandController","ChainSkillPresentationController","SquadChainRoundController","SquadFinisherSelectionController","SquadFinisherExecutionController","SquadChainCommandDisplay","SquadChainRoundDisplay","SquadFinisherSelectionDisplay"]
const TEST_MODE_META: StringName = &"player_skills_threat_test_mode"

# 在子节点进树前隔离，不依赖父process_mode，避免内部ALWAYS组件抢输入/申请暂停。
func _enter_tree() -> void:
	if Engine.is_editor_hint(): return
	_test_mode = clampi(int(get_tree().root.get_meta(TEST_MODE_META,0)),0,2)
	if get_tree().root.has_meta(TEST_MODE_META): get_tree().root.remove_meta(TEST_MODE_META)
	_combat_mode = _test_mode != 0
	var actors := get_node("ValidationActors")
	for actor: Node in actors.get_children():
		if _test_mode == 0 or _test_mode == 1 and actor.name != &"ValidationGuardian":
			actors.remove_child(actor)
			actor.free()
	if _test_mode != 2:
		for label: String in SQUAD_SYSTEMS:
			var component := get_node_or_null(NodePath(label))
			if component != null:
				remove_child(component)
				component.free()

func _ready() -> void:
	if _combat_mode:
		for enemy: EnemyBase in get_node("EnemyContainer").get_children():
			enemy.get_targeting_component().detection_enabled = true
		_feedback = "Threat Combat: E draws enemies; expiry restores normal threat competition."
	get_node("HUD/DebugPanel/Margin/Rows/ToggleCombat").pressed.connect(_toggle_combat_mode)
	get_node("HUD/DebugPanel/Margin/Rows/ToggleCombat").text = "Next: " + ["Threat Combat","Squad Combat","Training"][_test_mode]
	if _test_mode == 2:
		_feedback = "E → Q → 1–4 chain / finisher"
		# 联测使用正式HUD；保留观察器但收起长读数，避免挡住既有伙伴血条。
		var rows := get_node("HUD/DebugPanel/Margin/Rows")
		for label: String in ["Slot0","Slot1","Boundary","ThreatReadout"]:
			rows.get_node(NodePath(label)).hide()
		get_node("HUD/DebugPanel").offset_bottom = 16.0
	var hero := get_node("Hero") as PlayerBase
	_host = hero.get_node("SkillHost") as SkillHostComponent
	_driver = hero.get_node("AttackController") as PlayerAttackController
	_gather_range = get_node_or_null("GatherRangeDebug") as MeshInstance3D
	if _gather_range != null and _gather_range.mesh is TorusMesh:
		_gather_range.mesh = _gather_range.mesh.duplicate() as TorusMesh
	var controller := hero.get_node("PlayerSkillController") as PlayerSkillController
	controller.slot_accepted.connect(_on_accepted)
	controller.slot_rejected.connect(_on_rejected)
	_driver.external_action_lifecycle.connect(_on_action_event)
	for slot: int in range(2):
		var skill := _host.get_regular_skill(slot)
		if skill == null: continue
		skill.cast_started.connect(_on_cast_started.bind(slot))
		skill.delivery_started.connect(_on_delivery_started.bind(slot))
		skill.delivery_finished.connect(_on_delivery_finished.bind(slot))
		_labels.append(get_node("HUD/DebugPanel/Margin/Rows/Slot" + str(slot)) as Label)
	get_node("HUD/DebugPanel/Margin/Rows/Reload").pressed.connect(_reload_scene)
	_update_labels()
	_update_gather_range()

func _process(_delta: float) -> void:
	_update_labels()
	_update_gather_range()

## 返回只读副本供测试/调试；计数来自真实受理/交付/动作事实。affected为受理目标数，不代表物理抵达。
func get_status_snapshot() -> Dictionary:
	return {"slots":_slots.duplicate(true),"last_reason":_last_reason,"feedback":_feedback,"combat_mode":_combat_mode,"test_mode":_test_mode,"threats":get_threat_observation()}

func _on_accepted(slot: int, skill: SkillBase) -> void:
	_slots[slot].accepted += 1
	_last_reason = &""
	_feedback = "Accepted: " + skill.display_name

func _on_rejected(slot: int, reason: StringName) -> void:
	_last_reason = reason
	_feedback = "Rejected %s: %s" % ["Q" if slot == 0 else "E", reason]

func _on_cast_started(_context: SkillContext, slot: int) -> void:
	_slots[slot].started += 1
	_action_slots[_driver.get_external_action_serial()] = slot

func _on_delivery_started(_context: SkillContext, slot: int) -> void:
	_slots[slot].released += 1
	_slots[slot].affected = 0

func _on_delivery_finished(_context: SkillContext, result: SkillDeliveryResult, slot: int) -> void:
	_slots[slot].affected = result.affected_targets.size()

func _on_action_event(_request_id: int, serial: int, event: StringName) -> void:
	if not _action_slots.has(serial) or event == &"release":
		return
	var slot: int = _action_slots[serial]
	_action_slots.erase(serial)
	if event == &"finish": _slots[slot].finished += 1
	elif event == &"cancel": _slots[slot].cancelled += 1

func _update_labels() -> void:
	if not is_instance_valid(_host) or _labels.size() != 2:
		return
	for slot: int in range(2):
		var skill := _host.get_regular_skill(slot)
		if skill == null:
			_labels[slot].text = ("Q" if slot == 0 else "E") + " | EMPTY"
			continue
		var counts: Dictionary = _slots[slot]
		_labels[slot].text = "%s | %s | %s | CD %.1fs\nAccept %d  Start %d  Release %d\nFinish %d  Cancel %d  Affected %d" % [
			"Q" if slot == 0 else "E", skill.display_name,
			SkillBase.SkillState.keys()[skill.get_state()], skill.get_cooldown_remaining(),
			counts.accepted,counts.started,counts.released,counts.finished,counts.cancelled,counts.affected]
	get_node("HUD/DebugPanel/Margin/Rows/Feedback").text = _feedback
	var lines: PackedStringArray = []
	for row: Dictionary in get_threat_observation():
		lines.append("%s | Mark %s | Player %.0f | Target %s" % [row.name,"ON" if row.marked else "OFF",row.player_threat,row.target])
	get_node("HUD/DebugPanel/Margin/Rows/ThreatReadout").text = "\n".join(lines)

# 仅测试显示Q范围，读取Delivery模式/半径：目标范围跟随当前锁定，身前范围保留原朝向计算。
# E范围示意关闭；不复制范围参数，不改变技能目标、交付、冷却或实际聚集落点。
func _update_gather_range() -> void:
	if not is_instance_valid(_gather_range) or not is_instance_valid(_host):
		return
	var skill := _host.get_regular_skill(0)
	var config := skill.delivery as InstantTargetDeliveryConfig if skill != null else null
	var radius: float = config.effect_radius if config != null else 0.0
	var offset: float = config.center_forward_offset_m if config != null else 0.0
	_gather_range.visible = is_finite(radius) and radius > 0.0 and is_finite(offset) and offset >= 0.0
	if not _gather_range.visible:
		return
	var hero := _host.get_parent() as UnitBase
	if hero == null: return
	var center := hero.global_position + hero.get_facing_direction() * offset
	if config.target_collection_mode == InstantTargetDeliveryConfig.TargetCollectionMode.TARGET_RADIUS:
		var target := (hero as PlayerBase).get_locked_target()
		if not is_instance_valid(target) or target.is_dead():
			_gather_range.visible = false
			return
		center = target.global_position
	_gather_range.global_position = center + Vector3(0,0.025,0)
	var torus := _gather_range.mesh as TorusMesh
	if torus != null and not is_equal_approx(torus.outer_radius, radius + 0.025):
		torus.inner_radius = maxf(radius - 0.025,0.0)
		torus.outer_radius = radius + 0.025

## 测试只读快照：返回敌人名、真实绑定状态、玩家合计仇恨和AI锁定目标；不管理第二份计时或改写仇恨。
func get_threat_observation() -> Array[Dictionary]:
	var observations: Array[Dictionary] = []
	var hero := get_node_or_null("Hero") as UnitBase
	if not is_instance_valid(hero): return observations
	for enemy: EnemyBase in get_node("EnemyContainer").get_children():
		var target := enemy.get_targeting_component().get_locked_target()
		observations.append({"name":str(enemy.name),"marked":enemy.get_status_effect_component().has_named_status(&"temporary_threat"),"player_threat":enemy.get_threat_component().get_threat_for(hero),"target":str(target.name) if is_instance_valid(target) else "-"})
	return observations

func _toggle_combat_mode() -> void:
	get_tree().root.set_meta(TEST_MODE_META,(_test_mode+1)%3)
	get_tree().reload_current_scene()

func _reload_scene() -> void:
	get_tree().root.set_meta(TEST_MODE_META,_test_mode)
	get_tree().reload_current_scene()
