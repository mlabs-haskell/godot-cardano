class_name Tx
extends Node

var _cardano: Cardano
var _tx_builder: TxBuilder

func _init(cardano: Cardano) -> void:
	_cardano = cardano
	_tx_builder = TxBuilder.create(cardano)	

func pay_to_address(address: Address, coin: BigInt, assets: Dictionary) -> void:
	_tx_builder.pay_to_address(address, coin, assets)
	
func pay_to_address_with_datum(
	address: Address,
	coin: BigInt,
	assets: Dictionary,
	datum: Object
) -> void:
	_tx_builder.pay_to_address_with_datum(
		address,
		coin,
		assets,
		Datum.inline(Cbor.from_variant(datum.call("to_data")))
	)

func mint_assets(
	minting_policy: PlutusScript,
	tokens: Dictionary,
	redeemer: Object
) -> void:
	_tx_builder.mint_assets(
		minting_policy,
		tokens,
		Cbor.from_variant(redeemer.call("to_data"))
	)

func collect_from(utxos: Array[Utxo]) -> void:
	_tx_builder.collect_from(utxos)

func complete() -> TxComplete:
	var wallet_utxos := _cardano.wallet._get_utxos()
	var change_address := _cardano.wallet._get_change_address()
	var additional_utxos: Array[Utxo] = []
	var redeemers: Array[Redeemer] = await _cardano.provider._evaluate_transaction(
		_tx_builder.balance_and_assemble(wallet_utxos, change_address),
		wallet_utxos + additional_utxos
	)
	print(redeemers)
	return TxComplete.new(
		_cardano,
		_tx_builder.complete(
			wallet_utxos,
			change_address,
			redeemers
		)
	)
