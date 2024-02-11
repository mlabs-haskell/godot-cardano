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
	wallet_details.text = "No wallet set"
	
	# if a seed phrase file is available, we load the seed phrase from there
	var seed_phrase_file := FileAccess.open("./seed_phrase.txt", FileAccess.READ)
	if seed_phrase_file != null:
		phrase_input.text = seed_phrase_file.get_as_text(true)
		_create_wallet_from_seedphrase(phrase_input.text)
	
	# basic check for invertibility
	var strict := true
	var datum := ExampleDatum.new()
	var bytes_result := Cbor.serialize(datum.to_data(strict), strict)
	if bytes_result.is_ok():
		var data_result := Cbor.deserialize(bytes_result.value)
		
		if data_result.is_ok():
			var data := ExampleDatum.from_data(data_result.value)
			print(datum)
			print(data)

func _process(_delta: float) -> void:
	if wallet != null:
		timers_details.text = "Timer: %.2f" % wallet.time_left

func _on_wallet_set() -> void:
	var _ret := self.cardano.wallet.got_updated_utxos.connect(_on_utxos_updated)
	var addr := cardano.wallet.get_change_address().to_bech32()
	wallet_details.text = "Using wallet %s" % addr
	address_input.text = addr
	send_ada_button.disabled = false
	
func _on_utxos_updated(utxos: Array[Utxo]) -> void:
	var num_utxos := utxos.size()
	var total_lovelace : BigInt = utxos.reduce(
		func (acc: BigInt, utxo: Utxo) -> BigInt: return acc.add(utxo.coin()),
		BigInt.zero()
	)
	wallet_details.text = "Using wallet %s" % cardano.wallet.get_change_address().to_bech32()
	if num_utxos > 0:
		wallet_details.text += "\n\nFound %s UTxOs with %s lovelace" % [str(num_utxos), total_lovelace.to_str()]		

func _on_set_wallet_button_pressed() -> void:
	_create_wallet_from_seedphrase(phrase_input.text)

func _on_send_ada_button_pressed() -> void:
	var res: BigInt.ConversionResult = BigInt.from_str(amount_input.text)
	var amount := BigInt.zero()
	if res.is_ok():
		cardano.send_lovelace_to("1234", address_input.text, res.value)
		amount = res.value
	else:
		push_error("There was an error while parsing the amount as a BigInt", res.error)
	var address := Address.from_bech32(address_input.text)
		
	var tx: TxBuilder = cardano.new_tx()
	tx.pay_to_address_with_datum(address, amount, {}, ExampleDatum.new())
	var tx_complete: TxComplete = tx.complete()
	tx_complete.sign("1234")
	print(tx_complete._transaction.bytes().hex_encode())
	tx_complete.submit()
	
func _create_wallet_from_seedphrase(seedphrase: String) -> void:
	var res := SingleAddressWalletStore.import_from_seedphrase(
		seedphrase,
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
