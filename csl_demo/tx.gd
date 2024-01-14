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

func collect_from(utxos: Array[Utxo]) -> void:
	_tx_builder.collect_from(utxos)

func complete() -> TxComplete:
	return TxComplete.new(
		_cardano,
		_tx_builder.complete(
			_cardano.wallet._get_utxos(),
			_cardano.wallet._get_change_address()
		)
	)
