extends Node2D

var cardano: Cardano

func _ready():
	var token : String = FileAccess\
		.open("res://preview_token.txt", FileAccess.READ)\
		.get_as_text(true)\
		.replace("\n", "")
	print(token.c_escape())
	var provider: Provider = await BlockfrostProvider.new(
		Provider.Network.NETWORK_PREVIEW,
		token
	)
	cardano = Cardano.new(provider)
	add_child(cardano)

func _process(delta: float):
	if cardano.wallet != null and cardano.wallet.active:
		var utxos = await cardano.wallet.get_utxos()
		var num_utxos = utxos.size()
		var total_lovelace = utxos.reduce(
			func (acc, utxo): return acc.add(utxo.coin),
			BigInt.zero()
		)
		$WalletDetails.text = "Using wallet %s" % cardano.wallet.get_change_address()
		if num_utxos > 0:
			$WalletDetails.text += "\n\nFound %s UTxOs with %s lovelace" % [str(num_utxos), total_lovelace.to_str()]		
	else:
		$WalletDetails.text = "No wallet set"

func _on_set_wallet_button_pressed():
	cardano.set_wallet_from_mnemonic($SetWalletForm/MnemonicPhrase/Input.text)

func _on_send_ada_button_pressed():
	var address = $SendAdaForm/Recipient/Input.text
	var amount = BigInt.from_str($SendAdaForm/Amount/Input.text)
	
	cardano.send_lovelace_to(address, amount)
