extends RefCounted

class_name Constr

var _constructor: BigInt
var _fields: Array

func _init(constructor: BigInt, fields: Array):
	_constructor = constructor
	_fields = fields

func to_data() -> Variant:
	var unwrapped = _constr.fields.map(PlutusData.unwrap)
	return _Constr._create(_constr.constructor, unwrapped)

func _to_string() -> String:
	return "Constr %s %s" % [_constructor, _fields]
