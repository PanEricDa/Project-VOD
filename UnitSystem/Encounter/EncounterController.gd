class_name EncounterController
extends Node

## 单个敌群遭遇的运行时状态。
## 控制器只会在登记敌人、战斗状态变化、死亡或异常离树时切换该状态；CLEARED 为本轮终态。
enum PackState { DORMANT, ENGAGED, RESETTING, CLEARED, TRACKING_INVALID }

## 某个 Pack 首次进入本轮战斗时发送。
## pack 是 EnemyContainer 的直接子节点；registered_enemy_count 是本轮初始登记的敌人数量，不会因死亡减少。
signal pack_started(pack: Node3D, registered_enemy_count: int)
## Pack 内全部存活敌人稳定脱战后发送。
## 本版仅通知遭遇重置，不执行回血、复活、强制归位或奖励逻辑。
signal pack_reset(pack: Node3D, registered_enemy_count: int)
## Pack 内所有已登记敌人都经 died 信号确认死亡时发送。
## 不把异常离树或运行时删除误作击杀，确保奖励与开门等后续逻辑不会被错误触发。
signal pack_cleared(pack: Node3D, registered_enemy_count: int)
## 所有非空且追踪有效的 Pack 都已清除时发送一次。
## 此信号不直接决定奖励、门、场景切换或玩家胜负，只提供给未来房间逻辑订阅。
signal room_cleared()
## 已登记敌人未先发送 died 就离开场景树时发送。
## pack 会保持 TRACKING_INVALID，不会再触发本轮 clear，调用方应据此排查生成、删除或场景切换流程。
signal pack_tracking_invalid(pack: Node3D, removed_enemy: EnemyBase)

## Pack 内所有存活敌人脱战后，确认重置前持续保持非战斗的时间，单位为秒。
## 默认 1.0 秒；期间任一敌人重新进入战斗会取消本次重置，仅影响 EncounterController 状态与 pack_reset 信号。
@export_range(0.0, 10.0, 0.05) var reset_delay: float = 1.0

@export_category("Debug")
## 是否把 Pack 遭遇生命周期事件输出到 Godot Output 面板。
## 默认关闭；开启后仅记录 started、reset、cleared、room cleared 与 tracking invalid，
## 不改变敌人 AI、信号发送顺序或任何战斗结果，适用于关卡摆放与流程调试。
@export var debug_log_enabled: bool = false

## 单个 Pack 的内部登记数据。
## 该数据只由 EncounterController 管理，避免把遭遇状态写回 EnemyBase 或行为状态机。
class PackRecord extends RefCounted:
	var pack: Node3D
	var enemies: Array[EnemyBase] = []
	## 与 enemies 相同索引的稳定实例 ID 快照。
	## 敌人死亡特效完成后节点会被释放；此数组让控制器在节点已失效时仍可安全判断其是否已被 died 信号确认击杀，绝不再访问已释放节点的方法。
	var enemy_instance_ids: Array[int] = []
	var defeated_enemy_ids: Dictionary = {}
	var state: PackState = PackState.DORMANT
	var reset_remaining: float = 0.0
	var has_emitted_started: bool = false
	var has_emitted_cleared: bool = false
	var tracking_invalid: bool = false


## 以 Pack 节点为键保存全部登记记录。
## 只有 EnemyContainer 的直接 Node3D 子节点会创建记录，避免递归层级被误认为独立遭遇。
var _records_by_pack: Dictionary = {}

## 是否已经完成初始扫描。
## 未配置时控制器不会产生遭遇事件，防止场景节点仍在进入树时得到不完整敌人列表。
var _is_configured: bool = false
## 是否已收到上层主动场景卸载通知。
## 该运行时标记只抑制当前场景销毁期间的敌人离树误报；不会关闭正常游戏中的异常离树监测。
var _scene_unload_requested: bool = false

## 是否已经发出过当前房间的 room_cleared。
## 该信号在一轮房间遭遇中最多发送一次。
var _has_emitted_room_cleared: bool = false

## 事件到来后是否已经安排帧末结算。
## 通过合并同一帧的 exit_combat 与 died，保证死亡优先于脱战 reset。
var _evaluation_queued: bool = false


