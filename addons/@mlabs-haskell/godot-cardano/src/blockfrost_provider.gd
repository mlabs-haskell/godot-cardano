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
	
	func _init(epoch_: int) -> void:
		self.epoch = epoch_
	
	func url() -> String:
		return "epochs/%s/parameters" % (self.epoch if self.epoch != 0 else "latest")

class UtxosAtAddressRequest extends Request:
	var address: String
	
	func _init(address_: String) -> void:
		self.address = address_
		
	func url() -> String:
		return "addresses/%s/utxos" % self.address
		
class SubmitTransactionRequest extends Request:
	var tx_cbor: PackedByteArray
	
	func _init(tx_cbor_: PackedByteArray) -> void:
		self.tx_cbor = tx_cbor_
	
	func url() -> String:
		return "tx/submit"
		
	func method() -> HTTPClient.Method:
		return HTTPClient.METHOD_POST
		
	func headers() -> Array[String]:
		return ["content-type: application/cbor"]
		
	func body() -> PackedByteArray:
		return tx_cbor
		
var network: Network
var api_key: String

var current_epoch: int

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
		"%s/%s" % [network_endpoints[self.network], request.url()],
		[ "project_id: %s" % self.api_key ] + request.headers(),
		request.method(),
		request.body()
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

func get_protocol_parameters() -> ProtocolParameters:
	var params_json: Dictionary = await blockfrost_request(ProtocolParametersRequest.new(current_epoch))
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
		params_json.min_fee_a as Variant as int
	)
	self.got_protocol_parameters.emit(params)
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

func get_utxos_at_address(address: String) -> Array[Utxo]:
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
	
func submit_transaction(tx_cbor: PackedByteArray) -> void:
	blockfrost_request(SubmitTransactionRequest.new(tx_cbor))
