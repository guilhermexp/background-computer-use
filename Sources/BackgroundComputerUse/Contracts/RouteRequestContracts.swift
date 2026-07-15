import Foundation

protocol DebugNotesRequest {
    var debug: Bool? { get }
}

public enum ActionTargetRequestValidationError: Error, CustomStringConvertible, Sendable {
    case invalidDisplayIndex(String)
    case emptyTargetValue(ActionTargetKindDTO)

    public var description: String {
        switch self {
        case .invalidDisplayIndex(let value):
            return "display_index targets must use a non-negative integer value, got '\(value)'."
        case .emptyTargetValue(let kind):
            return "\(kind.rawValue) targets must use a non-empty string value."
        }
    }
}

public enum ActionTargetKindDTO: String, Decodable, Encodable, Sendable {
    case displayIndex = "display_index"
    case nodeID = "node_id"
    case refetchFingerprint = "refetch_fingerprint"
}

public struct ActionTargetRequestDTO: Decodable, Encodable, Sendable {
    public let kind: ActionTargetKindDTO
    public let value: String

    private init(uncheckedKind kind: ActionTargetKindDTO, value: String) {
        self.kind = kind
        self.value = value
    }

    init(kind: ActionTargetKindDTO, value: String) throws {
        self.kind = kind
        self.value = try Self.validatedValue(kind: kind, value: value)
    }

    public static func displayIndex(_ index: Int) throws -> ActionTargetRequestDTO {
        guard index >= 0 else {
            throw ActionTargetRequestValidationError.invalidDisplayIndex(String(index))
        }
        return ActionTargetRequestDTO(uncheckedKind: .displayIndex, value: String(index))
    }

    public static func nodeID(_ value: String) throws -> ActionTargetRequestDTO {
        ActionTargetRequestDTO(
            uncheckedKind: .nodeID,
            value: try validatedValue(kind: .nodeID, value: value)
        )
    }

    public static func refetchFingerprint(_ value: String) throws -> ActionTargetRequestDTO {
        ActionTargetRequestDTO(
            uncheckedKind: .refetchFingerprint,
            value: try validatedValue(kind: .refetchFingerprint, value: value)
        )
    }

    public var displayIndex: Int? {
        guard kind == .displayIndex else { return nil }
        return Int(value)
    }

    public var summary: String {
        switch kind {
        case .displayIndex:
            return "display_index \(value)"
        case .nodeID:
            return "node_id '\(value)'"
        case .refetchFingerprint:
            return "refetch_fingerprint '\(value)'"
        }
    }

    private static func validatedValue(kind: ActionTargetKindDTO, value: String) throws -> String {
        switch kind {
        case .displayIndex:
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let index = Int(trimmed), index >= 0 else {
                throw ActionTargetRequestValidationError.invalidDisplayIndex(value)
            }
            return String(index)

        case .nodeID, .refetchFingerprint:
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.isEmpty == false else {
                throw ActionTargetRequestValidationError.emptyTargetValue(kind)
            }
            return trimmed
        }
    }

    enum CodingKeys: String, CodingKey {
        case kind
        case value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decode(ActionTargetKindDTO.self, forKey: .kind)

        switch kind {
        case .displayIndex:
            let index = try container.decode(Int.self, forKey: .value)
            guard index >= 0 else {
                throw DecodingError.dataCorruptedError(
                    forKey: .value,
                    in: container,
                    debugDescription: "display_index targets must use a non-negative integer value."
                )
            }
            value = String(index)

        case .nodeID, .refetchFingerprint:
            let rawValue = try container.decode(String.self, forKey: .value)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard rawValue.isEmpty == false else {
                throw DecodingError.dataCorruptedError(
                    forKey: .value,
                    in: container,
                    debugDescription: "\(kind.rawValue) targets must use a non-empty string value."
                )
            }
            value = rawValue
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        if let displayIndex {
            try container.encode(displayIndex, forKey: .value)
        } else {
            try container.encode(value, forKey: .value)
        }
    }
}

public struct ListAppsRequest: Decodable, Sendable {
    public init() {}
}

public struct ListWindowsRequest: Decodable, Sendable {
    public let app: String

