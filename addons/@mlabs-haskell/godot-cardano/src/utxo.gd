extends RefCounted

class_name Utxo

class CreateResult extends Result:
	var _utxo: _Utxo
	
	## WARNING: This function may fail! First match on `tag` or call `is_ok`.
	var value: Utxo:
		get: return Utxo.new(_utxo)
	## WARNING: This function may fail! First match on `tag` or call `is_err`.
	var error: String:
		get: return _res.unsafe_error()
	
	func _init(results: ArrayResult):
		super(results._res)
		_utxo = _Utxo.create(
			(results.value[0] as TransactionHash)._transaction_hash,
			results.value[1],
			(results.value[2] as Address)._address,
			(results.value[3] as BigInt)._b,
			(results.value[4] as MultiAsset)._multi_asset,
		)
		
var _utxo : _Utxo

func tx_hash() -> TransactionHash:
	return TransactionHash.new(_utxo.tx_hash)

func output_index() -> int:
	return _utxo.output_index

func address() -> Address:
	return Address.new(_utxo.address)

func coin() -> BigInt:
	return BigInt.new(_utxo.coin)

func assets() -> MultiAsset:
	return MultiAsset.new(_utxo.assets)

static func create(
	tx_hash: String,
	output_index: int,
	address: String,
	coin: String,
	assets: Dictionary
) -> CreateResult:
	var results = Result.sequence([
		TransactionHash.from_hex(tx_hash),
		Result.Ok.new(output_index),
		Address.from_bech32(address),
		BigInt.from_str(coin),
		MultiAsset.from_dictionary(assets)
	])
	
	return CreateResult.new(results)
	
func _init(utxo: _Utxo) -> void:
	_utxo = utxo
	

