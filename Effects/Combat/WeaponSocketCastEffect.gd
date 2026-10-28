extends "res://Effects/Skills/FlameBarrage/FlameBarrageEffectPlayer.gd"
## 纯表现适配：VisualRoot/Focus跟随标准WeaponSocket；各资产自行编辑Focus下的局部偏移。
var _weapon_socket: WeakRef

## source为施法者，world_origin为动作发射变换，duration为实际施法秒数；无挂点时沿用基类固定焦点。
func configure_cast(source: Node3D, world_origin: Transform3D, duration: float) -> void:
	super.configure_cast(source, world_origin, duration)
	var socket := source.find_child("WeaponSocket", true, false) as Node3D if is_instance_valid(source) else null
	_weapon_socket = weakref(socket) if socket != null else null
	_follow_socket()

## delta为请求时钟秒数；只同步视觉，不修改武器、动作或战斗数据。
func advance_effect(delta: float) -> void:
	super.advance_effect(delta)
	if is_playing(): _follow_socket()

func _follow_socket() -> void:
	var socket := _weapon_socket.get_ref() as Node3D if _weapon_socket != null else null
	if is_instance_valid(socket) and socket.is_inside_tree():
		$VisualRoot/Focus.global_transform = socket.global_transform
