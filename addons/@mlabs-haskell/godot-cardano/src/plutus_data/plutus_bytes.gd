@tool
class_name PlutusBytes
extends PlutusData

@export
var _data: PackedByteArray

func _init(data: PackedByteArray = PackedByteArray()) -> void:
	_data = data
	
func _unwrap() -> Variant:
	return _data
	
func get_data() -> PackedByteArray:
	return _data

func _to_json() -> Dictionary:
	return { "bytes": _data.hex_encode() }

static func from_utf8(s: String) -> PlutusBytes:
	return new(s.to_utf8_buffer())

static func from_hex(s: String) -> PlutusBytes:
	return new(s.hex_decode())
