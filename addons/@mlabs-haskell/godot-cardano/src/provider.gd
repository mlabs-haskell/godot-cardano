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

signal got_protocol_parameters(
	parameters: ProtocolParameters,
	cost_models: CostModels
)
signal got_era_summaries(summaries: Array[EraSummary])
signal _empty()

enum Network {NETWORK_MAINNET, NETWORK_PREVIEW, NETWORK_PREPROD}

func _init() -> void:
	pass
	
func _get_protocol_parameters() -> ProtocolParameters:
	return null

func _get_utxos_at_address(_address: String) -> Array[Utxo]:
	return []

func _submit_transaction(_tx: Transaction) -> void:
	pass

func _get_era_summaries() -> Array[EraSummary]:
	await _empty
	return []
