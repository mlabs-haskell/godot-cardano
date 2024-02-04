extends RefCounted

class_name Cbor

class DecodeResult extends Result:
	## WARNING: This function may fail! First match on [Result_.tag] or call [Result_.is_ok].
	var value: Variant:
		get: return PlutusData.wrap(_res.unsafe_value().get_data())
	## WARNING: This function may fail! First match on [Result_.tag] or call [Result._is_err].
	var error: String:
		get: return _res.unsafe_error()
		
class EncodeResult extends Result:
	## WARNING: This function may fail! First match on [Result_.tag] or call [Result_.is_ok].
	var value: PackedByteArray:
		get: return _res.unsafe_value().bytes
	## WARNING: This function may fail! First match on [Result_.tag] or call [Result._is_err].
	var error: String:
		get: return _res.unsafe_error()

static func to_variant(bytes: PackedByteArray) -> DecodeResult:
	return DecodeResult.new(_Cbor._to_variant(bytes))

static func from_variant(data: Variant) -> EncodeResult:
	return EncodeResult.new(_Cbor._from_variant(PlutusData.unwrap(data)))
