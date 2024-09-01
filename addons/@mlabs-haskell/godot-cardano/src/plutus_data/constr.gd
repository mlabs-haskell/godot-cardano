@tool
extends PlutusData
class_name Constr

## Sum and Product type constructor for Plutus data
##
## --- Introduction to algebraic types ---[br][br]
##
## Plutus supports the use of so called "sum types" and "product types". These
## are part of a more general concept called "Algebraic Data Types" (or ADTs
## for short).[br][br]
##
## Products are more common in programming languages, so we start with
## them. A product type is the "combination" of multiple types to create
## a larger one containing all of its constituents. These are normally known as
## "tuples", "structs" or even "classes" (but without any of the methods!).[br][br]
##
## In GDScript, the closest thing to product types are classes (though this might
## change soon with the inclusion of structs):[br][br]
## [codeblock]
## class StringAndInt:
##     var a_string: String
##     var an_int: int
## [/codeblock]
## [br][br]
## In the previous example, the class we defined was the product of type [String]
## and type [int]. The central characteristic of products is that [b]one can always decompose
## them into their constituents[/b], i.e: one can always get the [String] and [int]
## out of a "StringAndInt" class.[br][br]
##
## Sum types can also be described as a "combination" of other types. However, in contrast to
## products, [b]one can only extract a single component out of them[/b]. So the sum type
## that combines [String] and [int] would be called "String[b]Or[/b]Int". This SDK already uses
## sum types, like [Result], to encode different [b]exclusive[/b] possibilities [b]or choices[/b]. But sum types are
## not well supported by GDScript, so one must be careful not to try to extract the wrong
## component from a sum (since only one component can be extracted at any given time).
## In other languages, the language itself disallows access to the component
## without checking for its presence first (resulting in a static error).[br][br]
##
## --- How [Constr] works ---[br][br]
##
## Plutus supports both sums and products with a single type: [Constr]. A
## [Constr] (from constructor) is a "sum of products" (or SOP). As the name
## suggests, it is possibly many products combined in a sum.[br][br]
##
## The reason this works for representing pure sums and pure products is that:[br][br]
##
## * A pure product can be thought of as a sum with [i]one choice[/i], where that choice
##   is a product composed of possibly many types.[br]
## * A pure sum can be thought of as a sum with [i]possibly many choices[/i], where
##   all the choices are basic, non-product types.[br][br]
##
## And of course, any combination of sums and products that can be imagined
## is possible by nesting [Constr]s appropriately.[br][br]
##
## A [Constr] is built by providing an index (which represents the specific
## product selected) and an [Array] of fields (which represents the product
## itself). The index used for constructing a specific product is appropriately called
## "constructor".[br][br]
##
## --- Notes on ordering ---[br][br]
## 
## It may be obvious that the constructor index represents an ordered choice,
## and hence using a different index will create a different value:[br][br]
## [code]
## Constr.new(BigInt.zero(), x) /= Constr.new(BigInt.one(), x)
## [/code][br][br]
##
## But it is worth mentioning this is also the case when changing the order of the
## fields:[br][br]
## [code]
## Constr.new(BigInt.zero(), [x, y]) /= Constr.new(BigInt.zero(), [y, x])
## [/code][br][br]
##
## The order of the fields [b]does[/b] change the product, so this is something
## very important to keep in mind when trying to encode/decode values from the
## blockchain.
# TODO: Move the explanations above to a separate tutorial.

@export
var _constructor: BigInt
@export
var _fields: Array[PlutusData]

## A [Constr] takes [param constructor] parameter, which is the index of the
## constructor being used. The parameters of that constructor are passed in
## [param fields].
func _init(constructor: BigInt = null, fields: Array[PlutusData] = []):
	_constructor = constructor
	_fields = fields

func _unwrap() -> Variant:
	var unwrapped = _fields.map(func (v): return v._unwrap())
	return _Constr._create(_constructor._b, unwrapped)

func _to_string() -> String:
	return "Constr %s %s" % [_constructor, _fields]

## Get the constructor index.
func get_constructor() -> BigInt:
	return _constructor

## Get the fields of the product.
func get_fields() -> Array[PlutusData]:
	return _fields
	var _data: Constr
	
func _to_json():
	return {
		"constructor": _constructor.to_int(),
		"fields": _fields.map(func (x): return x.to_json())
	}
