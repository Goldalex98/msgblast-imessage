import AppKit
import XCTest
@testable import msgblastCore

final class CompanionSendScriptTests: XCTestCase {
    func test_sourceHasNoPlaceholdersAndTakesArgv() {
        let source = CompanionSendScript.source
        XCTAssertTrue(source.contains("on run argv"))
        XCTAssertTrue(source.contains("with timeout of 20 seconds"))
        XCTAssertFalse(source.contains("%@"))
        XCTAssertFalse(source.contains("\\("))
        XCTAssertEqual(source.components(separatedBy: "send messageText to targetChat").count - 1, 1)
        XCTAssertFalse(source.contains("activate"), "never brings Messages forward")
        XCTAssertFalse(source.contains("make new"), "never creates a chat")
        for code in ["9001", "9002", "9003", "9004", "9005"] { XCTAssertTrue(source.contains(code), code) }
    }

    @MainActor
    func test_sourceCompiles() throws {
        var error: NSDictionary?
        let script = try XCTUnwrap(NSAppleScript(source: CompanionSendScript.source))
        XCTAssertTrue(script.compileAndReturnError(&error), "Compile-only check failed: \(error?.description ?? "unknown")")
    }

    func test_argumentsLayout() throws {
        XCTAssertEqual(try CompanionSendScript.arguments(threadGUID: "iMessage;-;+15555550100",
                                                         handles: ["+15555550100"], text: "hi"),
                       ["iMessage;-;+15555550100", "1", "+15555550100", "hi"])
        XCTAssertEqual(try CompanionSendScript.arguments(threadGUID: "iMessage;+;chat123",
                                                         handles: ["a@example.com", "+15555550101", "+15555550102"],
                                                         text: "group text"),
                       ["iMessage;+;chat123", "3", "a@example.com", "+15555550101", "+15555550102", "group text"])
    }

    func test_badTargetRefused() {
        let bad: [(String, [String])] = [
            ("-iMessage;-;x", ["+15555550100"]), ("iMessage;-;x\n", ["+15555550100"]), ("iMessage\u{0};-;x", ["+1"]),
            ("", ["+15555550100"]), ("iMessage;-;x", []), ("iMessage;-;x", ["-e"]), ("iMessage;-;x", ["a\u{7}b"]),
            ("iMessage;-;x", [""]),
        ]
        for (guid, handles) in bad {
            XCTAssertThrowsError(try CompanionSendScript.arguments(threadGUID: guid, handles: handles, text: "hi"),
                                 "\(guid.debugDescription) \(handles)") { error in
                XCTAssertEqual(error as? CompanionSendScriptError, .badTarget)
            }
        }
        XCTAssertNoThrow(try CompanionSendScript.arguments(threadGUID: "iMessage;-;x", handles: ["+1"], text: "-x\n\"q\""))
    }

    func test_parse() {
        XCTAssertEqual(CompanionSendScript.parse("SUBMITTED\n"), .submitted)
        XCTAssertEqual(CompanionSendScript.parse("NOT_SUBMITTED:-1743"), .notSubmitted(code: -1743))
        XCTAssertEqual(CompanionSendScript.parse("NOT_SUBMITTED:9004\n"), .notSubmitted(code: 9004))
        XCTAssertEqual(CompanionSendScript.parse("UNCERTAIN:-1712"), .uncertain(code: -1712))
        XCTAssertEqual(CompanionSendScript.parse("UNCERTAIN:abc"), .unexpected)
        XCTAssertEqual(CompanionSendScript.parse(""), .unexpected)
        XCTAssertEqual(CompanionSendScript.parse("READY"), .unexpected)
    }

    func test_resultOfRunOutput() {
        XCTAssertEqual(CompanionSendScript.result(of: .output("SUBMITTED")), .submitted)
        XCTAssertEqual(CompanionSendScript.result(of: .timedOut), .timedOut)
        XCTAssertEqual(CompanionSendScript.result(of: .failedToStart), .failedToStart)
        XCTAssertEqual(CompanionSendScript.result(of: .exitNonZero), .exitNonZero)
    }

    /// Proves text reaches AppleScript as data: an echo script (no Messages) returns each argument unchanged.
    func test_runnerPassesArgvVerbatim() async {
        let echo = """
        on run argv
            set AppleScript's text item delimiters to "<SEP>"
            return argv as text
        end run
        """
        let texts = ["-x", "\" & (do shell script \"echo pwned\") & \"", "line1\nline2", "émoji 👍🏽", "back\\slash",
                     "-e", "--", "tab\there"]
        for text in texts {
            let out = await OsascriptRunner().run(source: echo, arguments: ["guid", text], timeout: 10)
            XCTAssertEqual(out, .output("guid<SEP>" + text), text.debugDescription)
        }
    }

    func test_runnerForcesUTF8Locale() {
        let env = OsascriptRunner.environment(base: ["LANG": "C", "LC_ALL": "C", "LC_CTYPE": "C", "HOME": "/h"])
        XCTAssertEqual(env["LANG"], "en_US.UTF-8")
        XCTAssertEqual(env["LC_ALL"], "en_US.UTF-8")
        XCTAssertEqual(env["LC_CTYPE"], "en_US.UTF-8")
        XCTAssertEqual(env["HOME"], "/h")
    }

    func test_runnerTimesOut() async {
        let started = Date()
        let out = await OsascriptRunner().run(source: "delay 10\nreturn \"late\"", arguments: [], timeout: 1)
        XCTAssertEqual(out, .timedOut)
        XCTAssertLessThan(Date().timeIntervalSince(started), 4)
    }

    func test_runnerReportsNonZeroExit() async {
        let out = await OsascriptRunner().run(source: "error \"boom\" number 42", arguments: [], timeout: 10)
        XCTAssertEqual(out, .exitNonZero)
    }
}
