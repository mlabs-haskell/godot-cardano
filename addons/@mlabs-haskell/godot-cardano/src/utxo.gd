extends RefCounted
## An unspent transaction output (UTxO)
##
## This class is used for representing Cardano's UTxOs, specifically their
## identifying attributes (TX hash and output index) but also other useful
## information such as the [Address], [MultiAsset] value and datum information
## ([UtxoDatumInfo]) which can be very useful in TX tracking and building
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

## Get the [TransactionHash] of the transaction that produced this [Utxo].
func tx_hash() -> TransactionHash:
	return TransactionHash.new(_utxo.tx_hash)
	
## Get any datum information contained in this output.
func datum_info() -> UtxoDatumInfo:
	return _utxo.datum_info

## Get the index of this specific output in the transaction that produced it.
func output_index() -> int:
	return _utxo.output_index

## Get the [Address] that locks this output.
func address() -> Address:
	return Address.new(_utxo.address)

## Get the amount of Lovelace locked in this output.
func coin() -> BigInt:
	return BigInt.new(_utxo.coin)

## Get all the assets (and respective quantities) locked in this output.
func assets() -> MultiAsset:
	return MultiAsset.new(_utxo.assets)

## Construct a [Utxo] by providing its [param tx_hash], [param output_index] and
## other ancillary information.
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
	
## WARNING: This is for internal use. Use the [method create] method to safely
## construct a [Utxo].
func _init(utxo: _Utxo) -> void:
	_utxo = utxo
	

