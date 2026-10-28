class_name RunResultOverlay
extends CanvasLayer

## 房间结算的纯表现层界面。
## 该节点只显示成功或失败文案，并把重新开始意图向上发送；不读取单位、房间或场景树状态。

## 玩家点击“重新开始”按钮时发送。
## 订阅方负责恢复输入与重载场景，界面本身不直接控制游戏流程。
signal restart_requested()

@onready var _backdrop: Control = $Backdrop
@onready var _title_label: Label = $Backdrop/CenterContainer/Panel/Content/Title
@onready var _message_label: Label = $Backdrop/CenterContainer/Panel/Content/Message


func _ready() -> void:
	hide_result()


## 显示房间失败结果。
## 文案固定为当前最小游戏流程所需内容；未来可由上层传入检查点、复活或撤退说明。
func show_failure() -> void:
	_title_label.text = "战败"
	_title_label.modulate = Color(1.0, 0.38, 0.38, 1.0)
	_message_label.text = "队伍未能完成本次遭遇。"
	$Backdrop/CenterContainer/Panel/Content/Timing.visible = false
	_backdrop.visible = true


## 显示房间完成结果。
## 该调用不停止世界更新，因此胜利后的死亡消散、镜头与环境表现仍可自然结束。
func show_success() -> void:
	_title_label.text = "房间完成"
	_title_label.modulate = Color(0.42, 1.0, 0.60, 1.0)
	_message_label.text = "当前房间内的敌人已被清除。"
	$Backdrop/CenterContainer/Panel/Content/Timing.visible = false
	_backdrop.visible = true


## elapsed为本轮游戏秒，负数表示无计时组件；best为本次启动内最佳成功通关秒，负数表示暂无纪录。
## completed区分成功与失败文案；本方法只显示，不自行计时、判断胜负或保存纪录。
func set_run_times(elapsed: float, best: float, completed: bool) -> void:
	var timing: Control = $Backdrop/CenterContainer/Panel/Content/Timing
	timing.visible = elapsed >= 0.0
	if not timing.visible:
		return
	var suffix: String = "" if completed else "（未通关）"
	(timing.get_node(^"RunTime") as Label).text = "本轮时间：" + CombatRunTimer.format_time(elapsed) + suffix
	(timing.get_node(^"BestTime") as Label).text = "最佳通关：" + CombatRunTimer.format_time(best)


## 隐藏结算界面；用于切换或重载场景前复位，不改变任何房间或单位状态。
func hide_result() -> void:
	if is_instance_valid(_backdrop):
		_backdrop.visible = false


func _on_restart_button_pressed() -> void:
	restart_requested.emit()
