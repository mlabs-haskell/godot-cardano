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
	NO_CHANGE_ADDRESS = 12,
	COMPLETE_ERROR=13,
}

var _builder: _TxBuilder
var _wallet: Wallet
var _provider: Provider
var _results: Array[Result]
var _script_utxos: Array[Utxo]
var _other_utxos: Array[Utxo]

var _change_address: Address

func _init(provider: Provider, builder: _TxBuilder) -> void:
	_builder = builder
	_provider = provider

class CreateResult extends Result:
	var _provider: Provider
	var _builder: TxBuilder
	
	## WARNING: This function may fail! First match on `tag` or call `is_ok`.
	var value: TxBuilder:
		get: return _builder
	## WARNING: This function may fail! First match on `tag` or call `is_err`.
	var error: String:
		get: return _res.unsafe_error()
		
	func _init(provider: Provider, res: _Result) -> void:
		_provider = provider
		if res.is_ok():
			_builder = TxBuilder.new(_provider, res.unsafe_value() as _TxBuilder)
		super(res)

class BalanceResult extends Result:
	var _transaction: Transaction
	
	## WARNING: This function may fail! First match on `tag` or call `is_ok`.
	var value: Transaction:
		get: return _transaction
	## WARNING: This function may fail! First match on `tag` or call `is_err`.
	var error: String:
		get: return _res.unsafe_error()
	
	func _init(res: _Result):
		if res.is_ok():
			_transaction = Transaction.new(res.unsafe_value() as _Transaction)
		super(res)
		
class CompleteResult extends Result:
	var _transaction: TxComplete
	
	## WARNING: This function may fail! First match on `tag` or call `is_ok`.
	var value: TxComplete:
		get: return _transaction
	## WARNING: This function may fail! First match on `tag` or call `is_err`.
	var error: String:
		get: return _res.unsafe_error()
	
	func _init(
		provider: Provider,
		res: _Result,
		wallet: Wallet = null,
		input_utxos: Array[Utxo] = []
	) -> void:
		if res.is_ok():
			_transaction = TxComplete.new(
				provider,
				Transaction.new(res.unsafe_value() as _Transaction, input_utxos),
				wallet,
			)
		super(res)

class MintToken:
	var _asset_name: AssetName
	var _quantity: BigInt
	
	func _init(asset_name: AssetName, quantity: BigInt):
		_asset_name = asset_name
		_quantity = quantity
	
	func _to_string() -> String:
		return "%s" % { [_asset_name.to_hex()]: _quantity.to_str() }
		
## Create a TxBuilder object from a Provider. This action may fail.
static func create(provider: Provider) -> CreateResult:
	var params := await provider.get_protocol_parameters()
	if params == null:
		return CreateResult.new(
			provider,
			_Result.err(
				"Tried to create transaction with null protocol parameters",
				TxBuilderStatus.BAD_PROTOCOL_PARAMETERS
			)
		)
	return CreateResult.new(provider, _TxBuilder._create(params))

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
	datum: PlutusData
) -> TxBuilder:
	var serialize_result := datum.serialize()
	
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
	
func pay_to_address_with_datum_hash(
	address: Address,
	coin: BigInt,
	assets: MultiAsset,
	datum: PlutusData
) -> TxBuilder:
	var serialize_result := datum.serialize()

	if serialize_result.is_err():
		_results.push_back(serialize_result)
	else:
		_builder._pay_to_address_with_datum(
			address._address,
			coin._b,
			assets._multi_asset,
			Datum.hashed(serialize_result.value)
		)
	return self

