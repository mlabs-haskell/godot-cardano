class_name Cardano
extends _Cardano

var provider: Provider
var wallet: Wallet

func _init(provider: Provider) -> void:
	self.provider = provider
	self.wallet = null
	add_child(provider)
	provider.got_protocol_parameters.connect(_on_got_protocol_parameters)
	provider.got_era_summaries.connect(_on_got_era_summaries)

func _ready() -> void:
	provider._get_protocol_parameters()
	provider._get_era_summaries()

func _on_got_protocol_parameters(params: ProtocolParameters) -> void:
	set_protocol_parameters(params)

func _on_got_era_summaries(summaries: Array[Provider.EraSummary]) -> void:
	set_slot_config(
		summaries[-1]._start._time,
		summaries[-1]._start._slot,
		summaries[-1]._parameters._slot_length,
	)

func set_wallet_from_mnemonic(phrase: String) -> void:
	self.wallet = Wallet.MnemonicWallet.new(phrase, self.provider)
	add_child(self.wallet)

func new_tx() -> Tx:
	return Tx.new(self)
