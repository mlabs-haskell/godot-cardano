extends RefCounted

## A class that represents an arbitrary result from executing an operation. This
## class should never be used directly, it's only meant to be inherited from.

class_name Result

var _res : _Result

func _init(res: _Result) -> void:
	_res = res

## Returns true if the operation succeeded
func is_ok() -> bool:
	return _res.is_ok()

## Returns true if the operation failed
func is_err() -> bool:
	return _res.is_err()

## Returns a tag representing the status of the operation. This can
## be used in pattern matching.	Consult the [Status] enum of the class.
func tag() -> int:
	return _res.tag()

class Ok extends Result:
	var value: Variant:
		get: return _res.unsafe_value() as Variant
	
	func _init(value: Variant):
		super(_Result.ok(value))
	
class Err extends Result:
	var error: String:
		get: return _res.unsafe_error()
		
	func _init(err: String, tag: int):
		super(_Result.err(err, tag))

class VariantResult extends Result:
	## WARNING: This function may fail! First match on [Result_.tag] or call [Result_.is_ok].
	var value: Variant:
		get: return _res.unsafe_value()
	## WARNING: This function may fail! First match on [Result_.tag] or call [Result._is_err].
	var error: String:
		get: return _res.unsafe_error()
		
class ArrayResult extends Result:
	## WARNING: This function may fail! First match on [Result_.tag] or call [Result_.is_ok].
	var value: Array:
		get: return _res.unsafe_value() as Array
	## WARNING: This function may fail! First match on [Result_.tag] or call [Result._is_err].
	var error: String:
		get: return _res.unsafe_error()
		
static func sequence(results: Array[Result]) -> ArrayResult:
	var _results: Array = []
	for result: Result in results:
		if result.is_err():
			return ArrayResult.new(result.error)
		else:
			_results.push_back(result.value)
	return ArrayResult.new(_Result.ok(_results))
