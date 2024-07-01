extends RefCounted

class_name PubKeyHash

var _pub_key_hash: _PubKeyHash

enum Status { SUCCESS = 0, FROM_HEX_ERROR = 1 }

func _init(pub_key_hash: _PubKeyHash):
	_pub_key_hash = pub_key_hash

class FromHexResult extends Result:
	## WARNING: This function may fail! First match on [Result_.tag] or call [Result_.is_ok].
	var value: PubKeyHash:
		get: return PubKeyHash.new(_res.unsafe_value())
	## WARNING: This function may fail! First match on [Result_.tag] or call [Result._is_err].
	var error: String:
		get: return _res.unsafe_error()
		
static func from_hex(hash: String) -> FromHexResult:
	return FromHexResult.new(_PubKeyHash._from_hex(hash))
	
func to_hex() -> String:
	return _pub_key_hash.to_hex()
	
func to_bytes() -> PackedByteArray:
	return _pub_key_hash.to_bytes()
