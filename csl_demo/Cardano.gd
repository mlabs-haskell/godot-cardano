extends _Cardano

class_name Cardano

var provider: Provider
var wallet: Wallet

func _init(provider: Provider):
	self.provider = provider
	self.wallet = null
	add_child(provider)
	provider.got_protocol_parameters.connect(_on_got_protocol_parameters)

func _ready():
	provider.get_protocol_parameters()

func _on_got_protocol_parameters(params: ProtocolParameters):
	set_protocol_parameters(params)

func send_lovelace_to(recipient: String, amount: BigInt):
	var change_address = await wallet.get_change_address()
	var utxos = await wallet.get_utxos()
	var total_lovelace = await wallet.total_lovelace()
	
	if amount.gt(total_lovelace):
		print("Error: not enough lovelace in wallet")
		return
		
	var transaction: Transaction = send_lovelace(recipient, change_address, amount, utxos)
	transaction.add_signature(wallet.sign_transaction(transaction))
	print(transaction.bytes().hex_encode())
	provider.submit_transaction(transaction.bytes())

func set_wallet_from_mnemonic(phrase: String):
	self.wallet = Wallet.MnemonicWallet.new(phrase, self.provider)
	add_child(self.wallet)
