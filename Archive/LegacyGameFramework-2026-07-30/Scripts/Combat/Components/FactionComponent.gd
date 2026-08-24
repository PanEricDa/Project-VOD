class_name FactionComponent
extends Node

## 通用阵营与队伍关系组件。
##
## faction_id 只描述单位身份，team_id 才负责基础敌我关系。该组件不会搜索目标、
## 修改碰撞层或依赖任何具体角色父类。

@export_category("Faction")
## 描述性阵营标识，例如 player、ally、enemy；不直接决定敌我关系。
@export var faction_id: StringName = &"neutral"

## 用于计算关系的队伍编号。0 表示中立；相同非零编号友好，不同非零编号敌对。
@export var team_id: int = 0

## 供未来目标选择器读取的元数据。本组件的关系查询不会擅自过滤不可选目标。
@export var targetable: bool = true


## 判断另一个阵营组件是否属于友方队伍。
## 缺失组件或任意一方为中立队伍时均返回 false。
func is_friendly_to(other: FactionComponent) -> bool:
	if not is_instance_valid(other):
		return false
	if team_id == 0 or other.team_id == 0:
		return false
	return team_id == other.team_id


## 判断另一个阵营组件是否属于敌对队伍。
## 只有双方均为非零队伍且编号不同时才视为敌对。
func is_hostile_to(other: FactionComponent) -> bool:
	if not is_instance_valid(other):
		return false
	if team_id == 0 or other.team_id == 0:
		return false
	return team_id != other.team_id


## 判断双方是否为中立关系。
## 无效或缺失的另一方无法建立明确敌我关系，因此安全地视为中立。
func is_neutral_to(other: FactionComponent) -> bool:
	if not is_instance_valid(other):
		return true
	return team_id == 0 or other.team_id == 0
