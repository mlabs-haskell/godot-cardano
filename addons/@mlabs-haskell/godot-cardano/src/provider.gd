extends Node

class_name Provider

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

enum Network {MAINNET, PREVIEW, PREPROD}

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

func _get_era_summaries() -> Array[EraSummary]:
	await _empty
	return []

func _get_tx_status(tx_hash: TransactionHash) -> bool:
	return false
	
func await_response(
	f: Callable,
	check: Callable,
	s: Signal,
	interval: float = 2.5,
	timeout := 60
):	
	var start := Time.get_ticks_msec()
	var timer := Timer.new()
	timer.one_shot = false
	timer.wait_time = interval
	timer.timeout.connect(f)
	add_child(timer)
	timer.start()
	var status := false
	while true:
		var r = await s
		status = status or check.call(r)
		if status or (Time.get_ticks_msec() - start) / 1000 > timeout:
			break
	var connections: Array = timer.timeout.get_connections() 
	for c in connections:
		timer.timeout.disconnect(c['callable'])
	timer.stop()
	remove_child(timer)
	return status
	
func await_tx(tx_hash: TransactionHash, timeout := 60) -> bool:
	print("Waiting for transaction %s..." % tx_hash.to_hex())
	var confirmed = await await_response(
		func () -> void: _get_tx_status(tx_hash),
		func (result: TransactionStatus) -> bool:
			return result._tx_hash == tx_hash and result._confirmed,
		tx_status,
		timeout
	)
	if confirmed:
		print("Transaction confirmed")
	return confirmed

func await_utxos_at(
	address: Address,
	from_tx: TransactionHash = null,
	timeout := 60
) -> bool:
	return await await_response(
		func () -> void: _get_utxos_at_address(address),
		func (result: UtxoResult) -> bool:
			var found_utxos = false
			if from_tx == null:
				found_utxos = result._utxos != []
			else:
				found_utxos = result._utxos.any(
					func (utxo: Utxo) -> bool:
						return utxo.tx_hash().to_hex() == from_tx.to_hex()
				)
			return result._address.to_bech32() == address.to_bech32() and found_utxos,
		utxo_result,
		5,
		timeout
	)
