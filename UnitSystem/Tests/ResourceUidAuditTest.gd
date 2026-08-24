extends SceneTree

## 扫描项目中的正式 .tres，确保资源可加载且由 Godot 正式登记了 UID。
## 该测试不修改资源，只用于防止手写或复制资源再次产生无 UID 文件。

var failures: Array[String] = []
var resource_paths: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_scan_directory("res://")
	resource_paths.sort()
	for path: String in resource_paths:
		var resource_uid := ResourceLoader.get_resource_uid(path)
		_assert_true(
			resource_uid != ResourceUID.INVALID_ID,
			"resource has a valid UID: " + path
		)
		var resource: Resource = load(path) as Resource
		_assert_true(resource != null, "resource loads: " + path)
	if failures.is_empty():
		print("ResourceUidAuditTest: PASS (%d .tres resources)" % resource_paths.size())
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	quit(1)


func _scan_directory(directory_path: String) -> void:
	var directory := DirAccess.open(directory_path)
	if directory == null:
		failures.append("directory opens: " + directory_path)
		return
	for file_name: String in directory.get_files():
		if file_name.ends_with(".tres"):
			resource_paths.append(directory_path + file_name)
	for subdirectory_name: String in directory.get_directories():
		## Archive 均由各自的 `.gdignore` 隔离，不属于活动 Resource 的 UID 合同。
		## 历史资源会刻意保留旧依赖路径，因此既不加载，也不为其重新生成 UID。
		if subdirectory_name in [".godot", "Archive"]:
			continue
		_scan_directory(directory_path + subdirectory_name + "/")


func _assert_true(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
