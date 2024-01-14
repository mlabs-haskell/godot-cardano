class_name ExampleDatum
extends Object

func to_data() -> Variant:
	return Constr.create(
		BigInt.from_int(1), 
		[
			Constr.create(BigInt.from_int(0), []),
			"test".to_ascii_buffer(), 
			BigInt.from_int(24224), 
			BigInt.from_str("-123123123123123123123123123123123"),
			{
				"xyz".to_ascii_buffer(): BigInt.from_int(445)
			}
		]
	)
