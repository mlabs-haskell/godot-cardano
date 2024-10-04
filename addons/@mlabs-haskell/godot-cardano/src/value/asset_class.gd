extends RefCounted
class_name AssetClass

## A pair of policy ID and asset name that uniquely identifies a particular asset

var _policy_id: PolicyId
var _asset_name: AssetName

func _init(policy_id: PolicyId, asset_name: AssetName) -> void:
	_policy_id = policy_id
	_asset_name = asset_name

## Result of [method from_unit]. It the operation succeeds, [member value] will
## contain an [AssetClass].
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

## Try to parse an [AssetClass] from a [String] containing the concatenation of
## the [PolicyId] and [AssetName] hex encodings.
static func from_unit(asset_unit: String) -> FromUnitResult:
	if asset_unit == "lovelace":
		asset_unit = ""
		
	return FromUnitResult.new(Result.sequence([
		PolicyId.from_hex(asset_unit.substr(0, 56)),
		AssetName.from_hex(asset_unit.substr(56,))
	]))

## Convert the [AssetClass] into a [String] containing the concatenation of the
## hex encoding of the [PolicyId] and [AssetName].
func to_unit() -> String:
	var policy_id = _policy_id.to_hex()
	var asset_name = _asset_name.to_hex()
	if policy_id == "" and asset_name == "":
		return "lovelace"
	return policy_id + asset_name
