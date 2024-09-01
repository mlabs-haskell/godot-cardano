extends ProviderApi
class_name BlockfrostProviderApi

## An implementation of [class ProviderApi] using the Blockfrost API.

enum ResultsOrder { ASCENDING, DESCENDING }

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
		_epoch = epoch
	
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
		var method_to_string := {
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
		
class GenesisRequest extends Request:
	func _url() -> String:
		return "genesis"
		
class ProtocolParametersRequest extends Request:
	var _epoch: Epoch
	
	func _init(epoch: Epoch) -> void:
		_epoch = epoch
	
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
		_address = address
		_page = page
		
	func _url() -> String:
		return "addresses/%s/utxos?page=%d" % [_address, _page]
		
class UtxosAtAddressWithAssetRequest extends Request:
	var _address: String
	var _asset_unit: String
	var _page: int
	
	func _init(address: String, asset_unit: String, page := 1) -> void:
		_address = address
		_asset_unit = asset_unit
		_page = page
		
	func _url() -> String:
		return "addresses/%s/utxos/%s?page=%d" % [_address, _asset_unit, _page]

class AssetsAddressesRequest extends Request:
	var _asset_unit: String
	var _page: int
	
	func _init(asset_unit: String, page := 1) -> void:
		_asset_unit = asset_unit
		_page = page
		
	func _url() -> String:
		return "assets/%s/addresses?page=%d" % [_asset_unit, _page]
		
class AssetTransactionsRequest extends Request:
	var _asset_unit: String
	var _page: int
	var _order: ResultsOrder
	
	func _init(asset_unit: String, page := 1, order := ResultsOrder.DESCENDING) -> void:
		_asset_unit = asset_unit
		_page = page
		_order = order
		
	func _url() -> String:
		return "assets/%s/transactions?page=%d&order=%s" % [
			_asset_unit,
			_page,
			"asc" if _order == ResultsOrder.ASCENDING else "desc"
		]
		
class AssetsOfPolicyRequest extends Request:
	var _policy_id: String
	var _page: int
	var _order: ResultsOrder
	
	func _init(policy_id: String, page := 1, order := ResultsOrder.DESCENDING) -> void:
		_policy_id = policy_id
		_page = page
		_order = order
		
	func _url() -> String:
		return "assets/policy/%s?page=%d&order=%s" % [
			_policy_id,
			_page,
			"asc" if _order == ResultsOrder.ASCENDING else "desc"
		]

class DatumCborFromHash extends Request:
	var _hash: String

	func _init(datum_hash: String) -> void:
		_hash = datum_hash

	func _url() -> String:
		return "scripts/datum/%s/cbor" % _hash

class ScriptInfoFromHash extends Request:
	var _hash: String

	func _init(script_hash: String) -> void:
		_hash = script_hash

	func _url() -> String:
		return "scripts/%s" % _hash
		
class ScriptCborFromHash extends Request:
	var _hash: String

	func _init(script_hash: String) -> void:
		_hash = script_hash

	func _url() -> String:
		return "scripts/%s/cbor" % _hash
		
class SubmitTransactionRequest extends Request:
	var _tx_cbor: PackedByteArray
	
	func _init(tx_cbor: PackedByteArray) -> void:
		_tx_cbor = tx_cbor
	
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
		_tx_cbor = tx_cbor
	
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
		_tx_hash = tx_hash

	func _url() -> String:
		return "txs/%s" % _tx_hash
		
class TransactionUtxosRequest extends Request:
	var _tx_hash: String
	
	func _init(tx_hash: String) -> void:
		_tx_hash = tx_hash

	func _url() -> String:
		return "txs/%s/utxos" % _tx_hash

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
		push_error("Creating Blockfrost request failed: %s, %s" % [status, request])
		http_request.queue_free()
		return null

	var result : Array = await http_request.request_completed
	var status_code : int = result[1]
	var content_bytes : PackedByteArray = result[3]
	var content := content_bytes.get_string_from_utf8()
	http_request.queue_free()
	
	# TODO: handle error responses properly
	if status_code != 200:
		# NOTE: return parsed content if response is expected to be handled,
		#		this may be phased out
		if status_code == 404 or status_code == 400:
			return JSON.parse_string(content)
		push_error("Blockfrost request failed with status code ", status_code, ". Response content: ")
		push_error(content)
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

func _get_network_genesis() -> NetworkGenesis:
	var genesis_json: Dictionary = await blockfrost_request(GenesisRequest.new())
	var genesis := NetworkGenesis.new(
		genesis_json.active_slots_coefficient as Variant as int,
		genesis_json.update_quorum as Variant as int,
		genesis_json.max_lovelace_supply as Variant as String,
		genesis_json.network_magic as Variant as int,
		genesis_json.epoch_length as Variant as int,
		genesis_json.system_start as Variant as int,
		genesis_json.slots_per_kes_period as Variant as int,
		genesis_json.slot_length as Variant as int,
		genesis_json.max_kes_evolutions as Variant as int,
		genesis_json.security_param as Variant as int,
	)
	self.got_network_genesis.emit(genesis)
	return genesis
	
func utxo_assets(utxo: Dictionary) -> Dictionary:
	var assets: Dictionary = {}
	var amount: Array = utxo.amount
	var _ret := amount.map(
		func(asset: Dictionary) -> void:
			var quantity: String = asset.quantity
			var res : BigInt.ConversionResult = BigInt.from_str(quantity)
			if res.is_ok():
				assets[asset.unit] = res.value
			else:
				push_error("There was an error while reading the assets from a utxo", res.error)
	)
	return assets

func _get_utxos_at_address(address: Address, asset: AssetClass = null) -> Array[Utxo]:
	var utxos_json: Array = await _paged_request(
		func (page: int) -> Request:
			if asset == null:
				return UtxosAtAddressRequest.new(address.to_bech32(), page) 
			else:
				return UtxosAtAddressWithAssetRequest.new(address.to_bech32(), asset.to_unit(), page)
	)
	var utxos := await _utxos_from_json(utxos_json)
	got_utxos_at_address.emit(UtxosAtAddressResult.new(address, utxos, asset))
	return utxos

func _get_asset_addresses(asset: AssetClass) -> Array[Address]:
	var addresses_json: Array = await _paged_request(
		func (page: int) -> Request:
			return AssetsAddressesRequest.new(asset.to_unit(), page)
	)
	var addresses: Array[Address] = []
	
	addresses.assign(addresses_json.map(
		func (address: Dictionary) -> Address:
			var result := Address.from_bech32(address.address as Variant as String)
			if result.is_err():
				push_error("Couldn't parse address: %s" % address.address)
				return null
			return result.value
	).filter(func (address: Address) -> bool: return address != null))
	return addresses

func _get_utxos_with_asset(asset: AssetClass) -> Array[Utxo]:
	var addresses := await _get_asset_addresses(asset)
	var utxos: Array[Utxo] = []
	
	for address: Address in addresses:
		var address_utxos = await _get_utxos_at_address(address, asset)
		utxos.append_array(address_utxos.filter(
			func (utxo: Utxo) -> bool:
				return utxo.assets().get_asset_quantity(asset).gt(BigInt.zero())
		))

	got_utxos_with_asset.emit(UtxosWithAssetResult.new(asset, utxos))
	return utxos
	
func _get_utxo_with_nft(asset: AssetClass) -> Utxo:
	var asset_unit = asset.to_unit()
	var assets := await blockfrost_request(
		AssetsOfPolicyRequest.new(asset._policy_id.to_hex(), 1, ResultsOrder.DESCENDING)
	)
	if assets.has("status_code"):
		return null
	var asset_entry = assets.filter(
		func (json: Dictionary): return json.asset == asset_unit and json.quantity == "1"
	)
	if asset_entry.is_empty():
		return null
	var transactions := await blockfrost_request(
		AssetTransactionsRequest.new(asset_unit, 1, ResultsOrder.DESCENDING)
	)
	if transactions.has("status_code"):
		return null
	var transaction_utxos := await blockfrost_request(
		TransactionUtxosRequest.new(transactions[0].tx_hash)
	)
	if transaction_utxos.has("status_code"):
		return null
	var utxos_filtered = transaction_utxos.outputs.filter(
		func (json): return json.amount.any(func (asset): return asset.unit == asset_unit)
	)
	if utxos_filtered.is_empty():
		return null
	var utxo_json = utxos_filtered[0]
	utxo_json['tx_hash'] = transactions[0].tx_hash
	var utxo = (await _utxos_from_json([utxo_json]))[0]
	got_utxos_with_asset.emit([UtxoByOutRefResult.new(utxo)])

	return utxo

func _get_utxo_by_out_ref(tx_hash: TransactionHash, output_index: int) -> Utxo:
	var response: Dictionary = await blockfrost_request(
		TransactionUtxosRequest.new(tx_hash.to_hex())
	)
	if response.has("status_code") or response.outputs.size() < output_index + 1:
		return null
	
	var utxo_json = response.outputs[output_index]
	# There may be better ways to handle this, but the structure of the outputs
	# here doesn't match the usual UTxO structure returned by Blockfrost
	utxo_json['tx_hash'] = tx_hash.to_hex()
	var utxo = (await _utxos_from_json([utxo_json]))[0]
	got_utxo_by_out_ref.emit(UtxoByOutRefResult.new(utxo))
	return utxo
	
func _paged_request(make_request: Callable, page_size := 100) -> Array:
	var results: Array = []
	var page := 1
	while true:
		var response: Variant = await blockfrost_request(make_request.call(page) as Request)
		if typeof(response) == TYPE_DICTIONARY and response['status_code'] == 404:
			break
		results.append_array(response as Array)
		if (response as Array).size() < page_size:
			break
		page += 1
	return results
	
func _utxos_from_json(utxos_json: Array) -> Array[Utxo]:
	var utxos: Array[Utxo] = []
	
	var data_map := {}
	var script_map := {}
	
	for utxo: Dictionary in utxos_json:
		var data_hash: String = "" if utxo.data_hash == null else utxo.data_hash
		var inline_datum_str: String = utxo.inline_datum if utxo.inline_datum != null else ""
		if inline_datum_str == "" and data_hash != "" and not data_map.has(data_hash):
			var resolve_result: Variant = await blockfrost_request(DatumCborFromHash.new(data_hash))
			if resolve_result.get('status_code', null) != 404 and resolve_result.has('cbor'):
				data_map[data_hash] = resolve_result.cbor
		
		var script_hash: String = "" if utxo.reference_script_hash == null else utxo.reference_script_hash
		if script_hash != "" and not script_map.has(script_hash):
			var info_result: Variant = await blockfrost_request(ScriptInfoFromHash.new(script_hash))
			var resolve_result: Variant = await blockfrost_request(ScriptCborFromHash.new(script_hash))
			if (info_result.get('status_code', null) != 404 and
				resolve_result.get('status_code', null) != 404 and
				resolve_result.has('cbor')):
				var cbor_hex: String = resolve_result.cbor
				if info_result.type == "plutusV1":
					# can't be used as a reference input, but might be useful as script storage?
					script_map[script_hash] = PlutusScript.create_v1(cbor_hex.hex_decode())
				if info_result.type == "plutusV2":
					script_map[script_hash] = PlutusScript.create(cbor_hex.hex_decode())
	
	utxos.assign(
		utxos_json.map(
			func (utxo: Dictionary) -> Utxo:
				var assets: Dictionary = utxo_assets(utxo)
				var coin: BigInt = assets['lovelace']
				var _erased := assets.erase('lovelace')
				var tx_hash: String = utxo.tx_hash
				var output_index: int = utxo.output_index
				var address: String = utxo.address
				var data_hash: String = "" if utxo.data_hash == null else utxo.data_hash
				var inline_datum_str: String = utxo.inline_datum if utxo.inline_datum != null else ""
				var resolved_datum_str: String = ""
				var script_ref: PlutusScript = null if utxo.reference_script_hash == null else script_map[utxo.reference_script_hash]
				
				if inline_datum_str == "" and data_hash != "" and data_map.has(data_hash):
					resolved_datum_str = data_map.get(data_hash)
					
				var datum_info := self._build_datum_info(data_hash, inline_datum_str, resolved_datum_str)
				
				var result := Utxo.create(
					tx_hash,
					output_index,
					address,
					coin.to_str(),
					assets,
					datum_info,
					script_ref
				)
				
				if result.is_err():
					push_error("Could not create UTxO: %s" % result.error)
					return null
				
				return result.value
	).filter(func (utxo: Utxo) -> bool: return utxo != null))
	return utxos

func _get_datum_cbor(datum_hash: String) -> PackedByteArray:
	var cbor_resp : Dictionary = await blockfrost_request(DatumCborFromHash.new(datum_hash))
	var cbor_hex : String = cbor_resp.cbor
	return cbor_hex.hex_decode()

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
	
func _submit_transaction(tx: Transaction) -> ProviderApi.SubmitResult:
	var result = await blockfrost_request(SubmitTransactionRequest.new(tx.bytes()))
	if typeof(result) == TYPE_DICTIONARY:
		return SubmitResult.new(_Result.err(result.message, ProviderStatus.SUBMIT_ERROR))
	elif typeof(result) == null:
		return SubmitResult.new(_Result.err("Unknown error while submitting", ProviderStatus.SUBMIT_ERROR))
	return SubmitResult.new(_Result.ok(TransactionHash.from_hex(result).value))

func _get_tx_status(tx_hash: TransactionHash) -> bool:
	var tx_response: Dictionary = await blockfrost_request(
		TransactionRequest.new(tx_hash.to_hex())
	)
	var status := TransactionStatus.new(
		tx_hash,
		tx_response.get('status_code', 200) == 200
	)
	got_tx_status.emit(status)
	return status._confirmed