    public init(app: String) {
        self.app = app
    }
}

struct CursorFeedbackRequest: Decodable, Sendable {
    let operation: CursorFeedbackOperation
    let state: CursorFeedbackVisualState?
    let message: String?
    let append: Bool?
    let cursor: CursorRequestDTO?
    let window: String?
    let x: Double?
    let y: Double?
    let dwellMs: Double?
    let debug: Bool?

    enum CodingKeys: String, CodingKey {
        case operation
        case state
        case message
        case append
        case cursor
        case window
        case x
        case y
        case dwellMs
        case debug
    }

    init(
        operation: CursorFeedbackOperation,
        state: CursorFeedbackVisualState? = nil,
        message: String? = nil,
        append: Bool? = nil,
        cursor: CursorRequestDTO? = nil,
        window: String? = nil,
        x: Double? = nil,
        y: Double? = nil,
        dwellMs: Double? = nil,
        debug: Bool? = nil
    ) {
        self.operation = operation
        self.state = state
        self.message = message
        self.append = append
        self.cursor = cursor
        self.window = window
        self.x = x
        self.y = y
        self.dwellMs = dwellMs
        self.debug = debug
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        operation = try container.decode(CursorFeedbackOperation.self, forKey: .operation)
        state = try container.decodeIfPresent(CursorFeedbackVisualState.self, forKey: .state)
        message = try container.decodeIfPresent(String.self, forKey: .message)
        append = try container.decodeIfPresent(Bool.self, forKey: .append)
        cursor = try container.decodeIfPresent(CursorRequestDTO.self, forKey: .cursor)
        window = try container.decodeIfPresent(String.self, forKey: .window)
        x = try container.decodeIfPresent(Double.self, forKey: .x)
        y = try container.decodeIfPresent(Double.self, forKey: .y)
        dwellMs = try container.decodeIfPresent(Double.self, forKey: .dwellMs)
        debug = try container.decodeIfPresent(Bool.self, forKey: .debug)

        if x != nil || y != nil {
            guard let x, let y, x.isFinite, y.isFinite else {
                throw DecodingError.dataCorruptedError(
                    forKey: x == nil ? .x : .y,
                    in: container,
                    debugDescription: "cursor_feedback coordinates must include finite x and y values together."
                )
            }
        }
        if let dwellMs, dwellMs.isFinite == false {
            throw DecodingError.dataCorruptedError(
                forKey: .dwellMs,
                in: container,
                debugDescription: "cursor_feedback dwellMs must be finite when provided."
            )
        }
    }
}

public struct GetWindowStateRequest: Decodable, Sendable {
    public let window: String
    public let includeMenuBar: Bool?
    public let menuPath: [String]?
    public let webTraversal: AXWebTraversalMode?
    public let maxNodes: Int?
    public let imageMode: ImageMode?
    public let includeRawScreenshot: Bool?
    public let debugMode: StateDebugModeDTO?
    public let debug: Bool?
    public let includeRawCapture: Bool?
    public let includeSemanticTree: Bool?
    public let includeProjectedTree: Bool?
    public let includePlatformProfile: Bool?
    public let includeDiagnostics: Bool?
    public let includeOCR: Bool?
    public let scopeTarget: ActionTargetRequestDTO?

    public init(
        window: String,
        includeMenuBar: Bool? = nil,
        menuPath: [String]? = nil,
        webTraversal: AXWebTraversalMode? = nil,
        maxNodes: Int? = nil,
        imageMode: ImageMode? = nil,
        includeRawScreenshot: Bool? = nil,
        debugMode: StateDebugModeDTO? = nil,
        debug: Bool? = nil,
        includeRawCapture: Bool? = nil,
        includeSemanticTree: Bool? = nil,
        includeProjectedTree: Bool? = nil,
        includePlatformProfile: Bool? = nil,
        includeDiagnostics: Bool? = nil,
        includeOCR: Bool? = nil,
        scopeTarget: ActionTargetRequestDTO? = nil
    ) {
        self.window = window
        self.includeMenuBar = includeMenuBar
        self.menuPath = menuPath
        self.webTraversal = webTraversal
        self.maxNodes = maxNodes
        self.imageMode = imageMode
        self.includeRawScreenshot = includeRawScreenshot
        self.debugMode = debugMode
        self.debug = debug
        self.includeRawCapture = includeRawCapture
        self.includeSemanticTree = includeSemanticTree
        self.includeProjectedTree = includeProjectedTree
        self.includePlatformProfile = includePlatformProfile
        self.includeDiagnostics = includeDiagnostics
        self.includeOCR = includeOCR
        self.scopeTarget = scopeTarget
    }
}

public struct ClickRequest: Decodable, Sendable {
    public let window: String
    public let stateToken: String?
    public let target: ActionTargetRequestDTO?
    public let x: Double?
    public let y: Double?
    public let mode: ClickModeDTO?
    public let clickCount: Int?
    public let mouseButton: MouseButtonDTO?
    public let cursor: CursorRequestDTO?
    public let includeMenuBar: Bool?
    public let maxNodes: Int?
    public let imageMode: ImageMode?
    public let debug: Bool?
    public let confirm: Bool?

