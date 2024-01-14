extends Node2D

var cardano: Cardano

func _ready() -> void:
	var provider: Provider = BlockfrostProvider.new(
		Provider.Network.PREVIEW,
		"previewCBfdRYkHbWOga1ah6TXgHODuhCBi8SQJ"
	)
	cardano = Cardano.new(provider)
	add_child(cardano)

func update_wallet_display(utxos: Array[Utxo]) -> void:
	var wallet_details := $WalletDetails as RichTextLabel
	if cardano.wallet != null and cardano.wallet.active:
		var num_utxos := utxos.size()
		var total_lovelace: BigInt = utxos.reduce(
			func (acc: BigInt, utxo: Utxo) -> BigInt: return acc.add(utxo.coin),
			BigInt.zero()
		)
		wallet_details.text = "Using wallet %s" % cardano.wallet._get_change_address().to_bech32()
		if num_utxos > 0:
			wallet_details.text += "\n\nFound %s UTxOs with %s lovelace" % [str(num_utxos), total_lovelace.to_str()]		
	else:
		wallet_details.text = "No wallet set"

			
func _on_set_wallet_button_pressed() -> void:
	var mnemonic_input: TextEdit = $SetWalletForm/MnemonicPhrase/Input
	cardano.set_wallet_from_mnemonic(mnemonic_input.text)
	update_wallet_display([])
	cardano.wallet.utxos_updated.connect(update_wallet_display)

func _on_send_ada_button_pressed() -> void:
	var recipient_input: LineEdit = $SendAdaForm/Recipient/Input
	var amount_input: LineEdit = $SendAdaForm/Amount/Input
	var address := Address.from_bech32(recipient_input.text)
	var amount := BigInt.from_str(str(int(amount_input.text)/2))
	
	var tx: Tx = cardano.new_tx()
	tx.pay_to_address(address, amount, {})
	print(tx.complete()._transaction.bytes().hex_encode())
	tx.pay_to_address_with_datum(address, amount, {}, ExampleDatum.new())
	#print(tx.complete()._transaction.bytes().hex_encode())
	var tx_complete: TxComplete = tx.complete()
	tx_complete.sign()
	print(tx_complete._transaction.bytes().hex_encode())
	# tx_complete.submit()
