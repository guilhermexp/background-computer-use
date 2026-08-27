import Darwin
import Foundation
import Testing
@testable import BackgroundComputerUse

@Suite(.serialized)
struct BoundedProcessRunnerTests {
    @Test
    func passesStdinAndCapturesBothStreams() throws {
        let result = try BoundedProcessRunner().run(
            BoundedProcessInvocation(
                executableURL: URL(fileURLWithPath: "/bin/sh"),
                arguments: ["-c", "read value; printf '%s' \"$value\"; printf 'warn' >&2"],
                stdin: Data("hello\n".utf8),
                timeoutMs: 2_000
            )
        )

        #expect(result.status == 0)
        #expect(String(decoding: result.stdout, as: UTF8.self) == "hello")
        #expect(String(decoding: result.stderr, as: UTF8.self) == "warn")
        #expect(result.stdoutTruncated == false)
        #expect(result.stderrTruncated == false)
        #expect(result.timedOut == false)
    }

    @Test
    func killsASetSidDescendantOnTimeout() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("bcu-runner-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let pidFile = root.appendingPathComponent("child.pid")
        let shell = "/usr/bin/perl -MPOSIX -e 'POSIX::setsid(); sleep 30' & child=$!; echo $child > '\(pidFile.path)'; wait $child"

        let result = try BoundedProcessRunner().run(
            BoundedProcessInvocation(
                executableURL: URL(fileURLWithPath: "/bin/sh"),
                arguments: ["-c", shell],
                stdin: Data(),
                timeoutMs: 500
            )
        )

        let childPIDText = try String(contentsOf: pidFile, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let childPID = pid_t(try #require(Int(childPIDText)))
        #expect(result.timedOut)
        #expect(result.status == 124)
        errno = 0
        #expect(Darwin.kill(childPID, 0) == -1)
        #expect(errno == ESRCH)
    }

    @Test
    func truncatesOversizedStdoutWhileDrainingTheProcess() throws {
        let byteCount = BoundedProcessRunner.maximumCapturedOutputBytes + 8_192
        let result = try BoundedProcessRunner().run(
            BoundedProcessInvocation(
                executableURL: URL(fileURLWithPath: "/usr/bin/python3"),
                arguments: ["-c", "import sys; sys.stdout.write('x' * \(byteCount))"],
                stdin: Data(),
                timeoutMs: 5_000
            )
        )

        #expect(result.status == 0)
        #expect(result.stdout.count == BoundedProcessRunner.maximumCapturedOutputBytes)
        #expect(result.stdoutTruncated)
    }

    @Test
    func invalidExecutableFailsWithoutStartingAProcess() {
        #expect(throws: BoundedProcessRunnerError.self) {
            _ = try BoundedProcessRunner().run(
                BoundedProcessInvocation(
                    executableURL: URL(fileURLWithPath: "/definitely/missing/bcu-worker"),
                    arguments: [],
                    stdin: Data(),
                    timeoutMs: 1_000
                )
            )
        }
    }
}
