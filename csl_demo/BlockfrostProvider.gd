extends Provider

class_name BlockfrostProvider

enum Network {MAINNET, PREVIEW, PREPROD}

class Request:
	func to_url():
		return ""
		
class ProtocolParametersRequest extends Request:
	var epoch: int = 0
	
	func _init(epoch: int):
		self.epoch = epoch
	
	func to_url():
		return "epochs/%s/parameters" % (self.epoch if self.epoch != 0 else "latest")

class UtxosAtAddressRequest extends Request:
	var address: String
	
	func _init(address: String):
		self.address = address
		
	func to_url():
		return "address/%s/utxos" % self.address
		
var network: Network
var api_key: String

var current_epoch: int

const network_endpoints: Dictionary = {
	Network.MAINNET: "https://cardano-mainnet.blockfrost.io/api/v0",
	Network.PREVIEW: "https://cardano-preview.blockfrost.io/api/v0",
	Network.PREPROD: "https://cardano-preprod.blockfrost.io/api/v0"
}

func _init(network: Network, api_key: String):
	self.network = network
	self.api_key = api_key
	
func _ready():
	pass

func _process(delta):
	pass
	
func blockfrost_request(request: Request) -> Dictionary:
	var http_request = HTTPRequest.new()
	add_child(http_request)
	
	var status = http_request.request(
		"%s/%s" % [network_endpoints[self.network], request.to_url()],
		[ "project_id: %s" % self.api_key ]
	)
	
	if status != OK:
		print("Blockfrost request failed: ", status)
		remove_child(http_request)
		return {}

	var result = await http_request.request_completed
	remove_child(http_request)
	return JSON.parse_string(result[3].get_string_from_utf8())

func get_parameters():
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
	self.got_parameters.emit(params)
