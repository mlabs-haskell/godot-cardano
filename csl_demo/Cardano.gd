extends Node

class_name Cardano

## This signal is emitted shortly after getting the protocol parameters from the
## blockchain, after object initialization.
signal got_tx_builder(initialized: bool)

## This signal is emitted after a wallet is set
signal got_wallet

var provider: Provider
var wallet: Wallet
var tx_builder: TxBuilder

func _init(provider_: Provider) -> void:
	self.provider = provider_
	self.wallet = null
	self.tx_builder = null
	add_child(provider)
	if provider.got_protocol_parameters.connect(_on_got_protocol_parameters) == ERR_INVALID_PARAMETER:
		push_error("Failed to connect provider's 'got_protocol_parameters' signal ")

func _ready() -> void:
	@warning_ignore("redundant_await")
	var _params := await provider.get_protocol_parameters()

func _on_got_protocol_parameters(params: ProtocolParameters) -> void:
	var result := TxBuilder.create(params)
	match result.tag():
		TxBuilder.Status.SUCCESS:
			tx_builder = result.value
			got_tx_builder.emit()
		TxBuilder.Status.BAD_PROTOCOL_PARAMETERS:
			push_error("Failed to initialize tx_builder: bad protocol parameters", result.error)

func send_lovelace_to(recipient: String, amount: BigInt) -> void:
	@warning_ignore("redundant_await")
	var change_address := await wallet.get_change_address()
	@warning_ignore("redundant_await")
	var utxos := await wallet.get_utxos()
	var total_lovelace := await wallet.total_lovelace()
	
	if amount.gt(total_lovelace):
		print("Error: not enough lovelace in wallet")
		return
		
	var transaction: Transaction = tx_builder.send_lovelace(recipient, change_address, amount, utxos)
	transaction.add_signature(wallet.sign_transaction(transaction))
	print(transaction.bytes().hex_encode())
	provider.submit_transaction(transaction.bytes())

# FIXME: Return a Result
func set_wallet_from_mnemonic(phrase_str: String) -> Wallet.MnemonicWallet:
	var result := PrivateKeyAccount.from_mnemonic(phrase_str)
	match result.tag():
		PrivateKeyAccount.Status.SUCCESS:
			var account := result.value
			self.wallet = Wallet.MnemonicWallet.new(account, self.provider)
			add_child(self.wallet)
			got_wallet.emit()
			return self.wallet
		_:
			push_error("Error found while creating wallet from mnemonic", result.error)
			return null
