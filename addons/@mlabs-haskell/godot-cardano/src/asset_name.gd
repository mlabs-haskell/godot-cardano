extends RefCounted
class_name AssetName

var _asset_name: _AssetName

enum Status { SUCCESS = 0, COULD_NOT_DECODE_HEX = 1 }

func _init(asset_name: _AssetName):
	_asset_name = asset_name

class FromHexResult extends Result:
	## WARNING: This function may fail! First match on [Result_.tag] or call [Result_.is_ok].
	var value: AssetName:
		get: return AssetName.new(_res.unsafe_value())
	## WARNING: This function may fail! First match on [Result_.tag] or call [Result._is_err].
	var error: String:
		get: return _res.unsafe_error()
		
static func from_hex(hash: String) -> FromHexResult:
	return FromHexResult.new(_AssetName._from_hex(hash))
	
func to_hex() -> String:
	return _asset_name.to_hex()

func _to_string() -> String:
	return to_hex()