## 节点进入场景树后的初始化回调。
## 延迟到当前帧末扫描，确保同一房间中的敌人节点已完成各自的 _ready() 与信号初始化。
func _ready() -> void:
	call_deferred(&"configure_from_parent")


## 从父节点同级的 EnemyContainer 自动登记 Pack 与敌人。
## 此接口可在测试或未来房间重建后显式调用；重复调用会清空旧记录再重新扫描，
## 因此调用方必须只在未进行遭遇结算的安全时机使用。
func configure_from_parent() -> void:
	_records_by_pack.clear()
	_is_configured = false
	_has_emitted_room_cleared = false
	_scene_unload_requested = false
	var room_root: Node = get_parent()
	if not is_instance_valid(room_root):
		push_error("EncounterController: Parent room node is required.")
		return
	var enemy_container := room_root.get_node_or_null(^"EnemyContainer") as Node3D
	if not is_instance_valid(enemy_container):
		push_error("EncounterController: Missing sibling EnemyContainer. Room=" + str(room_root.get_path()))
		return
	for child: Node in enemy_container.get_children():
		if child is Node3D:
			_register_pack(child as Node3D)
	_is_configured = true
	_queue_evaluation()


## 返回指定 Pack 的当前遭遇状态。
## pack 必须是该控制器已经扫描到的 EnemyContainer 直接子节点；未知 Pack 返回 TRACKING_INVALID，供调试调用方安全识别错误引用。
func get_pack_state(pack: Node3D) -> PackState:
	var record := _get_record(pack)
	if record == null:
		return PackState.TRACKING_INVALID
	return record.state


## 返回指定 Pack 初始登记的敌人数量。
## 数量不会因死亡减少，用于 UI 或奖励系统稳定显示本组原始规模；未知 Pack 返回 0。
func get_registered_enemy_count(pack: Node3D) -> int:
	var record := _get_record(pack)
	return record.enemies.size() if record != null else 0


## 返回当前所有 ENGAGED 状态 Pack 中仍存活的敌人列表。
## 纯只读查询；不修改状态、不发射信号、不触发副作用。
## 调用方可以遍历返回值并对每个 EnemyBase 提交仇恨或其他战斗事件。
func get_engaged_enemies() -> Array[EnemyBase]:
	var enemies: Array[EnemyBase] = []
	if not _is_configured:
		return enemies
	for record_value: Variant in _records_by_pack.values():
		var record := record_value as PackRecord
		if record == null or record.state != PackState.ENGAGED:
			continue
		for index: int in range(record.enemies.size()):
			var enemy: EnemyBase = record.enemies[index]
			var enemy_instance_id: int = record.enemy_instance_ids[index]
			if record.defeated_enemy_ids.has(enemy_instance_id):
				continue
			if not is_instance_valid(enemy):
				continue
			enemies.append(enemy)
	return enemies


## 返回指定 Pack 当前仍存活且未被确认击杀的敌人数。
## 异常离树敌人不被计作存活，但会把 Pack 标记为 TRACKING_INVALID，不能据此视为已清除。
func get_alive_enemy_count(pack: Node3D) -> int:
	var record := _get_record(pack)
	return _get_alive_enemy_count(record) if record != null else 0


## 标记当前遭遇控制器即将随场景被正常卸载。
## 该方法必须由场景切换或重新开始流程在调用 reload_current_scene() 前调用；它只忽略本次销毁过程的 tree_exiting，不会改变 Pack 状态、敌人生命或后续新场景的配置。
func begin_scene_unload() -> void:
	_scene_unload_requested = true


## 每帧推进已进入 RESETTING 的 Pack 计时。
## 只有持续无存活敌人处于战斗中，才会在 reset_delay 结束后回到 DORMANT 并发送 pack_reset。
func _process(delta: float) -> void:
	if not _is_configured:
		return
	for record_value: Variant in _records_by_pack.values():
		var record := record_value as PackRecord
		if record == null or record.state != PackState.RESETTING:
			continue
		if _has_any_alive_enemy_in_combat(record):
			_set_engaged(record)
			continue
		record.reset_remaining = maxf(record.reset_remaining - delta, 0.0)
		if record.reset_remaining <= 0.0:
			_clear_pack_target_fallback_resolvers(record)
			record.state = PackState.DORMANT
			record.has_emitted_started = false
			pack_reset.emit(record.pack, record.enemies.size())
			_log_debug("Pack %s reset" % record.pack.name)


