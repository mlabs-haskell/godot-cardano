extends RefCounted
class_name PlutusData

## Recursively wraps native data types to PlutusData types
static func wrap(v: Variant) -> PlutusData:
	match typeof(v):
		TYPE_ARRAY:
			return PlutusList.new(v.map(PlutusData.wrap))
		TYPE_DICTIONARY:
			var wrapped: Dictionary = {}
			for key: Variant in v:
				var wrapped_key := PlutusData.wrap(key)
				var wrapped_value := PlutusData.wrap(v[key])
				if wrapped_key == null or wrapped_value == null:
					return null
				wrapped[wrapped_key] = wrapped_value
			return PlutusMap.new(wrapped)
		TYPE_OBJECT:
			var _class = v.get_class()
			if _class == "_Constr":
				var fields: Array[PlutusData] = []
				for data in v.fields:
					var wrapped = PlutusData.wrap(data)
					if wrapped == null:
						return null
					fields.push_back(wrapped)
				return Constr.new(BigInt.new(v.constructor), fields)
			if _class == "_BigInt":
				return BigInt.new(v)
			return v
		TYPE_PACKED_BYTE_ARRAY:
			return PlutusBytes.new(v)
		_: return null

static func deserialize(bytes: PackedByteArray) -> Cbor.DeserializeResult:
	return Cbor.deserialize(bytes)

## Converts parsed JSON to PlutusData
static func from_json(json: Dictionary) -> PlutusData:
	if json.has("constructor") and json.has("fields"):
		var constructor := BigInt.from_int(json.constructor)
		var fields: Array[PlutusData] = []
		for data in json.fields:
			fields.push_back(from_json(data))
		if constructor == null or fields.any(func (x): return x == null):
			return null
		return Constr.new(constructor, fields)
	if json.has("map"):
		var entries: Array = json.map
		var dict: Dictionary = {}
		for entry: Dictionary in entries:
			var key = from_json(entry.get("k"))
			var value = from_json(entry.get("v"))
			if key == null or value == null:
				return null
			dict[key] = value
		return PlutusMap.new(dict)
	if json.has("list"):
		var result: Array[PlutusData] = []
		for data in json.list:
			result.push_back(from_json(data))
		if result.any(func (x): return x == null):
			return null
		return PlutusList.new(result)
	if json.has("bytes"):
		if typeof(json.bytes) != TYPE_STRING:
			return null
		var data: PackedByteArray = json.bytes.hex_decode()
		if data.size() * 2 != json.bytes.length():
			return null
		return PlutusBytes.new(data)
	if json.has("int"):
		if typeof(json.int) == TYPE_STRING:
			var result = BigInt.from_str(json.int)
			if result.is_err():
				push_error("Failed to parse BigInt: %s" % result.error)
				return null
			return result.value
		elif typeof(json.int) == TYPE_FLOAT:
			var result = BigInt.from_int(int(json.int))
			return result
	return null

static func apply_script_parameters(
	script: PlutusScript,
	params: Array[PlutusData]
) -> PlutusScript:
	return script._apply_params(params.map(func (x): return x._unwrap()))

func to_json() -> Dictionary:
	return _to_json()

func _unwrap() -> Variant:
	return null

func _to_json() -> Dictionary:
	return {}

func _to_string() -> String:
	return "%s" % _unwrap()

func serialize() -> Cbor.SerializeResult:
	return Cbor.serialize(_unwrap())
