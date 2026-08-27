import Darwin
import Foundation

enum BoundedProcessRunnerError: Error, CustomStringConvertible {
    case pipeFailed(Int32)
    case spawnSetupFailed(Int32)
    case spawnFailed(Int32)
    case waitFailed(Int32)
    case configurePipeFailed(Int32)
    case processTreeSurvived(pid_t)

    var description: String {
        switch self {
        case .pipeFailed(let code): "Creating child-process pipes failed with errno \(code)."
        case .spawnSetupFailed(let code): "Preparing child-process spawn failed with code \(code)."
        case .spawnFailed(let code): "Launching the child process failed with code \(code)."
        case .waitFailed(let code): "Waiting for the child process failed with errno \(code)."
        case .configurePipeFailed(let code): "Configuring the child-process input pipe failed with errno \(code)."
        case .processTreeSurvived(let pid): "The timed-out process tree rooted at \(pid) survived SIGKILL."
        }
    }
}

struct BoundedProcessInvocation: Sendable {
    let executableURL: URL
    let arguments: [String]
    let stdin: Data
    let timeoutMs: Int
    let environment: [String]

    init(
        executableURL: URL,
        arguments: [String],
        stdin: Data,
        timeoutMs: Int,
        environment: [String] = Self.safeEnvironment()
    ) {
        self.executableURL = executableURL
        self.arguments = arguments
        self.stdin = stdin
        self.timeoutMs = timeoutMs
        self.environment = environment
    }

    static func safeEnvironment() -> [String] {
        let inherited = ProcessInfo.processInfo.environment
        let keys = ["HOME", "LANG", "LC_ALL", "LOGNAME", "TMPDIR", "USER"]
        var values = keys.compactMap { key in
            inherited[key].map { "\(key)=\($0)" }
        }
        values.append("PATH=/usr/bin:/bin:/usr/sbin:/sbin")
        return values
    }
}

struct BoundedProcessResult: Sendable {
    let status: Int
    let stdout: Data
    let stderr: Data
    let stdoutTruncated: Bool
    let stderrTruncated: Bool
    let durationMs: Double
    let timedOut: Bool
}

struct BoundedProcessRunner {
    static let maximumCapturedOutputBytes = 1_048_576

