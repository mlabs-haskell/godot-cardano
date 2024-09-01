extends RefCounted
class_name Cbor

enum Status {
	SUCCESS = 0,
	DECODING_INVALID_INT = 1,
	DECODING_INVALID_BYTES = 2,
	DECODING_INVALID_CONSTR = 3,
	DECODING_INVALID_TAG = 4,
	DECODING_UNSUPPORTED_TYPE = 5,
	ENCODING_INVALID_TAG = 6,
	ENCODING_UNKNOWN_OBJECT = 7,
	ENCODING_UNSUPPORTED_TYPE = 8,
	CBOR_EVENT_ERROR = 9,
}

class DeserializeResult extends Result:
	## WARNING: This function may fail! First match on [Result_.tag] or call [Result_.is_ok].
	var value: Variant:
		get: return _res.unsafe_value()
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

static func serialize(data: Variant) -> SerializeResult:
	return SerializeResult.new(_Cbor._from_variant(data))
