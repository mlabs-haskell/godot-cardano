extends Node

class_name Cardano

## This signal is emitted shortly after getting the protocol parameters from the
## blockchain, after object initialization.
signal got_tx_builder(initialized: bool)

var provider: Provider
var wallet: Wallet
var tx_builder: TxBuilder

func _init(wallet_: Wallet, provider_: Provider) -> void:
	self.provider = provider_
	self.wallet = wallet_
	self.tx_builder = null
	if provider.got_protocol_parameters.connect(_on_got_protocol_parameters) == ERR_INVALID_PARAMETER:
		push_error("Failed to connect provider's 'got_protocol_parameters' signal ")

func _ready() -> void:
	@warning_ignore("redundant_await")
	provider.get_protocol_parameters()

func _on_got_protocol_parameters(params: ProtocolParameters) -> void:
	var result := TxBuilder.create(params)
	match result.tag():
		TxBuilder.Status.SUCCESS:
			tx_builder = result.value
			got_tx_builder.emit()
		TxBuilder.Status.BAD_PROTOCOL_PARAMETERS:
			push_error("Failed to initialize tx_builder: bad protocol parameters", result.error)

func send_lovelace_to(password: String, recipient: String, amount: BigInt) -> void:
	@warning_ignore("redundant_await")
	var change_address := await wallet.get_change_address()
	@warning_ignore("redundant_await")
	var utxos := await wallet.get_utxos()
	var total_lovelace := await wallet.total_lovelace()
	
	if amount.gt(total_lovelace):
		print("Error: not enough lovelace in wallet")
		return
		
	var transaction: Transaction = tx_builder.send_lovelace(recipient, change_address, amount, utxos)
	transaction.add_signature(wallet.sign_transaction(password, transaction))
	provider.submit_transaction(transaction.bytes())
