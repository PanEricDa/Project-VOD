class_name CombatRoomController
extends Node

## 房间级流程裁决器。
## 只汇总单位生命事件和 EncounterController 的 Pack 事件，决定房间处于正常、残局、失败或完成；
## 不重置场景、不移动单位、不改写 AI，也不承担未来全局检查点和奖励逻辑。

enum FlowState {
	NORMAL,
	LAST_STAND,
	FAILED,
	COMPLETED,
}

## 房间流程状态发生变化时发送。
## previous_state 和 current_state 只描述本控制器运行时状态；订阅方可据此更新 UI、输入或未来结算表现。
signal flow_state_changed(previous_state: FlowState, current_state: FlowState)
## 玩家死亡但仍有至少一名伙伴存活时发送。
## 此信号只通知残局开始；本阶段不依据敌群是否激活、重置或清除来判定失败。
signal last_stand_started()
## 房间未完成且所有 Player 与 Ally 阵营单位均已死亡时发送一次。
## 当前仅通知未来 GameRunController 执行检查点、撤退或复活流程，本模块不自行切换场景。
signal room_failed()
## 房间全部敌群清除时发送一次，优先级高于任何玩家或伙伴死亡状态。
## 此信号不直接发奖励、开门或切换场景，保留给上层游戏流程处理。
signal room_completed()

@export_category("Defeat Resolution")
## 玩家死亡后、确认失败信号发出前的等待时间，单位为秒。
## 默认 3 秒，为镜头跟随幸存伙伴或最后敌军预留演出时间；设为 0 时下一帧结算，影响范围仅限本房间流程。
@export_range(0.0, 15.0, 0.05, "or_greater") var defeat_resolution_delay: float = 3.0

@export_category("Debug")
## 只读显示当前房间流程状态，值为 NORMAL、LAST_STAND、FAILED 或 COMPLETED。
## 仅用于 Inspector 调试，不可手动写入，也不会覆盖运行时裁决。
@export var debug_flow_state: StringName:
	get:
		return _get_flow_state_name()

const PLAYER_FACTION_ID: StringName = &"Player"
const ALLY_FACTION_ID: StringName = &"Ally"
const ENEMY_FACTION_ID: StringName = &"Enemy"

var _flow_state: FlowState = FlowState.NORMAL
var _player: UnitBase
var _encounter_controller: EncounterController
var _active_packs: Dictionary = {}
var _failure_timer: SceneTreeTimer
var _failure_scheduled: bool = false
var _completed_emitted: bool = false
var _configured: bool = false


func _ready() -> void:
	call_deferred(&"_configure_from_room")


func _exit_tree() -> void:
	_failure_timer = null
	_disconnect_unit_signals()
	_disconnect_encounter_signals()


## 返回当前房间流程状态，供 UI、测试和未来上层 GameRunController 只读查询。
## 返回值由 died、revived 与 Pack 生命周期事件统一维护，调用方不得直接写入。
func get_flow_state() -> FlowState:
	return _flow_state


func _configure_from_room() -> void:
	var room_root: Node = get_parent()
	if not is_instance_valid(room_root):
		push_error("CombatRoomController: Parent room node is required.")
		return
	_encounter_controller = room_root.get_node_or_null(^"EncounterController") as EncounterController
	if not is_instance_valid(_encounter_controller):
		push_error("CombatRoomController: Missing sibling EncounterController. Room=" + str(room_root.get_path()))
		return
	_player = _find_unique_player(room_root)
	if not is_instance_valid(_player):
		push_error("CombatRoomController: Missing unique Player faction unit. Room=" + str(room_root.get_path()))
		return
	_connect_unit_signals(room_root)
	_connect_encounter_signals()
	_refresh_active_packs(room_root)
	_configured = true
	_evaluate_party_state()


