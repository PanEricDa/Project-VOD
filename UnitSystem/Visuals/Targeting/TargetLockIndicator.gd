class_name TargetLockIndicator
extends Node3D

## 玩家锁定目标的正式世界空间特效控制器。
## 本类只管理进入、维持、退出三种表现状态与统一透明度、缩放、世界位置的推进；
## 它不读取 InputMap、不认识 UnitBase、不持有锁定目标、不发送锁定信号，
## 也不修改任何业务状态。业务组件只允许通过 play_enter / update_world_position /
## play_exit / hide_immediately 驱动表现。
## 透明度通过统一的内部表现值驱动并推送给正式材质参数；场景缺少 RingMesh 子节点时
## 三状态逻辑照常运行，只影响画面不产生错误。

enum EffectState {
	ENTER,
	MAINTAIN,
	EXIT,
}

## 进入动画起始透明度相对维持值的比例，只影响进入表现。
const ENTER_START_ALPHA_RATIO: float = 0.25
## 维持状态的目标统一缩放；进入与退出动画都向该值收敛或远离。
const MAINTAIN_SCALE: float = 1.0
## 正式材质接收总透明度的参数名；由本脚本独占写入，业务组件不得直接操作材质。
const MATERIAL_ALPHA_PARAMETER := &"overall_alpha"

## 进入动画时长，单位为秒；默认 0.16，设计范围 0.12～0.20，只影响进入表现速度。
@export_range(0.05, 2.0, 0.01, "or_greater")
var enter_duration: float = 0.16
## 退出动画时长，单位为秒；默认 0.13，设计范围 0.10～0.16，只影响退出表现速度。
@export_range(0.05, 2.0, 0.01, "or_greater")
var exit_duration: float = 0.13
## 维持状态的基础不透明度，取值 0～1；进入从其比例值淡入，退出衰减到 0。
@export_range(0.05, 1.0, 0.01)
var maintain_opacity: float = 0.85
## 进入动画的起始统一缩放，取值 0.1～1.0；进入过程由该值恢复到 1。
@export_range(0.1, 1.0, 0.01)
var enter_start_scale: float = 0.72
## 退出动画的结束统一缩放，取值 0.1～1.0；退出伴随轻微缩小。
@export_range(0.1, 1.0, 0.01)
var exit_end_scale: float = 0.82
## 维持状态亮度呼吸的透明度波动幅度，取值 0～0.3；0 表示完全静止的维持。
@export_range(0.0, 0.3, 0.005)
var breathe_amplitude: float = 0.08
## 维持状态亮度呼吸的速度，单位为圈每秒；只改变呼吸快慢，不影响基础透明度。
@export_range(0.1, 8.0, 0.05)
var breathe_speed: float = 2.0

## 场景内唯一的正式环形显示层；脚本独立实例（无该子节点）时为 null，仅影响画面。
@onready var _ring_mesh: MeshInstance3D = (
	get_node_or_null(^"RingRoot/RingMesh") as MeshInstance3D
)

## 当前表现状态；隐藏后保留最近一次状态供调试读取。
var _effect_state: EffectState = EffectState.EXIT
## 当前状态已经推进的时间，单位为秒；隐藏时不推进。
var _state_time: float = 0.0
## 统一表现透明度（0～1），由三状态推进并推送给正式材质。
var _presentation_alpha: float = 0.0
## 退出动画起始透明度，用于从当前表现平滑衰减而不是固定值。
var _exit_start_alpha: float = 0.0
## 退出动画起始统一缩放，用于从当前进入或维持尺寸连续缩小，避免快速解除时跳变。
var _exit_start_scale: float = MAINTAIN_SCALE
## 材质缺失诊断是否已经输出过；避免每帧刷屏。
var _material_issue_reported: bool = false


func _ready() -> void:
	# 初始保持隐藏，避免尚未锁定时短暂闪现；顶层世界变换确保不继承父级位移。
	visible = false
	top_level = true


func _process(delta: float) -> void:
	if not visible:
		return
	_state_time += delta
	match _effect_state:
		EffectState.ENTER:
			_advance_enter()
		EffectState.MAINTAIN:
			_advance_maintain()
		EffectState.EXIT:
			_advance_exit()


