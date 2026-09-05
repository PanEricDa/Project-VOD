class_name CombatHUD
extends CanvasLayer

## 屏幕空间队伍生命 HUD 的布局与绑定容器。
## 本组件持有一个固定的玩家信息框和一组动态创建的伙伴信息框，负责左下角
## 安全区布局、尺寸与间距配置，以及把外部传入的 UnitBase 队伍绑定到各信息框；
## 同时通过玩家现有 locked_target_changed 信号驱动顶部中央的唯一目标生命框；
## 它不发现单位（由 GameRunController 在场景变化时收集）、不读取 AI 组件、
## 不参与战斗逻辑，也不填充玩家框的扩展槽（该槽保留给未来的玩家资源内容）。

const UNIT_HEALTH_FRAME_SCENE: PackedScene = preload(
	"res://UnitSystem/Components/UI/UnitHealthFrame.tscn"
)

@export_category("Layout")
## HUD 与屏幕左边缘的安全距离，单位为像素；默认 48，只影响队伍 HUD 布局。
@export_range(0.0, 512.0, 1.0, "or_greater")
var safe_margin_left: float = 48.0
## HUD 与屏幕下边缘的安全距离，单位为像素；默认 48，只影响队伍 HUD 布局。
@export_range(0.0, 512.0, 1.0, "or_greater")
var safe_margin_bottom: float = 48.0
## 玩家与伙伴信息框之间以及伙伴之间的纵向间距，单位为像素；默认 10。
@export_range(0, 128, 1, "or_greater")
var frame_separation: int = 10
## 玩家信息框最小尺寸，单位为像素；默认 420×90，为未来玩家资源内容保留空间。
@export var player_frame_size: Vector2 = Vector2(420.0, 90.0)
## 伙伴信息框最小尺寸，单位为像素；默认 280×60，即玩家框宽高的三分之二。
@export var ally_frame_size: Vector2 = Vector2(280.0, 60.0)
## 顶部目标信息框与屏幕上边缘的安全距离，单位为像素；默认 36，只影响目标 HUD 布局。
@export_range(0.0, 512.0, 1.0, "or_greater")
var target_margin_top: float = 36.0
## 顶部目标信息框最小尺寸，单位为像素；默认 480×64，不影响玩家和伙伴信息框。
@export var target_frame_size: Vector2 = Vector2(480.0, 64.0)

@onready var _safe_area: MarginContainer = %SafeArea
@onready var _party_column: VBoxContainer = %PartyColumn
@onready var _ally_frames: VBoxContainer = %AllyFrames
@onready var _player_frame: UnitHealthFrame = %PlayerFrame
@onready var _target_safe_area: MarginContainer = %TargetSafeArea
@onready var _target_frame: UnitHealthFrame = %TargetFrame

## 当前存活的动态伙伴信息框列表；顺序与绑定时的输入数组一致。
var _active_ally_frames: Array[UnitHealthFrame] = []
## 当前为顶部目标框提供锁定信号的玩家单位；普通 UnitBase 没有锁定接口时保持 null。
var _target_source_player: UnitBase


## 用一个玩家和一组伙伴重建队伍显示。玩家无效时安全解绑；伙伴中的 null、重复项和玩家自身会被跳过。
func bind_party(player: UnitBase, allies: Array[UnitBase]) -> void:
	unbind_party()
	if not is_instance_valid(player) or not player.is_inside_tree():
		return
	_apply_layout_configuration()
	_player_frame.set_presentation_mode(UnitHealthFrame.PresentationMode.PLAYER)
	_player_frame.custom_minimum_size = _sanitize_size(player_frame_size)
	_player_frame.bind_unit(player)
	_bind_target_source(player)
	var seen_ids: Dictionary = {player.get_instance_id(): true}
	for ally: UnitBase in allies:
		if not is_instance_valid(ally) or not ally.is_inside_tree():
			continue
		var instance_id := ally.get_instance_id()
		if seen_ids.has(instance_id):
			continue
		seen_ids[instance_id] = true
		_add_ally_frame(ally)
	visible = true


## 清除所有单位信号和动态伙伴框并隐藏 HUD；不会释放 HUD 自身。
func unbind_party() -> void:
	_unbind_target_source()
	if is_instance_valid(_player_frame):
		_player_frame.unbind_unit()
	for frame: UnitHealthFrame in _active_ally_frames:
		if is_instance_valid(frame):
			frame.unbind_unit()
			frame.queue_free()
	_active_ally_frames.clear()
	visible = false


