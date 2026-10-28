class_name CinematicOcclusionFilter
extends RefCounted
## 特写期间的临时视觉遮挡抑制；只改视觉节点visible，不改单位根、碰撞、材质或战斗状态。
var _scope: WeakRef
var _caster: WeakRef
var _tree: SceneTree
var _dirty: bool = true
var _units: Array[Dictionary] = []
var _props: Array[WeakRef] = []
var _hidden: Dictionary = {}
var _hidden_units: Dictionary = {}
var _from := Vector3.ZERO
var _to := Vector3.ZERO
var _radius: float = 0.8
var _ground_y: float = 0.0
var _support: WeakRef
var _support_point := Vector3.ZERO

## scope为原世界，caster为必须保留的施放者；from/to为最终特写镜头至观察点的世界线段。
## width_m为通道完整宽度（米）；一次仅持有一个特写，开始前恢复上次记录。
func begin(scope: Node, caster: Node3D, from: Vector3, to: Vector3, width_m: float) -> void:
	restore()
	if not is_instance_valid(scope) or not scope.is_inside_tree() or not is_instance_valid(caster) or not caster.is_inside_tree() or not scope.is_ancestor_of(caster): return
	if not from.is_finite() or not to.is_finite() or not is_finite(width_m) or width_m <= 0: return
	_scope = weakref(scope)
	_caster = weakref(caster)
	_from = from
	_to = to
	_ground_y = caster.global_position.y
	_find_support(caster)
	_radius = width_m * 0.5
	_tree = scope.get_tree()
	_tree.node_added.connect(_on_node_added)
	_dirty = true
	refresh()

## 仅报告当前原世界与施放者是否仍有效；Camera用此处理卸载和死亡，旧请求不复活。
func is_valid() -> bool:
	var scope: Node = _scope.get_ref() as Node if _scope != null else null
	var caster: Node3D = _caster.get_ref() as Node3D if _caster != null else null
	return is_instance_valid(scope) and scope.is_inside_tree() and not scope.is_queued_for_deletion() and is_instance_valid(caster) and caster.is_inside_tree() and not caster.is_queued_for_deletion() and scope.is_ancestor_of(caster) and not (caster is UnitBase and caster.is_dead())

## 更新移动/新生遮挡物；已经隐藏的对象保持隐藏到切出，避免边界抖动闪烁。
func refresh() -> void:
	if not is_valid(): return
	if _dirty:
		_units.clear()
		_props.clear()
		_collect(_scope.get_ref() as Node)
		_dirty = false
	for id: int in _hidden.keys():
		var node := (_hidden[id] as WeakRef).get_ref() as Node3D
		if not is_instance_valid(node):
			_hidden.erase(id)
		elif not node.is_inside_tree():
			node.visible = true
			_hidden.erase(id)
		else:
			node.visible = false
	for data: Dictionary in _units:
		var unit := (data.unit as WeakRef).get_ref() as UnitBase
		if not is_instance_valid(unit) or not unit.is_inside_tree(): continue
		var blocked := _hidden_units.has(unit.get_instance_id())
		if not blocked:
			for ref: WeakRef in data.geometry:
				var mesh := ref.get_ref() as GeometryInstance3D
				if is_instance_valid(mesh) and mesh.is_inside_tree() and mesh.is_visible_in_tree() and _blocks(mesh,false):
					blocked = true
					break
		if blocked:
			_hidden_units[unit.get_instance_id()] = true
			_hide(unit.get_node_or_null("Visual") as Node3D)
			_hide(unit.get_node_or_null("WorldUIRoot") as Node3D)
			# 角色附属且不在上述两个插槽下的视觉（例如其他单位施法特效）也不能悬空遮挡。
			for ref: WeakRef in data.geometry:
				var mesh := ref.get_ref() as GeometryInstance3D
				if is_instance_valid(mesh) and mesh.is_inside_tree() and mesh.is_visible_in_tree(): _hide(mesh)
	for ref: WeakRef in _props:
		var mesh := ref.get_ref() as GeometryInstance3D
		if is_instance_valid(mesh) and mesh.is_inside_tree() and mesh.is_visible_in_tree() and _blocks(mesh,true): _hide(mesh)

