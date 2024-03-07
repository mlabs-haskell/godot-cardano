extends RefCounted

class_name TransactionHash

var _transaction_hash: _TransactionHash

enum Status { SUCCESS = 0, BECH32_ERROR = 1 }

func _init(transaction_hash: _TransactionHash):
	_transaction_hash = transaction_hash

class FromHexResult extends Result:
	## WARNING: This function may fail! First match on [Result_.tag] or call [Result_.is_ok].
	var value: TransactionHash:
		get: return TransactionHash.new(_res.unsafe_value())
	## WARNING: This function may fail! First match on [Result_.tag] or call [Result._is_err].
	var error: String:
		get: return _res.unsafe_error()
		
static func from_hex(hash: String) -> FromHexResult:
	return FromHexResult.new(_TransactionHash._from_hex(hash))
	
func to_hex() -> String:
	return _transaction_hash.to_hex()
