extends RefCounted

class_name MultiAsset

var _multi_asset: _MultiAsset

enum Status { 
	SUCCESS = 0,
	COULD_NOT_EXTRACT_POLICY_ID = 1,
	COULD_NOT_EXTRACT_ASSET_NAME = 2,
	COULD_NOT_DECODE_HEX = 3,
	INVALID_ASSET_NAME = 4,
	OTHER_ERROR = 5
}

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

static func empty() -> MultiAsset:
	return new(_MultiAsset.empty())

func quantity_of_asset(asset: AssetClass) -> BigInt:
	return BigInt.new(_multi_asset._quantity_of_asset(
		asset._policy_id._policy_id,
		asset._asset_name._asset_name
	))

func set_asset_quantity(asset: AssetClass, quantity: BigInt) -> Result:
	return Result.new(_multi_asset._set_asset_quantity(
		asset._policy_id._policy_id,
		asset._asset_name._asset_name,
		quantity._b
	))

func to_dictionary() -> Dictionary:
	var _dictionary := _multi_asset._to_dictionary()
	for key: String in _dictionary:
		_dictionary[key] = BigInt.new(_dictionary[key] as _BigInt)
	return _dictionary
