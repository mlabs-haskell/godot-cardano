class_name TxComplete
extends Node

var _cardano: Cardano = null
var _transaction: Transaction = null

func _init(cardano: Cardano, transaction: Transaction) -> void:
	_cardano = cardano
	_transaction = transaction

func sign(password: String) -> void:
	_transaction.add_signature(_cardano.wallet._sign_transaction(password, _transaction))

func submit() -> void:
	_cardano.provider._submit_transaction(_transaction)
	
func bytes() -> PackedByteArray:
	return _transaction.bytes()
