extends Node3D

## 用于自动识别玩家单位的阵营标识。
## 该值与 UnitBase.faction_id 的 Player 枚举值保持一致，不作为 Inspector 配置，
## 以保证更改玩家节点名称或场景层级时不需要重新连线。
const PLAYER_FACTION_ID: StringName = &"Player"
## 用于玩家死亡后的第一优先级镜头回退阵营标识。
## 只有存活的 Ally 单位才会作为回退焦点；该值与 UnitBase.faction_id 的 Ally 枚举保持一致。
const ALLY_FACTION_ID: StringName = &"Ally"
## 用于玩家与伙伴均死亡后的第二优先级镜头回退阵营标识。
## 只有存活的 Enemy 单位才会作为回退焦点；该值与 UnitBase.faction_id 的 Enemy 枚举保持一致。
const ENEMY_FACTION_ID: StringName = &"Enemy"

## 摄像机当前焦点的内部优先级类型。
## PLAYER 为正常玩家跟随；其余模式只会在唯一玩家死亡后使用；NONE 表示场景不存在可跟随的存活单位。
enum FocusMode {
	NONE,
	PLAYER,
	ALLY_FALLBACK,
	ENEMY_FALLBACK,
}

## 当前未找到唯一玩家时，重新扫描当前场景树的固定时间间隔，单位为秒。
## 该间隔只影响“玩家后加入场景”或“原目标已删除”时的重新绑定响应；
## 相机已经绑定有效目标后不会重复进行场景树扫描。
const TARGET_RESOLUTION_RETRY_INTERVAL: float = 0.25

## 摄像机相对于玩家的固定世界坐标偏移，单位为米。
## X 控制横向偏移、Y 控制高度、Z 控制镜头位于玩家后方的距离。
@export var camera_offset: Vector3 = Vector3(0.0, 9.0, 6.8)

## 摄像机追赶期望位置时的指数平滑强度。
## 数值越大镜头越紧贴玩家；数值越小滞后感越明显，作用范围仅为 CameraRig 的位置跟随。
@export_range(0.1, 20.0, 0.1, "or_greater") var follow_smoothness: float = 5.0

## 玩家达到参考速度时，镜头向移动方向预留的最大距离，单位为米。
## 该偏移只影响构图中心，不旋转镜头，保持固定朝向的俯视视角。
@export_range(0.0, 5.0, 0.05, "or_greater") var look_ahead_distance: float = 0.65

## 移动方向预留偏移的指数平滑强度。
## 较低值使方向变化更柔和，较高值使镜头更快响应角色运动方向。
@export_range(0.1, 20.0, 0.1, "or_greater") var look_ahead_smoothness: float = 4.0

## 用于计算完整预留距离的玩家参考速度，单位为米/秒。
## 水平速度达到该值时使用完整的 look_ahead_distance，低于该值则按比例缩放。
@export_range(0.1, 30.0, 0.1, "or_greater") var look_ahead_full_speed: float = 4.0

## 摄像机允许落后于期望位置的最大距离，单位为米。
## 即使平滑系数较低，该限制也会防止玩家高速移动时离开镜头构图范围。
@export_range(0.1, 10.0, 0.1, "or_greater") var maximum_follow_distance: float = 1.5

## 当镜头与期望位置相距超过此距离时直接对齐，单位为米。
## 用于传送、重生或切换区域，避免镜头从远处慢速飞越整个关卡。
@export_range(1.0, 100.0, 0.5, "or_greater") var snap_distance: float = 12.0

## 是否锁定镜头垂直跟随高度。
## 开启后，跳跃或物理起伏不会带动镜头上下晃动；XZ 水平跟随保持正常。
@export var lock_vertical_follow: bool = true

@export_category("Debug")
## 只读显示当前自动解析到的镜头焦点节点路径。
## 此字段仅用于 Inspector 调试，不保存到场景，也不能手动编辑；为空表示当前场景没有可跟随的存活单位。
@export var debug_resolved_target: NodePath:
	get:
		if _has_valid_target():
			return target.get_path()
		return NodePath()

