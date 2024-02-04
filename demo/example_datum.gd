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

func to_data(strict := false) -> Variant:
	if strict:
		var extra_data_encoded := {}
		for key: String in _extra_data:
			assert(typeof(key) == TYPE_STRING)
			var key_encoded := key.to_utf8_buffer()
			extra_data_encoded[key_encoded] = _extra_data[key]
			
		return Constr.new(
			BigInt.from_int(1),
			[
				_void.to_data(strict),
				_msg.to_utf8_buffer() as Variant,
				BoolData.new(_active).to_data(strict),
				BigInt.from_int(_int), 
				_big_int,
				extra_data_encoded as Variant
			]
		)
		
	return Constr.new(
		BigInt.from_int(1),
		[
			_void,
			_msg,
			_active,
			_int, 
			_big_int,
			_extra_data
		]
	)

static func from_data(v: Variant) -> ExampleDatum:
	assert(is_instance_of(v, Constr))
	var constr := v as Constr
	assert(constr._constructor.eq(BigInt.one()))
	var fields := constr._fields
	assert(typeof(fields[1]) == TYPE_PACKED_BYTE_ARRAY)
	assert(is_instance_of(fields[3], BigInt))
	assert(is_instance_of(fields[4], BigInt))
	assert(typeof(fields[5]) == TYPE_DICTIONARY)
	
	var msg := fields[1] as Variant as PackedByteArray
	var active := BoolData.from_data(fields[2])._b
	var i := fields[3] as Variant as BigInt
	var b := fields[4] as Variant as BigInt
	var extra_data := fields[5] as Variant as Dictionary
	var extra_data_decoded := {}
	for key: Variant in extra_data:
		assert(typeof(key) == TYPE_PACKED_BYTE_ARRAY)
		var key_decoded := (key as Variant as PackedByteArray).get_string_from_utf8()
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