    func run(_ invocation: BoundedProcessInvocation) throws -> BoundedProcessResult {
        let input = try Self.makePipe()
        let output = try Self.makePipe()
        let errorOutput = try Self.makePipe()
        var parentDescriptors = [input.read, input.write, output.read, output.write, errorOutput.read, errorOutput.write]
        defer {
            for descriptor in parentDescriptors where descriptor >= 0 {
                Darwin.close(descriptor)
            }
        }

        var fileActions: posix_spawn_file_actions_t? = nil
        var attributes: posix_spawnattr_t? = nil
        guard posix_spawn_file_actions_init(&fileActions) == 0,
              posix_spawnattr_init(&attributes) == 0 else {
            throw BoundedProcessRunnerError.spawnSetupFailed(errno)
        }
        defer {
            posix_spawn_file_actions_destroy(&fileActions)
            posix_spawnattr_destroy(&attributes)
        }

        let actionResults = [
            posix_spawn_file_actions_adddup2(&fileActions, input.read, STDIN_FILENO),
            posix_spawn_file_actions_adddup2(&fileActions, output.write, STDOUT_FILENO),
            posix_spawn_file_actions_adddup2(&fileActions, errorOutput.write, STDERR_FILENO),
            posix_spawn_file_actions_addclose(&fileActions, input.write),
            posix_spawn_file_actions_addclose(&fileActions, output.read),
            posix_spawn_file_actions_addclose(&fileActions, errorOutput.read),
            posix_spawn_file_actions_addclose(&fileActions, input.read),
            posix_spawn_file_actions_addclose(&fileActions, output.write),
            posix_spawn_file_actions_addclose(&fileActions, errorOutput.write),
        ]
        guard actionResults.allSatisfy({ $0 == 0 }) else {
            throw BoundedProcessRunnerError.spawnSetupFailed(actionResults.first(where: { $0 != 0 }) ?? EIO)
        }
        guard posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP)) == 0,
              posix_spawnattr_setpgroup(&attributes, 0) == 0 else {
            throw BoundedProcessRunnerError.spawnSetupFailed(errno)
        }

        let executablePath = invocation.executableURL.path
        let arguments = [executablePath] + invocation.arguments
        var cArguments = arguments.map { strdup($0) } + [nil]
        var environment = invocation.environment.map { strdup($0) } + [nil]
        defer {
            for argument in cArguments where argument != nil {
                free(argument)
            }
            for variable in environment where variable != nil {
                free(variable)
            }
        }

        var processID: pid_t = 0
        let spawnResult = executablePath.withCString { executable in
            cArguments.withUnsafeMutableBufferPointer { argumentBuffer in
                environment.withUnsafeMutableBufferPointer { environmentBuffer in
                    posix_spawn(
                        &processID,
                        executable,
                        &fileActions,
                        &attributes,
                        argumentBuffer.baseAddress,
                        environmentBuffer.baseAddress
                    )
                }
            }
        }
        guard spawnResult == 0 else {
            throw BoundedProcessRunnerError.spawnFailed(spawnResult)
        }

        Self.closeAndInvalidate(input.read, in: &parentDescriptors)
        Self.closeAndInvalidate(output.write, in: &parentDescriptors)
        Self.closeAndInvalidate(errorOutput.write, in: &parentDescriptors)
        guard Darwin.fcntl(input.write, F_SETNOSIGPIPE, 1) == 0 else {
            Self.signalProcessTree(processID, descendants: [])
            throw BoundedProcessRunnerError.configurePipeFailed(errno)
        }

        let stdoutBox = LockedByteBuffer()
        let stderrBox = LockedByteBuffer()
        let ioGroup = DispatchGroup()
        Self.readToEnd(descriptor: output.read, into: stdoutBox, group: ioGroup)
        Self.readToEnd(descriptor: errorOutput.read, into: stderrBox, group: ioGroup)
        Self.closeWithoutInvalidating(output.read, in: &parentDescriptors)
        Self.closeWithoutInvalidating(errorOutput.read, in: &parentDescriptors)
        Self.write(invocation.stdin, descriptor: input.write, group: ioGroup)
        Self.closeWithoutInvalidating(input.write, in: &parentDescriptors)

        let started = DispatchTime.now().uptimeNanoseconds
        let timeoutMs = max(0, invocation.timeoutMs)
        let deadline = started + UInt64(timeoutMs) * 1_000_000
        var processStatus: Int32 = 0
        var timedOut = false
        var observedDescendants = Set<pid_t>()
        while true {
            observedDescendants.formUnion(Self.descendantPIDs(of: processID))
            let result = Darwin.waitpid(processID, &processStatus, WNOHANG)
            if result == processID {
                break
            }
            if result < 0, errno != EINTR {
                throw BoundedProcessRunnerError.waitFailed(errno)
            }
            if DispatchTime.now().uptimeNanoseconds >= deadline {
                timedOut = true
                observedDescendants.formUnion(Self.descendantPIDs(of: processID))
                Self.signalProcessTree(processID, descendants: observedDescendants)
                while Darwin.waitpid(processID, &processStatus, 0) < 0 {
                    guard errno == EINTR else {
                        throw BoundedProcessRunnerError.waitFailed(errno)
                    }
                }
                do {
                    try Self.verifyProcessTreeTerminated(processID, descendants: observedDescendants)
                } catch {
                    _ = ioGroup.wait(timeout: .now() + 1)
                    throw error
                }
                break
            }
            usleep(10_000)
        }

        ioGroup.wait()
        let finished = DispatchTime.now().uptimeNanoseconds
        return BoundedProcessResult(
            status: timedOut ? 124 : Self.exitStatus(processStatus),
            stdout: stdoutBox.value,
            stderr: stderrBox.value,
            stdoutTruncated: stdoutBox.truncated,
            stderrTruncated: stderrBox.truncated,
            durationMs: Double(finished - started) / 1_000_000,
            timedOut: timedOut
        )
    }

    private static func makePipe() throws -> (read: Int32, write: Int32) {
        var descriptors = [Int32](repeating: 0, count: 2)
        let result = descriptors.withUnsafeMutableBufferPointer { buffer in
            Darwin.pipe(buffer.baseAddress!)
        }
        guard result == 0 else {
            throw BoundedProcessRunnerError.pipeFailed(errno)
        }
        return (descriptors[0], descriptors[1])
    }

    private static func readToEnd(
        descriptor: Int32,
        into box: LockedByteBuffer,
        group: DispatchGroup
    ) {
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        group.enter()
        DispatchQueue.global(qos: .utility).async {
            while let data = try? handle.read(upToCount: 65_536), data.isEmpty == false {
                box.append(data, limit: maximumCapturedOutputBytes)
            }
            group.leave()
        }
    }

    private static func write(_ data: Data, descriptor: Int32, group: DispatchGroup) {
        group.enter()
        DispatchQueue.global(qos: .utility).async {
            defer {
                Darwin.close(descriptor)
                group.leave()
            }
            data.withUnsafeBytes { buffer in
                guard let baseAddress = buffer.baseAddress else { return }
                var written = 0
                while written < buffer.count {
                    let result = Darwin.write(descriptor, baseAddress.advanced(by: written), buffer.count - written)
                    if result < 0, errno == EINTR { continue }
                    guard result > 0 else { return }
                    written += result
                }
            }
        }
    }

    private static func signalProcessTree(_ processID: pid_t, descendants: Set<pid_t>) {
        for descendant in descendants {
            _ = Darwin.kill(descendant, SIGTERM)
        }
        _ = Darwin.kill(-processID, SIGTERM)
        usleep(100_000)
        for descendant in descendants {
            _ = Darwin.kill(descendant, SIGKILL)
        }
        _ = Darwin.kill(-processID, SIGKILL)
    }

    private static func verifyProcessTreeTerminated(
        _ processID: pid_t,
        descendants: Set<pid_t>
    ) throws {
        let deadline = DispatchTime.now().uptimeNanoseconds + 1_000_000_000
        while DispatchTime.now().uptimeNanoseconds < deadline {
            errno = 0
            let groupIsGone = Darwin.kill(-processID, 0) == -1 && errno == ESRCH
            let descendantsAreGone = descendants.allSatisfy { descendant in
                errno = 0
                return Darwin.kill(descendant, 0) == -1 && errno == ESRCH
            }
            if groupIsGone, descendantsAreGone {
                return
            }
            usleep(10_000)
        }
        throw BoundedProcessRunnerError.processTreeSurvived(processID)
    }

    private static func descendantPIDs(of rootPID: pid_t) -> Set<pid_t> {
        var discovered = Set<pid_t>()
        var pending = [rootPID]
        while let parent = pending.popLast() {
            let requestedCount = max(0, Int(proc_listchildpids(parent, nil, 0)))
            guard requestedCount > 0 else { continue }
            var children = [pid_t](repeating: 0, count: requestedCount + 8)
            let returnedCount = children.withUnsafeMutableBytes { buffer in
                proc_listchildpids(parent, buffer.baseAddress, Int32(buffer.count))
            }
            guard returnedCount > 0 else { continue }
            for child in children.prefix(min(children.count, Int(returnedCount))) where child > 0 {
                if discovered.insert(child).inserted {
                    pending.append(child)
                }
            }
        }
        return discovered
    }

    private static func exitStatus(_ processStatus: Int32) -> Int {
        let signal = processStatus & 0x7F
        if signal == 0 {
            return Int((processStatus >> 8) & 0xFF)
        }
        return 128 + Int(signal)
    }

    private static func closeAndInvalidate(_ descriptor: Int32, in descriptors: inout [Int32]) {
        Darwin.close(descriptor)
        if let index = descriptors.firstIndex(of: descriptor) {
            descriptors[index] = -1
        }
    }

    private static func closeWithoutInvalidating(_ descriptor: Int32, in descriptors: inout [Int32]) {
        if let index = descriptors.firstIndex(of: descriptor) {
            descriptors[index] = -1
        }
    }
}

private final class LockedByteBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = Data()
    private var didTruncate = false

    var value: Data {
        lock.withLock { storage }
    }

    var truncated: Bool {
        lock.withLock { didTruncate }
    }

    func append(_ data: Data, limit: Int) {
        lock.withLock {
            let remaining = max(0, limit - storage.count)
            if remaining > 0 {
                storage.append(data.prefix(remaining))
            }
            if data.count > remaining {
                didTruncate = true
            }
        }
    }
}
