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
	
	func _init(address: String) -> void:
		self._address = address
		
	func _url() -> String:
		return "addresses/%s/utxos" % self._address
		
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

var network: Network
var api_key: String

const network_endpoints: Dictionary = {
	Network.NETWORK_MAINNET: "https://cardano-mainnet.blockfrost.io/api/v0",
	Network.NETWORK_PREVIEW: "https://cardano-preview.blockfrost.io/api/v0",
	Network.NETWORK_PREPROD: "https://cardano-preprod.blockfrost.io/api/v0"
}

func _init(network_: Network, api_key_: String) -> void:
	self.network = network_
	self.api_key = api_key_
		
func blockfrost_request(request: Request) -> Variant:
	var http_request := HTTPRequest.new()
	add_child(http_request)
	
	var status := http_request.request_raw(
		"%s/%s" % [network_endpoints[self.network], request._url()],
		[ "project_id: %s" % self.api_key ] + request._headers(),
		request._method(),
		request._body()
	)
	
	if status != OK:
		print("Blockfrost request failed: ", status)
		remove_child(http_request)
		return {}

	var result : Array = await http_request.request_completed
	var status_code : int = result[1]
	var content_bytes : PackedByteArray = result[3]
	var content := content_bytes.get_string_from_utf8()
	remove_child(http_request)
	
	# TODO: handle error responses properly
	if status_code != 200:
		print("Blockfrost request failed: ", content)
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

func _get_utxos_at_address(address: String) -> Array[Utxo]:
	var utxos_json: Array = await blockfrost_request(UtxosAtAddressRequest.new(address))
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
				
				return Utxo.new(
					tx_hash,
					tx_index, 
					utxo_address,
					coin,
					assets
				))
	)
	
	return utxos

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
	
func _submit_transaction(tx: Transaction) -> void:
	blockfrost_request(SubmitTransactionRequest.new(tx.bytes()))
