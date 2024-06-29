extends RefCounted
class_name PolicyId
## An asset policy ID

var _policy_id: _PolicyId

enum Status { SUCCESS = 0, COULD_NOT_DECODE_HEX = 1 }

## WARNING: Do not use this constructor directly, use [method from_hex] for safe
## building.
func _init(policy_id: _PolicyId):
	_policy_id = policy_id

class FromHexResult extends Result:
	## WARNING: This function may fail! First match on [Result_.tag] or call [Result_.is_ok].
	var value: PolicyId:
		get: return PolicyId.new(_res.unsafe_value())
	## WARNING: This function may fail! First match on [Result_.tag] or call [Result._is_err].
	var error: String:
		get: return _res.unsafe_error()

## Try to parse a [PolicyId] from its minting policy's [param hash] encoded as
## hex.
static func from_hex(hash: String) -> FromHexResult:
	return FromHexResult.new(_PolicyId._from_hex(hash))

## Get the hex encoding of the minting policy's hash
func to_hex() -> String:
	return _policy_id.to_hex()

func _to_string() -> String:
	return to_hex()
