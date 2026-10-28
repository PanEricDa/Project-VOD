class_name CameraFollowController
extends Node3D
## 本次request_id的close/area过渡已到位；每阶段仅一次，接收者必须核对身份后才解除自身暂停。
signal cinematic_transition_finished(request_id: int, phase: StringName)

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
## 镜头靠近一档的 InputMap 动作；具体滚轮或键盘绑定由项目设置维护。
const ZOOM_IN_ACTION: StringName = &"camera_zoom_in"
## 镜头远离一档的 InputMap 动作；脚本不判断鼠标按键编号。
const ZOOM_OUT_ACTION: StringName = &"camera_zoom_out"
## 只有最近两个档位降低俯角；第三近及更远档位保持常规俯角，属于内部固定规则。
const NEAR_PITCH_STEP_COUNT: int = 2
## 第二近档位采用近／常规俯角区间的75%；默认30°与50°时为45°，不增加Inspector配置。
const SECOND_CLOSEST_PITCH_BLEND: float = 0.75

@export_category("Follow")
## CameraRig 相对于跟随目标的基础世界坐标偏移，单位为米，默认 (0, 9, 6.8)。
## X/Z 保留基础构图，Y 设定基础高度；启用变俯角缩放时，以此基础镜头确定观察点和基准视距，再绕观察点降低或抬高子相机。
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

## 是否锁定镜头垂直跟随高度，默认关闭，使镜头平滑跟随玩家上下坡、跨层和下落。
## 开启后固定在绑定目标时的高度，忽略后续 Y 变化；仅影响普通位置跟随，XZ 跟随保持正常。
@export var lock_vertical_follow: bool = false

@export_category("Zoom")
## 各档相对基础视距增加的距离，单位米；须为非负、有限且从小到大排列。
## 默认 [0, 3, 6, 9] 提供四档；启用 Zoom Pitch 时仅最近两档降低俯角，第三近起保持常规俯角，FOV不变；空数组保留原始相机构图。
@export var zoom_distances: PackedFloat32Array = [0.0, 3.0, 6.0, 9.0]
## 初始缩放档位，下标从 0 开始；默认 1 为标准档，越界时限制到有效档位。
## 仅影响本 CameraRig 的初始视距，切换跟随目标不会重置当前档位。
@export_range(0, 16, 1, "or_greater") var initial_zoom_step: int = 1
## 分档切换的指数平滑强度，单位每秒；默认 15 约在 0.2 秒完成 95% 过渡。
## 仅影响子相机缩放；连续输入更新目标档位，不排队播放，也不受最大跟随距离限制。
@export_range(0.1, 40.0, 0.1, "or_greater") var zoom_smoothness: float = 15.0

@export_group("Zoom Pitch")
## 是否在分档缩放时同时改变相机高度与俯角，默认开启。
## 镜头围绕基础构图的观察点移动，仅进入最近两档时逐渐降低俯角；更远各档只改变距离。关闭后恢复原始固定角度的轴向缩放，仅影响普通玩家镜头。
@export var zoom_pitch_enabled: bool = true
## 最近缩放档位的下视俯角，单位度，相对世界水平面，默认 30；范围 1 至 85。
## 越小越接近平视；从最近档向第三近档平滑恢复常规俯角，更远档位不继续改变角度；不改变 FOV 或玩家跟随高度。
@export_range(1.0, 85.0, 0.5) var zoom_closest_pitch_degrees: float = 30.0
## 常规远景下视俯角，单位度，默认50；范围1至85，从第三近档起所有更远档位保持此角度。
## 字段名保留以兼容既有配置；通常应不小于最近俯角，运行时较小值按最近俯角处理。仅影响普通变俯角镜头。
@export_range(1.0, 85.0, 0.5) var zoom_farthest_pitch_degrees: float = 50.0
## 变俯角缩放的观察点相对玩家脚底的高度，单位米，默认 1，范围从 0 起。
## 用于让降低后的镜头仍观察玩家躯干；仅影响普通变俯角构图，技能特写仍使用自身配置，关闭变俯角或缩放时不生效。
@export_range(0.0, 5.0, 0.05, "or_greater") var zoom_focus_height_m: float = 1.0

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

