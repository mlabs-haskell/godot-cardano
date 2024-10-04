extends RefCounted
class_name ScriptHash

var _script_hash: _ScriptHash

enum Status { SUCCESS = 0, FROM_HEX_ERROR = 1 }

func _init(script_hash: _ScriptHash):
	_script_hash = script_hash

class FromHexResult extends Result:
	## WARNING: This function may fail! First match on [Result_.tag] or call [Result_.is_ok].
	var value: ScriptHash:
		get: return ScriptHash.new(_res.unsafe_value())
	## WARNING: This function may fail! First match on [Result_.tag] or call [Result._is_err].
	var error: String:
		get: return _res.unsafe_error()
		
static func from_hex(hash: String) -> FromHexResult:
	return FromHexResult.new(_ScriptHash._from_hex(hash))
	
func to_hex() -> String:
	return _script_hash.to_hex()
	
func to_bytes() -> PackedByteArray:
	return _script_hash.to_bytes()
