extends Node
class_name Provider

## Provides basic network functionality to interact with the blockchain
##
## A [Provider] implements basic functions that query transactions
## and other useful information from the blockchain. It also contains the
## [method new_tx] and [method submit_transaction] methods, which are used in
## [TxBuilder] to build and post transactions to the blockchain.
##
## This class should generally not be used directly, as most use cases that
## require connectivity are implemented in [OnlineWallet] and [TxBuilder].

class UtxoCacheEntry:
	var _query_id: String
	var _time: int
	var _result: Array[Utxo]
	
	func _init(query_id: String, time: int, result: Array[Utxo]) -> void:
		_query_id = query_id
		_time = time
		_result = result

## This signal is emitted shortly after getting the protocol parameters from the
## blockchain, after object initialization.
signal got_tx_builder(initialized: bool)

## Indicates the confirmation status of a given transaction. A status result of
## false indicates that the query timed out without the transaction being
## confirmed.
signal tx_status_confirmed(status: ProviderApi.TransactionStatus)

var _provider_api: ProviderApi
var _network_genesis: ProviderApi.NetworkGenesis
var _protocol_params: ProtocolParameters
var _era_summaries: Array[ProviderApi.EraSummary]
var _cost_models: CostModels

# maps (Address or AssetClass) => (OutRef => [Utxo])
var _chaining_map: Dictionary = {}
## If true, locally submitted transactions will be chained to allow for more 
## frequent interactions.
## @experimental
var use_chaining: bool = false

var _utxo_cache: Dictionary = {}
## Enables caching of UTxO queries via this Provider. This allows for faster
## and smoother interactions at the cost of data consistency.
var use_caching: bool = false
## The time in milliseconds for which a cached entry is valid.
var cache_timeout: int = 30000

var tx_status_timeout: int = 300

## The [param provider_api] object defines the Cardano API that will be used to
## resolve all requests made by the [Provider].
func _init(provider_api: ProviderApi) -> void:
	_provider_api = provider_api
	if provider_api.got_network_genesis.connect(_on_got_network_genesis) == ERR_INVALID_PARAMETER:
		push_error("Failed to connect provider's 'got_network_genesis' signal ")
	if provider_api.got_protocol_parameters.connect(_on_got_protocol_parameters) == ERR_INVALID_PARAMETER:
		push_error("Failed to connect provider's 'got_protocol_parameters' signal ")
	if provider_api.got_era_summaries.connect(_on_got_era_summaries) == ERR_INVALID_PARAMETER:
		push_error("Failed to connect provider's 'got_era_summaries' signal ")
	if tx_status_confirmed.connect(_on_tx_status_confirmed) == ERR_INVALID_PARAMETER:
		push_error("Failed to connect provider's 'got_tx_status' signal ")

func _ready() -> void:
	_provider_api._get_network_genesis()
	_provider_api._get_protocol_parameters()
	_provider_api._get_era_summaries()

func _on_got_network_genesis(
	genesis: ProviderApi.NetworkGenesis
) -> void:
	_network_genesis = genesis

func _on_got_protocol_parameters(
	params: ProtocolParameters,
	cost_models: CostModels
) -> void:
	_protocol_params = params
	_cost_models = cost_models

func _on_tx_status_confirmed(status: ProviderApi.TransactionStatus) -> void:
	if use_chaining:
		_handle_chaining_transaction_status(status)
	
func _on_got_era_summaries(summaries: Array[ProviderApi.EraSummary]) -> void:
	_era_summaries = summaries

func _get_utxos(query_id: String, query: Callable) -> Array[Utxo]:
	var utxos: Array[Utxo] = []
	var cache_entry: UtxoCacheEntry = _utxo_cache.get(query_id, null)
	var now = Time.get_ticks_msec()
	if cache_entry != null and (now - cache_entry._time) < cache_timeout:
		utxos = cache_entry._result
	else:
		utxos = await query.call() 
		_utxo_cache[query_id] = UtxoCacheEntry.new(query_id, now, utxos)
		
	return _chain_utxos(utxos)
	