## 缩放只作用于既有直接子节点 Camera3D；未装配相机时保留原跟随功能。
var _zoom_camera: Camera3D
var _zoom_levels: PackedFloat32Array = PackedFloat32Array()
var _zoom_step: int = 0
var _zoom_distance: float = 0.0
var _base_camera_position: Vector3 = Vector3.ZERO
## 缓存策划初始朝向，避免连续缩放或震动反馈把已经倾斜的姿态再次当作基础而积累漂移。
var _base_camera_basis: Basis = Basis.IDENTITY


## Godot 节点初始化回调。
## 控制器会立即尝试自动解析目标；找不到唯一玩家属于可恢复等待状态，不会关闭相机处理或输出配置错误。
func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_initialize_zoom()
	_resolve_follow_target()


## Godot 每个渲染帧回调，负责子相机分档缩放、目标重解析、速度预留和帧率无关的平滑跟随。
## 参数 delta 是当前渲染帧经过的秒数。
func _process(delta: float) -> void:
	if _cinematic_id > 0:
		_update_cinematic(delta)
		return
	if _presentation_clock_blocked(): return
	_update_zoom(delta)
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
	# 临时表现只叠加在正常跟随上，先取回未含偏移的玩家镜头位置。
	global_position -= _focus_applied_offset
	_focus_applied_offset = Vector3.ZERO
	if global_position.distance_to(desired_position) >= snap_distance:
		global_position = desired_position
		reset_physics_interpolation()
		if _focus_profile != null: _update_presentation_focus(delta, desired_position)
		return

	var follow_weight: float = 1.0 - exp(-follow_smoothness * delta)
	var smoothed_position: Vector3 = global_position.lerp(desired_position, follow_weight)
	var remaining_offset: Vector3 = desired_position - smoothed_position
	if remaining_offset.length() > maximum_follow_distance:
		smoothed_position = desired_position - remaining_offset.normalized() * maximum_follow_distance
	global_position = smoothed_position
	if _focus_profile != null: _update_presentation_focus(delta, desired_position)


## 接收未被 UI 消费的 InputMap 动作；只处理当前活动相机的首次按下事件。
## event 可以来自滚轮、键盘或手柄，具体绑定只由项目 Input Map 决定。
func _unhandled_input(event: InputEvent) -> void:
	if _cinematic_id > 0: return
	if get_tree().paused: return
	if not is_instance_valid(_zoom_camera) or _zoom_levels.is_empty() or not _zoom_camera.is_current():
		return
	var direction: int = 0
	if event.is_action_pressed(ZOOM_IN_ACTION):
		direction = -1
	elif event.is_action_pressed(ZOOM_OUT_ACTION):
		direction = 1
	if direction == 0:
		return
	_zoom_step = clampi(_zoom_step + direction, 0, _zoom_levels.size() - 1)
	get_viewport().set_input_as_handled()


func _initialize_zoom() -> void:
	_zoom_camera = get_node_or_null(^"Camera3D") as Camera3D
	if _zoom_camera == null: return
	if not _zoom_camera.tree_exiting.is_connected(_on_cinematic_camera_exiting):
		_zoom_camera.tree_exiting.connect(_on_cinematic_camera_exiting)
	# 基础构图独立于缩放开关；命中反馈始终从策划原始位置合成。
	_base_camera_position = _zoom_camera.position
	_base_camera_basis = _zoom_camera.basis
	if zoom_distances.is_empty(): return
	var previous: float = -1.0
	for distance: float in zoom_distances:
		if not is_finite(distance) or distance < 0.0 or distance < previous:
			push_warning("CameraFollowController: Zoom distances must be finite, nonnegative and ordered from near to far.")
			return
		previous = distance
	_zoom_levels = zoom_distances.duplicate()
	_base_camera_position = _zoom_camera.position
	_zoom_step = clampi(initial_zoom_step, 0, _zoom_levels.size() - 1)
	_zoom_distance = _zoom_levels[_zoom_step]
	_apply_zoom_position()


func _update_zoom(delta: float) -> void:
	if not is_instance_valid(_zoom_camera) or _zoom_levels.is_empty():
		return
	var desired: float = _zoom_levels[_zoom_step]
	var weight: float = 1.0 - exp(-zoom_smoothness * maxf(delta, 0.0))
	_zoom_distance = lerpf(_zoom_distance, desired, weight)
	if absf(_zoom_distance - desired) < 0.001:
		_zoom_distance = desired
	_apply_zoom_position()