## 只读显示当前镜头焦点模式，用于确认玩家死亡后的伙伴或敌军回退是否符合预期。
## 值为 PLAYER、ALLY_FALLBACK、ENEMY_FALLBACK 或 NONE；仅供调试观察，不可手动修改，也不影响选择算法。
@export var debug_focus_mode: StringName:
	get:
		return _get_focus_mode_name()

## 运行时缓存的实际跟随目标。
## 只接受场景树内存活的 UnitBase；其阵营优先级由 FocusMode 管理，绝不依赖节点名称、层级或手写 NodePath。
var target: UnitBase

## 当前已解析焦点的优先级类型。
## 该状态不导出，确保镜头选择只由统一算法维护；Inspector 通过 debug_focus_mode 只读查看。
var _focus_mode: FocusMode = FocusMode.NONE

## 玩家死亡瞬间记录的世界位置。
## 伙伴和敌军回退候选以此计算最近距离，避免尸体受重力、消散或复活移动后改变镜头选择基准。
var _fallback_origin: Vector3 = Vector3.ZERO

## 是否已获得可用于回退的玩家死亡位置。
## 只有检测到唯一 Player 已死亡时才置为 true；纯粹未放置玩家的场景不会意外改为跟随敌军。
var _has_fallback_origin: bool = false

## 当前经过平滑处理的移动方向预留偏移。
## 独立保存可让玩家改变方向时镜头柔和过渡，而不是瞬间横移。
var current_look_ahead: Vector3 = Vector3.ZERO

## 场景初始化或重新绑定时记录的目标高度。
## lock_vertical_follow 开启时镜头始终以该高度为基准，忽略目标后续的 Y 轴变化。
var locked_target_height: float = 0.0

## 未绑定有效目标时累计的重试时间，单位为秒。
## 达到 TARGET_RESOLUTION_RETRY_INTERVAL 后才执行一次场景树扫描，避免每个渲染帧递归遍历所有节点。
var _target_resolution_elapsed: float = 0.0

## 防止多个 Player 候选存在时每帧重复输出相同警告。
## 当候选恢复为零个或唯一一个时会自动复位，下一次真正的多玩家歧义仍会给出一次提示。
var _has_warned_multiple_players: bool = false


## Godot 节点初始化回调。
## 控制器会立即尝试自动解析目标；找不到唯一玩家属于可恢复等待状态，不会关闭相机处理或输出配置错误。
func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_resolve_follow_target()


## Godot 每个渲染帧回调，负责目标重解析、速度预留和帧率无关的平滑跟随。
## 参数 delta 是当前渲染帧经过的秒数。
func _process(delta: float) -> void:
	if not _has_valid_target():
		_clear_target()
		_resolve_follow_target()
		if not _has_valid_target():
			return
	elif _focus_mode != FocusMode.PLAYER:
		# 回退状态按既有低频重试节奏检查更高优先级目标，确保玩家复活后无需手动配置即可恢复镜头。
		_target_resolution_elapsed += delta
		if _target_resolution_elapsed >= TARGET_RESOLUTION_RETRY_INTERVAL:
			_target_resolution_elapsed = 0.0
			_resolve_follow_target()

	var interpolated_target_position: Vector3 = target.get_global_transform_interpolated().origin
	var desired_look_ahead: Vector3 = _calculate_desired_look_ahead()
	var look_ahead_weight: float = 1.0 - exp(-look_ahead_smoothness * delta)
	current_look_ahead = current_look_ahead.lerp(desired_look_ahead, look_ahead_weight)

	var desired_position: Vector3 = interpolated_target_position + camera_offset + current_look_ahead
	if lock_vertical_follow:
		desired_position.y = locked_target_height + camera_offset.y
	if global_position.distance_to(desired_position) >= snap_distance:
		global_position = desired_position
		reset_physics_interpolation()
		return

	var follow_weight: float = 1.0 - exp(-follow_smoothness * delta)
	var smoothed_position: Vector3 = global_position.lerp(desired_position, follow_weight)
	var remaining_offset: Vector3 = desired_position - smoothed_position
	if remaining_offset.length() > maximum_follow_distance:
		smoothed_position = desired_position - remaining_offset.normalized() * maximum_follow_distance
	global_position = smoothed_position


