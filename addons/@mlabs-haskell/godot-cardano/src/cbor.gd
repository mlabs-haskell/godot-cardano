extends RefCounted

class_name Cbor

class DeserializeResult extends Result:
	## WARNING: This function may fail! First match on [Result_.tag] or call [Result_.is_ok].
	var value: Variant:
		get: return PlutusData.wrap(_res.unsafe_value().get_data())
	## WARNING: This function may fail! First match on [Result_.tag] or call [Result._is_err].
	var error: String:
		get: return _res.unsafe_error()
		
class SerializeResult extends Result:
	## WARNING: This function may fail! First match on [Result_.tag] or call [Result_.is_ok].
	var value: PackedByteArray:
		get: return _res.unsafe_value().bytes
	## WARNING: This function may fail! First match on [Result_.tag] or call [Result._is_err].
	var error: String:
		get: return _res.unsafe_error()

static func deserialize(bytes: PackedByteArray) -> DeserializeResult:
	return DeserializeResult.new(_Cbor._to_variant(bytes))

static func serialize(data: Variant, strict := false) -> SerializeResult:
	return SerializeResult.new(_Cbor._from_variant(PlutusData.unwrap(data, strict)))
