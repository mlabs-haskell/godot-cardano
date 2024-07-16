@tool
class_name PlutusPair
extends PlutusData
	
@export
var _first: PlutusData
@export
var _second: PlutusData

func _init(first: PlutusData = null, second: PlutusData = null) -> void:
	_first = first
	_second = second

func _unwrap() -> Variant:
	return [_first._unwrap(), _second._unwrap()]

func _to_json() -> Dictionary:
	return { "list": [_first.to_json(), _second.to_json()] }

func _to_string() -> String:
	return "[%s, %s]" % [_first, _second]
