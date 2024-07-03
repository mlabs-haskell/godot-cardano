class_name PlutusMap
extends PlutusData

var _data: Dictionary

func _init(data: Dictionary) -> void:
	_data = data
	
func _unwrap() -> Variant:
	var unwrapped: Dictionary = {}
	for key: PlutusData in _data:
		var unwrapped_key := key._unwrap()
		var unwrapped_value := (_data[key] as PlutusData)._unwrap()
		if unwrapped_key == null or unwrapped_value == null:
			return null
		unwrapped[unwrapped_key] = unwrapped_value
	return unwrapped
	
func get_data() -> Dictionary:
	return _data

func _to_json() -> Dictionary:
	var map := []
	for key in _data:
		map.push_back({ "k": key, "v": _data[key]})
	return { "map": map }