func _apply_zoom_position() -> void:
	if _cinematic_id > 0: return
	var feedback := Vector3.ZERO
	for id in _feedback_offsets.keys():
		var record: Dictionary = _feedback_offsets[id]
		var offset_owner = record.owner.get_ref()
		if not is_instance_valid(offset_owner) or not offset_owner.is_inside_tree(): _feedback_offsets.erase(id)
		else: feedback += record.offset
	_zoom_camera.transform = _normal_zoom_transform()
	_zoom_camera.position += feedback


## 返回当前平滑视距对应的普通镜头局部姿态，不包含震动或技能特写。
## 观察点沿用初始镜头的水平构图并取配置的世界高度；始终从原始姿态计算，避免往返缩放时漂移。
func _normal_zoom_transform() -> Transform3D:
	var base_back: Vector3 = _base_camera_basis.z.normalized()
	if not zoom_pitch_enabled or _zoom_levels.is_empty():
		return Transform3D(_base_camera_basis, _base_camera_position + base_back * _zoom_distance)
	var near_pitch: float = clampf(zoom_closest_pitch_degrees, 1.0, 85.0)
	var far_pitch: float = clampf(zoom_farthest_pitch_degrees, near_pitch, 85.0)
	var normal_pitch_step: int = mini(NEAR_PITCH_STEP_COUNT, _zoom_levels.size() - 1)
	var span: float = _zoom_levels[normal_pitch_step] - _zoom_levels[0]
	var progress: float = clampf((_zoom_distance - _zoom_levels[0]) / span, 0.0, 1.0) if span > 0.001 else 0.0
	if normal_pitch_step > 1 and span > 0.001:
		var middle_progress: float = (_zoom_levels[1] - _zoom_levels[0]) / span
		if middle_progress > 0.001 and middle_progress < 0.999:
			if progress <= middle_progress:
				progress = SECOND_CLOSEST_PITCH_BLEND * progress / middle_progress
			else:
				progress = lerpf(SECOND_CLOSEST_PITCH_BLEND, 1.0, (progress - middle_progress) / (1.0 - middle_progress))
	var pitch: float = deg_to_rad(lerpf(near_pitch, far_pitch, progress))
	var world_back: Vector3 = (global_basis * base_back).normalized()
	var base_world_offset: Vector3 = camera_offset + global_basis * _base_camera_position
	var view_height: float = base_world_offset.y - zoom_focus_height_m
	var base_radius: float = view_height / world_back.y if world_back.y > 0.01 and view_height > 0.05 else maxf((base_world_offset - Vector3.UP * zoom_focus_height_m).length(), 0.1)
	var focus_offset: Vector3 = base_world_offset - world_back * base_radius
	focus_offset.y = zoom_focus_height_m
	var pivot: Vector3 = global_basis.inverse() * (focus_offset - camera_offset)
	var horizontal_back := Vector3(world_back.x, 0.0, world_back.z)
	if horizontal_back.length_squared() < 0.0001:
		horizontal_back = Vector3.BACK
	var orbit_back: Vector3 = horizontal_back.normalized() * cos(pitch) + Vector3.UP * sin(pitch)
	var orbit_basis: Basis = global_basis.inverse() * Basis.looking_at(-orbit_back, Vector3.UP)
	var position_on_orbit: Vector3 = pivot + global_basis.inverse() * orbit_back * maxf(base_radius + _zoom_distance, 0.1)
	return Transform3D(orbit_basis, position_on_orbit)


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
	if _focus_profile != null: return
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

const CINEMATIC_OCCLUSION_FILTER = preload("res://UnitSystem/Components/Camera/CinematicOcclusionFilter.gd")
var _cinematic_occlusion: CinematicOcclusionFilter = CINEMATIC_OCCLUSION_FILTER.new()
var _cinematic_occlusion_active: bool = false
var _cinematic_id: int = 0
var _cinematic_phase: StringName = &""
var _cinematic_transition_done: bool = false
var _cinematic_pause: WeakRef
var _cinematic_pause_token: int = 0
var _cinematic_original_process_mode: Node.ProcessMode = Node.PROCESS_MODE_INHERIT
var _cinematic_profile: SkillCinematicCameraProfile
var _cinematic_clock: SkillExecutionClock
var _cinematic_saved_local: Transform3D
var _cinematic_saved_projection: Dictionary = {}
var _cinematic_from: Transform3D
var _cinematic_destination: Transform3D
var _cinematic_elapsed: float = 0.0
var _cinematic_center: Vector3
var _cinematic_radius: float = 0.0

