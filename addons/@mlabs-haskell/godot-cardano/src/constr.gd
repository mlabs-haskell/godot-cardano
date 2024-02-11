extends RefCounted

class_name Constr

var _constructor: BigInt
var _fields: Array

func _init(constructor: BigInt, fields: Array):
	_constructor = constructor
	_fields = fields

func to_data(strict := false) -> Variant:
	var unwrapped = _fields.map(func (v): return PlutusData.unwrap(v, strict))
	return _Constr._create(_constructor._b, unwrapped)

func _to_string() -> String:
	return "Constr %s %s" % [_constructor, _fields]
