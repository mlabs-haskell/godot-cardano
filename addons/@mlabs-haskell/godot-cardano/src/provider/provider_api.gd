extends Node
class_name ProviderApi

## An interface for implementing different [Provider]s.
##
## This class factors out the necessary blockchain requests to implement a
## [Provider].
##
## By extending [ProviderApi] and implementing the methods documented
## as virtual, one can leverage the common machinery in [Provider] to use
## alternative Cardano APIs. An example of this is [class BlockfrostProvider].

## Possible error statuses.
enum ProviderStatus { SUCCESS = 0, SUBMIT_ERROR = 1 }

## Value returned by [method Provider.submit_transaction] is called. It
## contains the submitted transaction's hash or a [String] detailing the error.
class SubmitResult extends Result:
	## WARNING: This function may fail! First match on [Result_.tag] or call [Result_.is_ok].
	var value: TransactionHash:
		get: return _res.unsafe_value() as TransactionHash
	## WARNING: This function may fail! First match on [Result_.tag] or call [Result._is_err].
	var error: String:
		get: return _res.unsafe_error()

## The Cardano Network genesis parameters
class NetworkGenesis:
	var _active_slots_coefficient: float
	var _update_quorum: int
	var _max_lovelace_supply: String
	var _network_magic: int
	var _epoch_length: int
	var _system_start: int
	var _slots_per_kes_period: int
	var _slot_length: int
	var _max_kes_evolutions: int
	var _security_param: int
	
	func _init(
		active_slots_coefficient: float,
		update_quorum: int,
		max_lovelace_supply: String,
		network_magic: int,
		epoch_length: int,
		system_start: int,
		slots_per_kes_period: int,
		slot_length: int,
		max_kes_evolutions: int,
		security_param: int,
	) -> void:
		_active_slots_coefficient = active_slots_coefficient
		_update_quorum = update_quorum
		_max_lovelace_supply = max_lovelace_supply
		_network_magic = network_magic
		_epoch_length = epoch_length
		_system_start = system_start
		_slots_per_kes_period = slots_per_kes_period
		_slot_length = slot_length
		_max_kes_evolutions = max_kes_evolutions
		_security_param = security_param
		
class EraTime:
	var _time: int
	var _slot: int
	var _epoch: int
	
	func _init(time: int, slot: int, epoch: int) -> void:
		_time = time
		_slot = slot
		_epoch = epoch

class EraParameters:
	var _epoch_length: int
	var _slot_length: int
	var _safe_zone: int
	
	func _init(epoch_length: int, slot_length: int, safe_zone: int) -> void:
		_epoch_length = epoch_length
		_slot_length = slot_length
		_safe_zone = safe_zone
		
class EraSummary:
	var _start: EraTime
	var _end: EraTime
	var _parameters: EraParameters
	
	func _init(
		start: EraTime,
		end: EraTime,
		parameters: EraParameters,
	) -> void:
		_start = start
		_end = end
		_parameters = parameters

## Status of a submitted transaction.
class TransactionStatus:
	## Hash of the transaction
	var _tx_hash: TransactionHash
	## Whether the transaction could be confirmed or not by the [Provider]
	## implementation [i]at the moment the request was made[/i].[br][br]
	## NOTE: This does not imply failure! Keep in mind settling times in Cardano
	## can be quite long, so set the `timeout` parameter of [Provider.await_tx] appropriately.
	var _confirmed: bool
	
	func _init(tx_hash: TransactionHash, confirmed: bool) -> void:
		_tx_hash = tx_hash
		_confirmed = confirmed
	
	func set_confirmed(confirmed: bool) -> void:
		_confirmed = confirmed

## An asset specified by an [AssetClass] and a list of [Utxo]s that could be
## found containing this asset.
class UtxosWithAssetResult:
	## The asset that was searched
	var _asset: AssetClass
	## The UTxOs containing the asset
	var _utxos: Array[Utxo]
	
	func _init(asset: AssetClass, utxos: Array[Utxo]) -> void:
		_asset = asset
		_utxos = utxos

class UtxoByOutRefResult:
	var _utxo: Utxo
	
	func _init(utxo: Utxo) -> void:
		_utxo = utxo

class UtxosAtAddressResult:
	var _address: Address
	var _asset: AssetClass
	var _utxos: Array[Utxo]
	
	func _init(address: Address, utxos: Array[Utxo], asset: AssetClass = null) -> void:
		_address = address
		_asset = asset
		_utxos = utxos

