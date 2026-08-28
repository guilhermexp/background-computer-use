import BackgroundComputerUseControlShared
import BackgroundComputerUseLockedBroker
import BackgroundComputerUseLockedShared
import Darwin
import Foundation
import SystemConfiguration

private final class BrokerListenerDelegate: NSObject, NSXPCListenerDelegate {
    private let service: LockedUseBrokerService
    private let allowedPeers: [AppIdentity: LockedUseBrokerPeerRole]
    private let identityResolver = CodeSignatureIdentity()

    init(service: LockedUseBrokerService, allowedPeers: [AppIdentity: LockedUseBrokerPeerRole]) {
        self.service = service
        self.allowedPeers = allowedPeers
    }

    func listener(_: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        guard let identity = try? identityResolver.resolve(pid: connection.processIdentifier),
              let role = allowedPeers[identity]
        else {
            return false
        }
        connection.exportedInterface = NSXPCInterface(with: LockedUseBrokerXPCProtocol.self)
        connection.exportedObject = LockedUseBrokerConnectionService(
            broker: service,
            role: role,
            identity: identity
        )
        connection.resume()
        return true
    }
}

private func consoleUID() -> UInt32? {
    var uid: uid_t = 0
    var gid: gid_t = 0
    guard let user = SCDynamicStoreCopyConsoleUser(nil, &uid, &gid) as String?,
          user != "loginwindow", user != "_mbsetupuser"
    else {
        return nil
    }
    return uid
}

private func bootSessionID() -> String? {
    var bootTime = timeval()
    var size = MemoryLayout<timeval>.size
    guard sysctlbyname("kern.boottime", &bootTime, &size, nil, 0) == 0 else { return nil }
    return "\(bootTime.tv_sec).\(bootTime.tv_usec)"
}

private func relock(reason _: String) -> Bool {
    let path = "/System/Library/CoreServices/Menu Extras/User.menu/Contents/Resources/CGSession"
    guard FileManager.default.isExecutableFile(atPath: path) else { return false }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = ["-suspend"]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    do {
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus == 0
    } catch {
        return false
    }
}

guard getuid() == 0 else {
    FileHandle.standardError.write(Data("locked broker must run as root\n".utf8))
    exit(77)
}

let environment = ProcessInfo.processInfo.environment
let peersData = environment["BCU_LOCKED_ALLOWED_PEERS_BASE64"]
    .flatMap { Data(base64Encoded: $0) }
    ?? environment["BCU_LOCKED_ALLOWED_PEERS"]?.data(using: .utf8)
guard let peersData,
      let peers = try? JSONDecoder().decode([LockedUseBrokerPeer].self, from: peersData),
      peers.filter({ $0.role == .control }).count == 1,
      peers.filter({ $0.role == .core }).count == 1,
      peers.filter({ $0.role == .authorizationHost }).count == 1,
      let trustedCore = peers.first(where: { $0.role == .core })
else {
    FileHandle.standardError.write(Data("signed locked-use peer identities are required\n".utf8))
    exit(78)
}

let service = LockedUseBrokerService(
    trustedCoreDesignatedRequirement: trustedCore.identity.designatedRequirement,
    uidProvider: consoleUID,
    bootSessionProvider: bootSessionID,
    relock: relock
)
let peerRoles = Dictionary(uniqueKeysWithValues: peers.map { ($0.identity, $0.role) })
private let delegate = BrokerListenerDelegate(service: service, allowedPeers: peerRoles)
let listener = NSXPCListener(machServiceName: LockedUseBrokerMachService.name)
listener.delegate = delegate

let timer = DispatchSource.makeTimerSource(queue: .global(qos: .userInitiated))
timer.schedule(deadline: .now() + 1, repeating: 1)
timer.setEventHandler { service.checkDependencies() }
timer.resume()
let inputMonitor = LocalInputMonitor { service.handleLocalInput() }
guard inputMonitor.start() else {
    FileHandle.standardError.write(Data("failed to install trusted local-input event tap\n".utf8))
    exit(79)
}

listener.resume()
RunLoop.current.run()