## 建立一个 Pack 的递归敌人登记和信号连接。
## 参数 pack 必须是 EnemyContainer 的直接 Node3D 子节点；空 Pack 会保留调试记录但不参与房间完成判定。
func _register_pack(pack: Node3D) -> void:
	var record: PackRecord = PackRecord.new()
	record.pack = pack
	_collect_enemies(pack, record.enemies)
	_records_by_pack[pack] = record
	if record.enemies.is_empty():
		push_warning("EncounterController: Empty Pack is ignored. Pack=" + str(pack.get_path()))
		return
	for enemy: EnemyBase in record.enemies:
		record.enemy_instance_ids.append(enemy.get_instance_id())
		if not enemy.combat_state_changed.is_connected(_on_enemy_combat_state_changed.bind(pack, enemy)):
			enemy.combat_state_changed.connect(_on_enemy_combat_state_changed.bind(pack, enemy))
		if not enemy.died.is_connected(_on_enemy_died.bind(pack, enemy)):
			enemy.died.connect(_on_enemy_died.bind(pack, enemy))
		if not enemy.tree_exiting.is_connected(_on_enemy_tree_exiting.bind(pack, enemy)):
			enemy.tree_exiting.connect(_on_enemy_tree_exiting.bind(pack, enemy))
	_attach_pack_target_fallback_resolvers(record)


## 递归收集 Pack 子树中的 EnemyBase。
## 参数 node 是当前扫描节点；enemies 收集结果仅属于本次 Pack 登记，不会跨 Pack 共享。
func _collect_enemies(node: Node, enemies: Array[EnemyBase]) -> void:
	if node is EnemyBase:
		enemies.append(node as EnemyBase)
	for child: Node in node.get_children():
		_collect_enemies(child, enemies)


## 接收敌人公共战斗状态变化。
## previous_state 与 current_state 仅作为通用状态通知使用；Pack 真实结算在当前帧末统一执行，避免同帧信号顺序影响结果。
func _on_enemy_combat_state_changed(
	_previous_state: UnitBase.CombatState,
	current_state: UnitBase.CombatState,
	pack: Node3D,
	enemy: EnemyBase
) -> void:
	var record := _get_record(pack)
	if current_state == UnitBase.CombatState.IN_COMBAT and record != null:
		_attach_pack_target_fallback_resolvers(record)
		for member: EnemyBase in record.enemies:
			if (
				is_instance_valid(member)
				and member != enemy
				and not member.is_dead()
			):
				member.refresh_targeting()
	_queue_evaluation()


## 接收敌人死亡通知并标记该敌人已被合法击杀。
## source 是伤害或治疗来源，本控制器不消费；enemy 是绑定时保留的实际登记对象，用于区分同 Pack 的多个敌人。
func _on_enemy_died(_source: Node, pack: Node3D, enemy: EnemyBase) -> void:
	var record := _get_record(pack)
	if record == null:
		return
	record.defeated_enemy_ids[enemy.get_instance_id()] = true
	_queue_evaluation()


## 捕捉敌人离开场景树的异常情况。
## 只有未先收到 died 的离树会使 Pack 失效；已确认死亡后由死亡特效删除对象是正常流程，不影响 clear 统计。
func _on_enemy_tree_exiting(pack: Node3D, enemy: EnemyBase) -> void:
	var room_root: Node = get_parent()
	if (
		_scene_unload_requested
		or is_queued_for_deletion()
		or not is_instance_valid(room_root)
		or room_root.is_queued_for_deletion()
		or not room_root.is_inside_tree()
		or not is_instance_valid(pack)
		or not pack.is_inside_tree()
	):
		return
	var record := _get_record(pack)
	if (
		record == null
		or record.state == PackState.CLEARED
		or record.defeated_enemy_ids.has(enemy.get_instance_id())
	):
		return
	if record.tracking_invalid:
		return
	record.tracking_invalid = true
	record.state = PackState.TRACKING_INVALID
	pack_tracking_invalid.emit(pack, enemy)
	_log_debug("Pack %s tracking invalid: %s" % [pack.name, enemy.name])
	push_warning("EncounterController: Enemy left tree without died signal. Pack=" + str(pack.get_path()))


