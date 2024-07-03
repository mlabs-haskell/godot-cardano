class_name ExampleDatum
extends Object

# various example data associated with this type
var _void: VoidData
var _msg: String
var _active: bool
var _int: int
var _big_int: BigInt
var _extra_data: Dictionary # assumes that all keys are strings

func _init(
	void_data := VoidData.new(),
	msg := "test",
	active := true,
	i := 24224,
	b := BigInt.from_str("-123123123123123123123123123123123").value,
	extra_data := {
		"xyz": BigInt.from_int(445)
	}
) -> void:
	_void = void_data
	_msg = msg
	_active = active
	_int = i
	_big_int = b
	_extra_data = extra_data

func to_data() -> PlutusData:
	var extra_data_encoded := {}
	for key: String in _extra_data:
		assert(key is String)
		var key_encoded := PlutusBytes.new(key.to_utf8_buffer())
		extra_data_encoded[key_encoded] = _extra_data[key]
	var fields: Array[PlutusData] = [
		_void.to_data(),
		PlutusBytes.new(_msg.to_utf8_buffer()),
		BoolData.new(_active).to_data(),
		BigInt.from_int(_int), 
		_big_int,
		PlutusMap.new(extra_data_encoded)
	]
	return Constr.new(BigInt.from_int(1), fields)

static func from_data(v: PlutusData) -> ExampleDatum:
	assert(v is Constr)
	var constr := v as Constr
	assert(constr._constructor.eq(BigInt.one()))
	var fields := constr._fields
	assert(fields[1] is PlutusBytes)
	assert(fields[3] is BigInt)
	assert(fields[4] is BigInt)
	assert(fields[5] is PlutusMap)
	
	var msg: PackedByteArray = (fields[1] as PlutusBytes).get_data()
	var active := BoolData.from_data(fields[2])._b
	var i := fields[3] as BigInt
	var b := fields[4] as BigInt
	var extra_data: Dictionary = (fields[5] as PlutusMap).get_data()
	var extra_data_decoded := {}
	for key: PlutusBytes in extra_data:
		var key_decoded: String = key.get_data().get_string_from_utf8()
		extra_data_decoded[key_decoded] = extra_data[key]
	
	return ExampleDatum.new(
		VoidData.from_data(fields[0]),
		msg.get_string_from_utf8(),
		active,
		int(i.to_str()),
		b,
		extra_data_decoded
	)

func _to_string() -> String:
	return "(%s, %s, %s, %s, %s, %s)" % [_void, _msg, _active, _int, _big_int, _extra_data]

func eq(other: ExampleDatum) -> bool:
	return JSON.stringify(self) == JSON.stringify(other)