## 同世界正身份接管专属构图；source_pose为动作开始视觉朝向快照，clock负责真实活动秒数。
## 开始时保留当前画面，按镜头资源时长推进至正面；等待/暂停由外部协调器持有，到位时通知。
## 只由本控制器写活动Camera3D；不改正常target、玩家缩放档位、世界速度或单位动作。
## caster为同世界施放者，供排除本人及附属特效；旧四参数调用可留空，此时仅播放镜头、不隐藏对象。
func begin_cinematic(request_id: int, source_pose: Transform3D, profile: SkillCinematicCameraProfile, clock: SkillExecutionClock, caster: Node3D = null) -> bool:
	if request_id <= 0 or not source_pose.is_finite() or profile == null or clock == null or not is_instance_valid(_zoom_camera): return false
	var scope := clock.get_bound_scope()
	if scope == null or not scope.is_ancestor_of(self): return false
	var front := profile.get_front_pose(source_pose)
	if not front.is_finite(): return false
	# 从真正可见的当前画面起步，替换旧返程/连携构图时也不先跳回默认机位。
	var origin := _zoom_camera.global_transform
	if _cinematic_id > 0: _restore_cinematic()
	clear_presentation_focus()
	_cinematic_original_process_mode = process_mode
	process_mode = Node.PROCESS_MODE_ALWAYS
	_cinematic_transition_done = false
	_cinematic_pause = null
	_cinematic_pause_token = 0
	_cinematic_saved_local = _zoom_camera.transform
	_cinematic_saved_projection = {"projection":_zoom_camera.projection,"fov":_zoom_camera.fov,"size":_zoom_camera.size}
	_cinematic_id = request_id
	_cinematic_phase = &"close"
	_cinematic_profile = profile.duplicate() as SkillCinematicCameraProfile
	_cinematic_clock = clock
	_cinematic_elapsed = 0
	_cinematic_from = origin
	_zoom_camera.global_transform = origin
	_cinematic_destination = front
	if caster != null and _cinematic_profile.hide_closeup_occluders:
		_cinematic_occlusion.begin(scope,caster,front.origin,source_pose.origin+Vector3.UP*_cinematic_profile.look_height_m,_cinematic_profile.get_occlusion_corridor_width())
		_cinematic_occlusion_active = _cinematic_occlusion.is_valid()
	return true

## request_id须匹配当前演出；pause/token为同世界暂停协调器授予的镜头过渡凭证，菜单仍有优先权。
func bind_cinematic_transition_pause(request_id: int, pause: GamePauseCoordinator, token: int) -> bool:
	if request_id != _cinematic_id or pause == null or token <= 0 or _cinematic_clock == null or pause.get_bound_scope() != _cinematic_clock.get_bound_scope(): return false
	_cinematic_pause = weakref(pause)
	_cinematic_pause_token = token
	return true

## 转为普通战斗角度和冻结区域；可在真实释放前过渡，到位事实由cinematic_transition_finished通知。
## radius_m为需容纳的水平半径；Arc取散布+爆炸半径，0表示沿普通战斗镜头距离构图，不重复策划配置。
func show_cinematic_area(request_id: int, center: Vector3, radius_m: float) -> void:
	if request_id != _cinematic_id or _cinematic_phase != &"close" or not center.is_finite() or not is_finite(radius_m) or radius_m < 0: return
	_restore_cinematic_occlusion()
	_cinematic_phase = &"area"
	_cinematic_transition_done = false
	_cinematic_center = center
	_cinematic_radius = radius_m
	_cinematic_from = _zoom_camera.global_transform
	_cinematic_elapsed = 0
	var normal := _cinematic_normal_pose()
	var distance := maxf(normal.origin.distance_to(_normal_position() - camera_offset), radius_m / tan(deg_to_rad(_zoom_camera.fov) * 0.5) * 1.15)
	_cinematic_destination = Transform3D(normal.basis, center + normal.basis.z.normalized() * distance)