    public init(
        window: String,
        stateToken: String? = nil,
        target: ActionTargetRequestDTO,
        mode: ClickModeDTO? = nil,
        clickCount: Int? = nil,
        mouseButton: MouseButtonDTO? = nil,
        cursor: CursorRequestDTO? = nil,
        includeMenuBar: Bool? = nil,
        maxNodes: Int? = nil,
        imageMode: ImageMode? = nil,
        debug: Bool? = nil,
        confirm: Bool? = nil
    ) {
        self.window = window
        self.stateToken = stateToken
        self.target = target
        self.x = nil
        self.y = nil
        self.mode = mode
        self.clickCount = clickCount
        self.mouseButton = mouseButton
        self.cursor = cursor
        self.includeMenuBar = includeMenuBar
        self.maxNodes = maxNodes
        self.imageMode = imageMode
        self.debug = debug
        self.confirm = confirm
    }

    public init(
        window: String,
        stateToken: String? = nil,
        x: Double,
        y: Double,
        mode: ClickModeDTO? = nil,
        clickCount: Int? = nil,
        mouseButton: MouseButtonDTO? = nil,
        cursor: CursorRequestDTO? = nil,
        includeMenuBar: Bool? = nil,
        maxNodes: Int? = nil,
        imageMode: ImageMode? = nil,
        debug: Bool? = nil,
        confirm: Bool? = nil
    ) {
        self.window = window
        self.stateToken = stateToken
        self.target = nil
        self.x = x
        self.y = y
        self.mode = mode
        self.clickCount = clickCount
        self.mouseButton = mouseButton
        self.cursor = cursor
        self.includeMenuBar = includeMenuBar
        self.maxNodes = maxNodes
        self.imageMode = imageMode
        self.debug = debug
        self.confirm = confirm
    }

    enum CodingKeys: String, CodingKey {
        case window
        case stateToken
        case target
        case x
        case y
        case mode
        case clickCount
        case mouseButton
        case cursor
        case includeMenuBar
        case maxNodes
        case imageMode
        case debug
        case confirm
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        window = try container.decode(String.self, forKey: .window)
        stateToken = try container.decodeIfPresent(String.self, forKey: .stateToken)
        target = try container.decodeIfPresent(ActionTargetRequestDTO.self, forKey: .target)
        x = try container.decodeIfPresent(Double.self, forKey: .x)
        y = try container.decodeIfPresent(Double.self, forKey: .y)
        mode = try container.decodeIfPresent(ClickModeDTO.self, forKey: .mode)
        clickCount = try container.decodeIfPresent(Int.self, forKey: .clickCount)
        mouseButton = try container.decodeIfPresent(MouseButtonDTO.self, forKey: .mouseButton)
        cursor = try container.decodeIfPresent(CursorRequestDTO.self, forKey: .cursor)
        includeMenuBar = try container.decodeIfPresent(Bool.self, forKey: .includeMenuBar)
        maxNodes = try container.decodeIfPresent(Int.self, forKey: .maxNodes)
        imageMode = try container.decodeIfPresent(ImageMode.self, forKey: .imageMode)
        debug = try container.decodeIfPresent(Bool.self, forKey: .debug)
        confirm = try container.decodeIfPresent(Bool.self, forKey: .confirm)

