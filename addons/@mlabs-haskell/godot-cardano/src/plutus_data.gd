extends RefCounted
## A class for constructing on-chain Plutus data
##
## The Plutus language, which may be used for minting policies and validators,
## operates on a specific datatype called [PlutusData]. This class is used for
## constructing valid instances of this datatype, which then may be used as
## datums or redeemers in functions that require it.
##
## Most of the time, the different [PlutusData] constructs may be accurately
## represented by native GDScript types, such as [bool], [Array] or [Dictionary].
## But for other cases, like [BigInt] or [Constr], native GDScript types aren't
## accurate enough or are simply inexistent.
##
## This class tries to abstract most of the complexity by allowing the use of
## of nested native types and SDK types (like the aforementioned) to construct
## any PlutusData desired. These can subsequentely be converted into valid
## CBOR (the format used in transactions) with [method serialize]. In practice
## most users should not need to interact with this class directly, as most
## functions requiring [PlutusData] will take a [Variant] and do the conversion
## themselves.

# TODO: Add a specific tutorial on PlutusData conversions.

class_name PlutusData
		
## Recursively unwraps Objects to Plutus compatible data types
static func unwrap(v: Variant, strict: bool = false) -> Variant:
	match typeof(v):
		TYPE_ARRAY:
			var unwrapped = v.map(func (child): return unwrap(child, strict))
			if unwrapped.any(func (child): return child == null):
				return null
			return unwrapped
		TYPE_DICTIONARY:
			var unwrapped: Dictionary = {}
			for key in v:
				var unwrapped_key = unwrap(key, strict)
				var unwrapped_value = unwrap(v[key], strict)
				if unwrapped_key == null or unwrapped_value == null:
					return null
				unwrapped[unwrapped_key] = unwrapped_value
			return unwrapped
		TYPE_BOOL:
			if strict:
				push_error("Got native bool in strict data serialization")
				return null
			return unwrap(
				Constr.new(BigInt.from_int(0), []) if not v 
				else Constr.new(BigInt.from_int(1), []),
				strict
			)
		TYPE_STRING:
			if strict:
				push_error("Got native string in strict data serialization")
				return null
			return v.to_utf8_buffer()
		TYPE_INT:
			if strict:
				push_error("Got native int in strict data serialization")
				return null
			return _BigInt._from_int(v)
		TYPE_OBJECT:
			var _class: String = v.get_class()
			if v.has_method("to_data"):
				var data = v.to_data(strict)
				if strict:
					var __class: String = data.get_class()
					assert(
						__class == "_Constr" or __class == "_BigInt",
						"Constr field not data-encoded in strict data serialization"
					)
					return data
				return unwrap(data, strict)
			elif _class == "_Constr" or _class == "_BigInt":
				if strict:
					push_error("Tried to unwrap native types in strict data serialization")
					return null
				return v
			else:
				push_error("Constr field does not implement `to_data`: %s" % v)
				return null
		TYPE_PACKED_BYTE_ARRAY:
			return v
		_:
			push_error("Got unsupported type in data serialization: %s" % v)
			return null

## Recursively wraps Plutus compatible data types to GDScript types.
static func wrap(v: Variant) -> Variant:
	match typeof(v):
		TYPE_ARRAY:
			return v.map(PlutusData.wrap)
		TYPE_DICTIONARY:
			var wrapped: Dictionary = {}
			for key in v:
				wrapped[PlutusData.wrap(key)] = PlutusData.wrap(v[key])
			return wrapped
		TYPE_OBJECT:
			var _class = v.get_class()
			if _class == "_Constr":
				return Constr.new(BigInt.new(v.constructor), v.fields.map(PlutusData.wrap))
			if _class == "_BigInt":
				return BigInt.new(v)
			return v
		_: return v

## Serialize to CBOR format.
static func serialize(v: Variant, strict: bool = true) -> Cbor.SerializeResult:
	return Cbor.serialize(unwrap(v, strict), strict)

## Deserialize from CBOR format.
static func deserialize(bytes: PackedByteArray) -> Cbor.DeserializeResult:
	return Cbor.deserialize(bytes)

## WARNING: Currently incomplete and only used for test cases
static func from_json(json: Dictionary) -> Variant:
	if json.has("list"):
		return json.list.map(PlutusData.from_json)
	if json.has("bytes"):
		return json.bytes.hex_decode()
	if json.has("int"):
		return BigInt.from_str(json.int).value
	return null
