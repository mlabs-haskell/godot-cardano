extends RefCounted
class_name PolicyId

var _policy_id: _PolicyId

enum Status { SUCCESS = 0, COULD_NOT_DECODE_HEX = 1 }

func _init(policy_id: _PolicyId):
	_policy_id = policy_id

class FromHexResult extends Result:
	## WARNING: This function may fail! First match on [Result_.tag] or call [Result_.is_ok].
	var value: PolicyId:
		get: return PolicyId.new(_res.unsafe_value())
	## WARNING: This function may fail! First match on [Result_.tag] or call [Result._is_err].
	var error: String:
		get: return _res.unsafe_error()

static func from_hex(hash: String) -> FromHexResult:
	return FromHexResult.new(_PolicyId._from_hex(hash))

static func from_script(script: PlutusScript) -> PolicyId:
	var result = _PolicyId._from_hex(script.hash_as_hex())
	return new(result.unsafe_value())
	
func to_hex() -> String:
	return _policy_id.to_hex()

func _to_string() -> String:
	return to_hex()
