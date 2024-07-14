@tool
class_name PlutusList
extends PlutusData

@export
var _data: Array[PlutusData]

func _init(data: Array[PlutusData] = []) -> void:
	_data = data

func _unwrap() -> Variant:
	var unwrapped = _data.map(func (child): return child._unwrap())
	if unwrapped.any(func (child): return child == null):
		return null
	return unwrapped

func _to_json() -> Dictionary:
	return { "list": _data.map(to_json) }

func get_data() -> Array[PlutusData]:
	return _data
