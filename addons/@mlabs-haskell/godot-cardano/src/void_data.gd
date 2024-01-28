class_name VoidData
extends RefCounted

func to_data() -> Variant:
	return Constr._create(BigInt.from_int(0).value._b, [])
