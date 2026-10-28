extends "res://Effects/Skills/FlameBarrage/FlameBarrageEffectPlayer.gd"
## 定向命中纯视觉；局部-Z为穿出方向，散射不创建子技能、碰撞或伤害。
var _incoming := Vector3.FORWARD

func _ready() -> void:
	super._ready()
	_apply_direction()

## direction为世界空间箭矢入射方向；可在入树前注入，零/非有限输入保持默认-Z。
func configure_impact_direction(direction: Vector3) -> void:
	if not direction.is_finite() or direction.length_squared() < 0.000001: return
	_incoming = direction.normalized()
	if is_inside_tree(): _apply_direction()

func _apply_direction() -> void:
	var up := Vector3.FORWARD if absf(_incoming.dot(Vector3.UP)) > 0.999 else Vector3.UP
	global_basis = Basis.looking_at(_incoming,up)
