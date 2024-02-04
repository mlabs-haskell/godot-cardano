extends RefCounted

class_name BigInt

## You should not create a [BigInt] with [BigInt.new].
## Instead you should use the [BigInt.from_str] or [BigInt.from_int] conversion
## methods. Alternatively, you can use [BigInt.one] or [BigInt.zero] to get those
## numbers.

enum Status { SUCCESS = 0, COULD_NOT_PARSE_BIGINT = 1, COULD_NOT_CONVERT_FROM_INT = 2 }

var _b: _BigInt

func _init(b: _BigInt) -> void:
	_b = b

class ConversionResult extends Result:
	## WARNING: This function may fail! First match on [Result_.tag] or call [Result_.is_ok].
	var value: BigInt:
		get: return BigInt.new(_res.unsafe_value() as _BigInt)
	## WARNING: This function may fail! First match on [Result_.tag] or call [Result._is_err].
	var error: String:
		get: return _res.unsafe_error()

## Create a [BigInt] by parsing a [String].
static func from_str(s: String) -> ConversionResult:
	return ConversionResult.new(_BigInt._from_str(s))
	
## Convert an [int] into a [BigInt].
static func from_int(n: int) -> BigInt:
	return new(_BigInt._from_int(n))

static func zero() -> BigInt:
	return BigInt.new(_BigInt.zero())
	
static func one() -> BigInt:
	return BigInt.new(_BigInt.one())
	
func add(other: BigInt) -> BigInt:
	return BigInt.new(_b.add(other._b))
	
func mul(other: BigInt) -> BigInt:
	return BigInt.new(_b.mul(other._b))
	
func eq(other: BigInt) -> bool:
	return _b.eq(other._b)
	
func lt(other: BigInt) -> bool:
	return _b.lt(other._b)
	
func gt(other: BigInt) -> bool:
	return _b.gt(other._b)
	
func to_str() -> String:
	return _b.to_str()

func to_data(_strict := false) -> Variant:
	return _b

func _to_string() -> String:
	return _b.to_str()
