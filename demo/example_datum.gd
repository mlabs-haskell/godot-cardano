class_name ExampleDatum
extends Object

func to_data() -> Variant:
	return Constr._create(
		BigInt.from_int(1).value._b,
		[
			Constr._create(BigInt.from_int(0).value._b, []),
			"test".to_ascii_buffer(), 
			BigInt.from_int(24224).value._b, 
			BigInt.from_str("-123123123123123123123123123123123").value._b,
			{
				"xyz".to_ascii_buffer(): BigInt.from_int(445).value._b
			}
		]
	)
