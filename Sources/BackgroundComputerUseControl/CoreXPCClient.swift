import BackgroundComputerUseControlShared
import Foundation

public protocol CoreXPCTransporting: AnyObject {
    func ping() -> Bool
    func configure(sessionID: String, state: CoreSessionState) -> Bool
    func transition(sessionID: String, state: CoreSessionState) -> Bool
    func authorize(sessionID: String, operation: CoreOperationKind) -> CoreAuthorizationDecision
}

public final class CoreXPCClient: @unchecked Sendable {
    public typealias TransportFactory = () -> (any CoreXPCTransporting)?

    private let lock = NSLock()
    private let sessionID: String
    private let transportFactory: TransportFactory
    private var desiredState: CoreSessionState = .active

    public init(
        sessionID: String,
        transportFactory: @escaping TransportFactory = { FoundationCoreXPCTransport() }
    ) {
        self.sessionID = sessionID
        self.transportFactory = transportFactory
    }

    public func start() -> Bool {
        rehydrate(state: currentState())
    }

    @discardableResult
    public func setState(_ state: CoreSessionState) -> Bool {
        lock.lock()
        if desiredState == .stopped, state != .stopped {
            lock.unlock()
            return false
        }
        desiredState = state
        lock.unlock()

        guard let transport = transportFactory(), transport.ping() else { return false }
        if transport.transition(sessionID: sessionID, state: state) {
            return true
        }
        return transport.configure(sessionID: sessionID, state: state)
    }

    public func allows(_ operation: CoreOperationKind) -> Bool {
        let state = currentState()
        if state == .stopped || (state == .paused && operation == .mutation) {
            return false
        }
        guard let transport = transportFactory(),
              transport.configure(sessionID: sessionID, state: state)
        else {
            return false
        }
        return transport.authorize(sessionID: sessionID, operation: operation) == .allowed
    }

    public func state() -> CoreSessionState {
        currentState()
    }

    private func rehydrate(state: CoreSessionState) -> Bool {
        guard let transport = transportFactory(), transport.ping() else { return false }
        return transport.configure(sessionID: sessionID, state: state)
    }

    private func currentState() -> CoreSessionState {
        lock.lock()
        defer { lock.unlock() }
        return desiredState
    }
}

public final class FoundationCoreXPCTransport: CoreXPCTransporting, @unchecked Sendable {
    private let timeout: DispatchTimeInterval
    private let embeddedServiceIdentityValid: Bool

    public init(timeout: DispatchTimeInterval = .milliseconds(750)) {
        self.timeout = timeout
        embeddedServiceIdentityValid = Self.validateEmbeddedServiceIdentity()
    }

    public func ping() -> Bool {
        call(default: false) { proxy, reply in proxy.ping(reply: reply) }
    }

    public func configure(sessionID: String, state: CoreSessionState) -> Bool {
        call(default: false) { proxy, reply in
            proxy.configureSession(sessionID: sessionID, state: state.rawValue, reply: reply)
        }
    }

    public func transition(sessionID: String, state: CoreSessionState) -> Bool {
        call(default: false) { proxy, reply in
            proxy.transitionSession(sessionID: sessionID, state: state.rawValue, reply: reply)
        }
    }

    public func authorize(
        sessionID: String,
        operation: CoreOperationKind
    ) -> CoreAuthorizationDecision {
        let raw: String = call(default: CoreAuthorizationDecision.unavailable.rawValue) { proxy, reply in
            proxy.authorize(sessionID: sessionID, operation: operation.rawValue, reply: reply)
        }
        return CoreAuthorizationDecision(rawValue: raw) ?? .unavailable
    }

    private func call<Value: Sendable>(
        default defaultValue: Value,
        _ body: (BackgroundComputerUseCoreXPCProtocol, @escaping (Value) -> Void) -> Void
    ) -> Value {
        guard embeddedServiceIdentityValid else { return defaultValue }
        let connection = NSXPCConnection(serviceName: BackgroundComputerUseCoreXPCService.serviceName)
        connection.remoteObjectInterface = NSXPCInterface(with: BackgroundComputerUseCoreXPCProtocol.self)
        let semaphore = DispatchSemaphore(value: 0)
        let box = CoreXPCReplyBox(defaultValue)
        connection.interruptionHandler = { semaphore.signal() }
        connection.invalidationHandler = { semaphore.signal() }
        connection.resume()
        defer { connection.invalidate() }
        let rawProxy = connection.remoteObjectProxyWithErrorHandler { _ in semaphore.signal() }
        guard let proxy = rawProxy as? BackgroundComputerUseCoreXPCProtocol else { return defaultValue }
        body(proxy) { value in
            box.set(value)
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + timeout)
        return box.value
    }

    private static func validateEmbeddedServiceIdentity() -> Bool {
        let controlURL = Bundle.main.bundleURL
        let coreURL = controlURL
            .appendingPathComponent("Contents/XPCServices", isDirectory: true)
            .appendingPathComponent("BackgroundComputerUseCoreXPCService.xpc", isDirectory: true)
        let resolver = CodeSignatureIdentity()
        guard let control = try? resolver.resolve(url: controlURL),
              let core = try? resolver.resolve(url: coreURL)
        else {
            return false
        }
        return EmbeddedCoreIdentityPolicy.accepts(control: control, core: core)
    }
}

private final class CoreXPCReplyBox<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value

    init(_ value: Value) {
        stored = value
    }

    var value: Value {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }

    func set(_ value: Value) {
        lock.lock()
        stored = value
        lock.unlock()
    }
}
