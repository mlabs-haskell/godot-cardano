extends Provider

class_name BlockfrostProvider

class Epoch extends Abstract:
	const _abstract_name := "Epoch"
	
	func _to_string() -> String:
		return ""
		
class LatestEpoch extends Epoch:
	func _init() -> void:
		pass
		
	func _to_string() -> String:
		return "latest"
	
class SpecificEpoch extends Epoch:
	var _epoch: int
	
	func _init(epoch: int) -> void:
		self._epoch = epoch
	
	func _to_string() -> String:
		return str(_epoch)
		
class Request:
	func _url() -> String:
		push_error("_url() virtual method called")
		return ""
		
	func _method() -> HTTPClient.Method:
		return HTTPClient.METHOD_GET
		
	func _headers() -> Array[String]:
		return []
	
	func _body() -> PackedByteArray:
		return PackedByteArray()
	
	func _to_string() -> String:
		var method_to_string = {
			HTTPClient.METHOD_GET: 'GET',
			HTTPClient.METHOD_HEAD: 'HEAD',
			HTTPClient.METHOD_POST: 'POST',
			HTTPClient.METHOD_PUT: 'PUT',
			HTTPClient.METHOD_DELETE: 'DELETE',
			HTTPClient.METHOD_OPTIONS: 'OPTIONS',
			HTTPClient.METHOD_TRACE: 'TRACE',
			HTTPClient.METHOD_CONNECT: 'CONNECT',
			HTTPClient.METHOD_PATCH: 'PATCH'
		}
		return "%s %s" % [method_to_string[_method()], _url()]
		
class ProtocolParametersRequest extends Request:
	var _epoch: Epoch
	
	func _init(epoch: Epoch) -> void:
		self._epoch = epoch
	
	func _url() -> String:
		return "epochs/%s/parameters" % _epoch

class EraSummariesRequest extends Request:
	func _init() -> void:
		pass
	
	func _url() -> String:
		return "network/eras"

class UtxosAtAddressRequest extends Request:
	var _address: String
	var _page: int
	
	func _init(address: String, page := 1) -> void:
		self._address = address
		self._page = page
		
	func _url() -> String:
		return "addresses/%s/utxos?page=%d" % [self._address, self._page]

class DatumCborFromHash extends Request:
	var _hash: String

	func _init(datum_hash: String) -> void:
		self._hash = datum_hash

	func _url() -> String:
		return "scripts/datum/%s/cbor" % self._hash
		
class SubmitTransactionRequest extends Request:
	var _tx_cbor: PackedByteArray
	
	func _init(tx_cbor: PackedByteArray) -> void:
		self._tx_cbor = tx_cbor
	
	func _url() -> String:
		return "tx/submit"
		
	func _method() -> HTTPClient.Method:
		return HTTPClient.METHOD_POST
		
	func _headers() -> Array[String]:
		return ["content-type: application/cbor"]
		
	func _body() -> PackedByteArray:
		return _tx_cbor

class EvaluateTransactionRequest extends Request:
	var _tx_cbor: PackedByteArray
	
	func _init(tx_cbor: PackedByteArray) -> void:
		self._tx_cbor = tx_cbor
	
	func _url() -> String:
		return "utils/txs/evaluate"
	
	func _method() -> HTTPClient.Method:
		return HTTPClient.METHOD_POST
		
	func _headers() -> Array[String]:
		return ["content-type: application/cbor"]
		
	func _body() -> PackedByteArray:
		return _tx_cbor.hex_encode().to_ascii_buffer()

class TransactionRequest extends Request:
	var _tx_hash: String
	
	func _init(tx_hash: String) -> void:
		self._tx_hash = tx_hash

	func _url() -> String:
		return "txs/%s" % _tx_hash
	
var network: Network
var api_key: String

const network_endpoints: Dictionary = {
	Network.MAINNET: "https://cardano-mainnet.blockfrost.io/api/v0",
	Network.PREVIEW: "https://cardano-preview.blockfrost.io/api/v0",
	Network.PREPROD: "https://cardano-preprod.blockfrost.io/api/v0"
}

func _init(network_: Network, api_key_: String) -> void:
	self.network = network_
	self.api_key = api_key_

func blockfrost_request(request: Request) -> Variant:
	var http_request := HTTPRequest.new()
	add_child(http_request)
	
	var url := "%s/%s" % [network_endpoints[self.network], request._url()]

	var status := http_request.request_raw(
		url,
		[ "project_id: %s" % self.api_key ] + request._headers(),
		request._method(),
		request._body()
	)
	
	if status != OK:
		print("Creating Blockfrost request failed: %s, %s" % [status, request])
		remove_child(http_request)
		return null

	var result : Array = await http_request.request_completed
	var status_code : int = result[1]
	var content_bytes : PackedByteArray = result[3]
	var content := content_bytes.get_string_from_utf8()
	remove_child(http_request)
	
	# TODO: handle error responses properly
	if status_code != 200:
		if status_code == 404:
			return JSON.parse_string(content)
		print("Blockfrost request failed with status code ", status_code, ". Response content: ")
		print(content)
		return null

	return JSON.parse_string(content)

