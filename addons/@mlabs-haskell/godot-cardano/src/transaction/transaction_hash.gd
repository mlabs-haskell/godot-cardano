extends RefCounted
class_name TransactionHash

## Hash of a transaction
##
## The transaction hash is used to uniquely identify a transaction, which
## can be useful for many operations.

var _transaction_hash: _TransactionHash

enum Status { SUCCESS = 0, INVALID_HASH = 1 }

func _init(transaction_hash: _TransactionHash):
	_transaction_hash = transaction_hash

## Result of calling [method from_hex].
class FromHexResult extends Result:
	## WARNING: This function may fail! First match on [Result_.tag] or call [Result_.is_ok].
	var value: TransactionHash:
		get: return TransactionHash.new(_res.unsafe_value())
	## WARNING: This function may fail! First match on [Result_.tag] or call [Result._is_err].
	var error: String:
		get: return _res.unsafe_error()
		
## Tries to parse a [TransactionHash] from a hex-encoded [String].
static func from_hex(hash: String) -> FromHexResult:
	return FromHexResult.new(_TransactionHash._from_hex(hash))

## Obtain a hex-encoding of the hash.
func to_hex() -> String:
	return _transaction_hash.to_hex()

func _to_string() -> String:
	return to_hex()
