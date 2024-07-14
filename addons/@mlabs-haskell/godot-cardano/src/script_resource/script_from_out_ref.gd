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
