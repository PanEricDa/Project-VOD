class_name NearbySkillTargetQuery
extends RefCounted

## 命中点附近的即时物理目标查询；不依赖施法者的 AI 感知半径，也不保存跨帧候选。

const UNIT_COLLISION_MASK: int = 6
const COLLIDER_MARGIN_M: float = 0.5
const VERTICAL_QUERY_HEIGHT_M: float = 8.0
const QUERY_BATCH_SIZE: int = 64


## 从 world 的物理空间，在 origin 周围 radius_m 米的水平半径内最多选 max_targets 个目标。
## relation_flags 采用 TargetResolver 的关系位掩码；excluded 可为空，非空时排除本次已命中目标。
## 非有限坐标、非正半径、无效施法者或空关系掩码返回空数组；同距按实例 ID 稳定排序。
static func select_targets(
	world: World3D,
	caster: Node3D,
	origin: Vector3,
	radius_m: float,
	max_targets: int,
	relation_flags: int,
	excluded: Node3D
) -> Array[Node3D]:
	var selected: Array[Node3D] = []
	if (
		world == null or not is_instance_valid(caster) or not caster.is_inside_tree()
		or not origin.is_finite() or not is_finite(radius_m) or radius_m <= 0.0
		or max_targets <= 0 or relation_flags == 0
	):
		return selected
	var shape := CylinderShape3D.new()
	shape.radius = radius_m + COLLIDER_MARGIN_M
	shape.height = VERTICAL_QUERY_HEIGHT_M
	var parameters := PhysicsShapeQueryParameters3D.new()
	parameters.shape = shape
	parameters.transform = Transform3D(Basis.IDENTITY, origin + Vector3.UP * 0.4)
	parameters.collision_mask = UNIT_COLLISION_MASK
	parameters.collide_with_bodies = true
	parameters.collide_with_areas = false
	var excluded_rids: Array[RID] = []
	var candidates: Array[Node3D] = []
	var seen: Dictionary = {}
	# 分批排除已命中的碰撞 RID，避免 intersect_shape 默认数量截断最近目标。
	while true:
		parameters.exclude = excluded_rids
		var hits: Array[Dictionary] = world.direct_space_state.intersect_shape(parameters, QUERY_BATCH_SIZE)
		if hits.is_empty():
			break
		var new_rid_count := 0
		for hit: Dictionary in hits:
			var rid: RID = hit.get("rid", RID())
			if rid.is_valid() and not excluded_rids.has(rid):
				excluded_rids.append(rid)
				new_rid_count += 1
			var collider: Variant = hit.get("collider")
			if not collider is Node3D or not is_instance_valid(collider):
				continue
			var candidate := collider as Node3D
			if candidate == excluded or seen.has(candidate.get_instance_id()):
				continue
			seen[candidate.get_instance_id()] = true
			if not TargetResolver.is_candidate_valid(caster, candidate, relation_flags, true, true):
				continue
			var offset: Vector3 = candidate.global_position - origin
			offset.y = 0.0
			if offset.length() <= radius_m + 0.05:
				candidates.append(candidate)
		if new_rid_count == 0:
			break
	candidates.sort_custom(func(a: Node3D, b: Node3D) -> bool:
		var a_offset := a.global_position - origin
		var b_offset := b.global_position - origin
		a_offset.y = 0.0
		b_offset.y = 0.0
		var a_distance := a_offset.length_squared()
		var b_distance := b_offset.length_squared()
		if not is_equal_approx(a_distance, b_distance):
			return a_distance < b_distance
		return a.get_instance_id() < b.get_instance_id()
	)
	for candidate: Node3D in candidates:
		if selected.size() >= max_targets:
			break
		selected.append(candidate)
	return selected
