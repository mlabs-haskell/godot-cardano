extends RefCounted
class_name PubKeyHash

## A public key hash

var _pub_key_hash: _PubKeyHash

enum Status { SUCCESS = 0, FROM_HEX_ERROR = 1 }

## WARNING: Do not use this constructor directly, instead use [method from_hex]
## for a safe way of building a [PubKeyHash].
func _init(pub_key_hash: _PubKeyHash):
	_pub_key_hash = pub_key_hash

class FromHexResult extends Result:
	## WARNING: This function may fail! First match on [Result_.tag] or call [Result_.is_ok].
	var value: PubKeyHash:
		get: return PubKeyHash.new(_res.unsafe_value())
	## WARNING: This function may fail! First match on [Result_.tag] or call [Result._is_err].
	var error: String:
		get: return _res.unsafe_error()

## Tries to parse a [PubKeyhash] from the [param hash] passed as a hex-encoded
## [String].
static func from_hex(hash: String) -> FromHexResult:
	return FromHexResult.new(_PubKeyHash._from_hex(hash))

## Return a [String] containing the hex-encoded hash.
func to_hex() -> String:
	return _pub_key_hash.to_hex()
	
func to_bytes() -> PackedByteArray:
	return _pub_key_hash.to_bytes()
