extends Node2D

var cardano: Cardano
var wallet: Wallet.MnemonicWallet

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
@onready
var mint_token_button: Button = %MintTokenButton

func _ready() -> void:
	var token : String = FileAccess\
		.open("./preview_token.txt", FileAccess.READ)\
		.get_as_text(true)\
		.replace("\n", "")
	var provider: Provider = BlockfrostProvider.new(
		Provider.Network.NETWORK_PREVIEW,
		token
	)
	var seed_phrase_file := FileAccess.open("./seed_phrase.txt", FileAccess.READ)
	
	if seed_phrase_file != null:
		phrase_input.text = seed_phrase_file.get_as_text(true)
		
		var account_result := PrivateKeyAccount.from_mnemonic(phrase_input.text)
		
		if account_result.is_ok():
			var address_result := account_result.value.get_address_bech32()
			
			if address_result.is_ok():
				address_input.text = address_result.value
		
	cardano = Cardano.new(provider)
	add_child(cardano)
	
	# Connect signals to wallet details functions
	wallet_details.text = "No wallet set"
	var _ret := self.cardano.got_wallet.connect(_on_wallet_set)
	
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
	wallet_details.text = "Using wallet %s" % cardano.wallet._get_change_address().to_bech32()
	
func _on_utxos_updated(utxos: Array[Utxo]) -> void:
	var num_utxos := utxos.size()
	var total_lovelace : BigInt = utxos.reduce(
		func (acc: BigInt, utxo: Utxo) -> BigInt: return acc.add(utxo.coin()),
		BigInt.zero()
	)
	wallet_details.text = "Using wallet %s" % cardano.wallet._get_change_address().to_bech32()
	if num_utxos > 0:
		wallet_details.text += "\n\nFound %s UTxOs with %s lovelace" % [str(num_utxos), total_lovelace.to_str()]
		send_ada_button.disabled = false
		mint_token_button.disabled = false

func _on_set_wallet_button_pressed() -> void:
	wallet = cardano.set_wallet_from_mnemonic(phrase_input.text)

func _on_send_ada_button_pressed() -> void:
	var res: BigInt.ConversionResult = BigInt.from_str(amount_input.text)
	var amount := BigInt.zero()
	if res.is_ok():
		amount = res.value
	else:
		push_error("There was an error while parsing the amount as a BigInt", res.error)
	var address := Address.from_bech32(address_input.text)

	var tx: TxBuilder = cardano.new_tx()
	tx.pay_to_address(address, amount, {})
	var tx_complete: TxComplete = tx.complete()
	tx_complete.sign()
	tx_complete.submit()

func _on_mint_token_button_pressed() -> void:
	var address := Address.from_bech32(address_input.text)
	var tx: TxBuilder = cardano.new_tx()
	tx.mint_assets(
		PlutusScript.create("46010000222499".hex_decode()), 
		[ TxBuilder.MintToken.new("example token".to_utf8_buffer(), BigInt.one()) ],
		VoidData.new()
	)
	var tx_complete: TxComplete = tx.complete()
	tx_complete.sign()
	tx_complete.submit()
