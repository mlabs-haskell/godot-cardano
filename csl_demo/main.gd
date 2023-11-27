extends Node2D

var utxos = []
var address = null
var total_lovelace = 0
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
			$WalletDetails.text += "\n\nFound %s UTxOs with %s lovelace" % [str(num_utxos), str(total_lovelace)]		
	else:
		$WalletDetails.text = "No wallet set"
		
func _on_utxo_request_request_completed(result, response_code, headers, body):
	if response_code == 404:
		utxos = []
		return
		
	utxos = JSON.parse_string(body.get_string_from_utf8()).filter(func (utxo): return utxo.amount.size() == 1)
	total_lovelace = utxos.reduce(utxo_lovelace, 0)
	
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

func utxo_lovelace(acc, utxo):
	return acc + utxo.amount.reduce(
		func(acc, asset): 
			return acc + (int(asset.quantity) if asset.unit == "lovelace" else 0
		),
		0
	)

func _on_send_ada_button_pressed():
	var address = $SendAdaForm/Recipient/Input.text
	var amount = int($SendAdaForm/Amount/Input.text)
	
	if amount > total_lovelace:
		print("Error: not enough lovelace in wallet")
		return
	
	var new_utxos = utxos.map(
		func (utxo):
			return Utxo.create(
				utxo.tx_hash,
				utxo.tx_index, 
				utxo.address,
				utxo_lovelace(0, utxo),
				{}
			)
	)
	var transaction_bytes: PackedByteArray = cardano.send_lovelace(address, amount, new_utxos)
	$SubmitRequest.request_raw(
		"https://cardano-preview.blockfrost.io/api/v0/tx/submit",
		["project_id: previewCBfdRYkHbWOga1ah6TXgHODuhCBi8SQJ",
		 "content-type: application/cbor"
		],
		HTTPClient.METHOD_POST,
		transaction_bytes
	)
