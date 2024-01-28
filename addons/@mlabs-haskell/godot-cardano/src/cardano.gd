extends Node

class_name Cardano

## This signal is emitted shortly after getting the protocol parameters from the
## blockchain, after object initialization.
signal got_tx_builder(initialized: bool)

## This signal is emitted after a wallet is set
signal got_wallet

var provider: Provider
var wallet: Wallet
var _protocol_params: ProtocolParameters
var _era_summaries: Array[Provider.EraSummary]

func _init(provider_: Provider) -> void:
	self.provider = provider_
	self.wallet = null
	add_child(provider)
	if provider.got_protocol_parameters.connect(_on_got_protocol_parameters) == ERR_INVALID_PARAMETER:
		push_error("Failed to connect provider's 'got_protocol_parameters' signal ")
	if provider.got_era_summaries.connect(_on_got_era_summaries) == ERR_INVALID_PARAMETER:
		push_error("Failed to connect provider's 'got_era_summaries' signal ")

func _ready() -> void:
	@warning_ignore("redundant_await")
	var _params := await provider._get_protocol_parameters()
	var _summaries := await provider._get_era_summaries()

func _on_got_protocol_parameters(params: ProtocolParameters) -> void:
	_protocol_params = params
		
func new_tx() -> TxBuilder:
	var builder: TxBuilder = TxBuilder.create(self, _protocol_params).value
	if _era_summaries.size() > 0:
		builder.set_slot_config(
			_era_summaries[-1]._start._time,
			_era_summaries[-1]._start._slot,
			_era_summaries[-1]._parameters._slot_length,
		)
	return builder
	
func _on_got_era_summaries(summaries: Array[Provider.EraSummary]) -> void:
	_era_summaries = summaries

func send_lovelace_to(recipient: String, amount: BigInt) -> void:
	@warning_ignore("redundant_await")
	var change_address := await wallet._get_change_address()
	@warning_ignore("redundant_await")
	var utxos := await wallet._get_utxos()
	var total_lovelace := await wallet.total_lovelace()
	
	if amount.gt(total_lovelace):
		print("Error: not enough lovelace in wallet")
		return
		
	var builder = new_tx()
	builder.pay_to_address(Address.from_bech32(recipient), amount, {})
	var transaction = builder.complete()
	transaction.sign()
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