        let hasTarget = target != nil
        let hasCompleteCoordinate = x != nil && y != nil
        let hasPartialCoordinate = (x != nil) != (y != nil)
        if hasPartialCoordinate {
            throw DecodingError.dataCorruptedError(
                forKey: x == nil ? .x : .y,
                in: container,
                debugDescription: "Click coordinate targets must include both x and y."
            )
        }
        if hasTarget == hasCompleteCoordinate {
            throw DecodingError.dataCorruptedError(
                forKey: .target,
                in: container,
                debugDescription: "Click requests must supply exactly one target form: target or both x and y."
            )
        }
    }
}

public struct ScrollRequest: Decodable, Sendable {
    public let window: String
    public let stateToken: String?
    public let target: ActionTargetRequestDTO
    public let direction: ScrollDirectionDTO
    public let pages: Double?
    public let verificationMode: ActionVerificationModeDTO?
    public let cursor: CursorRequestDTO?
    public let includeMenuBar: Bool?
    public let maxNodes: Int?
    public let imageMode: ImageMode?
    public let debug: Bool?

    public init(
        window: String,
        stateToken: String? = nil,
        target: ActionTargetRequestDTO,
        direction: ScrollDirectionDTO,
        pages: Double? = nil,
        verificationMode: ActionVerificationModeDTO? = nil,
        cursor: CursorRequestDTO? = nil,
        includeMenuBar: Bool? = nil,
        maxNodes: Int? = nil,
        imageMode: ImageMode? = nil,
        debug: Bool? = nil
    ) {
        self.window = window
        self.stateToken = stateToken
        self.target = target
        self.direction = direction
        self.pages = pages
        self.verificationMode = verificationMode
        self.cursor = cursor
        self.includeMenuBar = includeMenuBar
        self.maxNodes = maxNodes
        self.imageMode = imageMode
        self.debug = debug
    }

    enum CodingKeys: String, CodingKey {
        case window
        case stateToken
        case target
        case direction
        case pages
        case verificationMode
        case cursor
        case includeMenuBar
        case maxNodes
        case imageMode
        case debug
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        window = try container.decode(String.self, forKey: .window)
        stateToken = try container.decodeIfPresent(String.self, forKey: .stateToken)
        target = try container.decode(ActionTargetRequestDTO.self, forKey: .target)
        direction = try container.decode(ScrollDirectionDTO.self, forKey: .direction)
        pages = try container.decodeIfPresent(Double.self, forKey: .pages)
        verificationMode = try container.decodeIfPresent(ActionVerificationModeDTO.self, forKey: .verificationMode)
        cursor = try container.decodeIfPresent(CursorRequestDTO.self, forKey: .cursor)
        includeMenuBar = try container.decodeIfPresent(Bool.self, forKey: .includeMenuBar)
        maxNodes = try container.decodeIfPresent(Int.self, forKey: .maxNodes)
        imageMode = try container.decodeIfPresent(ImageMode.self, forKey: .imageMode)
        debug = try container.decodeIfPresent(Bool.self, forKey: .debug)
    }
}

public struct PerformSecondaryActionRequest: Decodable, Sendable {
    public let window: String
    public let stateToken: String?
    public let target: ActionTargetRequestDTO
    public let action: String
    public let actionID: String?
    public let menuPath: [String]?
    public let webTraversal: AXWebTraversalMode?
    public let cursor: CursorRequestDTO?
    public let includeMenuBar: Bool?
    public let maxNodes: Int?
    public let imageMode: ImageMode?
    public let debug: Bool?
    public let confirm: Bool?

    public init(
        window: String,
        stateToken: String? = nil,
        target: ActionTargetRequestDTO,
        action: String,
        actionID: String? = nil,
        menuPath: [String]? = nil,
        webTraversal: AXWebTraversalMode? = nil,
        cursor: CursorRequestDTO? = nil,
        includeMenuBar: Bool? = nil,
        maxNodes: Int? = nil,
        imageMode: ImageMode? = nil,
        debug: Bool? = nil,
        confirm: Bool? = nil
    ) {
        self.window = window
        self.stateToken = stateToken
        self.target = target
        self.action = action
        self.actionID = actionID
        self.menuPath = menuPath
        self.webTraversal = webTraversal
        self.cursor = cursor
        self.includeMenuBar = includeMenuBar
        self.maxNodes = maxNodes
        self.imageMode = imageMode
        self.debug = debug
        self.confirm = confirm
    }

