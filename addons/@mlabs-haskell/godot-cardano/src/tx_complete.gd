class_name TxComplete
extends RefCounted

var _transaction: Transaction = null
var _provider: Provider
var _wallet: Wallet

var _results: Array[Result]

enum TxCompleteStatus { SUCCESS = 0, INVALID_SIGNATURE = 1, SUBMIT_ERROR = 2 }

class SubmitResult extends Result:
	## WARNING: This function may fail! First match on [Result_.tag] or call [Result_.is_ok].
	var value: TransactionHash:
		get: return _res.unsafe_value() as TransactionHash
	## WARNING: This function may fail! First match on [Result_.tag] or call [Result._is_err].
	var error: String:
		get: return _res.unsafe_error()

func _init(provider: Provider, transaction: Transaction, wallet: Wallet = null) -> void:
	_transaction = transaction
	_provider = provider
	_wallet = wallet

func sign(password: String, wallet: Wallet = _wallet) -> TxComplete:		
	var sign_result := wallet._sign_transaction(password, _transaction)
	_results.push_back(sign_result)
	if sign_result.is_ok():
		_transaction.add_signature(sign_result.value)
	else:
		_results.push_back(
			Result.Err.new(
				"Failed to sign transaction: %s" % sign_result.error,
				TxCompleteStatus.INVALID_SIGNATURE
			)
		)
	return self

func submit() -> SubmitResult:
	var error := _results.any(func (result: Result) -> bool: return result.is_err())
	if not error:
		var submit_result := await _provider.submit_transaction(_transaction)
		if submit_result.is_ok():
			return SubmitResult.new(_Result.ok(submit_result.value))
		else:
			return SubmitResult.new(_Result.err(submit_result.error, TxCompleteStatus.SUBMIT_ERROR))
	
	for result in _results:
		if result.is_err():
			push_error(result.error)

	return SubmitResult.new(
		_Result.err(
			"Failed to submit transaction; errors logged to output",
			TxCompleteStatus.SUBMIT_ERROR
		)
	)

	
func bytes() -> PackedByteArray:
	return _transaction.bytes()
