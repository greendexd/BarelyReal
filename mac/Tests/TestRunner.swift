import Foundation

enum TestFailure: Error {
    case message(String)
}

@MainActor
final class TestRunner {
    static var shared = TestRunner()

    private(set) var passed = 0
    private(set) var failed: [(String, String)] = []

    func run(_ name: String, _ block: () throws -> Void) {
        do {
            try block()
            passed += 1
            print("  ✓ \(name)")
        } catch let TestFailure.message(msg) {
            failed.append((name, msg))
            print("  ✗ \(name) — \(msg)")
        } catch {
            failed.append((name, "threw \(error)"))
            print("  ✗ \(name) — threw \(error)")
        }
    }

    func report() -> Int32 {
        print("")
        print("Passed: \(passed)  Failed: \(failed.count)")
        return failed.isEmpty ? 0 : 1
    }
}

func expect(_ condition: @autoclosure () -> Bool, _ message: String, file: StaticString = #file, line: UInt = #line) throws {
    if !condition() {
        throw TestFailure.message("\(message) [\(file):\(line)]")
    }
}

func expectEqual<T: Equatable>(_ a: T, _ b: T, file: StaticString = #file, line: UInt = #line) throws {
    if a != b {
        throw TestFailure.message("expected \(b), got \(a) [\(file):\(line)]")
    }
}

func expectThrows<E: Error & Equatable>(_ expected: E, _ block: () throws -> Void, file: StaticString = #file, line: UInt = #line) throws {
    do {
        try block()
        throw TestFailure.message("expected throw \(expected), nothing thrown [\(file):\(line)]")
    } catch let err as E {
        if err != expected {
            throw TestFailure.message("expected \(expected), got \(err) [\(file):\(line)]")
        }
    } catch let other as TestFailure {
        throw other
    } catch {
        throw TestFailure.message("expected \(expected), got \(error) [\(file):\(line)]")
    }
}
