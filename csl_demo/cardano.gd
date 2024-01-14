class_name Cardano
extends _Cardano

var provider: Provider
var wallet: Wallet

func _init(provider: Provider) -> void:
	self.provider = provider
	self.wallet = null
	add_child(provider)
	provider.got_protocol_parameters.connect(_on_got_protocol_parameters)

func _ready() -> void:
	provider._get_protocol_parameters()

func _on_got_protocol_parameters(params: ProtocolParameters) -> void:
	set_protocol_parameters(params)

func set_wallet_from_mnemonic(phrase: String) -> void:
	self.wallet = Wallet.MnemonicWallet.new(phrase, self.provider)
	add_child(self.wallet)

func new_tx() -> Tx:
	return Tx.new(self)
