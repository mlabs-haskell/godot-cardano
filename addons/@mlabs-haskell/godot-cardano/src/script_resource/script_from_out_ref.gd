@tool
class_name ScriptFromOutRef
extends ScriptResource

@export
var tx_hash: String
@export
var output_index: int
 
func _init(tx_hash: TransactionHash = null, output_index: int = 0) -> void:
	self.tx_hash = "" if tx_hash == null else tx_hash.to_hex()
	self.output_index = output_index

func _load_script(provider: Provider) -> PlutusScriptSource:
	var tx_hash_result := TransactionHash.from_hex(tx_hash)
	
	if tx_hash_result.is_ok():
		var utxo = await provider.get_utxo_by_out_ref(
			tx_hash_result.value,
			output_index
		)
		if utxo == null:
			push_error("Failed to get script from out ref: UTxO not found")
		else:
			var script_source = PlutusScriptSource.from_ref(utxo._utxo)
			if script_source == null:
				push_error("Failed to get script from out ref: UTxO has no script ref")
			return script_source
	else:
		push_error("Failed to get script from out ref: %s" % [tx_hash_result.error])
	return null
