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
	return { "list": _data.map(func (v): return v.to_json()) }

# Get the underlying Array of [class PlutusData]
func get_data() -> Array[PlutusData]:
	return _data

# Get an element from the list given [param index] 
func get_element(index: int) -> PlutusData:
	return _data[index]