func mint_assets(
	minting_policy: PlutusScript,
	tokens: Array[MintToken],
	redeemer: PlutusData
) -> TxBuilder:
	var serialize_result: Cbor.SerializeResult = redeemer.serialize()
	
	_results.push_back(serialize_result)
	if serialize_result.is_err():
		return self
		
	var tokens_dict: Dictionary = {}
	tokens.map(
		func (token: MintToken) -> void:
			var asset_name = token._asset_name.to_bytes()
			var prev = tokens_dict.get(asset_name, BigInt.zero()._b)
			tokens_dict[asset_name] = prev.add(token._quantity._b)
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
	
func mint_cip68_pair(
	minting_policy: PlutusScript,
	redeemer: PlutusData,
	conf: MintCip68
) -> TxBuilder:
	mint_assets(
		minting_policy, 
		[
			TxBuilder.MintToken.new(conf.get_user_token_name(), conf.get_quantity()),
			TxBuilder.MintToken.new(conf.get_ref_token_name(), BigInt.one())
		],
		redeemer
	)
	return self

func pay_cip68_ref_token(
	minting_policy: PlutusScript,
	address: Address,
	conf: MintCip68
) -> TxBuilder:
	var assets = MultiAsset.empty()
	assets.set_asset_quantity(conf.make_ref_asset_class(minting_policy), BigInt.one())
	pay_to_address_with_datum(address, BigInt.zero(), assets, conf.to_data())
	return self

func pay_cip68_user_tokens(
	minting_policy: PlutusScript,
	address: Address,
	conf: MintCip68
) -> TxBuilder:
	var assets = MultiAsset.empty()
	assets.set_asset_quantity(conf.make_user_asset_class(minting_policy), conf.get_quantity())
	pay_to_address(address, BigInt.zero(), assets)
	return self
	
func pay_cip68_user_tokens_with_datum(
	minting_policy: PlutusScript,
	address: Address,
	datum: PlutusData,
	conf: MintCip68,
	amount := conf.get_quantity()
) -> TxBuilder:
	var assets = MultiAsset.empty()
	assets.set_asset_quantity(conf.make_user_asset_class(minting_policy), amount)
	pay_to_address_with_datum(address, BigInt.zero(), assets, datum)
	return self

func collect_from(utxos: Array[Utxo]) -> TxBuilder:
	var _utxos: Array[_Utxo] = []
	_utxos.assign(
		utxos.map(
			func (utxo: Utxo) -> _Utxo: return utxo._utxo
		)
	)
	_builder._collect_from(_utxos)
	_other_utxos.append_array(utxos)
	return self
	
func collect_from_script(
	plutus_script_source: PlutusScriptSource,
	utxos: Array[Utxo],
	redeemer: PlutusData
) -> TxBuilder:
	var serialize_result: Cbor.SerializeResult = redeemer.serialize()
	
	var _utxos: Array[_Utxo] = []
	_utxos.assign(
		utxos.map(
			func (utxo: Utxo) -> _Utxo: return utxo._utxo
		)
	)
	
	_script_utxos.append_array(utxos)

	_builder._collect_from_script(
		plutus_script_source,
		_utxos,
		serialize_result.value
	)
	
	return self

func set_change_address(change_address: Address) -> TxBuilder:
	_change_address = change_address
	return self

func set_wallet(wallet: Wallet) -> TxBuilder:
	_wallet = wallet
	_change_address = wallet._get_change_address()
	return self

## Set the time in POSIX seconds after which the transaction is valid
func valid_after(time: int) -> TxBuilder:
	var slot := _provider.time_to_slot(time)
	_builder.valid_after(slot)
	return self

## Set the time in POSIX seconds before which the transaction is valid
func valid_before(time: int) -> TxBuilder:
	var slot := _provider.time_to_slot(time)
	_builder.valid_before(slot)
	return self

func add_required_signer(pub_key_hash: PubKeyHash) -> TxBuilder:
	_builder._add_required_signer(pub_key_hash._pub_key_hash)
	return self

func add_reference_input(utxo: Utxo) -> TxBuilder:
	_builder._add_reference_input(utxo._utxo)
	_script_utxos.push_back(utxo)
	return self

## Only balance the transaction and return the result. The resulting transaction
## will not have been evaluated and will have inaccurate script execution units,
## which may cause the transaction to fail at submission and potentially consume
## the provided collateral.
func balance(utxos: Array[Utxo] = []) -> BalanceResult:
	var wallet_utxos: Array[Utxo] = []
	if utxos.size() > 0:
		wallet_utxos = utxos
	elif _wallet != null:
		wallet_utxos = await _wallet._get_updated_utxos()
		
	var _wallet_utxos: Array[_Utxo] = []
	_wallet_utxos.assign(
		wallet_utxos.map(func (utxo: Utxo) -> _Utxo: return utxo._utxo)
	)
	
	var result: BalanceResult = null
	if wallet_utxos.size() == 0:
		result = BalanceResult.new(
			_Result.err(
				"Tried to balance transaction with no input UTxOs",
				TxBuilderStatus.NO_UTXOS
			)
		)
	
	if _change_address == null:
		result = BalanceResult.new(
			_Result.err(
				"Tried to balance transaction with no change address",
				TxBuilderStatus.NO_CHANGE_ADDRESS
			)
		)
	
	if result != null:
		_results.push_back(result)
		return result
		
	return BalanceResult.new(
		_builder._balance_and_assemble(_wallet_utxos, _change_address._address)
	)
	
func complete(utxos: Array[Utxo] = []) -> CompleteResult:
	var wallet_utxos: Array[Utxo] = []
	if utxos.size() > 0:
		wallet_utxos = utxos
	elif _wallet != null:
		wallet_utxos = await _wallet._get_updated_utxos()

	var _wallet_utxos: Array[_Utxo] = []
	_wallet_utxos.assign(
		wallet_utxos.map(func (utxo: Utxo) -> _Utxo: return utxo._utxo)
	)
	
	if wallet_utxos.size() == 0:
		_results.push_back(
			CompleteResult.new(
				_provider,
				_Result.err(
					"Tried to complete transaction with no input UTxOs",
					TxBuilderStatus.NO_UTXOS
				)
			)
		)
	_builder._add_dummy_redeemers()
	
	var balance_result := await balance()
	
	var error = _results.any(func (result: Result) -> bool: return result.is_err())
	
	if balance_result.is_ok():
		pass
	_results.push_back(balance_result)
	if not error and balance_result.is_ok():
		var eval_result := balance_result.value.evaluate(wallet_utxos + _script_utxos)
		
		_results.push_back(eval_result)
		if eval_result.is_ok():
			return CompleteResult.new(
				_provider,
				_builder._complete(
					_wallet_utxos,
					_change_address._address,
					eval_result.value
				),
				_wallet,
				wallet_utxos + _script_utxos + _other_utxos
			)
	
	for result in _results:
		if result.is_err():
			push_error(result.error)
	
	return CompleteResult.new(
		_provider,
		_Result.err(
			"Failed to complete transaction; errors logged to output",
			TxBuilderStatus.COMPLETE_ERROR
		)
	)
