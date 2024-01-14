class_name Provider
extends Abstract

signal _empty()
signal got_protocol_parameters(parameters: ProtocolParameters)

enum Network {MAINNET, PREVIEW, PREPROD}

const _abstract_name := "Provider"

func _get_protocol_parameters() -> ProtocolParameters:
	await _empty
	return null

func _get_utxos_at_address(_address: String) -> Array[Utxo]:
	await _empty
	return []

func _submit_transaction(_tx_cbor: PackedByteArray) -> void:
	await _empty
