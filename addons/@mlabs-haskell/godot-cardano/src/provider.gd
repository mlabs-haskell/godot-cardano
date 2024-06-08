extends Node

class_name Provider

## This signal is emitted shortly after getting the protocol parameters from the
## blockchain, after object initialization.
signal got_tx_builder(initialized: bool)

var _provider_api: ProviderApi
var _network_genesis: ProviderApi.NetworkGenesis
var _protocol_params: ProtocolParameters
var _era_summaries: Array[ProviderApi.EraSummary]
var _cost_models: CostModels
		
func _init(provider_api: ProviderApi) -> void:
	_provider_api = provider_api
	if provider_api.got_network_genesis.connect(_on_got_network_genesis) == ERR_INVALID_PARAMETER:
		push_error("Failed to connect provider's 'got_network_genesis' signal ")
	if provider_api.got_protocol_parameters.connect(_on_got_protocol_parameters) == ERR_INVALID_PARAMETER:
		push_error("Failed to connect provider's 'got_protocol_parameters' signal ")
	if provider_api.got_era_summaries.connect(_on_got_era_summaries) == ERR_INVALID_PARAMETER:
		push_error("Failed to connect provider's 'got_era_summaries' signal ")

func _ready() -> void:
	_provider_api._get_network_genesis()
	_provider_api._get_protocol_parameters()
	_provider_api._get_era_summaries()

func _on_got_network_genesis(
	genesis: ProviderApi.NetworkGenesis
) -> void:
	_network_genesis = genesis

func _on_got_protocol_parameters(
	params: ProtocolParameters,
	cost_models: CostModels
) -> void:
	_protocol_params = params
	_cost_models = cost_models

func new_tx() -> TxBuilder.CreateResult:
	var create_result := await TxBuilder.create(self)
	if create_result.is_ok():
		var builder := create_result.value
		if _era_summaries.size() > 0:
			builder.set_slot_config(
				_era_summaries[-1]._start._time,
				_era_summaries[-1]._start._slot,
				_era_summaries[-1]._parameters._slot_length,
			)
		if _cost_models != null:
			builder.set_cost_models(_cost_models)
	return create_result
	
func _on_got_era_summaries(summaries: Array[ProviderApi.EraSummary]) -> void:
	_era_summaries = summaries

func time_to_slot(time: int) -> int:
	# FIXME: should return a `Result`?
	if _network_genesis == null:
		return -1

	for era in _era_summaries:
		var era_start_time := _network_genesis._system_start + era._start._time
		var era_end_time := _network_genesis._system_start + era._end._time
		if time > era_start_time and time < era_end_time:
			var time_in_era := time - era_start_time
			return time_in_era / era._parameters._slot_length + era._start._slot
	
	return -1

func get_protocol_parameters() -> ProtocolParameters:
	if _protocol_params == null:
		await _provider_api.got_protocol_parameters
	return _protocol_params

func submit_transaction(tx: Transaction) -> ProviderApi.SubmitResult:
	return await _provider_api._submit_transaction(tx)
	
func await_response(
	f: Callable,
	check: Callable,
	s: Signal,
	interval: float = 2.5,
	timeout := 60
):	
	var start := Time.get_ticks_msec()
	var timer := Timer.new()
	timer.one_shot = false
	timer.wait_time = interval
	timer.timeout.connect(f)
	add_child(timer)
	timer.start()
	var status := false
	while true:
		var r = await s
		status = status or check.call(r)
		if status or (Time.get_ticks_msec() - start) / 1000 > timeout:
			break
	var connections: Array = timer.timeout.get_connections() 
	for c in connections:
		timer.timeout.disconnect(c['callable'])
	timer.stop()
	timer.queue_free()
	return status
	
func await_tx(tx_hash: TransactionHash, timeout := 60) -> bool:
	print("Waiting for transaction %s..." % tx_hash.to_hex())
	var confirmed = await await_response(
		func () -> void: _provider_api._get_tx_status(tx_hash),
		func (result: ProviderApi.TransactionStatus) -> bool:
			return result._tx_hash == tx_hash and result._confirmed,
		_provider_api.tx_status,
		timeout
	)
	if confirmed:
		print("Transaction confirmed")
	return confirmed

func await_utxos_at(
	address: Address,
	from_tx: TransactionHash = null,
	timeout := 60
) -> bool:
	print("Waiting for UTxOs at %s..." % address.to_bech32())
	return await await_response(
		func () -> void: _provider_api._get_utxos_at_address(address),
		func (result: ProviderApi.UtxoResult) -> bool:
			var found_utxos = false
			if from_tx == null:
				found_utxos = result._utxos != []
			else:
				found_utxos = result._utxos.any(
					func (utxo: Utxo) -> bool:
						return utxo.tx_hash().to_hex() == from_tx.to_hex()
				)
			return result._address.to_bech32() == address.to_bech32() and found_utxos,
		_provider_api.utxo_result,
		5,
		timeout
	)

func make_address(payment_cred: Credential, stake_cred: Credential = null) -> Address:
	return Address.build(
		1 if _provider_api.network == ProviderApi.Network.MAINNET else 0,
		payment_cred,
		stake_cred
	)

func get_utxos_at_address(address: Address) -> Array[Utxo]:
	return await _provider_api._get_utxos_at_address(address)
