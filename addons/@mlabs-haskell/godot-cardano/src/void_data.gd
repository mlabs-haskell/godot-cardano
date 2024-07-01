class_name VoidData
## An auxiliary class used for representing empty data in PlutusData
extends RefCounted

func to_data(_strict := false) -> Variant:
	return Constr.new(BigInt.from_int(0), [])

static func from_data(v: Variant) -> VoidData:
	assert(is_instance_of(v, Constr))
	var constr = v as Constr
	assert(constr._constructor.eq(BigInt.zero()) && constr._fields.size() == 0)
	return VoidData.new()

func _to_string() -> String:
	return "()"
