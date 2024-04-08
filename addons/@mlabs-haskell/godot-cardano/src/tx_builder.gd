extends RefCounted

class_name TxBuilder

## You should not create a [TxBuilder] with [TxBuilder.new], instead
## you should use [Cardano.new_tx].

enum TxBuilderStatus {
	SUCCESS = 0,
	BAD_PROTOCOL_PARAMETERS = 1,
	QUANTITY_EXCEEDS_MAXIMUM = 2,
	DESERIALIZE_ERROR = 3,
	BYRON_ADDRESS_UNSUPPORTED = 4,
	COULD_NOT_GET_KEY_HASH = 5,
	UNKNOWN_REDEEMER_INDEX = 6,
	UNEXPECTED_COLLATERAL_AMOUNT = 7,
	OTHER_ERROR = 8,
	CREATE_ERROR = 9,
	INVALID_DATA = 10,
	NO_UTXOS = 11,
}

var _builder: _TxBuilder
var _cardano: Cardano
var _results: Array[Result]
var _script_utxos: Array[Utxo]

var _change_address: Address

func _init(cardano: Cardano, builder: _TxBuilder) -> void:
	_cardano = cardano
	_builder = builder
	_change_address = cardano.wallet._get_change_address()

class CreateResult extends Result:
	var _cardano: Cardano
	
	## WARNING: This function may fail! First match on `tag` or call `is_ok`.
	var value: TxBuilder:
		get: return TxBuilder.new(_cardano, _res.unsafe_value() as _TxBuilder)
	## WARNING: This function may fail! First match on `tag` or call `is_err`.
	var error: String:
		get: return _res.unsafe_error()
		
	func _init(cardano: Cardano, res: _Result):
		_cardano = cardano
		super(res)

class BalanceResult extends Result:
	## WARNING: This function may fail! First match on `tag` or call `is_ok`.
	var value: Transaction:
		get: return Transaction.new(_res.unsafe_value() as _Transaction)
	## WARNING: This function may fail! First match on `tag` or call `is_err`.
	var error: String:
		get: return _res.unsafe_error()
		
class CompleteResult extends Result:
	var _cardano: Cardano
	
	## WARNING: This function may fail! First match on `tag` or call `is_ok`.
	var value: TxComplete:
		get: return TxComplete.new(
			_cardano,
			Transaction.new(_res.unsafe_value() as _Transaction)
		)
	## WARNING: This function may fail! First match on `tag` or call `is_err`.
	var error: String:
		get: return _res.unsafe_error()
	
	func _init(cardano: Cardano, res: _Result) -> void:
		_cardano = cardano
		super(res)

class MintToken:
	var _token_name: PackedByteArray
	var _quantity: BigInt
	
	func _init(token_name: PackedByteArray, quantity: BigInt):
		_token_name = token_name
		_quantity = quantity
		
## Create a TxBuilder object from a ProtocolParameters. This action may fail.
static func create(cardano: Cardano, params: ProtocolParameters) -> CreateResult:
	if params == null:
		return CreateResult.new(
			cardano,
			_Result.err("Tried to create transaction with null protocol parameters", 1)
		)
	var res := CreateResult.new(cardano, _TxBuilder._create(params))
	return res

func set_slot_config(start_time: int, start_slot: int, slot_length: int) -> TxBuilder:
	_builder.set_slot_config(start_time, start_slot, slot_length)
	return self

func set_cost_models(cost_models: CostModels) -> TxBuilder:
	_builder.set_cost_models(cost_models._cost_models)
	return self
	
func pay_to_address(address: Address, coin: BigInt, assets: MultiAsset) -> TxBuilder:
	_builder.pay_to_address(address._address, coin._b, assets._multi_asset)
	return self
	
