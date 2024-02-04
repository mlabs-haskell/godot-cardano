class_name VoidData
extends RefCounted

func to_data() -> Variant:
	return Constr.new(BigInt.from_int(0), [])
