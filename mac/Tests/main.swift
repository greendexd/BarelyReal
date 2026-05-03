import Foundation

@MainActor
func runAllTests() -> Int32 {
    ProtocolEncodingTests.runAll()
    return TestRunner.shared.report()
}

exit(MainActor.assumeIsolated { runAllTests() })
