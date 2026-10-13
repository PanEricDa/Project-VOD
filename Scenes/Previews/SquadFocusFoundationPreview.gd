extends Node3D
## 阶段一开发预览：使用真实扣血和专注事务，按钮不是正式连携指令。无额外导出配置。
@onready var _focus: SquadFocusComponent = $Focus
@onready var _source: UnitBase = $Source
@onready var _target: UnitBase = $Target
@onready var _info: Label = $Controls/Panel/VBox/Info
var _request: int = 0

func _ready() -> void:
	var party: Array[UnitBase] = [_source]
	_focus.bind_scope(self, party)
	$Controls/Panel/VBox/Damage/Normal.pressed.connect(_damage.bind(CombatDamageContext.Origin.NORMAL))
	$Controls/Panel/VBox/Damage/Chain.pressed.connect(_damage.bind(CombatDamageContext.Origin.CHAIN))
	$Controls/Panel/VBox/Damage/Finisher.pressed.connect(_damage.bind(CombatDamageContext.Origin.FINISHER))
	$Controls/Panel/VBox/Transactions/Reserve.pressed.connect(_reserve)
	$Controls/Panel/VBox/Transactions/Commit.pressed.connect(_commit)
	$Controls/Panel/VBox/Transactions/Refund.pressed.connect(_refund)
	$Controls/Panel/VBox/Reset.pressed.connect(_reset)
	_info.text = "先点击普通伤害积累专注，再验证预留和提交。"

func _damage(origin: int) -> void:
	if _target.get_current_health() < 110.0: _target.apply_healing(1000.0)
	var context := CombatDamageContext.create(_source, self, origin, CombatDamageContext.allocate_id(), 0, &"preview")
	var amount := CombatValueResolver.apply_damage(_source, _target, 100.0, 0.0, 1.0, 1.0, 0.0, context)
	_info.text = "真实扣血 %.1f；来源 %s；专注收益属性 %.1f" % [amount, ["未知", "普通", "连携", "终结"][origin], context.focus_yield_multiplier]

func _reserve() -> void:
	if _request != 0:
		_info.text = "已有一笔预留，请先提交或退款。"
		return
	var id := CombatDamageContext.allocate_id()
	if _focus.reserve(id, 20.0):
		_request = id
		_info.text = "预留 20 点，总量不变，可用量减少。"
	else: _info.text = "可用专注不足 20 点。"

func _commit() -> void:
	if _request == 0 or not _focus.commit(_request, 15.0):
		_info.text = "没有可以提交的预留。"
		return
	_focus.release_request(_request)
	_request = 0
	_info.text = "实扣 15 点，未使用的 5 点预留释放。"

func _refund() -> void:
	if _request == 0 or not _focus.refund(_request):
		_info.text = "没有可以归还的预留。"
		return
	_focus.release_request(_request)
	_request = 0
	_info.text = "归还预留，不向总量增加额外专注。"

func _reset() -> void:
	_request = 0
	_focus.reset_focus()
	_info.text = "开发会话已重置；不是正式游戏操作。"