    enum CodingKeys: String, CodingKey {
        case window
        case stateToken
        case target
        case action
        case actionID
        case menuPath
        case webTraversal
        case cursor
        case includeMenuBar
        case maxNodes
        case imageMode
        case debug
        case confirm
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        window = try container.decode(String.self, forKey: .window)
        stateToken = try container.decodeIfPresent(String.self, forKey: .stateToken)
        target = try container.decode(ActionTargetRequestDTO.self, forKey: .target)
        action = try container.decode(String.self, forKey: .action)
        actionID = try container.decodeIfPresent(String.self, forKey: .actionID)
        menuPath = try container.decodeIfPresent([String].self, forKey: .menuPath)
        webTraversal = try container.decodeIfPresent(AXWebTraversalMode.self, forKey: .webTraversal)
        cursor = try container.decodeIfPresent(CursorRequestDTO.self, forKey: .cursor)
        includeMenuBar = try container.decodeIfPresent(Bool.self, forKey: .includeMenuBar)
        maxNodes = try container.decodeIfPresent(Int.self, forKey: .maxNodes)
        imageMode = try container.decodeIfPresent(ImageMode.self, forKey: .imageMode)
        debug = try container.decodeIfPresent(Bool.self, forKey: .debug)
        confirm = try container.decodeIfPresent(Bool.self, forKey: .confirm)
    }
}

public struct DragRequest: Decodable, Sendable {
    public let window: String
    public let toX: Double
    public let toY: Double
    public let cursor: CursorRequestDTO?

    public init(window: String, toX: Double, toY: Double, cursor: CursorRequestDTO? = nil) {
        self.window = window
        self.toX = toX
        self.toY = toY
        self.cursor = cursor
    }
}

public struct ResizeRequest: Decodable, Sendable {
    public let window: String
    public let handle: ResizeHandleDTO
    public let toX: Double
    public let toY: Double
    public let cursor: CursorRequestDTO?

    public init(
        window: String,
        handle: ResizeHandleDTO,
        toX: Double,
        toY: Double,
        cursor: CursorRequestDTO? = nil
    ) {
        self.window = window
        self.handle = handle
        self.toX = toX
        self.toY = toY
        self.cursor = cursor
    }
}

public struct SetWindowFrameRequest: Decodable, Sendable {
    public let window: String
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double
    public let animate: Bool?
    public let cursor: CursorRequestDTO?

    public init(
        window: String,
        x: Double,
        y: Double,
        width: Double,
        height: Double,
        animate: Bool? = nil,
        cursor: CursorRequestDTO? = nil
    ) {
        self.window = window
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.animate = animate
        self.cursor = cursor
    }
}

public struct TypeTextRequest: Decodable, Sendable {
    public let window: String
    public let stateToken: String?
    public let target: ActionTargetRequestDTO?
    public let text: String
    public let focusAssistMode: TypeTextFocusAssistModeDTO?
    public let cursor: CursorRequestDTO?
    public let includeMenuBar: Bool?
    public let maxNodes: Int?
    public let imageMode: ImageMode?
    public let debug: Bool?
    public let confirm: Bool?

    public init(
        window: String,
        stateToken: String? = nil,
        target: ActionTargetRequestDTO? = nil,
        text: String,
        focusAssistMode: TypeTextFocusAssistModeDTO? = nil,
        cursor: CursorRequestDTO? = nil,
        includeMenuBar: Bool? = nil,
        maxNodes: Int? = nil,
        imageMode: ImageMode? = nil,
        debug: Bool? = nil,
        confirm: Bool? = nil
    ) {
        self.window = window
        self.stateToken = stateToken
        self.target = target
        self.text = text
        self.focusAssistMode = focusAssistMode
        self.cursor = cursor
        self.includeMenuBar = includeMenuBar
        self.maxNodes = maxNodes
        self.imageMode = imageMode
        self.debug = debug
        self.confirm = confirm
    }

