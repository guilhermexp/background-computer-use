import BackgroundComputerUseControlShared
import Darwin
import Foundation

private final class CoreXPCService: NSObject, BackgroundComputerUseCoreXPCProtocol {
    private let authority: CoreSessionAuthority

    init(authority: CoreSessionAuthority) {
        self.authority = authority
    }

    func configureSession(sessionID: String, state: String, reply: @escaping (Bool) -> Void) {
        guard let state = CoreSessionState(rawValue: state) else {
            reply(false)
            return
        }
        reply(authority.configure(sessionID: sessionID, state: state))
    }

    func transitionSession(sessionID: String, state: String, reply: @escaping (Bool) -> Void) {
        guard let state = CoreSessionState(rawValue: state) else {
            reply(false)
            return
        }
        reply(authority.transition(sessionID: sessionID, to: state))
    }

    func authorize(sessionID: String, operation: String, reply: @escaping (String) -> Void) {
        guard let operation = CoreOperationKind(rawValue: operation) else {
            reply(CoreAuthorizationDecision.unavailable.rawValue)
            return
        }
        reply(authority.authorize(sessionID: sessionID, operation: operation).rawValue)
    }

    func ping(reply: @escaping (Bool) -> Void) {
        reply(true)
    }
}

private final class CoreXPCListenerDelegate: NSObject, NSXPCListenerDelegate {
    private let service: CoreXPCService
    private let ownIdentity: AppIdentity?
    private let identityResolver = CodeSignatureIdentity()

    init(service: CoreXPCService) {
        self.service = service
        ownIdentity = try? identityResolver.resolve(pid: getpid())
    }

    func listener(_: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        guard let ownIdentity,
              let client = try? identityResolver.resolve(pid: connection.processIdentifier),
              client.bundleID == "xyz.dubdub.backgroundcomputeruse",
              client.teamID == ownIdentity.teamID
        else {
            return false
        }
        connection.exportedInterface = NSXPCInterface(with: BackgroundComputerUseCoreXPCProtocol.self)
        connection.exportedObject = service
        connection.resume()
        return true
    }
}

let authority = CoreSessionAuthority()
private let service = CoreXPCService(authority: authority)
private let delegate = CoreXPCListenerDelegate(service: service)
let listener = NSXPCListener.service()
listener.delegate = delegate
listener.resume()
RunLoop.current.run()
