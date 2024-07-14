extends PlutusData
## Sum type constructor for Plutus data
##
## Plutus supports the use of so called "sum types". Sum types are part of a
## more general concept called "Algebraic Data Types" (or ADTs for short), which
## consist of both products and sums.
##
## While products can be easily emulated in GDSCript via by the use of
## dictionaries, the same cannot be said of sums. For this reason, we provide
## the [Constr] class to be able to bridge that gap.
class_name Constr

var _constructor: BigInt
var _fields: Array[PlutusData]

## A [Constr] takes [param constructor] parameter, which is the index of the
## constructor being used. The parameters of that constructor are passed in
## [param fields].
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