func _connect_unit_signals(room_root: Node) -> void:
	var units: Array[UnitBase] = []
	_collect_units(room_root, units)
	for unit: UnitBase in units:
		var died_callback := Callable(self, "_on_unit_died").bind(unit)
		if not unit.died.is_connected(died_callback):
			unit.died.connect(died_callback)
		var revived_callback := Callable(self, "_on_unit_revived").bind(unit)
		if not unit.revived.is_connected(revived_callback):
			unit.revived.connect(revived_callback)
		var combat_callback := Callable(self, "_on_unit_combat_state_changed").bind(unit)
		if not unit.combat_state_changed.is_connected(combat_callback):
			unit.combat_state_changed.connect(combat_callback)


func _disconnect_unit_signals() -> void:
	var room_root: Node = get_parent()
	if not is_instance_valid(room_root):
		return
	var units: Array[UnitBase] = []
	_collect_units(room_root, units)
	for unit: UnitBase in units:
		var died_callback := Callable(self, "_on_unit_died").bind(unit)
		if unit.died.is_connected(died_callback):
			unit.died.disconnect(died_callback)
		var revived_callback := Callable(self, "_on_unit_revived").bind(unit)
		if unit.revived.is_connected(revived_callback):
			unit.revived.disconnect(revived_callback)
		var combat_callback := Callable(self, "_on_unit_combat_state_changed").bind(unit)
		if unit.combat_state_changed.is_connected(combat_callback):
			unit.combat_state_changed.disconnect(combat_callback)


func _connect_encounter_signals() -> void:
	if not is_instance_valid(_encounter_controller):
		return
	if not _encounter_controller.pack_started.is_connected(_on_pack_started):
		_encounter_controller.pack_started.connect(_on_pack_started)
	if not _encounter_controller.pack_reset.is_connected(_on_pack_reset):
		_encounter_controller.pack_reset.connect(_on_pack_reset)
	if not _encounter_controller.pack_cleared.is_connected(_on_pack_cleared):
		_encounter_controller.pack_cleared.connect(_on_pack_cleared)
	if not _encounter_controller.room_cleared.is_connected(_on_room_cleared):
		_encounter_controller.room_cleared.connect(_on_room_cleared)


func _disconnect_encounter_signals() -> void:
	if not is_instance_valid(_encounter_controller):
		return
	if _encounter_controller.pack_started.is_connected(_on_pack_started):
		_encounter_controller.pack_started.disconnect(_on_pack_started)
	if _encounter_controller.pack_reset.is_connected(_on_pack_reset):
		_encounter_controller.pack_reset.disconnect(_on_pack_reset)
	if _encounter_controller.pack_cleared.is_connected(_on_pack_cleared):
		_encounter_controller.pack_cleared.disconnect(_on_pack_cleared)
	if _encounter_controller.room_cleared.is_connected(_on_room_cleared):
		_encounter_controller.room_cleared.disconnect(_on_room_cleared)


func _on_unit_died(_source: Node, _unit: UnitBase) -> void:
	if not _configured:
		return
	_evaluate_party_state()


func _on_unit_revived(_health: float, _source: Node, unit: UnitBase) -> void:
	if not _configured or not _is_friendly_unit(unit):
		return
	_cancel_scheduled_failure()
	_evaluate_party_state()


## 单位通用战斗状态变化时重新评估残局。
## previous_state 与 current_state 仅用于信号签名匹配；真实结果始终通过 UnitBase 的
## 当前状态统一读取，避免信号同帧顺序导致使用过期状态。
func _on_unit_combat_state_changed(
	_previous_state: UnitBase.CombatState,
	_current_state: UnitBase.CombatState,
	_unit: UnitBase
) -> void:
	if not _configured:
		return
	_evaluate_party_state()


func _on_pack_started(pack: Node3D, _count: int) -> void:
	_active_packs[pack.get_instance_id()] = pack


func _on_pack_reset(pack: Node3D, _count: int) -> void:
	_active_packs.erase(pack.get_instance_id())


func _on_pack_cleared(pack: Node3D, _count: int) -> void:
	_active_packs.erase(pack.get_instance_id())


func _on_room_cleared() -> void:
	_active_packs.clear()
	_complete_room()


