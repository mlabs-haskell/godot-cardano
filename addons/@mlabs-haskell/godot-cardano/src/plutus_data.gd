extends RefCounted

class_name PlutusData

## Recursively unwraps Objects to native data types
static func unwrap(v: Variant, strict: bool = false) -> Variant:
	match typeof(v):
		TYPE_ARRAY:
			return v.map(func (child): return unwrap(child, strict))
		TYPE_DICTIONARY:
			var unwrapped: Dictionary = {}
			for key in v:
				unwrapped[unwrap(key, strict)] = unwrap(v[key], strict)
			return unwrapped
		TYPE_BOOL:
			if not strict:
				return unwrap(
					Constr.new(BigInt.from_int(0), []) if not v 
					else Constr.new(BigInt.from_int(1), [])
				)
			push_error("Got native bool in strict data serialization")
			return v
		TYPE_STRING:
			if not strict:
				return v.to_utf8_buffer()
			push_error("Got native string in strict data serialization")
			return v
		TYPE_INT:
			if not strict:
				return BigInt.from_int(v)
			push_error("Got native int in strict data serialization")
			return v
		TYPE_OBJECT:
			if v.has_method("to_data"):
				return v.to_data()
			else:
				push_error("Constr field does not implement `to_data`")
				return v
		TYPE_PACKED_BYTE_ARRAY:
			return v
		_:
			push_error("Got unsupported type in data serialization")
			return v

## Recursively wraps native data types to GDScript types
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