## 以完整队伍快照刷新 HUD；当前实现与重新绑定等价，不做增量排序或状态复制。
func refresh_party(player: UnitBase, allies: Array[UnitBase]) -> void:
	bind_party(player, allies)


## 进入场景树时应用布局配置并保持未绑定隐藏；在编辑器中直接实例化也安全。
func _ready() -> void:
	_apply_layout_configuration()
	visible = false


## 离开场景树时解绑全部单位并清理动态框，防止场景卸载后残留回调。
func _exit_tree() -> void:
	unbind_party()


## 为单个伙伴创建紧凑信息框：先入容器，再设置模式与尺寸，最后绑定单位。
## 实例化失败时输出错误并跳过该伙伴，不影响其余槽位。
func _add_ally_frame(ally: UnitBase) -> void:
	var frame := UNIT_HEALTH_FRAME_SCENE.instantiate() as UnitHealthFrame
	if not is_instance_valid(frame):
		push_error("CombatHUD: UnitHealthFrame could not be instantiated for ally %s." % ally.name)
		return
	_ally_frames.add_child(frame)
	frame.set_presentation_mode(UnitHealthFrame.PresentationMode.COMPACT_ALLY)
	frame.custom_minimum_size = _sanitize_size(ally_frame_size)
	frame.bind_unit(ally)
	_active_ally_frames.append(frame)


## 把导出的边距与间距写入主题常量覆盖；只在绑定前调用，不在 _process() 重复执行。
func _apply_layout_configuration() -> void:
	_safe_area.add_theme_constant_override("margin_left", int(roundf(safe_margin_left)))
	_safe_area.add_theme_constant_override("margin_bottom", int(roundf(safe_margin_bottom)))
	_party_column.add_theme_constant_override("separation", frame_separation)
	_ally_frames.add_theme_constant_override("separation", frame_separation)
	_target_safe_area.add_theme_constant_override(
		"margin_top",
		int(roundf(target_margin_top))
	)
	_target_frame.custom_minimum_size = _sanitize_size(target_frame_size)


## 连接玩家已有的锁定目标信号并立即同步当前锁定；缺少接口时只关闭目标框，队伍 HUD 继续工作。
func _bind_target_source(player: UnitBase) -> void:
	_unbind_target_source()
	if (
		not is_instance_valid(player)
		or not player.has_signal(&"locked_target_changed")
		or not player.has_method(&"get_locked_target")
	):
		return
	_target_source_player = player
	var callback := Callable(self, "_on_player_locked_target_changed")
	if not player.is_connected(&"locked_target_changed", callback):
		player.connect(&"locked_target_changed", callback)
	var current_target := player.call(&"get_locked_target") as UnitBase
	_on_player_locked_target_changed(current_target)


## 断开旧玩家锁定信号并清空顶部目标框；不会解除玩家自身的锁定。
func _unbind_target_source() -> void:
	if is_instance_valid(_target_source_player):
		var callback := Callable(self, "_on_player_locked_target_changed")
		if (
			_target_source_player.has_signal(&"locked_target_changed")
			and _target_source_player.is_connected(
				&"locked_target_changed",
				callback
			)
		):
			_target_source_player.disconnect(
				&"locked_target_changed",
				callback
			)
	_target_source_player = null
	if is_instance_valid(_target_frame):
		_target_frame.unbind_unit()


## 响应玩家稳定锁定接口：合法引用绑定顶部唯一目标框，null 或失效引用立即隐藏并解绑。
func _on_player_locked_target_changed(target: UnitBase) -> void:
	if not is_instance_valid(_target_frame):
		return
	if not is_instance_valid(target) or not target.is_inside_tree():
		_target_frame.unbind_unit()
		return
	_target_frame.set_presentation_mode(UnitHealthFrame.PresentationMode.TARGET)
	_target_frame.custom_minimum_size = _sanitize_size(target_frame_size)
	_target_frame.bind_unit(target)


## 将尺寸两个分量钳制到不小于 1.0，防止 Inspector 负值或零值破坏容器布局。
func _sanitize_size(value: Vector2) -> Vector2:
	return Vector2(maxf(value.x, 1.0), maxf(value.y, 1.0))
