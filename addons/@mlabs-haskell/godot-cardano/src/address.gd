extends RefCounted

class_name Address

var _address: _Address

enum Status { SUCCESS = 0, BECH32_ERROR = 1 }

func _init(address: _Address):
	_address = address
		
class ToBech32Result extends Result:
	## WARNING: This function may fail! First match on [Result_.tag] or call [Result_.is_ok].
	var value: String:
		get: return _res.unsafe_value()
	## WARNING: This function may fail! First match on [Result_.tag] or call [Result._is_err].
	var error: String:
		get: return _res.unsafe_error()
		
static func from_bech32(bech32: String) -> Address:
	return Address.new(_Address.from_bech32(bech32))
	
func to_bech32() -> String:
	var result = ToBech32Result.new(_address._to_bech32())
	match result.tag():
		Status.SUCCESS:
			return result.value
		_:
			push_error("An error was found while encoding an address as bech32", result.error)
			return ""
