extends RefCounted

class_name Utxo

var _utxo : _Utxo

func tx_hash() -> String:
	return _utxo.tx_hash

func output_index() -> int:
	return _utxo.output_index

func address() -> String:
	return _utxo.address

func coin() -> BigInt:
	return BigInt.new(_utxo.coin)

func assets() -> Dictionary:
	return _utxo.assets

func _init(tx_hash_: String, output_index_: int, address_: String, coin_: BigInt, assets_: Dictionary) -> void:
	_utxo = _Utxo.create(tx_hash_, output_index_, address_, coin_._b, assets_)
	

