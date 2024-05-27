extends Node

class_name ProviderApi

enum ProviderStatus { SUCCESS = 0, SUBMIT_ERROR = 1 }

class SubmitResult extends Result:
	## WARNING: This function may fail! First match on [Result_.tag] or call [Result_.is_ok].
	var value: TransactionHash:
		get: return _res.unsafe_value() as TransactionHash
	## WARNING: This function may fail! First match on [Result_.tag] or call [Result._is_err].
	var error: String:
		get: return _res.unsafe_error()

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
	):
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

class TransactionStatus:
	var _tx_hash: TransactionHash
	var _confirmed: bool
	
	func _init(tx_hash: TransactionHash, confirmed: bool) -> void:
		_tx_hash = tx_hash
		_confirmed = confirmed
	
	func set_confirmed(confirmed: bool) -> void:
		_confirmed = confirmed

class UtxoResult:
	var _address: Address
	var _utxos: Array[Utxo]
	
	func _init(address: Address, utxos: Array[Utxo]) -> void:
		_address = address
		_utxos = utxos

signal got_network_genesis(genesis: NetworkGenesis)
signal got_protocol_parameters(
	parameters: ProtocolParameters,
	cost_models: CostModels
)
signal got_era_summaries(summaries: Array[EraSummary])
signal tx_status(status: TransactionStatus)
signal utxo_result(result: UtxoResult)
signal _empty()

enum Network {MAINNET, PREVIEW, PREPROD, CUSTOM}

var network: Network

func _init() -> void:
	pass

func _get_network_genesis() -> NetworkGenesis:
	return null
	
func _get_protocol_parameters() -> ProtocolParameters:
	return null

func _get_utxos_at_address(_address: Address) -> Array[Utxo]:
	return []

func _submit_transaction(tx: Transaction) -> SubmitResult:
	return SubmitResult.new(_Result.ok(tx.hash()))

func _get_datum_cbor(_datum_hash: String) -> Cbor:
	return null

func _get_era_summaries() -> Array[EraSummary]:
	await _empty
	return []

func _get_tx_status(tx_hash: TransactionHash) -> bool:
	return false

