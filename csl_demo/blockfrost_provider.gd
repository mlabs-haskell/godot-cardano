class_name BlockfrostProvider
extends Provider

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

const network_endpoints: Dictionary = {
	Network.MAINNET: "https://cardano-mainnet.blockfrost.io/api/v0",
	Network.PREVIEW: "https://cardano-preview.blockfrost.io/api/v0",
	Network.PREPROD: "https://cardano-preprod.blockfrost.io/api/v0"
}

var network: Network
var api_key: String

func _init(network: Network, api_key: String) -> void:
	self.network = network
	self.api_key = api_key

func _get_protocol_parameters() -> ProtocolParameters:
	var params_json: Dictionary = await blockfrost_request(ProtocolParametersRequest.new(LatestEpoch.new()))
	# FIXME: find a better way to type JSON responses
	var params := ProtocolParameters.create(
		int(str(params_json["coins_per_utxo_size"])),
		int(str(params_json["pool_deposit"])),
		int(str(params_json["key_deposit"])),
		int(str(params_json["max_val_size"])),
		int(str(params_json["max_tx_size"])),
		int(str(params_json["min_fee_b"])),
		int(str(params_json["min_fee_a"]))
	)
	self.got_protocol_parameters.emit(params)
	return params

func _get_utxos_at_address(address: String) -> Array[Utxo]:
	var utxos_json: Array = await blockfrost_request(UtxosAtAddressRequest.new(address))
	var utxos: Array[Utxo] = []
	
	utxos.assign(
		utxos_json.map(
			func (utxo: Dictionary) -> Utxo:
				var assets: Dictionary = utxo_assets(utxo)
				var coin: BigInt = assets['lovelace']
				assets.erase('lovelace')
				return Utxo.create(
					str(utxo.tx_hash),
					int(str(utxo.tx_index)), 
					str(utxo.address),
					coin,
					assets
				))
	)
	
	return utxos
	
func _submit_transaction(tx_cbor: PackedByteArray) -> void:
	blockfrost_request(SubmitTransactionRequest.new(tx_cbor))

func utxo_assets(utxo: Dictionary) -> Dictionary:
	var assets: Dictionary = {}
	var amount: Array = utxo.amount
	amount.map(
		func(asset: Dictionary) -> void:
			assets[asset.unit] = BigInt.from_str(str(asset.quantity))
	)
	return assets

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
		push_warning("Blockfrost request failed: ", status)
		remove_child(http_request)
		return {}

	var result: Array = await http_request.request_completed
	remove_child(http_request)
	
	var body: PackedByteArray = result[3]
	# TODO: handle error responses properly
	if result[1] != 200:
		push_warning("Blockfrost request failed: ", body.get_string_from_utf8())
		return null
		
	return JSON.parse_string(body.get_string_from_utf8())
