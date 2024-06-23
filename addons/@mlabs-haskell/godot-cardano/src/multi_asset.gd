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
		
class SetAssetResult extends Result:
	## WARNING: This function may fail! First match on [Result_.tag] or call [Result_.is_ok].
	var value: Variant:
		get: return _res.unsafe_value()
	## WARNING: This function may fail! First match on [Result_.tag] or call [Result._is_err].
	var error: String:
		get: return _res.unsafe_error()

static func from_dictionary(assets: Dictionary) -> FromDictionaryResult:
	var unwrapped := {}
	for key in assets:
		unwrapped[key] = assets[key]._b
	return FromDictionaryResult.new(_MultiAsset._from_dictionary(unwrapped))

static func empty() -> MultiAsset:
	return new(_MultiAsset.empty())

func get_asset_quantity(asset: AssetClass) -> BigInt:
	return BigInt.new(_multi_asset._quantity_of_asset(
		asset._policy_id._policy_id,
		asset._asset_name._asset_name
	))

func set_asset_quantity(asset: AssetClass, quantity: BigInt) -> SetAssetResult:
	return SetAssetResult.new(_multi_asset._set_asset_quantity(
		asset._policy_id._policy_id,
		asset._asset_name._asset_name,
		quantity._b
	))
	
func add_asset(asset: AssetClass, quantity: BigInt) -> SetAssetResult:
	var prev := get_asset_quantity(asset)
	return SetAssetResult.new(_multi_asset._set_asset_quantity(
		asset._policy_id._policy_id,
		asset._asset_name._asset_name,
		quantity._b.add(prev._b)
	))

func merge(other: MultiAsset):
	var dict := other.to_dictionary()
	for key in dict:
		add_asset(AssetClass.from_unit(key).value, dict[key])

func to_dictionary() -> Dictionary:
	var _dictionary := _multi_asset._to_dictionary()
	for key: String in _dictionary:
		_dictionary[key] = BigInt.new(_dictionary[key] as _BigInt)
	return _dictionary

func duplicate() -> MultiAsset:
	return from_dictionary(to_dictionary()).value
