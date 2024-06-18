extends RefCounted
class_name AssetClass

var _policy_id: PolicyId
var _asset_name: AssetName

func _init(policy_id: PolicyId, asset_name: AssetName) -> void:
	_policy_id = policy_id
	_asset_name = asset_name

class FromUnitResult extends Result:
	var _policy_id: PolicyId
	var _asset_name: AssetName
	
	## WARNING: This function may fail! First match on `tag` or call `is_ok`.
	var value: AssetClass:
		get: return AssetClass.new(_policy_id, _asset_name)
	## WARNING: This function may fail! First match on `tag` or call `is_err`.
	var error: String:
		get: return _res.unsafe_error()
	
	func _init(results: ArrayResult):
		super(results._res)
		
		if results.is_ok():
			_policy_id = results.value[0] as PolicyId
			_asset_name = results.value[1] as AssetName

static func from_unit(asset_unit: String) -> FromUnitResult:
	return FromUnitResult.new(Result.sequence([
		PolicyId.from_hex(asset_unit.substr(0, 56)),
		AssetName.from_hex(asset_unit.substr(56,))
	]))

func to_unit() -> String:
	return _policy_id.to_hex() + _asset_name.to_hex()
