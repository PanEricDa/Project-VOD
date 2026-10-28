extends "res://Effects/Skills/FlameBarrage/FlameBarrageEffectPlayer.gd"
## 复用既有视觉生命周期；聚能焦点跟随真实弩口，不参与施法或伤害。
var _muzzle: WeakRef

## source为施法者，world_origin为世界发射变换，duration为实际施法秒数。
## 缺少ProjectileOrigin时沿基类固定偏移回退；不修改角色或动画。
func configure_cast(source: Node3D, world_origin: Transform3D, duration: float) -> void:
	super.configure_cast(source, world_origin, duration)
	var anchor := source.find_child("ProjectileOrigin",true,false) as Node3D if is_instance_valid(source) else null
	_muzzle = weakref(anchor) if anchor != null else null
	_follow_muzzle()

## delta为本实例时钟秒数；与基类一样由_process或外部单一路径调用。
func advance_effect(delta: float) -> void:
	super.advance_effect(delta)
	if is_playing(): _follow_muzzle()

func _follow_muzzle() -> void:
	var anchor := _muzzle.get_ref() as Node3D if _muzzle != null else null
	if is_instance_valid(anchor) and anchor.is_inside_tree():
		$VisualRoot/Focus.global_transform = anchor.global_transform