## 恢复本次确实隐藏过的节点；原本不可见者不纳入记录，删除对象安全跳过，不强持有场景。
func restore() -> void:
	if is_instance_valid(_tree) and _tree.node_added.is_connected(_on_node_added): _tree.node_added.disconnect(_on_node_added)
	_tree = null
	for ref: WeakRef in _hidden.values():
		var node := ref.get_ref() as Node3D
		if is_instance_valid(node): node.visible = true
	_hidden.clear()
	_hidden_units.clear()
	_units.clear()
	_props.clear()
	_scope = null
	_caster = null
	_support = null

func _collect(node: Node) -> void:
	if node == _caster.get_ref() or _belongs_to_caster(node): return
	if node is UnitBase:
		var geometry: Array[WeakRef] = []
		_collect_geometry(node,geometry)
		_units.append({"unit":weakref(node),"geometry":geometry})
		return
	if node is GeometryInstance3D: _props.append(weakref(node))
	for child: Node in node.get_children(): _collect(child)

func _collect_geometry(node: Node, result: Array[WeakRef]) -> void:
	# RESOLVED_TARGET表现可挂在另一个单位根下，仍按来源排除，不能误作该单位附属模型。
	if _belongs_to_caster(node): return
	if node is GeometryInstance3D: result.append(weakref(node))
	for child: Node in node.get_children(): _collect_geometry(child,result)

func _blocks(mesh: GeometryInstance3D, environment: bool) -> bool:
	var local := mesh.custom_aabb if mesh.custom_aabb.has_surface() else mesh.get_aabb()
	# 与渲染裁剪一致：模型局部容差先扩展，再随节点缩放/旋转到世界；通道宽度随后以世界米数扩展。
	if is_finite(mesh.extra_cull_margin) and mesh.extra_cull_margin > 0: local = local.grow(mesh.extra_cull_margin)
	var bounds := mesh.global_transform * local
	if not bounds.position.is_finite() or not bounds.size.is_finite(): return false
	# 地面/脚下支撑面不作为可隐藏物；判断真实世界包围盒，而非依赖Floor节点名或碰撞层。
	if environment and (bounds.end.y <= _ground_y + 0.05 or _is_support_geometry(mesh,bounds)): return false
	return bounds.grow(_radius).intersects_segment(_from,_to) != null

func _hide(node: Node3D) -> void:
	if not is_instance_valid(node) or not node.visible: return
	var id := node.get_instance_id()
	if not _hidden.has(id): _hidden[id] = weakref(node)
	node.visible = false

func _on_node_added(node: Node) -> void:
	var scope: Node = _scope.get_ref() as Node if _scope != null else null
	if not is_instance_valid(scope) or not scope.is_ancestor_of(node): return
	var caster: Node = _caster.get_ref() as Node if _caster != null else null
	if node == caster or (is_instance_valid(caster) and caster.is_ancestor_of(node)) or _belongs_to_caster(node): return
	if node is GeometryInstance3D or node is UnitBase: _dirty = true


func _belongs_to_caster(node: Node) -> bool:
	var caster: Node = _caster.get_ref() as Node if _caster != null else null
	while is_instance_valid(node):
		if node.has_meta(&"presentation_source_ref"):
			var ref := node.get_meta(&"presentation_source_ref") as WeakRef
			if ref != null and ref.get_ref() == caster: return true
		node = node.get_parent()
	return false

func _find_support(caster: Node3D) -> void:
	var query := PhysicsRayQueryParameters3D.create(caster.global_position+Vector3.UP*0.5,caster.global_position-Vector3.UP*2.0)
	if caster is CollisionObject3D: query.exclude = [caster.get_rid()]
	var state := caster.get_world_3d().direct_space_state
	for i: int in range(8):
		var hit := state.intersect_ray(query)
		if hit.is_empty(): return
		var collider := hit.get("collider") as Node
		if collider is UnitBase:
			var excluded := query.exclude
			excluded.append(hit.rid)
			query.exclude = excluded
			continue
		var normal: Vector3 = hit.normal
		if is_instance_valid(collider) and normal.y >= 0.5:
			_support = weakref(collider)
			_support_point = hit.position
		return

func _is_support_geometry(mesh: GeometryInstance3D, bounds: AABB) -> bool:
	var support: Node = _support.get_ref() as Node if _support != null else null
	if not is_instance_valid(support): return false
	# 只保留实际支撑命中点处的几何，不把同一碰撞父节点下远处的墙一起豁免。
	return (mesh == support or support.is_ancestor_of(mesh) or mesh.is_ancestor_of(support)) and bounds.grow(0.05).has_point(_support_point)
