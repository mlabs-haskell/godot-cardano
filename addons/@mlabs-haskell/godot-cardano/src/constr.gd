extends RefCounted
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
var _fields: Array

## A [Constr] takes [param constructor] parameter, which is the index of the
## constructor being used. The parameters of that constructor are passed in
## [param fields].
func _init(constructor: BigInt, fields: Array):
	_constructor = constructor
	_fields = fields

func to_data(strict := false) -> Variant:
	var unwrapped = _fields.map(func (v): return PlutusData.unwrap(v, strict))
	return _Constr._create(_constructor._b, unwrapped)

func _to_string() -> String:
	return "Constr %s %s" % [_constructor, _fields]
