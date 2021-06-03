import XCTest

#if !canImport(ObjectiveC)
    public func allTests() -> [XCTestCaseEntry] {
        return [
            testCase(RealtimeTests.allTests),
        ]
    }
#endif