func _await_response(
	f: Callable,
	check: Callable,
	s: Signal,
	interval: float = 4,
	timeout := 60
) -> bool:
	var start := Time.get_ticks_msec()
	var timer := Timer.new()
	timer.one_shot = false
	timer.wait_time = interval
	timer.timeout.connect(f)
	timer.autostart = true
	add_child(timer)
	var status := false
	var timeout_millis := timeout * 1000
	while true:
		var r: Variant = await s
		status = status or check.call(r)
		if status or (Time.get_ticks_msec() - start) > timeout_millis:
			break
	timer.stop()
	timer.queue_free()
	return status

func _chain_utxos(utxos: Array[Utxo]) -> Array[Utxo]:
	if not use_chaining:
		return utxos
	
	var chained: Array[Utxo] = utxos.duplicate()
	for utxo in utxos:
		var out_ref := utxo.to_out_ref_string()
		for key in _chaining_map:
			var inner: Dictionary = _chaining_map[key]
			if inner.has(out_ref):
				chained.erase(utxo)
				for new_utxo: Utxo in inner[out_ref]:
					if not chained.has(new_utxo):
						chained.push_back(new_utxo)
	return chained
	
func _handle_chaining_transaction_status(status: ProviderApi.TransactionStatus) -> void:
	var tx_hash := status._tx_hash.to_hex()
	var new_map := {}
	for key: String in _chaining_map:
		var inner: Dictionary = _chaining_map[key]
		new_map[key] = {}
		var pruned: Array[String] = []
		for out_ref: String in inner:
			if out_ref.begins_with(tx_hash) and not status._confirmed:
				# transaction was not confirmed, remove the entire map for this
				# stale outref
				pruned.push_back(out_ref)
				continue
			
			var utxos = inner[out_ref].duplicate()
			for utxo: Utxo in inner[out_ref]:
				if utxo.to_out_ref_string().begins_with(tx_hash):
					# if this transaction was confirmed we no longer need to chain
					# to it; if it failed, we want to remove all references
					utxos.erase(utxo)

			if utxos.size() == 0:
				# prune outrefs with no remaining mappings
				pruned.push_back(out_ref)
			else:
				inner[out_ref] = utxos
		
		get_tree().create_timer(cache_timeout / 1000).timeout.connect(
			func():
				# TODO: figure out how to handle asset keys
				var address_result = Address.from_bech32(key)
				
				if address_result.is_ok():
					if inner.size() == 0:
						_utxo_cache.erase(key)
					await await_utxos_at(address_result.value, status._tx_hash)
					
				for out_ref in pruned:
					inner.erase(out_ref)
		)

func _update_chaining_entry(
	entry_key: String,
	out_ref: String,
	outputs: Array[Utxo]
) -> void:
	# updates a particular chaining entry (address or asset) by mapping a spent
	# outref to a set of utxos
	var inner: Dictionary = _chaining_map[entry_key]
	inner[out_ref] = outputs
	
	# for each existing mapping, replace the given outref by the same set out
	# outputs as mapped directly above
	for key: String in inner:
		var mapping: Array = inner[key]
		var matches = mapping.filter(
			func (x: Utxo) -> bool: return x.to_out_ref_string() == out_ref
		)
		for utxo: Utxo in matches:
			# should really only exist once, but just in case
			mapping.erase(utxo)
		if matches.size() > 0:
			mapping.append_array(outputs)
	
func _handle_chaining_submit_transaction(tx: Transaction) -> void:
	# update chaining map for a given transaction:
	# inputs spent in this transaction are mapped to outputs based on either 
	# their address or an asset they carry
	var outputs: Array[Utxo] = tx.outputs()
	for input: Utxo in tx._input_utxos:
		var address := input.address().to_bech32()
		var assets := input.assets().to_dictionary().keys()
		var out_ref := input.to_out_ref_string()
		if _chaining_map.has(address):
			var matched_outputs = outputs.filter(
				func (utxo: Utxo) -> bool:
					return utxo.address().to_bech32() == address
			)
			_update_chaining_entry(address, out_ref, matched_outputs)
			
			# give priority to address chaining
			continue

		for asset: String in assets:
			var asset_class := AssetClass.from_unit(asset).value
			if _chaining_map.has(asset):
				var inner: Dictionary = _chaining_map[asset]
				var matched_outputs = outputs.filter(
					func (utxo: Utxo) -> bool:
						return not utxo.assets().get_asset_quantity(asset_class).eq(BigInt.zero())
				)
				_update_chaining_entry(asset, out_ref, matched_outputs)

