class_name ComboCostLedger
extends RefCounted
## 只管理重复计价；根请求登记一次，子碎片不登记。无导出配置，不负责评分计时或扣款。
var _records: Dictionary = {}
var _successes: Dictionary = {}
var _sequence: int = 0
var _closed_watermark: int = 0

## 正身份由系统单调分配；同轮次、伙伴、技能的实际成功次数决定费用。
## base_cost/repeat_cost 为有限非负专注点；重复相同登记幂等，冲突或已关闭批次失败。
func register_request(request_id: int, round_id: int, caster_id: int, skill_id: StringName, base_cost: float, repeat_cost: float) -> bool:
	if request_id <= 0 or round_id <= 0 or caster_id <= 0 or skill_id.is_empty() or not is_finite(base_cost) or not is_finite(repeat_cost) or base_cost < 0.0 or repeat_cost < 0.0: return false
	if _records.has(request_id):
		var r = _records[request_id]
		return r.round == round_id and r.caster == caster_id and r.skill == skill_id and r.base == base_cost and r.extra == repeat_cost
	if round_id <= _closed_watermark: return false
	_sequence += 1
	_records[request_id] = {"round": round_id, "caster": caster_id, "skill": skill_id, "base": base_cost, "extra": repeat_cost, "sequence": _sequence, "state": 0, "fee": -1.0}
	if not _successes.has(round_id): _successes[round_id] = {}
	return true

## 当前实际成功次数的报价；释放终态保留原费用，未知/失败返回 -1，不能被当免费请求。
func get_final_quote(request_id: int) -> float:
	if not _records.has(request_id): return -1.0
	var r = _records[request_id]
	if r.state == 2: return -1.0
	if r.state == 1: return r.fee
	return _quote(r, 0)

## 缓存足额上界，包含更早同伙伴同技能仍可能成功的请求，不包含自己或失败记录。
func get_reservation_quote(request_id: int) -> float:
	if not _records.has(request_id): return -1.0
	var r = _records[request_id]
	if r.state != 0: return get_final_quote(request_id)
	var pending: int = 0
	for earlier in _records.values():
		if earlier.state == 0 and earlier.sequence < r.sequence and earlier.round == r.round and earlier.caster == r.caster and earlier.skill == r.skill: pending += 1
	return _quote(r, pending)

## 实际释放后记录一次成功并返回费用；同伙伴必须按受理顺序执行，不能越过更早的未结束请求。
## 重复成功回调返回原费用，不重复计次；失败/未知/乱序返回 -1。
func mark_released(request_id: int) -> float:
	if not _records.has(request_id): return -1.0
	var r = _records[request_id]
	if r.state != 0: return get_final_quote(request_id)
	for earlier in _records.values():
		if earlier.state == 0 and earlier.sequence < r.sequence and earlier.caster == r.caster: return -1.0
	var fee = get_final_quote(request_id)
	if fee < 0.0: return -1.0
	r.fee = fee
	r.state = 1
	var key = _key(r)
	_successes[r.round][key] = int(_successes[r.round].get(key, 0)) + 1
	return fee

## 释放前失败，不计成功；成功终态不能被后续失败回调撤销。
func mark_failed(request_id: int) -> void:
	if _records.has(request_id) and _records[request_id].state == 0: _records[request_id].state = 2

## 系统批次按单调身份关闭，禁止该水位及之前的新登记；已有请求照常结算。
func close_round(round_id: int) -> void:
	if round_id <= 0: return
	_closed_watermark = maxi(_closed_watermark, round_id)
	_collect_closed()

## 回调生命周期结束后释放终态引用；待执行请求必须先失败或成功，不直接丢失账目。
func release_request(request_id: int) -> void:
	if not _records.has(request_id) or _records[request_id].state == 0: return
	_records.erase(request_id)
	_collect_closed()

## 只读预估下一请求的预留上界；包含已有同轮同伙伴同技能潜在前序，不新增任何记录。
## round/caster正身份、非空skill及有限非负费用有效；关闭/非法返回-1，未知开放轮从0成功计。
func preview_reservation_quote(round_id: int, caster_id: int, skill_id: StringName, base_cost: float, repeat_cost: float) -> float:
	if round_id <= _closed_watermark or round_id <= 0 or caster_id <= 0 or skill_id.is_empty() or not is_finite(base_cost) or not is_finite(repeat_cost) or base_cost < 0.0 or repeat_cost < 0.0: return -1.0
	var key := "%d:%s" % [caster_id, skill_id]
	var count: int = int(_successes.get(round_id, {}).get(key, 0))
	for record in _records.values():
		if record.state == 0 and record.round == round_id and record.caster == caster_id and record.skill == skill_id: count += 1
	var value := base_cost + count * repeat_cost
	return value if is_finite(value) else -1.0


func _key(r: Dictionary) -> String:
	return "%d:%s" % [r.caster, r.skill]

func _quote(r: Dictionary, pending: int) -> float:
	var count = int(_successes[r.round].get(_key(r), 0)) + pending
	var value = float(r.base) + count * float(r.extra)
	return value if is_finite(value) else -1.0

func _collect_closed() -> void:
	for id in _successes.keys():
		if id > _closed_watermark: continue
		var in_use = _records.values().any(func(r): return r.round == id)
		if not in_use: _successes.erase(id)
