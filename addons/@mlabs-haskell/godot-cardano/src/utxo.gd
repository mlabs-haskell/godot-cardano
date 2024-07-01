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
		
		if results.is_ok():
			_utxo = _Utxo.create(
				(results.value[0] as TransactionHash)._transaction_hash,
				results.value[1],
				(results.value[2] as Address)._address,
				(results.value[3] as BigInt)._b,
				(results.value[4] as MultiAsset)._multi_asset,
				(results.value[5])
			)
		
var _utxo : _Utxo

func tx_hash() -> TransactionHash:
	return TransactionHash.new(_utxo.tx_hash)

func datum_info() -> UtxoDatumInfo:
	return _utxo.datum_info

func datum() -> PlutusData:
	if not _utxo.datum_info.has_datum():
		return null
	var result := PlutusData.deserialize(datum_info().datum_value().unsafe_value().hex_decode())
	if result == null:
		push_error('Invalid datum for UTxO %s#%d' % [tx_hash().to_hex(), output_index()])
	return result

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
	assets: Dictionary,
	datum_info: UtxoDatumInfo
) -> CreateResult:
	var results := Result.sequence([
		TransactionHash.from_hex(tx_hash),
		Result.Ok.new(output_index),
		Address.from_bech32(address),
		BigInt.from_str(coin),
		MultiAsset.from_dictionary(assets),
		Result.Ok.new(datum_info)
	])
	
	return CreateResult.new(results)
	
func _init(utxo: _Utxo) -> void:
	_utxo = utxo

func _to_string() -> String:
	return """{
		transaction_hash: %s,
		output_index: %d,
		address: %s,
		coin: %s,
		assets: %s,
		datum: %s
	}""" % [
		_utxo.tx_hash.to_hex(),
		_utxo.output_index,
		_utxo.address._to_bech32().unsafe_value(),
		_utxo.coin.to_str(),
		MultiAsset.new(_utxo.assets).to_dictionary(),
		datum().serialize().value.hex_encode() if datum() else null
	]
	
func to_out_ref_string() -> String:
	return "%s#%d" % [_utxo.tx_hash.to_hex(), _utxo.output_index]