func _get_protocol_parameters() -> ProtocolParameters:
	var float_to_ten_millionths := func (x: float) -> int:
		var padded := str(x).pad_decimals(7)
		var point := padded.find(".")
		return int(padded.substr(0, point) + padded.substr(point + 1))
	
	var params_json: Dictionary = await blockfrost_request(ProtocolParametersRequest.new(LatestEpoch.new()))
	# Type hints and dictionaries don't interact well...
	# We have to cast the dictionary values to [Variant] before [int], otherwise
	# it will complain about the operation not being safe.
	var params := ProtocolParameters.create(
		params_json.coins_per_utxo_size as Variant as int,
		params_json.pool_deposit as Variant as int,
		params_json.key_deposit as Variant as int,
		params_json.max_val_size as Variant as int,
		params_json.max_tx_size as Variant as int,
		params_json.min_fee_b as Variant as int,
		params_json.min_fee_a as Variant as int,
		float_to_ten_millionths.call(params_json.price_mem),
		float_to_ten_millionths.call(params_json.price_step),
		params_json.collateral_percent as Variant as int,
		params_json.max_tx_ex_steps as Variant as int,
		params_json.max_tx_ex_mem as Variant as int,
	)
	var cost_models := CostModels.new(params_json.cost_models)
	self.got_protocol_parameters.emit(params, cost_models)
	return params

func utxo_assets(utxo: Dictionary) -> Dictionary:
	var assets: Dictionary = {}
	var amount: Array = utxo.amount
	var _ret := amount.map(
		func(asset: Dictionary) -> void:
			var quantity: String = asset.quantity
			var res : BigInt.ConversionResult = BigInt.from_str(quantity)
			if res.is_ok():
				# We have to return a [_BigInt] here because that is what the Rust code
				# expects. This should be fixed from the Rust side of things.
				assets[asset.unit] = res.value._b
			else:
				push_error("There was an error while reading the assets from a utxo", res.error)
	)
	return assets

func _get_utxos_at_address(address: Address) -> Array[Utxo]:
	var utxos_json: Array = []
	
	var page := 1
	while true:
		var utxos_response := await blockfrost_request(
			UtxosAtAddressRequest.new(address.to_bech32(), page)
		)
		if typeof(utxos_response) == TYPE_DICTIONARY and utxos_response['status_code'] == 404:
			utxo_result.emit(UtxoResult.new(address, []))
			return []
		utxos_json.append_array(utxos_response)
		if utxos_response.size() < 100:
			break
		page += 1
	
	var utxos: Array[Utxo] = []
	
	utxos.assign(
		utxos_json.map(
			func (utxo: Dictionary) -> Utxo:
				var assets: Dictionary = utxo_assets(utxo)
				var coin: BigInt = BigInt.new(assets['lovelace'] as Variant as _BigInt)
				var _erased := assets.erase('lovelace')
				var tx_hash: String = utxo.tx_hash
				var tx_index: int = utxo.tx_index
				var utxo_address: String = utxo.address
				var data_hash: String = "" if utxo.data_hash == null else utxo.data_hash
				var inline_datum_str: String = utxo.inline_datum if utxo.inline_datum != null else ""
				var datum_info := self._build_datum_info(data_hash, inline_datum_str)
				
				var result = Utxo.create(
					tx_hash,
					tx_index,
					utxo_address,
					coin.to_str(),
					assets,
					datum_info
				)
				
				if result.is_err():
					push_error("Could not create UTxO: %s" % result.error)
					return null
					
				return result.value
	))
	utxo_result.emit(UtxoResult.new(address, utxos))
	return utxos
	
func _build_datum_info(datum_hash: String, datum_inline_str: String) -> UtxoDatumInfo:
	if datum_hash == "":
		return UtxoDatumInfo.empty()
	elif datum_inline_str == "":
		return UtxoDatumInfo.create_with_hash(datum_hash)
	else:
		return UtxoDatumInfo.create_with_datum(datum_hash, datum_inline_str)

func _get_datum_cbor(_datum_hash: String) -> Cbor:
	var cbor_resp : Dictionary = await blockfrost_request(DatumCborFromHash.new(_datum_hash))
	var cbor_hex : String = cbor_resp.cbor
	var res := Cbor.deserialize(cbor_hex.hex_decode())
	return null

func _get_era_summaries() -> Array[EraSummary]:
	var summaries_json: Array = await blockfrost_request(EraSummariesRequest.new())
	var summaries: Array[EraSummary] = []
	summaries.assign(
		summaries_json.map(
			func (summary: Dictionary) -> EraSummary: 
				return EraSummary.new(
					EraTime.new(
						summary["start"]["time"] as Variant as int,
						summary["start"]["slot"] as Variant as int,
						summary["start"]["epoch"] as Variant as int
					),
					EraTime.new(
						summary["end"]["time"] as Variant as int,
						summary["end"]["slot"] as Variant as int,
						summary["end"]["epoch"] as Variant as int
					),
					EraParameters.new(
						summary["parameters"]["epoch_length"] as Variant as int,
						summary["parameters"]["slot_length"] as Variant as int,
						summary["parameters"]["safe_zone"] as Variant as int,
					)
				))
	)
	got_era_summaries.emit(summaries)
	return summaries
	
func _submit_transaction(tx: Transaction) -> TransactionHash:
	var result = await blockfrost_request(SubmitTransactionRequest.new(tx.bytes()))
	if typeof(result) == TYPE_DICTIONARY or result == null:
		return null
	return TransactionHash.from_hex(result).value

func _get_tx_status(tx_hash: TransactionHash) -> bool:
	var tx_response: Dictionary = await blockfrost_request(
		TransactionRequest.new(tx_hash.to_hex())
	)
	var status := TransactionStatus.new(
		tx_hash,
		tx_response.get('status_code', 200) == 200
	)
	tx_status.emit(status)
	return status._confirmed