## Signal emitted by [method get_network_genesis].
signal got_network_genesis(genesis: NetworkGenesis)
## Signal emitted by [method get_protocol_parameters].
signal got_protocol_parameters(
	parameters: ProtocolParameters,
	cost_models: CostModels
)
## Signal emitted by [method _get_era_summaries].
signal got_era_summaries(summaries: Array[EraSummary])
## Signal emitted by [method _get_tx_status].
signal got_tx_status(status: TransactionStatus)
## Signal emitted by [method _get_utxos_at_address].
signal got_utxos_at_address(result: UtxosAtAddressResult)
## Signal emitted by [method _get_utxos_with_asset].
signal got_utxos_with_asset(result: UtxosWithAssetResult)
## Signal emitted by [method _get_utxo_by_out_ref].
signal got_utxo_by_out_ref(result: UtxoByOutRefResult)
signal _empty()

## The possible networks the [Provider] can run queries on or submit
## transactions to.
enum Network {MAINNET, PREVIEW, PREPROD, CUSTOM}

var network: Network

func _init() -> void:
	pass

## [b]WARNING: Virtual function.[/b][br]
##
## Get the Cardano network genesis parameters
func _get_network_genesis() -> NetworkGenesis:
	await _empty
	return null
	
## [b]WARNING: Virtual function.[/b][br]
##
## Get the latest protocol parameters
func _get_protocol_parameters() -> ProtocolParameters:
	await _empty
	return null

## [b]WARNING: Virtual function.[/b][br]
##
## Should return the full set of [Utxo]s at a [param _address], optionally holding a
## specified [param _asset].
func _get_utxos_at_address(_address: Address, _asset: AssetClass = null) -> Array[Utxo]:
	await _empty
	return []

## [b]WARNING: Virtual function.[/b][br]
##
## Should return the full set of [Utxo]s containing the specified [param _asset].
func _get_utxos_with_asset(_asset: AssetClass) -> Array[Utxo]:
	await _empty
	return []

## [b]WARNING: Virtual function.[/b][br]
##
## Should return the [Utxo] carrying the given [param _asset] with the assumption that
## it is unique in the ledger. Should return null if the asset does not currently
## exist.
func _get_utxo_with_nft(_asset: AssetClass) -> Utxo:
	await _empty
	return null

## [b]WARNING: Virtual function.[/b][br]
##
## Should return the transaction output with the given output reference.
## Ideally would return null if the output has been spent; currently this is not
## the behavior of the Blockfrost provider. 
func _get_utxo_by_out_ref(_tx_hash: TransactionHash, _output_index: int) -> Utxo:
	await _empty
	return null

## [b]WARNING: Virtual function.[/b][br]
##
## Should submit a [param tx] to the network and return a result indicating
## submission success or failure.
func _submit_transaction(tx: Transaction) -> SubmitResult:
	await _empty
	return SubmitResult.new(_Result.ok(tx.hash()))

## [b]WARNING: Virtual function.[/b][br]
##
## Should return the datum associated to the given [param _datum_hash].
## The datum is returned as a CBOR encoded byte array.
func _get_datum_cbor(_datum_hash: String) -> PackedByteArray:
	await _empty
	return PackedByteArray([])

## [b]WARNING: Virtual function.[/b][br]
##
## Should return the era summaries.
func _get_era_summaries() -> Array[EraSummary]:
	await _empty
	return []

## [b]WARNING: Virtual function.[/b][br]
##
## Should return the status of a submitted transaction, identified by its
## [param _tx_hash].
func _get_tx_status(_tx_hash: TransactionHash) -> bool:
	await _empty
	return false

## Helper function used for constructing a [UtxoDatumInfo].[br][br]
## A [UtxoDatumInfo] can either:[br]
## * Contain no datum[br]
## * Contain a datum hash[br]
## * Contain an inline datum[br][br]
## If [param datum_hash] is [code]""[/code] the result will have no datum. The
## other parameters are ignored.[br]
## If [param datum_inline_str] is not [code]""[/code], the result will have an
## inline datum set to it.[br]
## Otherwise, the result will contain the provided [param datum_hash]
## and, optionally, the [param datum_resolved_str] as the hashed data.
func _build_datum_info(
	datum_hash: String,
	datum_inline_str: String,
	datum_resolved_str: String,
) -> UtxoDatumInfo:
	if datum_hash == "":
		return UtxoDatumInfo.empty()
	elif datum_inline_str == "":
		if datum_resolved_str == "":
			return UtxoDatumInfo.create_with_hash(datum_hash)
		else:
			return UtxoDatumInfo.create_with_resolved_datum(datum_hash, datum_resolved_str)
	else:
		return UtxoDatumInfo.create_with_inline_datum(datum_hash, datum_inline_str)