## 合并同一帧的敌人信号，只安排一次帧末遭遇结算。
## 该顺序保证 UnitBase 致死时先出现的 exit_combat 不会抢先把 Pack 误判为 RESETTING。
func _queue_evaluation() -> void:
	if not _is_configured or _evaluation_queued:
		return
	_evaluation_queued = true
	call_deferred(&"_evaluate_packs")


## 在当前帧末按固定优先级结算全部 Pack。
## 优先级为追踪失效、全灭清除、任一存活敌人战斗中、全部存活敌人脱战；CLEARED 不可回退。
func _evaluate_packs() -> void:
	_evaluation_queued = false
	if not _is_configured:
		return
	for record_value: Variant in _records_by_pack.values():
		var record := record_value as PackRecord
		if record == null or record.enemies.is_empty() or record.state == PackState.CLEARED:
			continue
		if record.tracking_invalid:
			record.state = PackState.TRACKING_INVALID
			continue
		if _get_alive_enemy_count(record) == 0:
			_set_cleared(record)
			continue
		if _has_any_alive_enemy_in_combat(record):
			_set_engaged(record)
			continue
		if record.state == PackState.ENGAGED:
			record.state = PackState.RESETTING
			record.reset_remaining = maxf(reset_delay, 0.0)
	_check_room_cleared()


## 将 Pack 标记为战斗中，并仅在新一轮从 DORMANT 进入时发送 pack_started。
## reset 中重入战斗只取消 reset，不重复发送开始信号。
func _set_engaged(record: PackRecord) -> void:
	if record.state == PackState.CLEARED or record.tracking_invalid:
		return
	var should_emit_started: bool = record.state == PackState.DORMANT and not record.has_emitted_started
	record.state = PackState.ENGAGED
	record.reset_remaining = 0.0
	if should_emit_started:
		record.has_emitted_started = true
		pack_started.emit(record.pack, record.enemies.size())
		_log_debug("Pack %s started" % record.pack.name)


## 将 Pack 标记为已清除，并只发送一次 pack_cleared。
## 该状态为终态；后续 reset、再次进入战斗和已死亡节点的离树均不能使其回退。
func _set_cleared(record: PackRecord) -> void:
	if record.has_emitted_cleared:
		return
	record.state = PackState.CLEARED
	_clear_pack_target_fallback_resolvers(record)
	record.reset_remaining = 0.0
	record.has_emitted_cleared = true
	pack_cleared.emit(record.pack, record.enemies.size())
	_log_debug("Pack %s cleared" % record.pack.name)


## 移除 Pack 内所有敌人的运行时目标兜底查询。
## 此方法不改变敌人的生命、仇恨、位置或行为状态，只在 Pack reset/clear 生命周期边界调用。
func _clear_pack_target_fallback_resolvers(record: PackRecord) -> void:
	if record == null:
		return
	for enemy: EnemyBase in record.enemies:
		if is_instance_valid(enemy):
			enemy.clear_pack_target_fallback_resolver()


## 为 Pack 内每个已登记敌人绑定同一控制器提供的目标兜底查询。
## 绑定参数固定为所属 Pack 与注册敌人，运行时请求者由 AITargetingComponent 传入；重复绑定会安全覆盖旧 Callable。
func _attach_pack_target_fallback_resolvers(record: PackRecord) -> void:
	if record == null or not is_instance_valid(record.pack):
		return
	for enemy: EnemyBase in record.enemies:
		if is_instance_valid(enemy):
			enemy.set_pack_target_fallback_resolver(
			Callable(self, "_resolve_pack_fallback_target").bind(record.pack, enemy)
		)


