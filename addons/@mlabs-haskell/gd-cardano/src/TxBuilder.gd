extends RefCounted

class_name TxBuilder

## You should not create a [TxBuilder] with [TxBuilder.new], instead
## you should use [TxBuilder.create].

enum Status { SUCCESS = 0, BAD_PROTOCOL_PARAMETERS = 1 }

var _builder: _TxBuilder

func _init(builder: _TxBuilder) -> void:
	self._builder = builder
	
class CreateResult extends Result:
	## WARNING: This function may fail! First match on `tag` or call `is_ok`.
	var value: TxBuilder:
		get: return TxBuilder.new(_res.unsafe_value() as _TxBuilder)
	## WARNING: This function may fail! First match on `tag` or call `is_err`.
	var error: String:
		get: return _res.unsafe_error()

## Create a TxBuilder object from a ProtocolParameters. This action may fail.
static func create(params: ProtocolParameters) -> CreateResult:
	var res : CreateResult = CreateResult.new(_TxBuilder._create(params))
	return res
	
func send_lovelace(recipient_bech32: String, change_address_bech32: String, amount: BigInt, gutxos: Array[Utxo]) -> Transaction:
	var gutxos_: Array[_Utxo] = []
	gutxos_.assign(gutxos.map(func(utxo: Utxo) -> _Utxo: return utxo._utxo) as Array[_Utxo])
		
	var _tx : _Transaction = _builder.send_lovelace(
		recipient_bech32,
		change_address_bech32,
		amount._b,
		gutxos_)

	return Transaction.new(_tx)

	
