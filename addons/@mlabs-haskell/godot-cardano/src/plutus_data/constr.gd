extends PlutusData
class_name Constr

var _constructor: BigInt
var _fields: Array[PlutusData]

func _init(constructor: BigInt, fields: Array[PlutusData]):
	_constructor = constructor
	_fields = fields

func _unwrap() -> Variant:
	var unwrapped = _fields.map(func (v): return v._unwrap())
	return _Constr._create(_constructor._b, unwrapped)

func _to_string() -> String:
	return "Constr %s %s" % [_constructor, _fields]

func get_constructor() -> BigInt:
	return _constructor

func get_fields() -> Array[PlutusData]:
	return _fields
	var _data: Constr
	
func _to_json():
	return {
		"constructor": _constructor.to_int(),
		"fields": _fields.map(func (x): return x.to_json())
	}
