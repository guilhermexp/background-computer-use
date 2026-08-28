import Foundation

public struct ActionPerformanceDTO: Encodable, Equatable, Sendable {
    public let resolveMs: Double?
    public let captureMs: Double?
    public let preparationMs: Double?
    public let transportMs: Double?
    public let settleMs: Double?
    public let verificationMs: Double?
    public let totalMs: Double

    public init(
        resolveMs: Double?,
        captureMs: Double?,
        preparationMs: Double?,
        transportMs: Double?,
        settleMs: Double?,
        verificationMs: Double?,
        totalMs: Double
    ) {
        self.resolveMs = resolveMs.map(sanitizedJSONDouble)
        self.captureMs = captureMs.map(sanitizedJSONDouble)
        self.preparationMs = preparationMs.map(sanitizedJSONDouble)
        self.transportMs = transportMs.map(sanitizedJSONDouble)
        self.settleMs = settleMs.map(sanitizedJSONDouble)
        self.verificationMs = verificationMs.map(sanitizedJSONDouble)
        self.totalMs = sanitizedJSONDouble(totalMs)
    }
}
