extends RefCounted
class_name TxBuilder

## Main interface for transaction building
##
## The [TxBuilder] offers a stateful interface for the building of transactions,
## not unlike other frameworks such as Lucid.
##
## The general flow for transaction building is: initialization
## ([method Provider.new_tx]), addition of constraints (e.g:
## [method pay_to_address], [method set_change_address], [method collect_from],
## etc.) and balancing/evaluation [method complete].
##
## This last step returns a [TxComplete], which is a balanced and evaluated
## transaction that can be subsequently signed and submitted.

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
var _wallet: OnlineWallet
var _provider: Provider
var _results: Array[Result]
var _script_utxos: Array[Utxo]
var _other_utxos: Array[Utxo]

var _change_address: Address

## You should not create a [TxBuilder] with [TxBuilder.new], instead
## you should use [Provider.new_tx] (or [OnlineWallet.new_tx]).
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
		wallet: OnlineWallet = null,
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

## TODO: This probably shouldn't be exposed.
## Create a TxBuilder object from a Provider. You should use [method Provider.new_tx]
## instead of this method, since that one will make sure to initialize other
## necessary fields.
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

## Set the slot configuration. This is automatically done on initialization, do
## not use unless you know what you are doing.
func set_slot_config(start_time: int, start_slot: int, slot_length: int) -> TxBuilder:
	_builder.set_slot_config(start_time, start_slot, slot_length)
	return self
	
## Set the cost models. This is automatically done on initialization, do
## not use unless you know what you are doing.
func set_cost_models(cost_models: CostModels) -> TxBuilder:
	_builder.set_cost_models(cost_models._cost_models)
	return self
	
## Pay to a given [param address]. [param coin] specifies the quantity of
## lovelace to transfer, while the optional parameter [param assets] specifies
## any additional assets to transfer.[br] May optionally include a [param datum]
## and [param script_ref], and a flag [param hash_datum] determining whether
## the provided datum should be inline.
## NOTE: If [param assets] contains ADA it will be added to the amount set by
## [param coin].
func pay_to_address(
	address: Address,
	coin: BigInt,
	assets: MultiAsset = MultiAsset.empty(),
	datum: PlutusData = null,
	script_ref: PlutusScript = null,
	hash_datum := false
) -> TxBuilder:
	var datum_serialized: Datum = null
	if datum != null:
		var serialize_result := datum.serialize()
	
		if serialize_result.is_err():
			_results.push_back(serialize_result)
		elif hash_datum:
			datum_serialized = Datum.hashed(serialize_result.value)
		else:
			datum_serialized = Datum.inline(serialize_result.value)
	
	_builder._pay_to_address(
		address._address,
		coin._b,
		assets._multi_asset,
		datum_serialized,
		script_ref
	)
	return self
	
## Similar to [method pay_to_address], but it also takes a [param datum]
## argument that will be used to embed the datum hash in the transaction.
## [param datum] should be convertable to PlutusData.
func pay_to_address_with_datum_hash(
	address: Address,
	coin: BigInt,
	assets: MultiAsset,
	datum: PlutusData,
	script_ref: PlutusScript = null
) -> TxBuilder:
	return pay_to_address(address, coin, assets, datum, script_ref, true)

