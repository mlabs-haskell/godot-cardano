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
