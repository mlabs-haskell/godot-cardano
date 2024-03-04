extends Node

class_name Cardano

## This signal is emitted shortly after getting the protocol parameters from the
## blockchain, after object initialization.
signal got_tx_builder(initialized: bool)

var provider: Provider
var wallet: Wallet
var _protocol_params: ProtocolParameters
var _era_summaries: Array[Provider.EraSummary]
var _cost_models: CostModels

func _init(wallet_: Wallet, provider_: Provider) -> void:
	self.provider = provider_
	self.wallet = wallet_
	if provider.got_protocol_parameters.connect(_on_got_protocol_parameters) == ERR_INVALID_PARAMETER:
		push_error("Failed to connect provider's 'got_protocol_parameters' signal ")
	if provider.got_era_summaries.connect(_on_got_era_summaries) == ERR_INVALID_PARAMETER:
		push_error("Failed to connect provider's 'got_era_summaries' signal ")

func _ready() -> void:
	provider._get_protocol_parameters()
	provider._get_era_summaries()

func _on_got_protocol_parameters(
	params: ProtocolParameters,
	cost_models: CostModels
) -> void:
	_protocol_params = params
	_cost_models = cost_models
		
func new_tx() -> TxBuilder:
	var builder: TxBuilder = TxBuilder.create(self, _protocol_params).value
	if _era_summaries.size() > 0:
		builder.set_slot_config(
			_era_summaries[-1]._start._time,
			_era_summaries[-1]._start._slot,
			_era_summaries[-1]._parameters._slot_length,
		)
	if _cost_models != null:
		builder.set_cost_models(_cost_models)
	return builder
	
func _on_got_era_summaries(summaries: Array[Provider.EraSummary]) -> void:
	_era_summaries = summaries

func send_lovelace_to(password: String, recipient: String, amount: BigInt) -> void:
	@warning_ignore("redundant_await")
	var change_address := await wallet._get_change_address()
	@warning_ignore("redundant_await")
	var utxos := await wallet._get_utxos()
	var total_lovelace := await wallet.total_lovelace()
	
	if amount.gt(total_lovelace):
		print("Error: not enough lovelace in wallet")
		return
		
	var builder := new_tx()
	builder.pay_to_address(Address.from_bech32(recipient), amount, {})
	var transaction := builder.complete()
	transaction.sign(password)
	print(transaction.bytes().hex_encode())
	transaction.submit()
