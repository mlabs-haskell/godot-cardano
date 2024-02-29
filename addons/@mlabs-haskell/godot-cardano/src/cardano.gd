extends Node

class_name Cardano

## This signal is emitted shortly after getting the protocol parameters from the
## blockchain, after object initialization.
signal got_tx_builder(initialized: bool)

var provider: Provider
var wallet: Wallet
var _protocol_params: ProtocolParameters
var _era_summaries: Array[Provider.EraSummary]

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

func _on_got_protocol_parameters(params: ProtocolParameters) -> void:
	_protocol_params = params
	
func _on_got_era_summaries(summaries: Array[Provider.EraSummary]) -> void:
	_era_summaries = summaries
		
func new_tx() -> TxBuilder:
	var builder: TxBuilder = TxBuilder.create(self, _protocol_params).value
	return builder

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