## 显示特效、设置世界位置并重置进入进度；允许中断正在播放的退出。
## world_position 应为目标脚下的世界坐标，通常已含统一高度偏移。
func play_enter(world_position: Vector3) -> void:
	global_position = world_position
	_effect_state = EffectState.ENTER
	_state_time = 0.0
	_apply_enter(0.0)
	visible = true


## 只更新世界位置，不重播进入，也不改变当前业务锁定。
## 隐藏时同样保存位置作为等待位置，但不会自行显示特效。
func update_world_position(world_position: Vector3) -> void:
	global_position = world_position


## 从当前位置和当前透明度开始退出；已经隐藏时为空操作。
func play_exit() -> void:
	if not visible:
		return
	_effect_state = EffectState.EXIT
	_state_time = 0.0
	_exit_start_alpha = _presentation_alpha
	_exit_start_scale = scale.x


## 场景销毁或初始化失败时立即复位并隐藏，不播放退出动画。
func hide_immediately() -> void:
	visible = false
	_effect_state = EffectState.EXIT
	_state_time = exit_duration
	_presentation_alpha = 0.0
	_exit_start_scale = MAINTAIN_SCALE
	_push_alpha_to_material()


## 返回当前三状态；隐藏后保留最近状态，可见性必须另行调用 is_effect_visible()。
func get_effect_state() -> EffectState:
	return _effect_state


## 返回特效是否仍在显示，包括进入、维持和尚未结束的退出。
func is_effect_visible() -> bool:
	return visible


## 返回当前统一表现透明度（0～1），供自动测试与调试读取；业务组件不应依赖该值。
func get_presentation_alpha() -> float:
	return _presentation_alpha


func _advance_enter() -> void:
	if _state_time >= enter_duration:
		_effect_state = EffectState.MAINTAIN
		_state_time = 0.0
		_apply_maintain()
		return
	_apply_enter(_state_time / enter_duration)


func _advance_maintain() -> void:
	_apply_maintain()


func _advance_exit() -> void:
	if _state_time >= exit_duration:
		visible = false
		_presentation_alpha = 0.0
		_push_alpha_to_material()
		return
	_apply_exit(_state_time / exit_duration)


func _apply_enter(progress: float) -> void:
	var eased := _ease_out_saturate(clampf(progress, 0.0, 1.0))
	_presentation_alpha = lerpf(
		maintain_opacity * ENTER_START_ALPHA_RATIO,
		maintain_opacity,
		eased
	)
	var target_scale := lerpf(enter_start_scale, MAINTAIN_SCALE, eased)
	_apply_transforms(target_scale)
	_push_alpha_to_material()


func _apply_maintain() -> void:
	var breathe := breathe_amplitude * sin(TAU * breathe_speed * _state_time)
	_presentation_alpha = clampf(
		maintain_opacity + breathe,
		0.0,
		1.0
	)
	_apply_transforms(MAINTAIN_SCALE)
	_push_alpha_to_material()


func _apply_exit(progress: float) -> void:
	var eased := _ease_out_saturate(clampf(progress, 0.0, 1.0))
	_presentation_alpha = lerpf(_exit_start_alpha, 0.0, eased)
	var exit_scale := lerpf(_exit_start_scale, exit_end_scale, eased)
	_apply_transforms(exit_scale)
	_push_alpha_to_material()


func _apply_transforms(uniform_scale: float) -> void:
	scale = Vector3.ONE * uniform_scale


## 把统一透明度推送给正式 ShaderMaterial；缺少场景子节点时静默跳过，
## 存在网格但材质缺失时只诊断一次，不上抛到锁定组件。
## 对未声明同名 uniform 的 shader 写入参数覆盖在运行时是静默且安全的，
## 因此不依赖引擎的参数存在性查询接口。
func _push_alpha_to_material() -> void:
	if _ring_mesh == null:
		return
	var material := _ring_mesh.get_active_material(0) as ShaderMaterial
	if material == null:
		if not _material_issue_reported:
			_material_issue_reported = true
			push_warning(
				"TargetLockIndicator: RingMesh has no ShaderMaterial; "
				+ "state logic keeps running without the visual layer."
			)
		return
	material.set_shader_parameter(MATERIAL_ALPHA_PARAMETER, _presentation_alpha)


func _ease_out_saturate(progress: float) -> float:
	return 1.0 - (1.0 - progress) * (1.0 - progress)
