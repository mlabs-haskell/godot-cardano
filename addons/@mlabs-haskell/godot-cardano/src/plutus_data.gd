extends RefCounted

class_name PlutusData

## Recursively unwraps Objects to native data types
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
		TYPE_PACKED_BYTE_ARRAY:
			return v
		_:
			push_error("Got unsupported type in data serialization: %s" % v)
			return null

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
