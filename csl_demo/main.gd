extends Node2D

var utxos: Array[Utxo] = []
var address = null
var total_lovelace = BigInt.zero()
var cardano: Cardano
	
# Called when the node enters the scene tree for the first time.
func _ready():
	var provider: Provider = await BlockfrostProvider.new(
		BlockfrostProvider.Network.PREVIEW,
		"previewCBfdRYkHbWOga1ah6TXgHODuhCBi8SQJ"
	)
	add_child(provider)
	cardano = Cardano.new(provider)
	cardano.set_wallet($Wallet)
	
# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	if address != null:
		$WalletDetails.text = "Using wallet %s" % address
		var num_utxos = utxos.size()
		if num_utxos > 0:
			$WalletDetails.text += "\n\nFound %s UTxOs with %s lovelace" % [str(num_utxos), total_lovelace.to_str()]		
	else:
		$WalletDetails.text = "No wallet set"
		
func _on_utxo_request_request_completed(result, response_code, headers, body):
	if response_code == 404:
		utxos = []
		return
		
	utxos.assign(
		JSON.parse_string(body.get_string_from_utf8()).filter(func (utxo): return utxo.amount.size() == 1).map(
			func (utxo) -> Utxo:
				return Utxo.create(
					utxo.tx_hash,
					int(utxo.tx_index), 
					utxo.address,
					utxo_lovelace(utxo),
					{}
				)
	))
	
	total_lovelace = utxos.reduce(func (acc, utxo): return acc.add(utxo.get_coin()), BigInt.zero())
	
func _on_submit_request_request_completed(result, response_code, headers, body):
	print(response_code, body.get_string_from_utf8())

func _on_set_wallet_button_pressed():
	$Wallet.set_from_mnemonic($SetWalletForm/MnemonicPhrase/Input.text)
	address = $Wallet.get_address_bech32();
	print("Getting utxos for " + address)
	$UTXORequest.request(
		"https://cardano-preview.blockfrost.io/api/v0/addresses/" + address + "/utxos",
		["project_id: previewCBfdRYkHbWOga1ah6TXgHODuhCBi8SQJ"]
	)

func utxo_lovelace(utxo: Dictionary) -> BigInt:
	return utxo.amount.reduce(
		func(acc, asset): 
			return acc.add(BigInt.from_str(asset.quantity) if asset.unit == "lovelace" else BigInt.zero()
		),
		BigInt.zero()
	)

func _on_send_ada_button_pressed():
	var address = $SendAdaForm/Recipient/Input.text
	var amount = BigInt.from_str($SendAdaForm/Amount/Input.text)
	
	if amount.gt(total_lovelace):
		print("Error: not enough lovelace in wallet")
		return
		
	var transaction_bytes: PackedByteArray = cardano.send_lovelace(address, amount, utxos)

	$SubmitRequest.request_raw(
		"https://cardano-preview.blockfrost.io/api/v0/tx/submit",
		["project_id: previewCBfdRYkHbWOga1ah6TXgHODuhCBi8SQJ",
		 "content-type: application/cbor"
		],
		HTTPClient.METHOD_POST,
		transaction_bytes
	)
