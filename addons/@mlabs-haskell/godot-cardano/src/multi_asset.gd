extends RefCounted

class_name MultiAsset

var _multi_asset: _MultiAsset

enum Status { SUCCESS = 0, BECH32_ERROR = 1 }

func _init(multi_asset: _MultiAsset):
	_multi_asset = multi_asset

class FromDictionaryResult extends Result:
	## WARNING: This function may fail! First match on [Result_.tag] or call [Result_.is_ok].
	var value: MultiAsset:
		get: return MultiAsset.new(_res.unsafe_value())
	## WARNING: This function may fail! First match on [Result_.tag] or call [Result._is_err].
	var error: String:
		get: return _res.unsafe_error()
		
static func from_dictionary(assets: Dictionary) -> FromDictionaryResult:
	return FromDictionaryResult.new(_MultiAsset._from_dictionary(assets))
