extends RefCounted
## Transaction class

class_name Transaction

var _tx: _Transaction

enum TransactionStatus {
	SUCCESS = 0,
	EVALUATION_ERROR = 1,
	DESERIALIZE_ERROR = 2,
}

class EvaluationResult extends Result:
	## WARNING: This function may fail! First match on `tag` or call `is_ok`.
	var value: _EvaluationResult:
		get: return _res.unsafe_value()
	## WARNING: This function may fail! First match on `tag` or call `is_err`.
	var error: String:
		get: return _res.unsafe_error()
	
func _init(tx: _Transaction) -> void:
	_tx = tx
	
func bytes() -> PackedByteArray:
	return _tx.bytes()

## Add a signature to the witness set
func add_signature(signature: Signature) -> void:
	_tx.add_signature(signature)

## Try to evaluate the transaction
func evaluate(utxos: Array[Utxo]) -> EvaluationResult:
	var _utxos: Array[_Utxo] = []
	_utxos.assign(
		utxos.map(func (utxo: Utxo) -> _Utxo: return utxo._utxo)
	)
	return EvaluationResult.new(_tx._evaluate(_utxos))

## Get the unique hash of the transaction
func hash() -> TransactionHash:
	return TransactionHash.new(_tx.hash())
