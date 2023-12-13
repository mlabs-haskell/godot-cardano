extends Provider

class_name BlockfrostProvider

class Request:
	func url() -> String:
		return ""
		
	func method() -> HTTPClient.Method:
		return HTTPClient.METHOD_GET
		
	func headers() -> Array[String]:
		return []
	
	func body() -> PackedByteArray:
		return PackedByteArray()
		
class ProtocolParametersRequest extends Request:
	var epoch: int = 0
	
	func _init(epoch: int):
		self.epoch = epoch
	
	func url():
		return "epochs/%s/parameters" % (self.epoch if self.epoch != 0 else "latest")

class UtxosAtAddressRequest extends Request:
	var address: String
	
	func _init(address: String):
		self.address = address
		
	func url():
		return "addresses/%s/utxos" % self.address
		
class SubmitTransactionRequest extends Request:
	var tx_cbor: PackedByteArray
	
	func _init(tx_cbor: PackedByteArray):
		self.tx_cbor = tx_cbor
	
	func url():
		return "tx/submit"
		
	func method():
		return HTTPClient.METHOD_POST
		
	func headers():
		return ["content-type: application/cbor"]
		
	func body():
		return tx_cbor
		
var network: Network
var api_key: String

var current_epoch: int

const network_endpoints: Dictionary = {
	Network.NETWORK_MAINNET: "https://cardano-mainnet.blockfrost.io/api/v0",
	Network.NETWORK_PREVIEW: "https://cardano-preview.blockfrost.io/api/v0",
	Network.NETWORK_PREPROD: "https://cardano-preprod.blockfrost.io/api/v0"
}

func _init(network: Network, api_key: String):
	self.network = network
	self.api_key = api_key
	
func _ready():
	pass

func _process(delta):
	pass
	
func blockfrost_request(request: Request) -> Variant:
	var http_request = HTTPRequest.new()
	add_child(http_request)
	
	var status = http_request.request_raw(
		"%s/%s" % [network_endpoints[self.network], request.url()],
		[ "project_id: %s" % self.api_key ] + request.headers(),
		request.method(),
		request.body()
	)
	
	if status != OK:
		print("Blockfrost request failed: ", status)
		remove_child(http_request)
		return {}

	var result = await http_request.request_completed
	remove_child(http_request)
	
	# TODO: handle error responses properly
	if result[1] != 200:
		print("Blockfrost request failed: ", result[3].get_string_from_utf8())
		return null
		
	return JSON.parse_string(result[3].get_string_from_utf8())

func get_protocol_parameters() -> ProtocolParameters:
	var params_json: Dictionary = await blockfrost_request(ProtocolParametersRequest.new(current_epoch))
	var params = ProtocolParameters.create(
		int(params_json["coins_per_utxo_size"]),
		int(params_json["pool_deposit"]),
		int(params_json["key_deposit"]),
		int(params_json["max_val_size"]),
		int(params_json["max_tx_size"]),
		int(params_json["min_fee_b"]),
		int(params_json["min_fee_a"])
	)
	self.got_protocol_parameters.emit(params)
	return params

func utxo_assets(utxo: Dictionary) -> Dictionary:
	var assets: Dictionary = {}
	utxo.amount.map(
		func(asset): assets[asset.unit] = BigInt.from_str(asset.quantity)
	)
	return assets

func get_utxos_at_address(address: String) -> Array[Utxo]:
	var utxos_json: Array = await blockfrost_request(UtxosAtAddressRequest.new(address))
	var utxos: Array[Utxo]
	
	utxos.assign(
		utxos_json.map(
			func (utxo) -> Utxo:
				var assets: Dictionary = utxo_assets(utxo)
				var coin: BigInt = assets['lovelace']
				assets.erase('lovelace')
				return Utxo.create(
					utxo.tx_hash,
					int(utxo.tx_index), 
					utxo.address,
					coin,
					assets
				))
	)
	
	return utxos
	
func submit_transaction(tx_cbor: PackedByteArray) -> void:
	blockfrost_request(SubmitTransactionRequest.new(tx_cbor))
