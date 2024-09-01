extends RefCounted
class_name Transaction

## Transaction class

var _tx: _Transaction
var _input_utxos: Array[Utxo]

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
	
func _init(tx: _Transaction, input_utxos: Array[Utxo] = []) -> void:
	_tx = tx
	_input_utxos = []
	var json: Dictionary = to_json()
	for utxo in input_utxos:
		var utxo_out_ref = utxo.to_out_ref_string()
		for input: Dictionary in json.body.inputs:
			var input_out_ref := "%s#%d" % [input.transaction_id, input.index]
			if utxo_out_ref == input_out_ref:
				_input_utxos.push_back(utxo)

func bytes() -> PackedByteArray:
	return _tx.bytes()

func to_json() -> Dictionary:
	return JSON.parse_string(_tx.to_json())
	
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
func to_hash() -> TransactionHash:
	return TransactionHash.new(_tx.hash())

func input_utxos() -> Array[Utxo]:
	return _input_utxos
	
func outputs() -> Array[Utxo]:
	var _outputs: Array[_Utxo] = _tx.outputs()
	var outputs: Array[Utxo]
	for _utxo in _outputs:
		outputs.push_back(Utxo.new(_utxo))
	return outputs
