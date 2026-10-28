extends "res://Effects/Combat/StatusModifierVisualPlayer.gd"
## 通用头顶状态标记：复用gain/idle/out，只跟随头顶血条并朝向相机，不读取状态数值或计时。
## 标记中心高于已有WorldHealthBar锚点的世界米数，默认0.4，避开血条及小圆点。
## 没有血条的预览/单位使用场景根节点原有局部位置；仅影响此标记，不移动血条或单位。
@export_range(0.0,3.0,0.05) var height_above_bar_m: float = 0.4
var _bar_ref: WeakRef

func _ready() -> void:
	super._ready()
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var ancestor := get_parent()
	while ancestor != null and not ancestor is UnitBase:
		ancestor = ancestor.get_parent()
	if ancestor != null:
		var bars := ancestor.find_children("*","WorldHealthBar",true,false)
		if not bars.is_empty(): _bar_ref = weakref(bars[0])
	_update_pose()

func _process(_delta: float) -> void:
	_update_pose()

func _update_pose() -> void:
	var bar := _bar_ref.get_ref() as Node3D if _bar_ref != null else null
	if is_instance_valid(bar) and bar.is_inside_tree():
		# 本节点逐渲染帧面向镜头，必须取血条的渲染插值位置，而不是最新物理位置。
		global_position = bar.get_global_transform_interpolated().origin + Vector3.UP * height_above_bar_m
	var camera := get_viewport().get_camera_3d()
	if camera != null:
		# 整组符号统一朝向，不能仅逐网格billboard，否则折角位置会随单位旋转散开。
		global_basis = camera.global_basis.orthonormalized()
