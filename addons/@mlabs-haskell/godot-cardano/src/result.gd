extends RefCounted
class_name Result

## A result type which may hold either a value or an error
##
## A virtual class that represents an arbitrary result from executing an
## operation. This class should never be used directly, it's only meant to be
## inherited from.
##
## The [Result] type is inspired by the homonymous Rust datatype and the "Either"
## value that can be found in Haskell. It is widely used in godot-cardano to
## provide descriptive return values for operations that may fail.
##
## Any class extending [Result] will expose "value" and "error" members [b]that
## should only be accessed after validating whether the operation failed or not
## [/b]. To do this, [method is_ok] or [method is_err] can be used.
##
## Alternatively, a pattern match may be performed on on the value returned by
## [method tag]. All classes that expose operations which may fail, will also
## expose a "Status" enum that can be used to distinguish the different failure
## modes.

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

## Convert an [Array] of [Result]s into a [Result] containing either an [Array]
## with [b]all[/b] of the values or the first error found in the [Array].
static func sequence(results: Array[Result]) -> ArrayResult:
	var _results: Array = []
	for result: Result in results:
		if result.is_err():
			return ArrayResult.new(_Result.err(result.error, 1))
		else:
			_results.push_back(result.value)
	return ArrayResult.new(_Result.ok(_results))
