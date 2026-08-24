extends SceneTree

## 以 Godot ResourceSaver 正式创建 Delivery 预设资源。
## 本脚本可重复运行；每次都会覆盖为同类型的基础预设，并由 Godot 重新维护 UID 索引。

const PRESET_DIRECTORY := "res://SkillSystem/02-Delivery/Presets"
const INSTANT_PRESET_PATH := PRESET_DIRECTORY + "/InstantTargetDelivery.tres"
const TRACKING_PRESET_PATH := PRESET_DIRECTORY + "/TrackingProjectileDelivery.tres"
const GROUND_PRESET_PATH := PRESET_DIRECTORY + "/GroundAreaDelivery.tres"


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PRESET_DIRECTORY))
	_save_preset(InstantTargetDeliveryConfig.new(), INSTANT_PRESET_PATH)
	_save_preset(TrackingProjectileDeliveryConfig.new(), TRACKING_PRESET_PATH)
	_save_preset(GroundAreaDeliveryConfig.new(), GROUND_PRESET_PATH)
	# UID 需要由编辑器文件系统扫描后写入下一进程的资源索引；
	# `DeliveryResourceIndexTest.gd` 必须在编辑器扫描后的独立进程运行，
	# 以验证 Inspector Quick Load 所依赖的真实最终状态。
	print("Delivery presets saved. Run an editor filesystem scan, then DeliveryResourceIndexTest.")
	quit(0)


## 将一个强类型 Delivery 配置保存为外部资源；失败时立即终止，避免产生半成品资源。
func _save_preset(preset: SkillDeliveryConfig, resource_path: String) -> void:
	# ResourceSaver 不会在纯命令行首次保存时自动写入 UID；先向 Godot 的 UID 注册表登记，
	# 再保存，才能让文件头和编辑器文件系统索引使用同一个正式 UID。
	# 同步设置资源路径；FLAG_CHANGE_PATH 使 ResourceSaver 以该路径作为资源自身路径保存，
	# 避免命令行保存时只生成无 UID 的纯文本资源。
	preset.resource_path = resource_path
	var save_error := ResourceSaver.save(preset, resource_path, ResourceSaver.FLAG_CHANGE_PATH)
	if save_error != OK:
		push_error("Unable to save Delivery preset (%s): %s" % [resource_path, error_string(save_error)])
		quit(1)
		return
	# 运行时的 ResourceSaver 不会自动将 UID 写回磁盘。明确生成并写入 UID，
	# 使随后启动的编辑器与 Inspector 都能把它当作正式外部资源索引。
	# 已登记的资源必须复用既有 UID，避免共享预设被重新保存后导致引用断开。
	var generated_uid := ResourceLoader.get_resource_uid(resource_path)
	if generated_uid == ResourceUID.INVALID_ID:
		generated_uid = ResourceUID.create_id()
	ResourceSaver.set_uid(resource_path, generated_uid)