    enum CodingKeys: String, CodingKey {
        case window
        case stateToken
        case target
        case text
        case focusAssistMode
        case cursor
        case includeMenuBar
        case maxNodes
        case imageMode
        case debug
        case confirm
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        window = try container.decode(String.self, forKey: .window)
        stateToken = try container.decodeIfPresent(String.self, forKey: .stateToken)
        target = try container.decodeIfPresent(ActionTargetRequestDTO.self, forKey: .target)
        text = try container.decode(String.self, forKey: .text)
        focusAssistMode = try container.decodeIfPresent(TypeTextFocusAssistModeDTO.self, forKey: .focusAssistMode)
        cursor = try container.decodeIfPresent(CursorRequestDTO.self, forKey: .cursor)
        includeMenuBar = try container.decodeIfPresent(Bool.self, forKey: .includeMenuBar)
        maxNodes = try container.decodeIfPresent(Int.self, forKey: .maxNodes)
        imageMode = try container.decodeIfPresent(ImageMode.self, forKey: .imageMode)
        debug = try container.decodeIfPresent(Bool.self, forKey: .debug)
        confirm = try container.decodeIfPresent(Bool.self, forKey: .confirm)
    }
}

public struct PressKeyRequest: Decodable, Sendable {
    public let window: String
    public let stateToken: String?
    public let key: String
    public let cursor: CursorRequestDTO?
    public let includeMenuBar: Bool?
    public let maxNodes: Int?
    public let imageMode: ImageMode?
    public let debug: Bool?
    public let confirm: Bool?

    public init(
        window: String,
        stateToken: String? = nil,
        key: String,
        cursor: CursorRequestDTO? = nil,
        includeMenuBar: Bool? = nil,
        maxNodes: Int? = nil,
        imageMode: ImageMode? = nil,
        debug: Bool? = nil,
        confirm: Bool? = nil
    ) {
        self.window = window
        self.stateToken = stateToken
        self.key = key
        self.cursor = cursor
        self.includeMenuBar = includeMenuBar
        self.maxNodes = maxNodes
        self.imageMode = imageMode
        self.debug = debug
        self.confirm = confirm
    }
}

public struct SetValueRequest: Decodable, Sendable {
    public let window: String
    public let stateToken: String?
    public let target: ActionTargetRequestDTO
    public let value: String
    public let cursor: CursorRequestDTO?
    public let includeMenuBar: Bool?
    public let maxNodes: Int?
    public let imageMode: ImageMode?
    public let debug: Bool?
    public let confirm: Bool?

    public init(
        window: String,
        stateToken: String? = nil,
        target: ActionTargetRequestDTO,
        value: String,
        cursor: CursorRequestDTO? = nil,
        includeMenuBar: Bool? = nil,
        maxNodes: Int? = nil,
        imageMode: ImageMode? = nil,
        debug: Bool? = nil,
        confirm: Bool? = nil
    ) {
        self.window = window
        self.stateToken = stateToken
        self.target = target
        self.value = value
        self.cursor = cursor
        self.includeMenuBar = includeMenuBar
        self.maxNodes = maxNodes
        self.imageMode = imageMode
        self.debug = debug
        self.confirm = confirm
    }

    enum CodingKeys: String, CodingKey {
        case window
        case stateToken
        case target
        case value
        case cursor
        case includeMenuBar
        case maxNodes
        case imageMode
        case debug
        case confirm
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        window = try container.decode(String.self, forKey: .window)
        stateToken = try container.decodeIfPresent(String.self, forKey: .stateToken)
        target = try container.decode(ActionTargetRequestDTO.self, forKey: .target)
        value = try container.decode(String.self, forKey: .value)
        cursor = try container.decodeIfPresent(CursorRequestDTO.self, forKey: .cursor)
        includeMenuBar = try container.decodeIfPresent(Bool.self, forKey: .includeMenuBar)
        maxNodes = try container.decodeIfPresent(Int.self, forKey: .maxNodes)
        imageMode = try container.decodeIfPresent(ImageMode.self, forKey: .imageMode)
        debug = try container.decodeIfPresent(Bool.self, forKey: .debug)
        confirm = try container.decodeIfPresent(Bool.self, forKey: .confirm)
    }
}

public struct WaitForRequest: Decodable, Sendable {
    public let window: String
    public let role: String?
    public let label: String?
    public let valueContains: String?
    public let windowTitleContains: String?
    public let windowTitleChanged: Bool?
    public let urlContains: String?
    public let textContains: String?
    public let gone: Bool?
    public let timeoutSeconds: Double?
    public let pollIntervalMs: Int?
    public let includeMenuBar: Bool?
    public let maxNodes: Int?
    public let imageMode: ImageMode?

