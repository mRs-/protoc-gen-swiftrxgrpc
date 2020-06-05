import XCTest

#if !canImport(ObjectiveC)
public func allTests() -> [XCTestCaseEntry] {
    return [
        testCase(protoc_gen_swiftrxgrpcTests.allTests),
    ]
}
#endif
