class_name ExampleDatum
extends Object

func to_data() -> Variant:
	return Constr.new(
		BigInt.from_int(1),
		[
			Constr.new(BigInt.from_int(0), []),
			"test",
			true,
			BigInt.from_int(24224), 
			BigInt.from_str("-123123123123123123123123123123123").value,
			{
				"xyz": BigInt.from_int(445)
			}
		]
	)