## Mint tokens with the given [param minting_policy] and using the a list of
## specs defined in [param tokens]. A [param redeemer] is also required for the
## minting policy.
func mint_assets(
	minting_policy_source: PlutusScriptSource,
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
	
	if minting_policy_source.is_ref():
		add_reference_input(Utxo.new(minting_policy_source.utxo()))
		
	var result := Result.VariantResult.new(
		_builder._mint_assets(
			minting_policy_source,
			tokens_dict,
			serialize_result.value
		)
	)

	_results.push_back(result)
	
	return self

## Mint a pair of CIP68 user and reference tokens using the given 
## [param redeemer] and minting configuration in [param conf].
func mint_cip68_pair(redeemer: PlutusData, conf: Cip68Config) -> TxBuilder:
	if conf.minting_policy_source == null:
		await conf.init_script(_provider)

	mint_assets(
		conf.minting_policy_source, 
		[
			TxBuilder.MintToken.new(conf.get_user_token_name(), conf.get_quantity()),
			TxBuilder.MintToken.new(conf.get_ref_token_name(), BigInt.one())
		],
		redeemer
	)
	return self

## Mint user tokens for a given [param conf]. This should generally be used
## for fungible tokens after the initial mint has been performed by
## [method mint_cip68_pair].
func mint_cip68_user_tokens(
	redeemer: PlutusData,
	conf: Cip68Config,
	quantity := conf.get_quantity()
) -> TxBuilder:
	if conf.minting_policy_source == null:
		await conf.init_script(_provider)

	mint_assets(
		conf.minting_policy_source, 
		[TxBuilder.MintToken.new(conf.get_user_token_name(), quantity)],
		redeemer
	)
	return self

## Pay the CIP68 reference token specified by [param minting_policy] and
## [param conf] to the given [param address].
func pay_cip68_ref_token(address: Address, conf: Cip68Config) -> TxBuilder:
	if conf.minting_policy_source == null:
		await conf.init_script(_provider)

	var assets = MultiAsset.empty()
	assets.set_asset_quantity(conf.make_ref_asset_class(), BigInt.one())
	pay_to_address(address, BigInt.zero(), assets, conf.to_data())
	return self

## Pay the CIP68 user tokens specified by [param minting_policy] and
## [param conf] to the given [param address].
func pay_cip68_user_tokens(
	address: Address,
	conf: Cip68Config,
	quantity := conf.get_quantity()
) -> TxBuilder:
	if conf.minting_policy_source == null:
		await conf.init_script(_provider)

	var assets = MultiAsset.empty()
	assets.set_asset_quantity(conf.make_user_asset_class(), quantity)
	pay_to_address(address, BigInt.zero(), assets)
	return self
	
## Pay the CIP68 user tokens specified by [param minting_policy] and
## [param conf] to the given [param address]. The output will contain a
## [param datum].
func pay_cip68_user_tokens_with_datum(
	address: Address,
	datum: PlutusData,
	conf: Cip68Config,
	quantity := conf.get_quantity()
) -> TxBuilder:
	if conf.minting_policy_source == null:
		await conf.init_script(_provider)
		
	var assets = MultiAsset.empty()
	assets.set_asset_quantity(conf.make_user_asset_class(), quantity)
	pay_to_address(address, BigInt.zero(), assets, datum)
	return self

## Consume all the [param utxos] specified.
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

## Consume all the [param utxos] locked by the [param plutus_script_source] using
## the provided [param redeemer].
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

	if plutus_script_source.is_ref():
		add_reference_input(Utxo.new(plutus_script_source.utxo()))

	_builder._collect_from_script(
		plutus_script_source,
		_utxos,
		serialize_result.value
	)
	
	return self

## When the transaction is balanced (usually when [method complete] is called),
## send any change to the provided [param change_address].
func set_change_address(change_address: Address) -> TxBuilder:
	_change_address = change_address
	return self

## Use the provided [param wallet] for balancing. This automatically sets the
## change address to that wallet's address.
func set_wallet(wallet: OnlineWallet) -> TxBuilder:
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

## Add a required signer constraint to the transaction.
func add_required_signer(pub_key_hash: PubKeyHash) -> TxBuilder:
	_builder._add_required_signer(pub_key_hash._pub_key_hash)
	return self

## Add a [param utxo] as a reference input. This input will not be consumed
## but will be available in the script evaluation context.
func add_reference_input(utxo: Utxo) -> TxBuilder:
	_builder._add_reference_input(utxo._utxo)
	_script_utxos.push_back(utxo)
	return self

## Only balance the transaction and return the result.[br]The resulting transaction
## will not have been evaluated and will have inaccurate script execution units,
## which may cause the transaction to fail at submission and potentially consume
## the provided collateral.[br][br]
## Do not use this function unless you know what you are doing.
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
	
## Attempts to balance and evaluate the transaction. The provided [param utxos]
## can be used for balancing the transaction.
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
	
	var balance_result := await balance(wallet_utxos)
	var error = _results.any(func (result: Result) -> bool: return result.is_err())
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
