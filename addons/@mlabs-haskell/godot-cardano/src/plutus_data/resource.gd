@tool
class_name PlutusDataResource
extends Resource

var data: PlutusData = VoidData.to_data():
	get:
		if FileAccess.file_exists(data_json_path):
			var json := JSON.parse_string(FileAccess.get_file_as_string(data_json_path))
			if json != null:
				return PlutusData.from_json(json)
		return data
	set(v):
		assert(v.serialize().is_ok()
		, "Failed to serialize of data")
		data = v
enum DataType {
	INT,
	BYTES,
	JSON_FILE,
	JSON_INLINE,
	CBOR_HEX
}

# TODO: Use _set and _get instead of allocating data where possible
@export
var data_type: DataType = 0:
	set(v):
		data_type = v
		notify_property_list_changed()
@export
var data_int: int:
	get:
		if data is BigInt:
			return data.to_str().to_int()
		return 0
	set(v):
		data = BigInt.from_int(v)
		data_json = JSON.stringify(data.to_json())
		data_json_path = ""

@export
var data_bytes: PackedByteArray:
	get:
		if data is PlutusBytes:
			return data.get_data()
		return PackedByteArray()
	set(v):
		data = PlutusBytes.new(v)
		data_json = JSON.stringify(data.to_json())
		data_json_path = ""

@export
# FIXME: Currently this doesn't work if you put one character at a time.
var data_as_hex: String:
	get:
		return data_bytes.hex_encode()
	set(v):
		if (v.length() % 2 == 0):
			data_bytes = v.hex_decode()
@export
var data_as_utf8: String:
	get:
		return data_bytes.get_string_from_utf8()
	set(v):
		data_bytes = v.to_utf8_buffer()

var data_cbor: PackedByteArray:
	get:
		var result = data.serialize()
		if result.is_ok():
			return result.value
		push_error("Failed to serialize PlutusData: %s" % result.error)
		return PackedByteArray()
	set(v):
		var result = PlutusData.deserialize(v)
		if result != null:
			data = result
			data_json = JSON.stringify(data.to_json())
			data_json_path = ""
@export
# FIXME: Currently this doesn't work if you put one character at a time.
var data_cbor_hex: String:
	get:
		return data_cbor.hex_encode()
	set(v):
		if (v.length() % 2 == 0):
			data_cbor = v.hex_decode()

@export_multiline
var data_json: String:
	get:
		var json = JSON.new()
		var error = json.parse(data_json)
		if error != OK:
			return data_json
		var parsed := PlutusData.from_json(json.data)
		if parsed == null:
			return data_json
		var from_data = JSON.stringify(data.to_json(), "  ")
		return from_data
	set(v):
		var json := JSON.parse_string(v)
		data_json = v
		if json != null:
			var data = PlutusData.from_json(json)
			if data != null:
				data = data
			else:
				push_error("Failed to parse PlutusData")
		else:
			push_error("Failed to parse JSON")

@export_file("*.json")
var data_json_path: String = ""
	
func _validate_property(property):
	var hide_conditions: Array[bool] = [
		property.name == 'initial_quantity' and not self.fungible,
		property.name == 'data_int' and data_type != DataType.INT,
		property.name == 'data_bytes' and data_type != DataType.BYTES,
		property.name == 'data_as_hex' and data_type != DataType.BYTES,
		property.name == 'data_as_utf8' and data_type != DataType.BYTES,
		property.name == 'data_json_path' and data_type != DataType.JSON_FILE,
		property.name == 'data_json' and data_type != DataType.JSON_INLINE,
		property.name == 'data_cbor_hex' and data_type != DataType.CBOR_HEX,
	]
	var readonly_conditions: Array[bool] = [
		property.name == 'data_json' and FileAccess.file_exists(data_json_path)
	]
	if hide_conditions.any(func (x): return x):
		property.usage &= ~PROPERTY_USAGE_EDITOR
	if readonly_conditions.any(func (x): return x):
		property.usage |= PROPERTY_USAGE_READ_ONLY
