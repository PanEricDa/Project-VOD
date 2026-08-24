@tool
class_name EditorWeaponPreview
extends Node3D

## 仅用于 Godot 编辑器中的武器视觉预览。
##
## 本节点不参与运行时装备、动画或命中检测。它读取父单位根节点的
## starting_weapon，并把 WeaponData.visual_scene 生成到具体 Visual 的
## CharacterRoot/WeaponSocket 下；生成的预览实例没有 owner，因此不会被保存进场景。

const VISUAL_SLOT_PATH: NodePath = ^"Visual"
const WEAPON_SOCKET_PATH: NodePath = ^"CharacterRoot/WeaponSocket"
const PREVIEW_NODE_NAME: StringName = &"__EditorWeaponPreview"

var _last_weapon: WeaponData
var _preview_visual: Node3D


func _ready() -> void:
	# 预览节点本身永远不承担游戏显示；真正的临时模型会直接挂到 WeaponSocket。
	visible = false
	set_process(Engine.is_editor_hint())
	if Engine.is_editor_hint():
		call_deferred("_refresh_preview")


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		_refresh_preview()


## 公开刷新接口，供单位根节点或编辑器工具主动调用。
func set_weapon(weapon_data: WeaponData) -> void:
	if _last_weapon == weapon_data and is_instance_valid(_preview_visual):
		return
	_last_weapon = weapon_data
	_rebuild_preview()


## 清理临时预览模型；不会触碰运行时正式装备的节点。
func clear_preview() -> void:
	_last_weapon = null
	_remove_preview()


func _refresh_preview() -> void:
	var unit_root := get_parent()
	if not is_instance_valid(unit_root):
		return
	var weapon_data := unit_root.get("starting_weapon") as WeaponData
	if weapon_data == null:
		clear_preview()
		return
	set_weapon(weapon_data)


func _rebuild_preview() -> void:
	_remove_preview()
	if _last_weapon == null or _last_weapon.visual_scene == null:
		return
	var weapon_socket := _find_weapon_socket()
	if weapon_socket == null:
		return
	var instance := _last_weapon.visual_scene.instantiate()
	if not instance is Node3D:
		if instance != null:
			instance.free()
		return
	_preview_visual = instance as Node3D
	_preview_visual.name = PREVIEW_NODE_NAME
	# owner 保持 null，确保该节点只是编辑器运行期对象，不会写入 tscn。
	_preview_visual.owner = null
	weapon_socket.add_child(_preview_visual)


func _remove_preview() -> void:
	if is_instance_valid(_preview_visual):
		_preview_visual.queue_free()
	_preview_visual = null
	var weapon_socket := _find_weapon_socket()
	if weapon_socket == null:
		return
	for child: Node in weapon_socket.get_children():
		if child.name == PREVIEW_NODE_NAME:
			child.queue_free()


func _find_weapon_socket() -> Node3D:
	var unit_root := get_parent()
	if not is_instance_valid(unit_root):
		return null
	var visual_slot := unit_root.get_node_or_null(VISUAL_SLOT_PATH) as Node3D
	if visual_slot == null:
		return null
	# Visual 插槽允许存在辅助或额外视觉子节点；按标准端点查找真正的角色视觉。
	var resolved_socket: Node3D
	var valid_visual_count: int = 0
	for child: Node in visual_slot.get_children():
		var candidate_visual := child as Node3D
		if candidate_visual == null:
			continue
		var weapon_socket := candidate_visual.get_node_or_null(
			WEAPON_SOCKET_PATH
		) as Node3D
		if weapon_socket != null:
			valid_visual_count += 1
			resolved_socket = weapon_socket
	return resolved_socket if valid_visual_count == 1 else null
