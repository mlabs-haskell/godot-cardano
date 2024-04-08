extends Node2D

var provider: Provider
var cardano: Cardano = null
var wallet: Wallet.MnemonicWallet = null
var loader := SingleAddressWalletLoader.new()

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
@onready
var consume_script_input: Button = %ConsumeScriptInput
@onready
var set_button: Button = %SetButton

func _ready() -> void:
	var token : String = FileAccess\
		.open("./preview_token.txt", FileAccess.READ)\
		.get_as_text(true)\
		.replace("\n", "")
		
	provider = BlockfrostProvider.new(
		Provider.Network.PREVIEW,
		token
	)
	add_child(provider)
	add_child(loader)
	wallet_details.text = "No wallet set"
	
	# if a seed phrase file is available, we load the seed phrase from there
	var seed_phrase_file := FileAccess.open("./seed_phrase.txt", FileAccess.READ)
	if seed_phrase_file != null:
		phrase_input.text = seed_phrase_file.get_as_text(true)
		_create_wallet_from_seedphrase(phrase_input.text)
	
	# basic check for invertibility
	#var strict := true
	#var datum := ExampleDatum.new()
	#var bytes_result := Cbor.serialize(datum.to_data(strict), strict)
	#if bytes_result.is_ok():
		#var data_result := Cbor.deserialize(bytes_result.value)
		#
		#if data_result.is_ok():
			#var data := ExampleDatum.from_data(data_result.value)
			#print(datum)
			#print(data)

func _process(_delta: float) -> void:
	if wallet != null:
		timers_details.text = "Timer: %.2f" % wallet.time_left

func _on_wallet_set() -> void:
	var _ret := self.wallet.got_updated_utxos.connect(_on_utxos_updated)
	var addr := wallet._get_change_address().to_bech32()
	wallet_details.text = "Using wallet %s" % addr
	address_input.text = addr
	send_ada_button.disabled = false
	consume_script_input.disabled = false
	
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
	_create_wallet_from_seedphrase(phrase_input.text)

func _on_send_ada_button_pressed() -> void:
	var amount_result: BigInt.ConversionResult = BigInt.from_str(amount_input.text)
	
	if amount_result.is_err():
		push_error("There was an error while parsing the amount as a BigInt", amount_result.error)
		return
		
	var address_result := Address.from_bech32(address_input.text)
	
	if address_result.is_err():
		push_error("There was an error while parsing the address: %s", address_result.error)
		return
		
	var create_tx_result := cardano.new_tx()
	
	if create_tx_result.is_err():
		push_error("There was an error while creating the transaction: %s", create_tx_result.error)
		return
		
	var tx := create_tx_result.value
	tx.pay_to_address(
		address_result.value,
		amount_result.value,
		MultiAsset.from_dictionary({}).value
	)
	var result := await tx.complete()
	
	if result.is_ok():
		result.value.sign("1234")
		var tx_hash = await result.value.submit()
		if tx_hash == null:
			print('Failed to submit transaction')
		else:
			await provider.await_tx(tx_hash)
			print('Tx confirmed: %s' % tx_hash.to_hex())

func _on_mint_token_button_pressed() -> void:
	var address := Address.from_bech32(address_input.text)
	var create_tx_result := cardano.new_tx()
	
	if create_tx_result.is_err():
		push_error("There was an error while creating the transaction: %s", create_tx_result.error)
		return
		
	var tx := create_tx_result.value
	tx.mint_assets(
		PlutusScript.create("46010000222499".hex_decode()), 
		[ TxBuilder.MintToken.new("example token".to_utf8_buffer(), BigInt.one()) ],
		VoidData.new()
	)
	var result := await tx.complete()
	
	if result.is_ok():
		result.value.sign("1234")
		print(result.value._transaction.bytes().hex_encode())
		result.value.submit()
	
# Asynchronously load the wallet from a seedphrase
func _create_wallet_from_seedphrase(seedphrase: String) -> void:
	var old_text := set_button.text
	set_button.text = "Loading wallet..."
	set_button.disabled = true
	var res := await loader.import_from_seedphrase(
		seedphrase,
		"",
		"1234",
		0,
		"First account",
		"The first account created")
	if res.is_ok():
		var key_ring := res.value.wallet
		wallet = Wallet.MnemonicWallet.new(key_ring, provider)
		add_child(wallet)
		cardano = Cardano.new(wallet, provider)
		add_child(cardano)
		_on_wallet_set()
	else:
		push_error("Could not set wallet, found error", res.error)
	set_button.text = old_text
	set_button.disabled = false


func _on_create_script_output():
	var tx := cardano.new_tx()
	if tx.is_err():
		push_error("could not create tx_builder", tx.error)
		return
		
	var script_addr := Address.from_bech32("addr_test1wz74sepyjkvmwxkcmvlz0eyjsqmczqshwl5gr78aej0jvtcgqmvtm")
	
	if script_addr.is_err():
		push_error("something bad with address")
		return
	
	tx.value.pay_to_address_with_datum(script_addr.value, BigInt.from_int(5_000_000), MultiAsset.empty(), VoidData.new())
	
	var result : TxBuilder.CompleteResult = await tx.value.complete()

	if result.is_err():
		print("Could not complete transaction", result.error)
		return
		
	if result.is_ok():
		result.value.sign("1234")
		print(result.value._transaction.bytes().hex_encode())
		var hash := await result.value.submit()
		print("Transaction hash:", hash.value.to_hex())
	
func _on_consume_script_input_pressed():
	var utxos := await provider._get_utxos_at_address(Address.from_bech32("addr_test1wz74sepyjkvmwxkcmvlz0eyjsqmczqshwl5gr78aej0jvtcgqmvtm").value)
	
	var utxos_filtered = utxos.filter(func(u: Utxo): return u.datum_info().has_datum())
	
	var tx_result := cardano.new_tx()
	if tx_result.is_err():
		push_error("could not create tx_builder", tx_result.error)
		return
	
	var tx = tx_result.value
	tx.collect_from_script(
		PlutusScriptSource.from_script(
			PlutusScript.create("581b0100003222253330043330043370e900124008941288a4c2cae681".hex_decode())
		),
		utxos_filtered,
		PackedByteArray([0x80])
	)
	var result : TxBuilder.CompleteResult = await tx.complete()
	
	if result.is_err():
		print("Could not complete transaction", result.error)
		return 
		
	if result.is_ok():
		result.value.sign("1234")
		print(result.value._transaction.bytes().hex_encode())
		var hash := await result.value.submit()
		#print("Transaction hash:", hash.value.to_hex())
