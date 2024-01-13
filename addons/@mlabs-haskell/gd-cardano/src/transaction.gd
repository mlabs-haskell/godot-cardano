extends RefCounted

class_name Transaction

var _tx: _Transaction

func _init(tx: _Transaction) -> void:
	_tx = tx
	
func bytes() -> PackedByteArray:
	return _tx.bytes()

func add_signature(signature: Signature) -> void:
	_tx.add_signature(signature)
