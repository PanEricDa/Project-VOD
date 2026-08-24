extends SceneTree

## 旧游戏框架归档契约测试。
##
## 该测试保护三项用户可观察结果：
## 1. 当前游戏仍从新的职责目录加载相机与投射物实现。
## 2. 已停用的旧框架不再留在活动目录，也不会被活动资源引用。
## 3. 旧实现完整进入带 `.gdignore` 的可恢复归档。

const ARCHIVE_ROOT := "res://Archive/LegacyGameFramework-2026-07-30"
const CURRENT_REQUIRED_FILES: Array[String] = [
	"res://Scenes/TestScene2.tscn",
	"res://UnitSystem/Components/Camera/CameraFollowController.gd",
	"res://Item/Projectiles/TrackingArcProjectile.gd",
	"res://Item/Projectiles/FireballProjectile.gd",
	"res://UnitSystem/Player/Hero/Hero.tscn",
	"res://UnitSystem/AI/Ally/AllyBase.tscn",
	"res://UnitSystem/AI/Enemy/EnemyBase.tscn",
	"res://SkillSystem/01-Core/SkillBase.tscn",
]
const LEGACY_ACTIVE_PATHS: Array[String] = [
	"res://Scenes/ObjectScenes",
	"res://Scenes/EnemyScenes",
	"res://Scenes/Components",
	"res://Scripts",
	"res://Resources",
]
const REQUIRED_ARCHIVE_FILES: Array[String] = [
	ARCHIVE_ROOT + "/.gdignore",
	ARCHIVE_ROOT + "/README.md",
	ARCHIVE_ROOT + "/Scenes/ObjectScenes/AllyBase.tscn",
	ARCHIVE_ROOT + "/Scenes/EnemyScenes/EnemyBase.tscn",
	ARCHIVE_ROOT + "/Scripts/AI/AllyBase.gd",
	ARCHIVE_ROOT + "/Resources/Combat/AI/DefaultAIAttackProfile.tres",
]
const ACTIVE_SCAN_ROOTS: Array[String] = [
	"res://UnitSystem/",
	"res://SkillSystem/",
	"res://Item/",
	"res://Effects/",
	"res://Scenes/",
]
const FORBIDDEN_REFERENCES: Array[String] = [
	"res://Scenes/ObjectScenes/",
	"res://Scenes/EnemyScenes/",
	"res://Scenes/Components/",
	"res://Scripts/",
	"res://Resources/Combat/",
	"res://Archive/",
]

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for path: String in CURRENT_REQUIRED_FILES:
		_assert_true(FileAccess.file_exists(path), "current file exists: " + path)
	for path: String in LEGACY_ACTIVE_PATHS:
		_assert_true(not _path_exists(path), "legacy active path is absent: " + path)
	for path: String in REQUIRED_ARCHIVE_FILES:
		_assert_true(FileAccess.file_exists(path), "archive file exists: " + path)
	for root_path: String in ACTIVE_SCAN_ROOTS:
		_scan_active_directory(root_path)
	_assert_scene_loads("res://Scenes/TestScene2.tscn")
	_finish()


func _scan_active_directory(directory_path: String) -> void:
	var directory := DirAccess.open(directory_path)
	if directory == null:
		failures.append("active directory opens: " + directory_path)
		return
	for file_name: String in directory.get_files():
		if not (
			file_name.ends_with(".gd")
			or file_name.ends_with(".tscn")
			or file_name.ends_with(".tres")
			or file_name.ends_with(".res")
		):
			continue
		var file_path := directory_path + file_name
		## 本文件必须保存待禁止的路径字面量，不能把契约定义本身当成活动依赖。
		if file_path == get_script().resource_path:
			continue
		var file := FileAccess.open(file_path, FileAccess.READ)
		if file == null:
			failures.append("active file opens: " + file_path)
			continue
		var content := file.get_as_text()
		for forbidden: String in FORBIDDEN_REFERENCES:
			_assert_true(
				not content.contains(forbidden),
				"active file does not reference %s: %s" % [
					forbidden,
					file_path,
				]
			)
	for subdirectory_name: String in directory.get_directories():
		_scan_active_directory(directory_path + subdirectory_name + "/")


func _assert_scene_loads(path: String) -> void:
	var packed_scene := load(path) as PackedScene
	_assert_true(packed_scene != null, "scene loads: " + path)
	if packed_scene == null:
		return
	var instance := packed_scene.instantiate()
	_assert_true(instance != null, "scene instantiates: " + path)
	if instance != null:
		instance.free()


func _path_exists(path: String) -> bool:
	return (
		FileAccess.file_exists(path)
		or DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(path))
	)


func _assert_true(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("LegacyFrameworkArchiveContractTest: PASS")
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	quit(1)
