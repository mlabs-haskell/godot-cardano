extends Node2D

var provider: Provider
@onready
var cardano: Cardano = null
@onready
var key_ring_store: SingleAddressWalletStore = null
@onready
var wallet: Wallet.MnemonicWallet = null

@onready
var wallet_details: RichTextLabel = %WalletDetails
@onready
var address_input: LineEdit = %AddressInput
@onready
var amount_input: LineEdit = %AmountInput
@onready
var phrase_input: TextEdit = %PhraseInput
@onready
var timers_details: Label = %WalletTimers
@onready
var send_ada_button: Button = %SendAdaButton

func _ready() -> void:
	var token : String = FileAccess\
		.open("./preview_token.txt", FileAccess.READ)\
		.get_as_text(true)\
		.replace("\n", "")
		
	provider = BlockfrostProvider.new(
		Provider.Network.NETWORK_PREVIEW,
		token
	)
	add_child(provider)
	
	# Connect signals to wallet details functions
	wallet_details.text = "No wallet set"

func _process(_delta: float) -> void:
	if wallet != null:
		timers_details.text = "Timer: %.2f" % wallet.time_left

func _on_wallet_set() -> void:
	var _ret := self.cardano.wallet.got_updated_utxos.connect(_on_utxos_updated)
	wallet_details.text = "Using wallet %s" % cardano.wallet.get_change_address()
	send_ada_button.disabled = false
	
func _on_utxos_updated(utxos: Array[Utxo]) -> void:
	var num_utxos := utxos.size()
	var total_lovelace : BigInt = utxos.reduce(
		func (acc: BigInt, utxo: Utxo) -> BigInt: return acc.add(utxo.coin()),
		BigInt.zero()
	)
	wallet_details.text = "Using wallet %s" % cardano.wallet.get_change_address()
	if num_utxos > 0:
		wallet_details.text += "\n\nFound %s UTxOs with %s lovelace" % [str(num_utxos), total_lovelace.to_str()]		

func _on_set_wallet_button_pressed() -> void:
	var res := SingleAddressWalletStore.import_from_seedphrase(
		phrase_input.text,
		"",
		"1234",
		0,
		"First account",
		"The first account created")
	if res.is_ok():
		key_ring_store = res.value.wallet_store
		var key_ring := res.value.wallet
		wallet = Wallet.MnemonicWallet.new(key_ring, provider)
		add_child(wallet)
		cardano = Cardano.new(wallet, provider)
		add_child(cardano)
		_on_wallet_set()
	else:
		push_error("Could not set wallet, found error", res.error)

func _on_send_ada_button_pressed() -> void:
	var address := address_input.text
	var res: BigInt.ConversionResult = BigInt.from_str(amount_input.text)
	if res.is_ok():
		cardano.send_lovelace_to("1234", address, res.value)
	else:
		push_error("There was an error while parsing the amount as a BigInt", res.error)
