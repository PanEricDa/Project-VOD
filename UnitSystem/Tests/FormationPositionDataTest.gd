extends SceneTree

## FormationPositionData 与六份标准阵型位置资源的契约测试。
##
## Forward 使用明确的字面量验证 Amy 迁移结果；其余资源验证类型、命名与左右镜像，
## 防止设计师列表中出现丢失、错位或无法加载的阵型选项。

const POSITION_DIRECTORY: String = (
	"res://UnitSystem/AI/Ally/Formation/Positions/"
)
const POSITION_FILES: Array[String] = [
	"Defender.tres",
	"DefensiveMid.tres",
	"LeftWingBack.tres",
	"RightWingBack.tres",
	"AttackingMid.tres",
	"Forward.tres",
]

var _failures: Array[String] = []


func _initialize() -> void:
	var loaded_positions: Dictionary = {}
	for file_name: String in POSITION_FILES:
		var data := load(
			POSITION_DIRECTORY + file_name
		) as FormationPositionData
		_expect(
			data != null,
			"%s loads as FormationPositionData" % file_name
		)
		_expect(
			ResourceLoader.get_resource_uid(
				POSITION_DIRECTORY + file_name
			) != ResourceUID.INVALID_ID,
			"%s has an editor-indexed external resource UID" % file_name
		)
		if data != null:
			loaded_positions[file_name] = data

	var data := loaded_positions.get(
		"Forward.tres"
	) as FormationPositionData
	if data != null:
		_expect(
			data.display_name == "Forward",
			"Amy now uses the generic Forward position name"
		)
		_expect(
			data.center_offset.is_equal_approx(Vector2(0.0, 2.5)),
			"Forward keeps Amy's current center offset"
		)
		_expect(
			is_equal_approx(data.lateral_radius, 1.1),
			"Forward keeps Amy's current lateral radius"
		)
		_expect(
			is_equal_approx(data.lateral_minimum, 0.0),
			"Forward keeps Amy's current lateral minimum"
		)
		_expect(
			is_equal_approx(data.forward_radius, 0.65),
			"Forward keeps Amy's current forward radius"
		)
		_expect(
			data.side_mode
				== FormationPositionData.SideMode.FREE_CROSSING,
			"Forward keeps Amy's free-crossing behavior"
		)

	var left := loaded_positions.get(
		"LeftWingBack.tres"
	) as FormationPositionData
	var right := loaded_positions.get(
		"RightWingBack.tres"
	) as FormationPositionData
	if left != null and right != null:
		_expect(
			is_equal_approx(
				left.center_offset.x,
				-right.center_offset.x
			),
			"wing-back horizontal centers are mirrored"
		)
		_expect(
			is_equal_approx(
				left.center_offset.y,
				right.center_offset.y
			),
			"wing-back forward offsets match"
		)
	_finish()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("FormationPositionDataTest: PASS")
		quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	print(
		"FormationPositionDataTest: FAIL (%d)"
		% _failures.size()
	)
	quit(1)
