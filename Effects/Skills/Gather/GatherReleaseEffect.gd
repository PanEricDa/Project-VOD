extends "res://Effects/Skills/FlameBarrage/FlameBarrageEffectPlayer.gd"
## 收束风视觉：几何只来自已冻结的表现快照；不索敌、不移动单位，也不读取技能节点。
const RESIDUE_SECONDS := 0.15
var _radius: float = 1.0
var _selection_center := Vector3.ZERO
var _destination_center := Vector3.ZERO
var _disk_radius: float = 0.1
var _pull_seconds: float = 0.35
var _elapsed: float = 0.0

## presentation为实际成功释放的只读快照；入树前配置，未提供有效数据则保留独立资产预览默认值。
func configure_release(presentation: SkillPresentationContext) -> void:
	var data := presentation.get_effect_data(&"pull")
	var pose := presentation.release_caster_transform
	if data.is_empty() or not pose.is_finite(): return
	_radius = presentation.effect_radius
	# 视觉根在哪里不决定玩法圆心；选择范围与拉拽终点分别来自同次不可变快照。
	var pull_center := pose.origin - pose.basis.z * float(data.get("front_distance_m",0.0))
	if bool(data.get("center_on_target",false)):
		if not presentation.release_target_position.is_finite(): return
		pull_center = presentation.release_target_position
		pose.origin = pull_center
	var selection_center := presentation.release_effect_center_position
	if not selection_center.is_finite(): return
	_selection_center = pose.affine_inverse() * selection_center
	_destination_center = pose.affine_inverse() * pull_center
	_disk_radius = float(data.get("gather_radius_m",0.1))
	_pull_seconds = maxf(float(data.get("duration_seconds",0.35)),0.001)
	# 根节点top_level：世界父节点缩放、玩家移动均不能二次变换已冻结的米制几何。
	transform = pose
	_speed = 1.0 / (_pull_seconds + RESIDUE_SECONDS)

func _ready() -> void:
	super._ready()

## 从头播放；继承共享生命周期、独立时钟和自动回收契约，不附加战斗事件。
func play() -> void:
	_elapsed = 0.0
	super.play()
	_update_geometry()

## delta为当前表现时钟的秒数；外部手动推进前须set_process(false)，避免双重计时。
func advance_effect(delta: float) -> void:
	if not _playing or not is_finite(delta) or delta <= 0.0: return
	_elapsed += delta
	super.advance_effect(delta)
	if _playing: _update_geometry()

func _update_geometry() -> void:
	var boundary: Node3D = $VisualRoot/Boundary
	var destination: Node3D = $VisualRoot/Destination
	boundary.position = _selection_center + Vector3(0,0.04,0)
	boundary.scale = Vector3(_radius,1,_radius)
	for arc: MeshInstance3D in boundary.get_children():
		arc.transparency = clampf(_elapsed / (_pull_seconds + 0.08),0,1)
	destination.position = _destination_center + Vector3(0,0.06,0)
	var t := clampf(_elapsed / _pull_seconds,0.0,1.0)
	var residue := clampf((_elapsed-_pull_seconds)/RESIDUE_SECONDS,0.0,1.0)
	var ring: MeshInstance3D = $VisualRoot/Destination/CollapseRing
	var ring_radius := maxf(_disk_radius,0.18) * lerpf(1.25,0.25,residue)
	ring.scale = Vector3(ring_radius,0.45,ring_radius)
	ring.transparency = lerpf(0.55,0.1,t) if t < 1.0 else residue
	var ribbons: Node3D = $VisualRoot/Ribbons
	ribbons.visible = t < 1.0
	if not ribbons.visible: return
	for i: int in range(ribbons.get_child_count()):
		var ribbon := ribbons.get_child(i) as MeshInstance3D
		var mesh := ImmediateMesh.new()
		mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
		var angle := TAU * float(i) / float(ribbons.get_child_count()) + 0.13
		var start := _selection_center + Vector3(cos(angle)*_radius,0.12,sin(angle)*_radius)
		var end := _destination_center + Vector3(cos(angle)*_disk_radius*0.45,0.15,sin(angle)*_disk_radius*0.45)
		var side := Vector3(-sin(angle),0,cos(angle))
		var head := pow(t,0.75)
		var tail := maxf(0.0,head-0.40)
		for segment: int in range(12):
			var a := lerpf(tail,head,float(segment)/12.0)
			var b := lerpf(tail,head,float(segment+1)/12.0)
			var pa := _point(start,end,side,a)
			var pb := _point(start,end,side,b)
			var wa := 0.065 * sin(PI*float(segment)/12.0)
			var wb := 0.065 * sin(PI*float(segment+1)/12.0)
			for vertex: Vector3 in [pa-side*wa,pa+side*wa,pb+side*wb,pa-side*wa,pb+side*wb,pb-side*wb]:
				mesh.surface_add_vertex(vertex)
		mesh.surface_end()
		ribbon.mesh = mesh

func _point(start: Vector3, end: Vector3, side: Vector3, progress: float) -> Vector3:
	return start.lerp(end,progress) + side*sin(PI*progress)*_radius*0.16 + Vector3.UP*sin(PI*progress)*0.38