## 根据 CharacterBody3D 的水平速度计算移动方向预留偏移。
## 返回世界坐标 XZ 平面的偏移，不包含垂直分量；非 CharacterBody3D 目标安全返回零偏移。
func _calculate_desired_look_ahead() -> Vector3:
	if not target is CharacterBody3D:
		return Vector3.ZERO
	var target_velocity: Vector3 = (target as CharacterBody3D).velocity
	var horizontal_velocity := Vector3(target_velocity.x, 0.0, target_velocity.z)
	var horizontal_speed := horizontal_velocity.length()
	if horizontal_speed <= 0.001:
		return Vector3.ZERO
	var speed_ratio: float = clampf(horizontal_speed / look_ahead_full_speed, 0.0, 1.0)
	return horizontal_velocity.normalized() * look_ahead_distance * speed_ratio


## 立即将相机对齐到当前玩家的构图位置。
## 可在传送、重生或区域切换后调用；无有效目标时安全返回，不改变相机位置。
func snap_to_target() -> void:
	if not _has_valid_target():
		return
	current_look_ahead = Vector3.ZERO
	var desired_position := target.global_position + camera_offset
	if lock_vertical_follow:
		desired_position.y = locked_target_height + camera_offset.y
	global_position = desired_position
	reset_physics_interpolation()


## 自动按“存活玩家、最近存活伙伴、最近存活敌军”的固定优先级解析镜头焦点。
## 该接口供场景初始化、焦点死亡后的即时重选、回退状态低频重试及测试调用；多个 Player 候选保持不绑定，
## 防止相机在错误玩家之间随机切换。未检测到玩家死亡时不会把仅有敌军的场景误当作玩家死亡回退。
func _resolve_follow_target() -> void:
	var search_root: Node = get_tree().current_scene
	if search_root == null:
		search_root = get_tree().root
	if search_root == null:
		_clear_target()
		return
	var player_units: Array[UnitBase] = []
	var living_allies: Array[UnitBase] = []
	var living_enemies: Array[UnitBase] = []
	_collect_focus_candidates(search_root, player_units, living_allies, living_enemies)
	var living_players: Array[UnitBase] = []
	for player: UnitBase in player_units:
		if not player.is_dead():
			living_players.append(player)
	if living_players.size() == 1:
		_has_warned_multiple_players = false
		_has_fallback_origin = false
		_assign_target(living_players[0], FocusMode.PLAYER)
		return
	if living_players.size() > 1:
		_clear_target()
		if not _has_warned_multiple_players:
			push_warning("CameraFollowController: Multiple Player faction units were found; camera follow is waiting for a unique target.")
			_has_warned_multiple_players = true
		return
	_has_warned_multiple_players = false
	if player_units.size() != 1:
		_clear_target()
		return
	var dead_player: UnitBase = player_units[0]
	if not _has_fallback_origin:
		_fallback_origin = dead_player.global_position
		_has_fallback_origin = true
	if not living_allies.is_empty():
		if _focus_mode == FocusMode.ALLY_FALLBACK and _has_valid_target():
			return
		_assign_target(_find_nearest_unit(living_allies), FocusMode.ALLY_FALLBACK)
		return
	if not living_enemies.is_empty():
		if _focus_mode == FocusMode.ENEMY_FALLBACK and _has_valid_target():
			return
		_assign_target(_find_nearest_unit(living_enemies), FocusMode.ENEMY_FALLBACK)
		return
	_clear_target()


