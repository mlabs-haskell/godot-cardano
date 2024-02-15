extends GutTest

func before_all():
	gut.p("Runs once before all tests.")

func before_each():
	gut.p("Runs before each test.")

func after_each():
	if not is_passing():
		gut.p("Test did not pass.")

func after_all():
	gut.p("Runs after all tests.")

# func test_assert_eq_number_not_equal():
# 	assert_eq(1, 2, "Should fail.  1 != 2")

func test_assert_eq_string_equal():
	assert_eq('asdf', 'asdf', "Should pass")

func test_assert_bigint_eq():
	var bigint_result = BigInt.from_str("1")
	assert_true(
		bigint_result.is_ok() and bigint_result.value.eq(BigInt.one()),
		"BigInt.from_int(1) should equal Bigint.one()"
	)

class TestSomeAspects:
	extends GutTest

	# func test_assert_eq_number_not_equal():
	# 	assert_eq(1, 2, "Should fail.  1 != 2")

	func test_assert_eq_string_equal():
		assert_eq('asdf', 'asdf', "Should pass")

class TestOtherAspects:
	extends GutTest

	func test_assert_true_with_true():
		assert_true(true, "Should pass, true is true")
