extends RefCounted

class_name BoolData

var _b: bool

func _init(b: bool) -> void:
	_b = b

func to_data(_strict := false) -> Variant:
	return Constr.new(BigInt.zero(), []) if not _b else Constr.new(BigInt.one(), [])
	
static func from_data(v: Variant) -> BoolData:
	assert(is_instance_of(v, Constr) &&
	  (v as Variant as Constr)._constructor.lt(BigInt.from_int(2)))
	return BoolData.new((v as Variant as Constr)._constructor.eq(BigInt.one()))