## 递归收集镜头焦点候选。
## player_units 保留存活与死亡玩家，供调用方记录死亡位置；伙伴和敌军数组仅收集存活单位，避免相机落到尸体上。
func _collect_focus_candidates(
	node: Node,
	player_units: Array[UnitBase],
	living_allies: Array[UnitBase],
	living_enemies: Array[UnitBase]
) -> void:
	if node is UnitBase:
		var unit: UnitBase = node as UnitBase
		match StringName(unit.faction_id):
			PLAYER_FACTION_ID:
				player_units.append(unit)
			ALLY_FACTION_ID:
				if not unit.is_dead():
					living_allies.append(unit)
			ENEMY_FACTION_ID:
				if not unit.is_dead():
					living_enemies.append(unit)
	for child: Node in node.get_children():
		_collect_focus_candidates(child, player_units, living_allies, living_enemies)


## 返回距玩家死亡位置最近的候选单位。
## candidates 必须只包含场景树内存活单位；空数组安全返回 null，调用方会转入下一优先级或无焦点状态。
func _find_nearest_unit(candidates: Array[UnitBase]) -> UnitBase:
	var nearest_unit: UnitBase
	var nearest_distance_squared: float = INF
	for candidate: UnitBase in candidates:
		if not is_instance_valid(candidate) or not candidate.is_inside_tree() or candidate.is_dead():
			continue
		var distance_squared: float = candidate.global_position.distance_squared_to(_fallback_origin)
		if distance_squared < nearest_distance_squared:
			nearest_distance_squared = distance_squared
			nearest_unit = candidate
	return nearest_unit


## 把已确认的存活单位设为相机焦点并记录其优先级模式。
## 参数 next_target 必须属于 next_focus_mode 对应阵营且仍在场景树内；绑定时立即对齐以避免从旧焦点缓慢飞越战场。
func _assign_target(next_target: UnitBase, next_focus_mode: FocusMode) -> void:
	if not is_instance_valid(next_target) or not next_target.is_inside_tree() or next_target.is_dead():
		_clear_target()
		return
	if target == next_target and _focus_mode == next_focus_mode:
		return
	target = next_target
	_focus_mode = next_focus_mode
	locked_target_height = target.global_position.y
	_target_resolution_elapsed = 0.0
	snap_to_target()


## 清除当前运行时跟随目标及构图缓存。
## 此方法不会关闭相机处理循环；无目标是可恢复状态，控制器会按固定间隔重新解析。
func _clear_target() -> void:
	target = null
	_focus_mode = FocusMode.NONE
	current_look_ahead = Vector3.ZERO


## 返回当前缓存目标是否仍可安全作为相机跟随对象。
## 有效目标必须存在、仍在场景树中且存活，并与当前 FocusMode 的阵营约定一致；否则调用方应清除并重新搜索。
func _has_valid_target() -> bool:
	if not is_instance_valid(target) or not target.is_inside_tree() or target.is_dead():
		return false
	match _focus_mode:
		FocusMode.PLAYER:
			return StringName(target.faction_id) == PLAYER_FACTION_ID
		FocusMode.ALLY_FALLBACK:
			return StringName(target.faction_id) == ALLY_FACTION_ID
		FocusMode.ENEMY_FALLBACK:
			return StringName(target.faction_id) == ENEMY_FACTION_ID
	return false


## 返回供 Inspector 调试字段显示的稳定焦点模式名称。
## 不接受外部输入；返回值只反映本控制器已选择的运行时状态，不参与任何相机计算。
func _get_focus_mode_name() -> StringName:
	match _focus_mode:
		FocusMode.PLAYER:
			return &"PLAYER"
		FocusMode.ALLY_FALLBACK:
			return &"ALLY_FALLBACK"
		FocusMode.ENEMY_FALLBACK:
			return &"ENEMY_FALLBACK"
	return &"NONE"


## 返回当前自动解析到的存活镜头焦点，供其他模块或测试进行只读查询。
## 没有可用焦点时返回 null；调用方不得通过返回值修改相机内部绑定关系。
func get_resolved_target() -> UnitBase:
	if not _has_valid_target():
		return null
	return target