## 仅匹配本次身份可交回玩家；immediate为A首发或异常退出，B正常结束按镜头资源的RETURN时长返回当前位置，默认0.2活动秒。
func end_cinematic(request_id: int, immediate: bool = false) -> void:
	if request_id != _cinematic_id or _cinematic_id == 0: return
	_restore_cinematic_occlusion()
	if immediate:
		_restore_cinematic()
		return
	_cinematic_phase = &"return"
	_cinematic_from = _zoom_camera.global_transform
	_cinematic_elapsed = 0

## 是否仍持有特写、区域或返程构图；不等于世界正在慢放。
func is_cinematic_active() -> bool:
	return _cinematic_id > 0

func _cinematic_normal_pose() -> Transform3D:
	var pose := global_transform
	pose.origin = _normal_position()
	return pose * _cinematic_saved_local

func _update_cinematic(delta: float) -> void:
	if _cinematic_clock == null: return
	if _cinematic_occlusion_active:
		if not _cinematic_occlusion.is_valid():
			_restore_cinematic()
			return
		_cinematic_occlusion.refresh()
	if _cinematic_clock.get_bound_scope() == null or not is_instance_valid(_zoom_camera) or not _zoom_camera.is_inside_tree():
		_restore_cinematic()
		return
	if not _has_valid_target():
		_clear_target()
		_resolve_follow_target()
	var seconds := 0.0
	if get_tree().paused:
		var pause := _cinematic_pause.get_ref() as GamePauseCoordinator if _cinematic_pause != null else null
		if _cinematic_transition_done or _cinematic_phase not in [&"close",&"area"] or pause == null or not pause.can_advance_cinematic_transition(_cinematic_pause_token): return
		var world_time_scale := Engine.time_scale
		seconds = clampf(delta/world_time_scale,0.0,0.1) if is_finite(world_time_scale) and world_time_scale > 0 and is_finite(delta) else 0.0
	else:
		seconds = _cinematic_clock.get_presentation_delta(delta,false)
	if seconds <= 0: return
	_cinematic_elapsed += seconds
	if _cinematic_phase == &"close":
		var push_duration := maxf(_cinematic_profile.get_closeup_transition_duration(), 0.000001)
		var progress := clampf(_cinematic_elapsed / push_duration, 0.0, 1.0)
		_zoom_camera.global_transform = _cinematic_from.interpolate_with(_cinematic_destination, progress * progress * (3.0 - 2.0 * progress))
		if progress >= 1 and not _cinematic_transition_done:
			_cinematic_transition_done = true
			cinematic_transition_finished.emit(_cinematic_id,&"close")
		return
	var duration := _cinematic_profile.get_phase_duration(CameraEffectProfile.Phase.RETURN if _cinematic_phase == &"return" else CameraEffectProfile.Phase.ENTER)
	var t := 1.0 if duration <= 0.0 else clampf(_cinematic_elapsed / duration, 0.0, 1.0)
	var destination := _cinematic_normal_pose() if _cinematic_phase == &"return" else _cinematic_destination
	_zoom_camera.global_transform = _cinematic_from.interpolate_with(destination, t * t * (3.0 - 2.0 * t))
	if t >= 1 and _cinematic_phase == &"return":
		_restore_cinematic()
	elif t >= 1 and not _cinematic_transition_done:
		_cinematic_transition_done = true
		cinematic_transition_finished.emit(_cinematic_id,&"area")

func _on_cinematic_camera_exiting() -> void:
	if _cinematic_id > 0: _restore_cinematic()
	else: _restore_cinematic_occlusion()


func _restore_cinematic_occlusion() -> void:
	_cinematic_occlusion_active = false
	_cinematic_occlusion.restore()


func _exit_tree() -> void:
	_restore_cinematic_occlusion()


func _restore_cinematic() -> void:
	_restore_cinematic_occlusion()
	process_mode = _cinematic_original_process_mode
	_cinematic_pause = null
	_cinematic_pause_token = 0
	_cinematic_transition_done = false
	_cinematic_id = 0
	_cinematic_phase = &""
	_cinematic_clock = null
	_cinematic_profile = null
	if is_instance_valid(_zoom_camera):
		if _has_valid_target(): global_position = _normal_position()
		_zoom_camera.transform = _cinematic_saved_local
		if not _cinematic_saved_projection.is_empty():
			_zoom_camera.projection = _cinematic_saved_projection.projection
			_zoom_camera.fov = _cinematic_saved_projection.fov
			_zoom_camera.size = _cinematic_saved_projection.size
		_apply_zoom_position()

