class_name Provider
extends Abstract

signal _empty()
signal got_protocol_parameters(parameters: ProtocolParameters)
signal got_era_summaries(summaries: Array[EraSummary])

enum Network {MAINNET, PREVIEW, PREPROD}

const _abstract_name := "Provider"

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
	
func _get_protocol_parameters() -> ProtocolParameters:
	await _empty
	return null

func _get_utxos_at_address(_address: String) -> Array[Utxo]:
	await _empty
	return []

func _submit_transaction(_tx: Transaction) -> void:
	await _empty

func _evaluate_transaction(_tx: Transaction, _utxos: Array[Utxo]) -> Array[Redeemer]:
	await _empty
	return []

func _get_era_summaries() -> Array[EraSummary]:
	await _empty
	return []
