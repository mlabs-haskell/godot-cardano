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

func _ready() -> void:
	var token : String = FileAccess\
		.open("./preview_token.txt", FileAccess.READ)\
		.get_as_text(true)\
		.replace("\n", "")
	var provider: Provider = BlockfrostProvider.new(
		Provider.Network.NETWORK_PREVIEW,
		token
	)
	cardano = Cardano.new(provider)
	add_child(cardano)
	
	# Connect signals to wallet details functions
	wallet_details.text = "No wallet set"
	var _ret := self.cardano.got_wallet.connect(_on_wallet_set)
	
	var bytes := Cbor.from_variant(ExampleDatum.new().to_data()).value
	var data := Cbor.to_variant(bytes)
	print(data.value)

func _process(_delta: float) -> void:
	if wallet != null:
		timers_details.text = "Timer: %.2f" % wallet.time_left

func _on_wallet_set() -> void:
	var _ret := self.cardano.wallet.got_updated_utxos.connect(_on_utxos_updated)
	wallet_details.text = "Using wallet %s" % cardano.wallet._get_change_address().to_bech32()
	send_ada_button.disabled = false
	
func _on_utxos_updated(utxos: Array[Utxo]) -> void:
	var num_utxos := utxos.size()
	var total_lovelace : BigInt = utxos.reduce(
		func (acc: BigInt, utxo: Utxo) -> BigInt: return acc.add(utxo.coin()),
		BigInt.zero()
	)
	wallet_details.text = "Using wallet %s" % cardano.wallet._get_change_address().to_bech32()
	if num_utxos > 0:
		wallet_details.text += "\n\nFound %s UTxOs with %s lovelace" % [str(num_utxos), total_lovelace.to_str()]		

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
	print((await tx.complete())._transaction.bytes().hex_encode())
	tx.pay_to_address_with_datum(address, amount, {}, ExampleDatum.new())
	print((await tx.complete())._transaction.bytes().hex_encode())
	tx.mint_assets(
		PlutusScript.create("46010000222499".hex_decode()), 
		[ TxBuilder.MintToken.new("667788".hex_decode(), BigInt.one()) ],
		VoidData.new()
	)
	tx.mint_assets(
		PlutusScript.create("46010000222601".hex_decode()),
		[ TxBuilder.MintToken.new("8899aa".hex_decode(), BigInt.one()) ],
		VoidData.new()
	)
	var tx_complete: TxComplete = await tx.complete()
	tx_complete.sign()
	print(tx_complete._transaction.bytes().hex_encode())
	#tx_complete.submit()
