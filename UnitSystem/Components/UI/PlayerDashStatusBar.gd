class_name PlayerDashStatusBar
extends ProgressBar

## 玩家 Dash 的纯只读 HUD 监控条。
## 本组件只复制 PlayerBase 已结算的最大次数与连续进度，不计算 CD、不推进时间，
## 也不写入玩家状态；删除、隐藏或解绑本组件都不会影响 Dash 业务。

## 当前绑定的唯一玩家数据源；null 或已失效表示组件处于隐藏停用态。
var _bound_player: PlayerBase


func _ready() -> void:
	visible = false
	set_process(false)


## 绑定唯一玩家数据源；传入 null 等同解绑。组件不会修改玩家的 Dash 状态。
func bind_player(player: PlayerBase) -> void:
	unbind_player()
	if not is_instance_valid(player) or not player.is_inside_tree():
		return
	_bound_player = player
	max_value = float(player.get_dash_charge_capacity())
	value = player.get_dash_charge_progress()
	visible = true
	set_process(true)


## 清除玩家引用并隐藏显示；不会重置玩家的次数或 CD。
func unbind_player() -> void:
	_bound_player = null
	value = 0.0
	visible = false
	set_process(false)


## 返回当前是否持有有效玩家引用，只用于 HUD 生命周期测试与诊断。
func is_bound() -> bool:
	return is_instance_valid(_bound_player)


## 每个显示帧把业务层已结算的最大值与连续进度复制到进度条；
## 两个显示值均直接来自 PlayerBase 的只读查询，本组件不做任何钳制或换算。
func _process(_delta: float) -> void:
	if not is_instance_valid(_bound_player) or not _bound_player.is_inside_tree():
		unbind_player()
		return
	max_value = float(_bound_player.get_dash_charge_capacity())
	value = _bound_player.get_dash_charge_progress()


## 组件离开场景树时清除玩家引用，防止场景卸载后残留回调。
func _exit_tree() -> void:
	unbind_player()