## Used for creating a new [TxBuilder].
func new_tx() -> TxBuilder.CreateResult:
	var create_result := await TxBuilder.create(self)
	if create_result.is_ok():
		var builder := create_result.value
		if _era_summaries.size() > 0:
			builder.set_slot_config(
				_era_summaries[-1]._start._time,
				_era_summaries[-1]._start._slot,
				_era_summaries[-1]._parameters._slot_length,
			)
		if _cost_models != null:
			builder.set_cost_models(_cost_models)
	return create_result
	
## Converts POSIX time to slots.
func time_to_slot(time: int) -> int:
	# FIXME: should return a `Result`?
	if _network_genesis == null:
		return -1

	for era in _era_summaries:
		var era_start_time := _network_genesis._system_start + era._start._time
		var era_end_time := _network_genesis._system_start + era._end._time
		if time > era_start_time and time < era_end_time:
			var time_in_era := time - era_start_time
			return time_in_era / era._parameters._slot_length + era._start._slot
	
	return -1

## Get the latest protocol parameters
func get_protocol_parameters() -> ProtocolParameters:
	if _protocol_params == null:
		await _provider_api.got_protocol_parameters
	return _protocol_params

## Submit a transaction to the blockchain.
func submit_transaction(tx: Transaction) -> ProviderApi.SubmitResult:
	var submit_result := await _provider_api._submit_transaction(tx)

	if submit_result.is_err():
		return submit_result

	if use_chaining:
		_handle_chaining_submit_transaction(tx)

	await_tx(tx.to_hash(), tx_status_timeout)
	return submit_result

## Poll the backend to confirm if a submitted TX has been added to the blockchain
## or not. The [param timeout] defines for how many seconds this polling is done
## before the function gives up and returns [code]false[/code].[br][br]
##
## NOTE: The default timeout is far too short to confirm if a TX has landed on
## the blockchain or not, settling times can be much longer. However, it is
## useful in testing conditions.
func await_tx(tx_hash: TransactionHash, timeout := 60) -> bool:
	var confirmed := await _await_response(
		func () -> void: _provider_api._get_tx_status(tx_hash),
		func (result: ProviderApi.TransactionStatus) -> bool:
			return result._tx_hash == tx_hash and result._confirmed,
		_provider_api.got_tx_status,
		5,
		timeout
	)
	tx_status_confirmed.emit(ProviderApi.TransactionStatus.new(tx_hash, confirmed))
	return confirmed

## Poll the backend to confirm if the UTxOs from a given TX have appeared at
## a specific address. If [param from_tx] is [code]null[/code], then it will poll
## until any UTxOs are found in that address.
##
## Like in [method await_tx], the [param timeout] defines for how long the polling
## will be performed until the function fails.
func await_utxos_at(
	address: Address,
	from_tx: TransactionHash = null,
	timeout := 60
) -> bool:
	return await _await_response(
		func () -> void: _provider_api._get_utxos_at_address(address),
		func (result: ProviderApi.UtxosAtAddressResult) -> bool:
			var found_utxos := false
			if from_tx == null:
				found_utxos = result._utxos != []
			else:
				found_utxos = result._utxos.any(
					func (utxo: Utxo) -> bool:
						return utxo.tx_hash().to_hex() == from_tx.to_hex()
				)
			return result._address.to_bech32() == address.to_bech32() and found_utxos,
		_provider_api.got_utxos_at_address,
		5,
		timeout
	)

## Construct an [Address] from a pair of payment and staking [Credential]s.
## Staking [Credential]s are optional, but their use is [b]strongly[/b] encouraged,
## since not including them might restrict users from staking their ADA.
func make_address(payment_cred: Credential, stake_cred: Credential = null) -> Address:
	return Address.build(
		_provider_api.network,
		payment_cred,
		stake_cred
	)

