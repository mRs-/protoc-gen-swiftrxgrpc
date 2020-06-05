import XCTest

import protoc_gen_swiftrxgrpcTests

var tests = [XCTestCaseEntry]()
tests += protoc_gen_swiftrxgrpcTests.allTests()
XCTMain(tests)
