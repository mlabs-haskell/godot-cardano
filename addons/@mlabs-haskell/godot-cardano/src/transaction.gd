extends RefCounted

class_name Transaction

var _tx: _Transaction

enum TransactionStatus {
	SUCCESS = 0,
	TRANSACTION_UTXO_ERROR = 1,
	TRANSACTION_JS_ERROR = 2,
	TRANSACTION_EVALUATION_ERROR = 3,
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

func add_signature(signature: Signature) -> void:
	_tx.add_signature(signature)

func evaluate(utxos: Array[Utxo]) -> EvaluationResult:
	var _utxos: Array[_Utxo] = []
	_utxos.assign(
		utxos.map(func (utxo: Utxo) -> _Utxo: return utxo._utxo)
	)
	return EvaluationResult.new(_tx._evaluate(_utxos))