## 为 Pack 成员查询残局接力目标。
## requester 必须是注册时绑定的存活 EnemyBase；只会返回其他存活、战斗中成员当前锁定的有效敌对 UnitBase。
## pack 与 registered_requester 均由 Callable 绑定，用于拒绝跨 Pack、过期或伪造的查询请求。
func _resolve_pack_fallback_target(
	requester: UnitBase,
	pack: Node3D,
	registered_requester: EnemyBase
) -> UnitBase:
	var requester_enemy := requester as EnemyBase
	var record := _get_record(pack)
	if (
		record == null
		or record.state == PackState.CLEARED
		or record.tracking_invalid
		or requester_enemy == null
		or requester_enemy != registered_requester
		or requester_enemy.is_dead()
	):
		return null
	var selected_target: UnitBase
	var selected_distance_squared: float = INF
	var seen_target_ids: Dictionary = {}
	for member: EnemyBase in record.enemies:
		if (
			not is_instance_valid(member)
			or member == requester_enemy
			or member.is_dead()
			or not member.is_in_combat()
		):
			continue
		var targeting := member.get_targeting_component()
		var candidate := targeting.get_locked_target() if targeting != null else null
		if (
			not is_instance_valid(candidate)
			or not candidate.is_inside_tree()
			or candidate.is_dead()
			or not candidate.is_targetable()
			or not requester_enemy.is_hostile_to(candidate)
		):
			continue
		var candidate_id := candidate.get_instance_id()
		if seen_target_ids.has(candidate_id):
			continue
		seen_target_ids[candidate_id] = true
		var offset := candidate.global_position - requester_enemy.global_position
		offset.y = 0.0
		var distance_squared := offset.length_squared()
		if distance_squared < selected_distance_squared:
			selected_distance_squared = distance_squared
			selected_target = candidate
	return selected_target


## 检查所有非空 Pack 是否均清除，并最多发送一次 room_cleared。
## 任何 TRACKING_INVALID 或尚未 CLEARED 的非空 Pack 都会阻止房间完成。
func _check_room_cleared() -> void:
	if _has_emitted_room_cleared:
		return
	var has_non_empty_pack: bool = false
	for record_value: Variant in _records_by_pack.values():
		var record := record_value as PackRecord
		if record == null or record.enemies.is_empty():
			continue
		has_non_empty_pack = true
		if record.state != PackState.CLEARED:
			return
	if has_non_empty_pack:
		_has_emitted_room_cleared = true
		room_cleared.emit()
		_log_debug("Room cleared")


## 返回 Pack 对应的内部记录。
## 未登记、已释放或不属于此控制器的 Pack 返回 null，供所有查询接口安全处理。
func _get_record(pack: Node3D) -> PackRecord:
	if not is_instance_valid(pack):
		return null
	return _records_by_pack.get(pack, null) as PackRecord


## 统计记录中尚未被 died 确认击杀的有效敌人数。
## 若发生未死亡离树，调用方会先将 Pack 标记为 TRACKING_INVALID；本方法只提供计数，不掩盖该异常状态。
func _get_alive_enemy_count(record: PackRecord) -> int:
	var alive_count: int = 0
	for index: int in range(record.enemies.size()):
		var enemy: EnemyBase = record.enemies[index]
		var enemy_instance_id: int = record.enemy_instance_ids[index]
		if not record.defeated_enemy_ids.has(enemy_instance_id) and is_instance_valid(enemy):
			alive_count += 1
	return alive_count


## 判断 Pack 内是否存在至少一名存活且处于公共战斗状态的敌人。
## 死亡敌人不会维持 ENGAGED，避免同帧 exit_combat 与 died 的信号顺序影响最终结算。
func _has_any_alive_enemy_in_combat(record: PackRecord) -> bool:
	for index: int in range(record.enemies.size()):
		var enemy: EnemyBase = record.enemies[index]
		var enemy_instance_id: int = record.enemy_instance_ids[index]
		if record.defeated_enemy_ids.has(enemy_instance_id) or not is_instance_valid(enemy):
			continue
		if enemy.is_in_combat():
			return true
	return false


## 按 Inspector 的 debug_log_enabled 开关输出遭遇调试事件。
## 参数 message 必须是完整事件描述；本方法不参与状态计算，关闭开关时不会产生任何 Output 记录。
func _log_debug(message: String) -> void:
	if debug_log_enabled:
		print("[Encounter] " + message)