## Get the [Utxo]s located the provided [param address].
func get_utxos_at_address(address: Address, asset: AssetClass = null) -> Array[Utxo]:
	var query_id = address.to_bech32()
	return await _get_utxos(
		query_id,
		func (): return await _provider_api._get_utxos_at_address(address, asset)
	)

## Get the [Utxo]s containing the provided [param asset].
func get_utxos_with_asset(asset: AssetClass) -> Array[Utxo]:
	var query_id = asset.to_unit()
	return await _get_utxos(
		query_id,
		func (): return await _provider_api._get_utxos_with_asset(asset)
	)

## Returns the most recent UTxO containing a given asset class, or null if the
## asset does not currently exist in the ledger.
func get_utxo_with_nft(asset: AssetClass) -> Utxo:
	var query_id = asset.to_unit()
	return (await _get_utxos(
		query_id,
		func (): return [await _provider_api._get_utxo_with_nft(asset)] as Array[Utxo]
	))[0]

	
## Get the [Utxo] uniquely identified by the given [param tx_hash] and
## [param output_index].
# FIXME: The Blockfrost provider does not offer a way to distinguish between
# a spent and unspent output using this query.
func get_utxo_by_out_ref(tx_hash: TransactionHash, output_index: int) -> Utxo:
	var query_id = "%s#%d" % [tx_hash.to_hex(), output_index]
	return (await _get_utxos(
		query_id,
		func (): return [await _provider_api._get_utxo_by_out_ref(tx_hash, output_index)] as Array[Utxo]
	))[0]

## Returns the datum attached to the ref token for the given CIP68 config, or
## null if the ref token does not currently exist in the ledger.
func get_cip68_datum(conf: Cip68Config) -> Cip68Datum:
	var asset_class := conf.make_ref_asset_class()
	var utxos := await get_utxos_with_asset(asset_class)
	if utxos.size() == 0:
		return null
	return Cip68Datum.unsafe_from_constr(utxos[0].datum())

## Have the Provider chain UTxOs by address. Locally spent UTxOs will be translated
## to outputs of the spending transaction by matching the input and output address.
## Note that this currently will not chain with remotely submitted transactions,
## such as those in the mempool.
func chain_address(address: Address) -> void:
	var bech32 := address.to_bech32()
	if not _chaining_map.has(bech32):
		_chaining_map[bech32] = {}

## Similar to [method Provider.chain_address], but translates UTxOs based on an asset.
## In general this will be most reliable when used for authoritative NFTs.
func chain_asset(asset_class: AssetClass) -> void:
	var unit := asset_class.to_unit()
	if not _chaining_map.has(unit):
		_chaining_map[unit] = {}

## Deletes the current cached data for a given key, or all cached data.
## A key may be in the form of a Bech32 address or an asset unit string.
func invalidate_cache(key: String = "") -> void:
	if key == "":
		_utxo_cache = {}
	else:
		_utxo_cache.erase(key)

func load_script(res: ScriptResource) -> PlutusScriptSource:
	return await res.load_script(self)

## Builds, signs and submits a transaction using the provided functions.
## [param wallet] is the wallet to use for balancing the transaction
## [param builder] should expect a [class TxBuilder]
## [param signer] should expect a [class TxComplete]
## Returns a transaction hash on success which can be awaited, or null on failure.
func tx_with(
	wallet: OnlineWallet,
	builder: Callable,
	signer: Callable
) -> TransactionHash:
	var new_tx_result := await new_tx()
	if new_tx_result.is_err():
		push_error("Failed to create transaction: %s" % new_tx_result.error)
		return null
	var tx_builder := new_tx_result.value
	
	tx_builder.set_wallet(wallet)
	await builder.call(tx_builder)
	
	var complete_result := await tx_builder.complete()
	if complete_result.is_err():
		push_error("Failed to build transaction: %s" % complete_result.error)
		return

	var tx := complete_result.value
	await signer.call(tx)
	
	var submit_result := await tx.submit()
	if submit_result.is_err():
		push_error("Failed to submit transaction: %s" % submit_result.error)
		return
	
	return submit_result.value
