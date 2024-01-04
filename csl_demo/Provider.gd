extends Node

class_name Provider

enum Network {NETWORK_MAINNET, NETWORK_PREVIEW, NETWORK_PREPROD}

func _init() -> void:
	pass
	
func get_protocol_parameters() -> ProtocolParameters:
	return null

func get_utxos_at_address(_address: String) -> Array[Utxo]:
	return []

func submit_transaction(_tx_cbor: PackedByteArray) -> void:
	pass

signal got_protocol_parameters(parameters: ProtocolParameters)