var _focus_id: int = 0
var _focus_source: WeakRef
var _focus_profile: CameraEffectProfile
var _focus_phase: int = CameraEffectProfile.Phase.ENTER
var _focus_origin: Transform3D
var _focus_elapsed: float = 0.0
# 每阶段起始时计算一次适配时长；负值表示尚未计算，运行中不因目标运动反复伸缩。
var _focus_duration: float = -1.0
# 上一帧只属于表现的偏移，与玩家正常跟随独立累积；不序列化。
var _focus_applied_offset: Vector3 = Vector3.ZERO
var _focus_anchor_position: Vector3 = Vector3.ZERO
var _pause_ref: WeakRef
var _original_process_mode: Node.ProcessMode = Node.PROCESS_MODE_INHERIT
var _feedback_offsets: Dictionary = {}

## id为正且source同正常世界存活；只叠加临时Rig构图，不更换玩家target或停止正常跟随，非法策略返回false。
func begin_presentation_focus(presentation_id: int, source: Node3D, profile: CameraEffectProfile) -> bool:
	if _cinematic_id > 0:
		if _cinematic_phase != &"return": return false
		_restore_cinematic()
	if presentation_id <= 0 or profile == null or not is_instance_valid(source) or not source.is_inside_tree() or source.is_queued_for_deletion(): return false
	if source is UnitBase and source.is_dead(): return false
	var world := _normal_world()
	if world == null or not world.is_ancestor_of(source): return false
	for phase in [CameraEffectProfile.Phase.ENTER,CameraEffectProfile.Phase.RETURN]:
		var duration := profile.get_phase_duration(phase)
		if not is_finite(duration) or duration < 0.0: return false
	var destination := _source_pose(source)
	if not profile.sample_rig_transform(global_transform,destination,0.0,0).is_finite(): return false
	_focus_id = presentation_id
	_focus_source = weakref(source)
	_focus_profile = profile.duplicate() as CameraEffectProfile
	_focus_origin = global_transform
	_focus_anchor_position = global_position - _focus_applied_offset
	_focus_elapsed = 0
	_focus_duration = -1.0
	_focus_phase = CameraEffectProfile.Phase.ENTER
	_update_presentation_focus(0.0,_normal_position())
	return true

## 仅匹配id可结束当前镜头；淡出临时偏移，正常玩家跟随继续推进，不等待动作尾或命中。
func end_presentation_focus(presentation_id: int) -> void:
	if _focus_profile == null or _focus_id != presentation_id or _focus_phase == CameraEffectProfile.Phase.RETURN: return
	_focus_id = 0
	_focus_source = null
	_focus_phase = CameraEffectProfile.Phase.RETURN
	_focus_origin = global_transform
	_focus_anchor_position = global_position - _focus_applied_offset
	_focus_elapsed = 0
	_focus_duration = -1.0
	_update_presentation_focus(0.0,_normal_position())

## 解绑时撤销临时占用；不操作技能/暂停，不重绑正常target。
func clear_presentation_focus() -> void:
	global_position -= _focus_applied_offset
	_focus_applied_offset = Vector3.ZERO
	_focus_id = 0
	_focus_source = null
	_focus_profile = null
	_focus_elapsed = 0
	_focus_duration = -1.0

## 装配层注入同世界暂停源；null恢复原process_mode；显式暂停与释放强调均冻结镜头，但不冻结纯释放资产。
func set_presentation_pause_source(source: GamePauseCoordinator) -> void:
	if _pause_ref != null:
		process_mode = _original_process_mode
		_pause_ref = null
	if source == null: return
	var world := source.get_bound_scope()
	if world == null or not world.is_ancestor_of(self): return
	_original_process_mode = process_mode
	_pause_ref = weakref(source)
	process_mode = Node.PROCESS_MODE_ALWAYS

## owner为偏移来源，offset有限相机局部米数；统一合成，避免缩放与震动争写。
@warning_ignore("shadowed_variable_base_class")
func set_feedback_offset(owner: Node, offset: Vector3) -> void:
	if not is_instance_valid(owner) or not offset.is_finite(): return
	_feedback_offsets[owner.get_instance_id()] = {"owner":weakref(owner),"offset":offset}
	if is_instance_valid(_zoom_camera): _apply_zoom_position()

