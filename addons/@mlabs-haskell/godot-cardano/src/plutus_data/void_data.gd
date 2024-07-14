class_name VoidData
extends RefCounted

static func to_data() -> PlutusData:
	return Constr.new(BigInt.from_int(0), [])

static func from_data(v: Variant) -> VoidData:
	assert(v is Constr)
	var constr: Constr = v
	assert(constr._constructor.eq(BigInt.zero()) && constr._fields.size() == 0)
	return VoidData.new()

func _to_string() -> String:
	return "Void"
