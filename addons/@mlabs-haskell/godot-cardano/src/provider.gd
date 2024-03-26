extends Node

class_name Provider

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
	
func _get_protocol_parameters() -> ProtocolParameters:
	return null

func _get_utxos_at_address(_address: Address) -> Array[Utxo]:
	return []

func _submit_transaction(tx: Transaction) -> TransactionHash:
	return tx.hash()

func _get_era_summaries() -> Array[EraSummary]:
	await _empty
	return []

func _get_tx_status(tx_hash: TransactionHash) -> bool:
	return false
	
func await_response(f: Callable, check: Callable, s: Signal, interval: float = 2.5):	
	var timer := Timer.new()
	timer.one_shot = false
	timer.wait_time = interval
	timer.timeout.connect(f)
	add_child(timer)
	timer.start()
	while true:
		var r = await s
		if check.call(r):
			var connections: Array = timer.timeout.get_connections() 
			for c in connections:
				timer.timeout.disconnect(c['callable'])
			timer.stop()
			timer.start()
			await timer.timeout
			remove_child(timer)
			return
	
func await_tx(tx_hash: TransactionHash) -> void:
	print("Waiting for transaction %s..." % tx_hash.to_hex())
	await await_response(
		func () -> void: _get_tx_status(tx_hash),
		func (result: TransactionStatus) -> bool:
			return result._tx_hash == tx_hash and result._confirmed,
		tx_status
	)
	print("Transaction confirmed")

func await_utxos_at(address: Address, from_tx: TransactionHash = null) -> void:
	await await_response(
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
		5
	)