## 仅撤销此owner偏移，幂等；其他反馈及缩放不受影响。
@warning_ignore("shadowed_variable_base_class")
func clear_feedback_offset(owner: Node) -> void:
	if is_instance_valid(owner): _feedback_offsets.erase(owner.get_instance_id())
	if is_instance_valid(_zoom_camera): _apply_zoom_position()

func _normal_world() -> Node:
	var pause = _pause_ref.get_ref() if _pause_ref != null else null
	if is_instance_valid(pause): return pause.get_bound_scope()
	return target.get_parent() if _has_valid_target() else null

func _normal_position() -> Vector3:
	if not _has_valid_target(): return global_position
	var result := target.global_position + camera_offset + current_look_ahead
	if lock_vertical_follow: result.y = locked_target_height + camera_offset.y
	return result

func _source_pose(source: Node3D) -> Transform3D:
	var desired := source.global_position + camera_offset
	if lock_vertical_follow: desired.y = locked_target_height + camera_offset.y
	return Transform3D(global_basis,desired)

# 使用现有镜头投影和缩放求参考宽度；无子相机的测试/轻装配使用保守12米。
func _focus_view_width() -> float:
	if not is_instance_valid(_zoom_camera) or not _has_valid_target(): return 12.0
	var normal_camera_pose := _zoom_camera.global_transform
	normal_camera_pose.origin -= _focus_applied_offset
	var depth := -(normal_camera_pose.affine_inverse() * target.global_position).z
	if depth <= _zoom_camera.near: return 12.0
	var size := _zoom_camera.get_viewport().get_visible_rect().size
	var left := _zoom_camera.project_position(Vector2(0.0, size.y * 0.5), depth)
	var right := _zoom_camera.project_position(Vector2(size.x, size.y * 0.5), depth)
	var width := left.distance_to(right)
	return width if is_finite(width) and width > 0.0 else 12.0

func _presentation_clock_blocked() -> bool:
	var pause = _pause_ref.get_ref() if _pause_ref != null else null
	if _pause_ref != null and not is_instance_valid(pause):
		_pause_ref = null
		process_mode = _original_process_mode
		return get_tree().paused
	if not is_instance_valid(pause): return get_tree().paused
	# 纯释放资产仍由协调器独立推进；只有镜头在释放强调中保持当前画面。
	return not pause.is_presentation_allowed() or pause.has_release_accent()

func _update_presentation_focus(delta: float, normal_position: Vector3) -> bool:
	if _focus_profile == null: return false
	if _presentation_clock_blocked(): return true
	if not _has_valid_target():
		clear_presentation_focus()
		return false
	var baseline := global_position - _focus_applied_offset
	_focus_origin.origin += baseline - _focus_anchor_position
	_focus_anchor_position = baseline
	var destination := Transform3D(global_basis, baseline)
	if _focus_phase == CameraEffectProfile.Phase.ENTER:
		var source = _focus_source.get_ref() if _focus_source != null else null
		if not is_instance_valid(source) or not source.is_inside_tree() or source.is_queued_for_deletion() or (source is UnitBase and source.is_dead()):
			end_presentation_focus(_focus_id)
			return true
		var source_offset: Vector3 = source.global_position - (normal_position - camera_offset - current_look_ahead)
		var offset := _focus_profile.get_focus_offset(source_offset, _focus_view_width())
		if not offset.is_finite():
			clear_presentation_focus()
			return false
		destination.origin += offset
	if _focus_duration < 0.0:
		_focus_duration = _focus_profile.get_transition_duration(_focus_origin, destination, _focus_phase)
	var duration := _focus_duration
	if not is_finite(duration) or duration < 0:
		clear_presentation_focus()
		return false
	_focus_elapsed += maxf(delta,0.0)
	var progress := 1.0 if duration == 0 else clampf(_focus_elapsed/duration,0,1)
	var pose := _focus_profile.sample_rig_transform(_focus_origin,destination,progress,_focus_phase)
	if not pose.is_finite():
		clear_presentation_focus()
		return false
	global_transform = pose
	_focus_applied_offset = pose.origin - baseline
	if progress >= 1.0 and _focus_phase == CameraEffectProfile.Phase.RETURN: clear_presentation_focus()
	return true