    public init(
        window: String,
        role: String? = nil,
        label: String? = nil,
        valueContains: String? = nil,
        windowTitleContains: String? = nil,
        windowTitleChanged: Bool? = nil,
        urlContains: String? = nil,
        textContains: String? = nil,
        gone: Bool? = nil,
        timeoutSeconds: Double? = nil,
        pollIntervalMs: Int? = nil,
        includeMenuBar: Bool? = nil,
        maxNodes: Int? = nil,
        imageMode: ImageMode? = nil
    ) {
        self.window = window
        self.role = role
        self.label = label
        self.valueContains = valueContains
        self.windowTitleContains = windowTitleContains
        self.windowTitleChanged = windowTitleChanged
        self.urlContains = urlContains
        self.textContains = textContains
        self.gone = gone
        self.timeoutSeconds = timeoutSeconds
        self.pollIntervalMs = pollIntervalMs
        self.includeMenuBar = includeMenuBar
        self.maxNodes = maxNodes
        self.imageMode = imageMode
    }
}

public struct AnnotateWindowRequest: Decodable, Sendable {
    public let window: String
    public let includeMenuBar: Bool?
    public let webTraversal: AXWebTraversalMode?
    public let maxNodes: Int?
    public let maxMarks: Int?
    public let includeStaticText: Bool?
    public let imageMode: ImageMode?

    public init(
        window: String,
        includeMenuBar: Bool? = nil,
        webTraversal: AXWebTraversalMode? = nil,
        maxNodes: Int? = nil,
        maxMarks: Int? = nil,
        includeStaticText: Bool? = nil,
        imageMode: ImageMode? = nil
    ) {
        self.window = window
        self.includeMenuBar = includeMenuBar
        self.webTraversal = webTraversal
        self.maxNodes = maxNodes
        self.maxMarks = maxMarks
        self.includeStaticText = includeStaticText
        self.imageMode = imageMode
    }
}

public struct ReadTextRequest: Decodable, Sendable {
    public let window: String
    public let target: ActionTargetRequestDTO
    public let offset: Int?
    public let length: Int?
    public let includeMenuBar: Bool?
    public let maxNodes: Int?

    public init(
        window: String,
        target: ActionTargetRequestDTO,
        offset: Int? = nil,
        length: Int? = nil,
        includeMenuBar: Bool? = nil,
        maxNodes: Int? = nil
    ) {
        self.window = window
        self.target = target
        self.offset = offset
        self.length = length
        self.includeMenuBar = includeMenuBar
        self.maxNodes = maxNodes
    }
}

public struct SelectTextRequest: Decodable, Sendable {
    public let window: String
    public let stateToken: String?
    public let target: ActionTargetRequestDTO
    public let text: String
    public let occurrence: Int?
    public let position: TextSelectionPositionDTO?
    public let includeMenuBar: Bool?
    public let maxNodes: Int?
    public let imageMode: ImageMode?
    public let debug: Bool?
    public let confirm: Bool?

    public init(
        window: String,
        stateToken: String? = nil,
        target: ActionTargetRequestDTO,
        text: String,
        occurrence: Int? = nil,
        position: TextSelectionPositionDTO? = nil,
        includeMenuBar: Bool? = nil,
        maxNodes: Int? = nil,
        imageMode: ImageMode? = nil,
        debug: Bool? = nil,
        confirm: Bool? = nil
    ) {
        self.window = window
        self.stateToken = stateToken
        self.target = target
        self.text = text
        self.occurrence = occurrence
        self.position = position
        self.includeMenuBar = includeMenuBar
        self.maxNodes = maxNodes
        self.imageMode = imageMode
        self.debug = debug
        self.confirm = confirm
    }
}

extension ClickRequest: DebugNotesRequest {}
extension ScrollRequest: DebugNotesRequest {}
extension PerformSecondaryActionRequest: DebugNotesRequest {}
extension TypeTextRequest: DebugNotesRequest {}
extension PressKeyRequest: DebugNotesRequest {}
extension SetValueRequest: DebugNotesRequest {}
extension SelectTextRequest: DebugNotesRequest {}