func pay_to_address_with_datum(
	address: Address,
	coin: BigInt,
	assets: MultiAsset,
	datum: Object
) -> TxBuilder:
	if !datum.has_method("to_data"):
		_results.push_back(
			Result.Err.new(
				"Provided datum does not implement `to_data`",
				TxBuilderStatus.INVALID_DATA
			)
		)

	var serialize_result := Cbor.serialize(datum.to_data(true), true)

	if serialize_result.is_err():
		_results.push_back(serialize_result)
	else:
		_builder._pay_to_address_with_datum(
			address._address,
			coin._b,
			assets._multi_asset,
			Datum.inline(serialize_result.value)
		)
	
	return self

func mint_assets(
	minting_policy: PlutusScript,
	tokens: Array[MintToken],
	redeemer: Object
) -> TxBuilder:
	if !redeemer.has_method("to_data"):
		_results.push_back(
			Result.Err.new(
				"Provided redeemer does not implement `to_data`",
				TxBuilderStatus.INVALID_DATA
			)
		)
		return self

	var serialize_result: Cbor.SerializeResult = Cbor.serialize(redeemer.to_data(true), true)
	
	_results.push_back(serialize_result)
	if serialize_result.is_err():
		return self
		
	var tokens_dict: Dictionary = {}
	tokens.map(
		func (token: MintToken) -> void:
			var prev = tokens_dict.get(token._token_name, BigInt.zero()._b)
			tokens_dict[token._token_name] = prev.add(token._quantity._b)
	)
	
	var result := Result.VariantResult.new(
		_builder._mint_assets(
			minting_policy,
			tokens_dict,
			serialize_result.value
		)
	)
	
	
	_results.push_back(result)
	
	return self

func collect_from(utxos: Array[Utxo]) -> TxBuilder:
	var _utxos: Array[_Utxo] = []
	_utxos.assign(
		utxos.map(func (utxo: Utxo) -> _Utxo: return utxo._utxo)
	)
	_builder._collect_from(_utxos)
	return self
	
func collect_from_script(plutus_script_source: PlutusScriptSource, utxos: Array[Utxo], redeemer: PackedByteArray) -> void:
	var _utxos: Array[_Utxo] = []
	_utxos.assign(
		utxos.map(func (utxo: Utxo) -> _Utxo: return utxo._utxo)
	)
	
	_script_utxos.append_array(utxos)

	_builder._collect_from_script(
		plutus_script_source,
		_utxos,
		redeemer
	)

func set_change_address(change_address: Address) -> TxBuilder:
	_change_address = change_address
	return self
	
func complete() -> CompleteResult:
	var wallet_utxos: Array[Utxo] = await _cardano.wallet._get_updated_utxos()
	var _wallet_utxos: Array[_Utxo] = []
	_wallet_utxos.assign(
		_cardano.wallet._get_utxos().map(func (utxo: Utxo) -> _Utxo: return utxo._utxo)
	)
	var additional_utxos: Array[Utxo] = [] # TODO
	additional_utxos.assign(wallet_utxos)
	
	if wallet_utxos.size() == 0:
		_results.push_back(
			CompleteResult.new(
				_cardano,
				_Result.err(
					"",
					TxBuilderStatus.NO_UTXOS
				)
			)
		)
	
	var balance_result := \
		BalanceResult.new(
			_builder._balance_and_assemble(_wallet_utxos, _change_address._address)
		)
	
	var error = _results.any(func (result: Result) -> bool: return result.is_err())
	
	_results.push_back(balance_result)
	if not error and balance_result.is_ok():
		var eval_result := balance_result.value.evaluate(wallet_utxos + additional_utxos + _script_utxos)
		
		_results.push_back(eval_result)
		if eval_result.is_ok():
			return CompleteResult.new(
				_cardano,
				_builder._complete(
					_wallet_utxos,
					_change_address._address,
					eval_result.value
				)
			)
	
	for result in _results:
		if result.is_err():
			push_error(result.error)
			
	return CompleteResult.new(
		_cardano,
		_Result.err(
			"Failed to complete transaction; errors logged to output",
			TxBuilderStatus.CREATE_ERROR
		)
	)
