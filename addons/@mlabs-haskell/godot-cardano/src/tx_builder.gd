extends RefCounted

class_name TxBuilder

## You should not create a [TxBuilder] with [TxBuilder.new], instead
## you should use [TxBuilder.create].

enum Status { SUCCESS = 0, BAD_PROTOCOL_PARAMETERS = 1 }

var _builder: _TxBuilder
var _cardano: Cardano

func _init(cardano: Cardano, builder: _TxBuilder) -> void:
	_cardano = cardano
	_builder = builder
	
class CreateResult extends Result:
	var _cardano: Cardano
	
	## WARNING: This function may fail! First match on `tag` or call `is_ok`.
	var value: TxBuilder:
		get: return TxBuilder.new(_cardano, _res.unsafe_value() as _TxBuilder)
	## WARNING: This function may fail! First match on `tag` or call `is_err`.
	var error: String:
		get: return _res.unsafe_error()
		
	func _init(cardano: Cardano, res: _Result):
		_cardano = cardano
		super(res)

class MintToken:
	var _token_name: PackedByteArray
	var _quantity: BigInt
	
	func _init(token_name: PackedByteArray, quantity: BigInt):
		_token_name = token_name
		_quantity = quantity
		
## Create a TxBuilder object from a ProtocolParameters. This action may fail.
static func create(cardano: Cardano, params: ProtocolParameters) -> CreateResult:
	var res : CreateResult = CreateResult.new(cardano, _TxBuilder._create(params))
	return res

func pay_to_address(address: Address, coin: BigInt, assets: Dictionary) -> void:
	_builder.pay_to_address(address._address, coin._b, assets)
	
func pay_to_address_with_datum(
	address: Address,
	coin: BigInt,
	assets: Dictionary,
	datum: Object
) -> void:
	if !datum.has_method("to_data"):
		push_error("Provided datum does not implement `to_data`")
		return
	
	var encoded_datum := Cbor.serialize(datum.to_data(true), true)
	
	if encoded_datum.is_err():
		push_error("Encoding/serializing datum failed")
		return
		
	_builder.pay_to_address_with_datum(
		address._address,
		coin._b,
		assets,
		Datum.inline(encoded_datum.value)
	)

func collect_from(utxos: Array[Utxo]) -> void:
	_builder.collect_from(utxos)

func complete() -> TxComplete:
	var wallet_utxos: Array[_Utxo] = []
	var change_address := _cardano.wallet._get_change_address()
	var additional_utxos: Array[_Utxo] = []
	
	wallet_utxos.assign(
		_cardano.wallet._get_utxos().map(func (utxo: Utxo) -> _Utxo: return utxo._utxo)
	)
		
	return TxComplete.new(
		_cardano,
		Transaction.new(
			_builder.complete(
				wallet_utxos,
				change_address._address
			)
		)
	)
