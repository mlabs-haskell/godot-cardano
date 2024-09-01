extends RefCounted
class_name Utxo

## An unspent transaction output (UTxO)
##
## This class is used for representing Cardano's UTxOs, specifically their
## identifying attributes (TX hash and output index) but also other useful
## information such as the [Address], [MultiAsset] value and datum information
## ([UtxoDatumInfo]) which can be very useful in TX tracking and building

## WARNING: This is for internal use. Use the [method create] method to safely
## construct a [Utxo].
func _init(utxo: _Utxo) -> void:
	_utxo = utxo
	
class CreateResult extends Result:
	var _utxo: Utxo
	
	## WARNING: This function may fail! First match on `tag` or call `is_ok`.
	var value: Utxo:
		get: return _utxo
	## WARNING: This function may fail! First match on `tag` or call `is_err`.
	var error: String:
		get: return _res.unsafe_error()
	
	func _init(results: ArrayResult):
		super(results._res)

		if results.is_ok():
			_utxo = Utxo.new(
				_Utxo.create(
					(results.value[0] as TransactionHash)._transaction_hash,
					results.value[1],
					(results.value[2] as Address)._address,
					(results.value[3] as BigInt)._b,
					(results.value[4] as MultiAsset)._multi_asset,
					(results.value[5]),
					(results.value[6] as PlutusScript)
				)
			)

var _utxo : _Utxo

## Get the [TransactionHash] of the transaction that produced this [Utxo].
func tx_hash() -> TransactionHash:
	return TransactionHash.new(_utxo.tx_hash)

## Get any datum information contained in this output.
func datum_info() -> UtxoDatumInfo:
	return _utxo.datum_info

func datum() -> PlutusData:
	if not _utxo.datum_info.has_datum():
		return null
	var result := PlutusData.deserialize(datum_info().datum_value().unsafe_value().hex_decode())
	if result == null:
		push_error('Invalid datum for UTxO %s#%d' % [tx_hash().to_hex(), output_index()])
	return result

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
	datum_info: UtxoDatumInfo,
	script_ref: PlutusScript
) -> CreateResult:
	var results := Result.sequence([
		TransactionHash.from_hex(tx_hash),
		Result.Ok.new(output_index),
		Address.from_bech32(address),
		BigInt.from_str(coin),
		MultiAsset.from_dictionary(assets),
		Result.Ok.new(datum_info),
		Result.Ok.new(script_ref)
	])

	return CreateResult.new(results)

func _to_string() -> String:
	return """{
		transaction_hash: %s,
		output_index: %d,
		address: %s,
		coin: %s,
		assets: %s,
		datum: %s,
		ref_script: %s,
	}""" % [
		_utxo.tx_hash.to_hex(),
		_utxo.output_index,
		_utxo.address._to_bech32().unsafe_value(),
		_utxo.coin.to_str(),
		MultiAsset.new(_utxo.assets).to_dictionary(),
		datum().serialize().value.hex_encode() if datum() else null,
		null if _utxo.script_ref == null else _utxo.script_ref.hash_as_hex()
	]
	
func to_out_ref_string() -> String:
	return "%s#%d" % [_utxo.tx_hash.to_hex(), _utxo.output_index]

func to_script_source() -> PlutusScriptSource:
	if _utxo.script_ref == null:
		return null
	return PlutusScriptSource.from_ref(_utxo)
