import Foundation

// iMessage companion (fork-only), phase 3. A fixed AppleScript that takes the thread, its participants and the
// text as `argv`, so nothing from a message is ever part of the script's source (send notes, Borrow 2). The
// identity checks follow the phase 0 send probe (spike c), which covered groups.

public enum CompanionSendScriptError: Error, Equatable { case badTarget }

public enum ScriptResult: Equatable, Sendable {
    case submitted, notSubmitted(code: Int), uncertain(code: Int), timedOut, failedToStart, exitNonZero, unexpected
}

public enum ScriptRunOutput: Equatable, Sendable { case output(String), timedOut, failedToStart, exitNonZero }

public protocol CompanionScriptRunning: Sendable {
    func run(source: String, arguments: [String], timeout: TimeInterval) async -> ScriptRunOutput
}

public enum CompanionSendScript {
    /// argv: thread GUID, participant count N, N handles, text (always last).
    public static let source = """
    on run argv
        set submissionAttempted to false
        try
            set argCount to count of argv
            if argCount < 4 then error "arguments" number 9005
            set targetID to item 1 of argv
            set expectedCount to (item 2 of argv) as integer
            if argCount is not (expectedCount + 3) then error "arguments" number 9005
            set expectedHandles to items 3 thru (2 + expectedCount) of argv
            set messageText to item argCount of argv
            with timeout of 20 seconds
                tell application "Messages"
                    set targetChat to chat id targetID
                    if (id of targetChat as text) is not targetID then error "identity" number 9001
                    if service type of account of targetChat is not iMessage then error "service" number 9003
                    set seen to {}
                    repeat with p in participants of targetChat
                        set end of seen to (handle of p as text)
                    end repeat
                    if (count of seen) is not expectedCount then error "count" number 9002
                    repeat with h in expectedHandles
                        if seen does not contain (h as text) then error "member" number 9004
                    end repeat
                    set submissionAttempted to true
                    send messageText to targetChat
                    return "SUBMITTED"
                end tell
            end timeout
        on error detail number code
            if submissionAttempted then return "UNCERTAIN:" & code
            return "NOT_SUBMITTED:" & code
        end try
    end run
    """

    public static func arguments(threadGUID: String, handles: [String], text: String)
        throws(CompanionSendScriptError) -> [String] {
        guard targetAllowed(threadGUID), !handles.isEmpty, handles.allSatisfy(targetAllowed) else { throw .badTarget }
        return [threadGUID, String(handles.count)] + handles + [text]
    }

    public static func parse(_ output: String) -> ScriptResult {
        let line = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if line == "SUBMITTED" { return .submitted }
        for (prefix, make) in [("NOT_SUBMITTED:", ScriptResult.notSubmitted), ("UNCERTAIN:", ScriptResult.uncertain)]
            where line.hasPrefix(prefix) {
            guard let code = Int(line.dropFirst(prefix.count)) else { return .unexpected }
            return make(code)
        }
        return .unexpected
    }

    public static func result(of run: ScriptRunOutput) -> ScriptResult {
        switch run {
        case .output(let text): parse(text)
        case .timedOut: .timedOut
        case .failedToStart: .failedToStart
        case .exitNonZero: .exitNonZero
        }
    }

    private static func targetAllowed(_ value: String) -> Bool {
        !value.isEmpty && !value.hasPrefix("-")
            && !value.unicodeScalars.contains { $0.properties.generalCategory == .control }
    }
}

/// Runs `/usr/bin/osascript -` with the source on stdin and `arguments` as its argv.
public struct OsascriptRunner: CompanionScriptRunning {
    public init() {}

    public func run(source: String, arguments: [String], timeout: TimeInterval) async -> ScriptRunOutput {
        await Task.detached { Self.execute(source: source, arguments: arguments, timeout: timeout) }.value
    }

    private static func execute(source: String, arguments: [String], timeout: TimeInterval) -> ScriptRunOutput {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-"] + arguments
        let input = Pipe(), output = Pipe(), errors = Pipe()
        process.standardInput = input; process.standardOutput = output; process.standardError = errors
        let completed = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in completed.signal() }
        do { try process.run() } catch { return .failedToStart }
        do {
            try input.fileHandleForWriting.write(contentsOf: Data(source.utf8))
            try input.fileHandleForWriting.close()
        } catch {
            // The script may already be running: treat like a timeout, never as "not started".
            terminate(process, completed)
            return .timedOut
        }
        if completed.wait(timeout: .now() + timeout) == .timedOut {
            terminate(process, completed)
            return .timedOut
        }
        let stdout = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        _ = errors.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0 else { return .exitNonZero }
        return .output(stdout.hasSuffix("\n") ? String(stdout.dropLast()) : stdout)
    }

    private static func terminate(_ process: Process, _ completed: DispatchSemaphore) {
        if process.isRunning { process.terminate() }
        if completed.wait(timeout: .now() + 2) == .timedOut, process.isRunning { kill(process.processIdentifier, SIGKILL) }
    }
}
