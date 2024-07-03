class_name PlutusBytes
extends PlutusData

var _data: PackedByteArray

func _init(data: PackedByteArray) -> void:
	_data = data
	
func _unwrap() -> Variant:
	return _data
	
func get_data() -> PackedByteArray:
	return _data

func _to_json():
	return { "bytes": _data.hex_encode() }