## 按当前两层房间规则重新评估友方阵营状态。
## 第一层“敌群全清”由 _complete_room() 单独处理且永远优先；此方法仅处理尚未完成房间中的全体友方死亡与玩家死亡残局。
func _evaluate_party_state() -> void:
	if _flow_state == FlowState.COMPLETED or _flow_state == FlowState.FAILED:
		return
	if not _has_living_friendly_unit():
		_schedule_failure()
		return
	if is_instance_valid(_player) and _player.is_dead():
		var was_last_stand: bool = _flow_state == FlowState.LAST_STAND
		_set_flow_state(FlowState.LAST_STAND)
		if not was_last_stand:
			last_stand_started.emit()
		## 玩家死亡但伙伴存活时，只有房间仍有活敌人、且敌我双方都已离开
		## 通用战斗状态，才认定幸存伙伴无法继续推进战斗并开始失败倒计时。
		## 任一方重新进入战斗即取消未提交的倒计时，避免一次瞬时目标切换误判失败。
		if (
			_has_living_enemy_unit()
			and not _has_living_friendly_unit_in_combat()
			and not _has_living_enemy_unit_in_combat()
		):
			_schedule_failure()
		else:
			_cancel_scheduled_failure()
		return
	_cancel_scheduled_failure()
	_set_flow_state(FlowState.NORMAL)


func _schedule_failure() -> void:
	if _failure_scheduled or _flow_state == FlowState.FAILED or _flow_state == FlowState.COMPLETED:
		return
	_failure_scheduled = true
	var delay: float = maxf(defeat_resolution_delay, 0.0)
	if delay <= 0.0:
		call_deferred(&"_commit_failure")
		return
	_failure_timer = get_tree().create_timer(delay)
	_failure_timer.timeout.connect(_commit_failure)


func _commit_failure() -> void:
	_failure_timer = null
	if not _failure_scheduled or not _should_commit_failure():
		_failure_scheduled = false
		return
	_failure_scheduled = false
	_set_flow_state(FlowState.FAILED)
	room_failed.emit()


func _cancel_scheduled_failure() -> void:
	_failure_timer = null
	_failure_scheduled = false


## 返回当前帧的房间是否仍满足已排队失败的提交条件。
## 除“所有友方死亡”外，玩家死亡后的残局还要求：存在活敌人，且存活伙伴与敌人
## 都已离开通用战斗状态。倒计时期间任一方重新交战或玩家复活都会使本方法返回 false。
func _should_commit_failure() -> bool:
	if not _has_living_friendly_unit():
		return true
	return (
		is_instance_valid(_player)
		and _player.is_dead()
		and _has_living_enemy_unit()
		and not _has_living_friendly_unit_in_combat()
		and not _has_living_enemy_unit_in_combat()
	)


func _set_flow_state(next_state: FlowState) -> void:
	if _flow_state == next_state:
		return
	var previous_state: FlowState = _flow_state
	_flow_state = next_state
	flow_state_changed.emit(previous_state, _flow_state)


## 返回房间中是否仍有任一存活的 Player 或 Ally 阵营单位。
## 此查询只描述第二层失败条件，不读取敌群状态，也不推断伙伴的攻击能力；后续第三层规则会在独立接口中扩展。
func _has_living_friendly_unit() -> bool:
	var room_root: Node = get_parent()
	if not is_instance_valid(room_root):
		return false
	var units: Array[UnitBase] = []
	_collect_units(room_root, units)
	for unit: UnitBase in units:
		if _is_friendly_unit(unit) and not unit.is_dead():
			return true
	return false


## 返回房间中是否仍有存活敌方单位。
## 此查询只服务于“玩家死亡后的残局脱战失败”条件；敌群全清仍由 room_cleared
## 以更高优先级直接结算成功，不依赖本方法。
func _has_living_enemy_unit() -> bool:
	return _has_living_unit_matching_faction(ENEMY_FACTION_ID)


