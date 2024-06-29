extends RefCounted
## The boolean representation used in Plutus
##
## This is a utility class used in the serialization of [PlutusData]. Do not
## use it directly.

class_name BoolData

var _b: bool

func _init(b: bool) -> void:
	_b = b

func to_data(_strict := false) -> PlutusData:
	return Constr.new(BigInt.zero(), []) if not _b else Constr.new(BigInt.one(), [])
	
static func from_data(v: PlutusData) -> BoolData:
	assert(v is Constr &&
	  (v as Constr)._constructor.lt(BigInt.from_int(2)))
	return BoolData.new((v as Variant as Constr)._constructor.eq(BigInt.one()))
