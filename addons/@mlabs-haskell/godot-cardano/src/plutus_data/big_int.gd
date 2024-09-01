@tool
extends PlutusData
class_name BigInt

## Integers of arbitrary size
##
## This class is used for representing both positive and negative integers of
## arbitrary size.
##
## You should not create a [BigInt] with [method new]. Instead you should use the
## static [method from_str] or [method from_int] conversion methods.
##
## Alternatively, you can use [method one] or [method zero] to get those
## numbers.

enum Status { SUCCESS = 0, COULD_NOT_PARSE_BIGINT = 1, COULD_NOT_DESERIALIZE_BIGINT = 2 }

var _b: _BigInt

@export
var value: String:
	get:
		return _b.to_str()
	set(v):
		var result = _BigInt._from_str(v)
		if result.is_ok():
			_b = result.unsafe_value()
		else:
			push_error("Could not parse BigInt: %s" % result.error)

func _init(b: _BigInt = _BigInt.zero()) -> void:
	_b = b

## Result of calling either [method from_str]. If the operation succeeds,
## [member value] will contain a valid [BigInt].
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

## Return 0
static func zero() -> BigInt:
	return BigInt.new(_BigInt.zero())

## Return 1
static func one() -> BigInt:
	return BigInt.new(_BigInt.one())
	
## Return the result of adding [param other].
func add(other: BigInt) -> BigInt:
	return BigInt.new(_b.add(other._b))

## Return the result of multiplying by [param other].
func mul(other: BigInt) -> BigInt:
	return BigInt.new(_b.mul(other._b))

## Check if is equal to [param other].
func eq(other: BigInt) -> bool:
	return _b.eq(other._b)

## Check if it is less than [param other].
func lt(other: BigInt) -> bool:
	return _b.lt(other._b)

## Check if it is greater than [param other].	
func gt(other: BigInt) -> bool:
	return _b.gt(other._b)

## Return the additive inverse.
func negate() -> BigInt:
	var str = to_str()
	if str[0] == "-":
		return BigInt.from_str(str.substr(1)).value
	else:
		return BigInt.from_str("-" + str).value

## Return the result of substracting [param other].
func sub(other: BigInt) -> BigInt:
	return self.add(other.negate())
	
## Convert to [String].
func to_str() -> String:
	return _b.to_str()

func to_int() -> int:
	return _b.to_str().to_int()

func _unwrap() -> Variant:
	return _b
	
func _to_string() -> String:
	return _b.to_str()

func format_price(quantity_decimals: float = 6, format_decimals: int = 2) -> String:
	return ("%." + str(format_decimals) + "f") % (float(to_string()) / pow(10, quantity_decimals))

func _to_json():
	return { "int": to_str() }
