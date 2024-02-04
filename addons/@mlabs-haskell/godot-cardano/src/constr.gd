extends RefCounted

class_name Constr

var _constr: _Constr

func _init(constructor: BigInt, fields: Array):
	_constr = _Constr._create(constructor._b, fields)

func to_data() -> Variant:
	var unwrapped = _constr.fields.map(PlutusData.unwrap)
	return _Constr._create(_constr.constructor, unwrapped)

func _to_string() -> String:
	return "Constr %s %s" % [BigInt.new(_constr.constructor), _constr.fields]