## 返回是否有存活友方单位仍处于通用战斗状态。
## 伙伴攻击冷却、持距绕行与追击均保持 IN_COMBAT，因此不会因未播放动画而误判脱战。
func _has_living_friendly_unit_in_combat() -> bool:
	return _has_living_unit_in_combat_matching_factions([
		PLAYER_FACTION_ID,
		ALLY_FACTION_ID,
	])


## 返回是否有存活敌方单位仍处于通用战斗状态。
## 该状态由 Enemy 行为状态机在追击或攻击时维护，用于确认敌群仍在实际交战。
func _has_living_enemy_unit_in_combat() -> bool:
	return _has_living_unit_in_combat_matching_factions([ENEMY_FACTION_ID])


## 按阵营查询房间内是否存在至少一个存活单位。
## faction 参数只接受 UnitBase 统一维护的阵营标识，避免房间流程依赖具体单位场景类型。
func _has_living_unit_matching_faction(faction: StringName) -> bool:
	var room_root: Node = get_parent()
	if not is_instance_valid(room_root):
		return false
	var units: Array[UnitBase] = []
	_collect_units(room_root, units)
	for unit: UnitBase in units:
		if StringName(unit.faction_id) == faction and not unit.is_dead():
			return true
	return false


## 按阵营集合查询是否存在至少一个存活且战斗中的单位。
## factions 为内部常量集合；仅在残局判定时读取，不会控制单位 AI 或改写其状态。
func _has_living_unit_in_combat_matching_factions(factions: Array[StringName]) -> bool:
	var room_root: Node = get_parent()
	if not is_instance_valid(room_root):
		return false
	var units: Array[UnitBase] = []
	_collect_units(room_root, units)
	for unit: UnitBase in units:
		if (
			StringName(unit.faction_id) in factions
			and not unit.is_dead()
			and unit.is_in_combat()
		):
			return true
	return false


## 判断单位是否属于本房间失败规则中的友方阵营。
## 当前只包含唯一 Player 阵营与 Ally 阵营；Neutral 和 Enemy 均不参与“全体友方死亡”判断。
func _is_friendly_unit(unit: UnitBase) -> bool:
	if not is_instance_valid(unit):
		return false
	var faction: StringName = StringName(unit.faction_id)
	return faction == PLAYER_FACTION_ID or faction == ALLY_FACTION_ID


## 以最高优先级提交房间完成。
## 房间完成会先取消已排队的失败倒计时，因此敌群全清与友方同时死亡时始终以成功结算，不再被后续失败计时器覆盖。
func _complete_room() -> void:
	if _flow_state == FlowState.COMPLETED:
		return
	_cancel_scheduled_failure()
	_set_flow_state(FlowState.COMPLETED)
	if _completed_emitted:
		return
	_completed_emitted = true
	room_completed.emit()


func _refresh_active_packs(room_root: Node) -> void:
	var container := room_root.get_node_or_null(^"EnemyContainer") as Node3D
	if not is_instance_valid(container) or not is_instance_valid(_encounter_controller):
		return
	for child: Node in container.get_children():
		var pack := child as Node3D
		if pack != null and _encounter_controller.get_pack_state(pack) == EncounterController.PackState.ENGAGED:
			_active_packs[pack.get_instance_id()] = pack


func _find_unique_player(room_root: Node) -> UnitBase:
	var units: Array[UnitBase] = []
	_collect_units(room_root, units)
	var player: UnitBase = null
	for unit: UnitBase in units:
		if StringName(unit.faction_id) != PLAYER_FACTION_ID:
			continue
		if player != null:
			return null
		player = unit
	return player


func _collect_units(node: Node, units: Array[UnitBase]) -> void:
	if node is UnitBase:
		units.append(node as UnitBase)
	for child: Node in node.get_children():
		_collect_units(child, units)


func _get_flow_state_name() -> StringName:
	match _flow_state:
		FlowState.LAST_STAND:
			return &"LAST_STAND"
		FlowState.FAILED:
			return &"FAILED"
		FlowState.COMPLETED:
			return &"COMPLETED"
	return &"NORMAL"
