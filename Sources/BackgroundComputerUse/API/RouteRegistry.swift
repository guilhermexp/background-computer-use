import Foundation

enum RouteID: String, CaseIterable {
    case health
    case bootstrap
    case routes
    case listApps = "list_apps"
    case listWindows = "list_windows"
    case launchApp = "launch_app"
    case cursorFeedback = "cursor_feedback"
    case getWindowState = "get_window_state"
    case findElements = "find_elements"
    case runScript = "run_script"
    case annotateWindow = "annotate_window"
    case click
    case scroll
    case performSecondaryAction = "perform_secondary_action"
    case drag
    case resize
    case setWindowFrame = "set_window_frame"
    case typeText = "type_text"
    case paste
    case pressKey = "press_key"
    case setValue = "set_value"
    case waitFor = "wait_for"
    case readText = "read_text"
    case selectText = "select_text"
}

enum RouteRegistry {
    static let descriptors: [RouteDescriptorDTO] = [
        RouteDescriptorDTO(
            id: RouteID.health.rawValue,
            method: "GET",
            path: "/health",
            category: "system",
            summary: "Health probe for the local loopback runtime.",
            execution: RouteExecutionPolicyDTO(
                lane: .sharedRead,
                backgroundBehavior: .backgroundRequired,
                focusStealPolicy: .forbidden,
                mainThreadBehavior: .avoid,
                readActRead: false,
                allowsConcurrentClients: true,
                notes: ["System routes should remain cheap, background-safe, and independent of per-window execution lanes."]
            ),
            implementationStatus: .implemented,
            notes: RuntimeMetadata.systemRouteNotes
        ),
        RouteDescriptorDTO(
            id: RouteID.bootstrap.rawValue,
            method: "GET",
            path: "/v1/bootstrap",
            category: "system",
            summary: "Connection, permission, and route discovery for the local API.",
            execution: RouteExecutionPolicyDTO(
                lane: .sharedRead,
                backgroundBehavior: .backgroundRequired,
                focusStealPolicy: .forbidden,
                mainThreadBehavior: .avoid,
                readActRead: false,
                allowsConcurrentClients: true,
                notes: [
                    "Agents should read the local runtime manifest first, then call bootstrap with the manifest auth token to confirm runtime URL, permissions, and launch readiness.",
                    "When Accessibility or Screen Recording is missing, bootstrap returns user-facing instructions and presents a local permission alert.",
                ]
            ),
            implementationStatus: .implemented,
            notes: RuntimeMetadata.systemRouteNotes + [
                "Call this before action routes. If instructions.ready is false, pause action attempts until the user grants the requested macOS permissions and relaunches the signed app bundle.",
            ]
        ),
        RouteDescriptorDTO(
            id: RouteID.routes.rawValue,
            method: "GET",
            path: "/v1/routes",
            category: "system",
            summary: "Self-documenting route catalog for the API surface.",
            execution: RouteExecutionPolicyDTO(
                lane: .sharedRead,
                backgroundBehavior: .backgroundRequired,
                focusStealPolicy: .forbidden,
                mainThreadBehavior: .avoid,
                readActRead: false,
                allowsConcurrentClients: true,
                notes: [
                    "The route registry is the machine-readable source of truth for request and response shapes.",
                    "Read the runtime manifest and call /v1/bootstrap first, then use /v1/routes to plan action calls.",
                ]
            ),
            implementationStatus: .implemented,
            notes: RuntimeMetadata.systemRouteNotes + [
                "For visual work, call get_window_state with imageMode path or base64 whenever possible and inspect screenshots before and after actions.",
                "Use AX tree nodes for semantic targets, but treat screenshots as the visual ground truth because AX trees and verifier summaries can lag, be incomplete, or miss purely visual state.",
                "All POST routes decode strictly: an unknown top-level request field returns invalid_request naming the offending field(s) and the route's accepted fields. Match request.fields exactly.",
            ]
        ),
        RouteDescriptorDTO(
            id: RouteID.listApps.rawValue,
            method: "POST",
            path: "/v1/list_apps",
            category: "discovery",
            summary: "List targetable running apps.",
            execution: RouteExecutionPolicyDTO(
                lane: .sharedRead,
                backgroundBehavior: .backgroundRequired,
                focusStealPolicy: .forbidden,
                mainThreadBehavior: .avoid,
                readActRead: false,
                allowsConcurrentClients: true,
                notes: ["Discovery routes should remain independent of any one window lane."]
            ),
            implementationStatus: .implemented,
            notes: ["Discovery routes are coordinated by the shared-read runtime lane."]
        ),
        RouteDescriptorDTO(
            id: RouteID.listWindows.rawValue,
            method: "POST",
            path: "/v1/list_windows",
            category: "discovery",
            summary: "List windows for one exact running application PID.",
            execution: RouteExecutionPolicyDTO(
                lane: .sharedRead,
                backgroundBehavior: .backgroundRequired,
                focusStealPolicy: .forbidden,
                mainThreadBehavior: .avoid,
                readActRead: false,
                allowsConcurrentClients: true,
                notes: ["Window enumeration should stay outside per-window write lanes."]
            ),
            implementationStatus: .implemented,
            notes: [
                "Stable derived window IDs use bundle ID, pid, launch date, and window number.",
                "Only real AXWindow entries are returned; auxiliary AX containers and duplicate backing window IDs are excluded.",
            ]
        ),
        RouteDescriptorDTO(
            id: RouteID.launchApp.rawValue,
            method: "POST",
            path: "/v1/launch_app",
            category: "action",
            summary: "Authorize and launch an exact signed macOS app without foreground activation.",
            execution: actionPolicy(lane: .windowWrite, mainThreadBehavior: .allowed),
            implementationStatus: .implemented,
            notes: [
                "Resolves identity from the live or static code signature; request-supplied identity is never trusted.",
                "Control ask/deny and unavailable policy authority fail closed before NSWorkspace is called.",
                "A successful launch returns the exact PID, live window IDs, and foreground-preservation evidence.",
            ]
        ),
        RouteDescriptorDTO(
            id: RouteID.cursorFeedback.rawValue,
            method: "POST",
            path: "/v1/cursor_feedback",
            category: "feedback",
            summary: "Update the visible Agent cursor with public agent response text, observations, or a semantic pointing cue without dispatching input.",
            execution: RouteExecutionPolicyDTO(
                lane: .sharedRead,
                backgroundBehavior: .backgroundRequired,
                focusStealPolicy: .forbidden,
                mainThreadBehavior: .allowed,
                readActRead: false,
                allowsConcurrentClients: true,
                notes: [
                    "This route only updates the visual cursor overlay. It does not dispatch mouse, keyboard, AX, or window-motion input.",
                    "When window is omitted and the cursor session has no existing window attachment, feedback is accepted but visual presentation is deferred to prevent global overlays above unrelated apps.",
                ]
            ),
            implementationStatus: .implemented,
            notes: [
                "Use operation=update or append for public visible agent narration. Avoid route labels, tool names, product branding, and hidden chain-of-thought in feedback messages.",
                "Use finish for a short final dwell, hide to clear immediately, and point to schedule an asynchronous pointing cue.",
                "Feedback bubbles are excluded from model-facing screenshots and OCR by default.",
            ]
        ),
        RouteDescriptorDTO(
            id: RouteID.getWindowState.rawValue,
            method: "POST",
            path: "/v1/get_window_state",
            category: "state",
            summary: "Read the state surface for one window, including screenshot and projected tree.",
            execution: RouteExecutionPolicyDTO(
                lane: .windowRead,
                backgroundBehavior: .backgroundRequired,
                focusStealPolicy: .forbidden,
                mainThreadBehavior: .avoid,
                readActRead: false,
                allowsConcurrentClients: true,
                notes: ["Window-scoped reads should share a lane so future deduplication and caching can sit behind one contract."]
            ),
            implementationStatus: .implemented,
            notes: [
                "Default response is model-facing: resolved window, normalized screenshot, projected tree, menu/focus/selection, safety, performance, and notes.",
                "Pipeline internals stay opt-in under debug via debugMode summary/full or specific includeRawCapture/includeSemanticTree/includeProjectedTree/includePlatformProfile/includeDiagnostics flags.",
            ]
        ),
        RouteDescriptorDTO(
            id: RouteID.findElements.rawValue,
            method: "POST",
            path: "/v1/find_elements",
            category: "state",
            summary: "Find matching projected nodes without returning the full window tree.",
            execution: RouteExecutionPolicyDTO(
                lane: .windowRead,
                backgroundBehavior: .backgroundRequired,
                focusStealPolicy: .forbidden,
                mainThreadBehavior: .avoid,
                readActRead: false,
                allowsConcurrentClients: true,
                notes: ["This read-only route filters one state capture and returns its stateToken and interactionToken unchanged."]
            ),
            implementationStatus: .implemented,
            notes: [
                "Use role and/or text to return only matching projected nodes.",
                "Returned targets and interactionToken come from the same capture and are directly actionable.",
            ]
        ),
        RouteDescriptorDTO(
            id: RouteID.runScript.rawValue,
            method: "POST",
            path: "/v1/run_script",
            category: "action",
            summary: "Execute arbitrary AppleScript or JavaScript for Automation with an enforced timeout and owner-only audit log.",
            execution: RouteExecutionPolicyDTO(
                lane: .windowWrite,
                backgroundBehavior: .backgroundRequired,
                focusStealPolicy: .forbidden,
                mainThreadBehavior: .avoid,
                readActRead: false,
                allowsConcurrentClients: true,
                notes: [
                    "This mutating lane participates in action throttling and session exclusion.",
                    "It dispatches arbitrary Apple Events source without effect verification.",
                    "The signed BCU Control app blocks this route with control_policy_required because arbitrary source cannot be scoped to one approved app identity.",
                ]
            ),
            implementationStatus: .implemented,
            notes: [
                "Process-level status and output do not prove any UI effect.",
                "Confirm intended effects with get_window_state or find_elements after execution.",
                "Audit log: $TMPDIR/background-computer-use/audit/script-executions.jsonl (0600 in a 0700 directory).",
            ]
        ),
        RouteDescriptorDTO(
            id: RouteID.waitFor.rawValue,
            method: "POST",
            path: "/v1/wait_for",
            category: "state",
            summary: "Wait for a matching UI condition to appear, disappear, or change, then return fresh state.",
            execution: RouteExecutionPolicyDTO(
                lane: .windowRead,
                backgroundBehavior: .backgroundRequired,
                focusStealPolicy: .forbidden,
                mainThreadBehavior: .avoid,
                readActRead: true,
                allowsConcurrentClients: true,
                notes: ["Polls the target window state instead of forcing clients to hand-roll get_window_state loops."]
            ),
            implementationStatus: .implemented,
            notes: [
                "Match by role, label text, value text, window title, URL-bearing nodes, rendered text, or any combination.",
                "Use gone=true for supported disappearance waits. Intermediate polls omit screenshots and the response returns one fresh final state.",
            ]
        ),
        RouteDescriptorDTO(
            id: RouteID.annotateWindow.rawValue,
            method: "POST",
            path: "/v1/annotate_window",
            category: "state",
            summary: "Return a model-facing screenshot with numbered visual marks and matching semantic targets.",
            execution: RouteExecutionPolicyDTO(
                lane: .windowRead,
                backgroundBehavior: .backgroundRequired,
                focusStealPolicy: .forbidden,
                mainThreadBehavior: .allowed,
                readActRead: false,
                allowsConcurrentClients: true,
                notes: [
                    "Uses normal background-safe state capture, then draws an opt-in annotated screenshot artifact.",
                    "Annotations are for visual grounding only; action routes still require semantic targets or explicit coordinates.",
                ]
            ),
            implementationStatus: .implemented,
            notes: [
                "Use this when a raw screenshot and AX tree are hard to align visually.",
                "Marks are bounded and include reusable display_index/node_id/refetch targets when available.",
            ]
        ),
        RouteDescriptorDTO(
            id: RouteID.click.rawValue,
            method: "POST",
            path: "/v1/click",
            category: "action",
            summary: "Dispatch a click against a semantic target or screenshot coordinate and return refreshed state.",
            execution: actionPolicy(lane: .windowWrite, mainThreadBehavior: .avoid),
            implementationStatus: .implemented,
            notes: [
                "Uses semantic AX first for eligible targets, then native target-only SLPS/SLEvent background pointer dispatch for target-derived and direct x/y coordinates.",
                "Coordinate clicks default to a single click; double-click is used only when explicitly requested.",
                "Right and middle mouse buttons are reported as unsupported rather than mapped to hidden secondary/default actions.",
            ]
        ),
        RouteDescriptorDTO(
            id: RouteID.scroll.rawValue,
            method: "POST",
            path: "/v1/scroll",
            category: "action",
            summary: "Dispatch a scroll action against a semantic target and return refreshed state.",
            execution: actionPolicy(lane: .windowWrite, mainThreadBehavior: .avoid),
            implementationStatus: .implemented,
            notes: [
                "Ranks the target and ancestor panes, classifies the surface, tries AX dispatch first, then uses targeted wheel or process-scoped paging fallbacks with reread verification.",
                "The route preserves honest classifications including success, boundary, unsupported, unresolved, and verifier_ambiguous.",
            ]
        ),
        RouteDescriptorDTO(
            id: RouteID.performSecondaryAction.rawValue,
            method: "POST",
            path: "/v1/perform_secondary_action",
            category: "action",
            summary: "Dispatch an exposed secondary action label against a semantic target and return verification evidence.",
            execution: actionPolicy(lane: .windowWrite, mainThreadBehavior: .avoid),
            implementationStatus: .implemented,
            notes: [
                "Dispatches an exact public secondary-action label against the requested semantic target.",
                "Dispatch is AX-only through captured action bindings; no LaunchServices, shell open, primary click, typing, keypress, or file-open fallback is used.",
                "Outcome classification is verifier-first. transports[].rawAXStatus is diagnostic AX telemetry and can report an error even when the requested effect verifies.",
            ]
        ),
        RouteDescriptorDTO(
            id: RouteID.drag.rawValue,
            method: "POST",
            path: "/v1/drag",
            category: "action",
            summary: "Move a window or drag target using background-safe motion and return refreshed motion state.",
            execution: actionPolicy(lane: .windowWrite, mainThreadBehavior: .allowed),
            implementationStatus: .implemented,
            notes: ["Window motion uses the shared planner/executor/verifier flow and reports background-safety observations with motion telemetry."]
        ),
        RouteDescriptorDTO(
            id: RouteID.resize.rawValue,
            method: "POST",
            path: "/v1/resize",
            category: "action",
            summary: "Resize a window from a named handle and return refreshed motion state.",
            execution: actionPolicy(lane: .windowWrite, mainThreadBehavior: .allowed),
            implementationStatus: .implemented,
            notes: ["Resize shares the same window-motion stack, lane policy, and verification model as drag."]
        ),
        RouteDescriptorDTO(
            id: RouteID.setWindowFrame.rawValue,
            method: "POST",
            path: "/v1/set_window_frame",
            category: "action",
            summary: "Set a target window frame directly and return refreshed motion state.",
            execution: actionPolicy(lane: .windowWrite, mainThreadBehavior: .allowed),
            implementationStatus: .implemented,
            notes: ["set_window_frame is the canonical window-layout route and shares the same motion telemetry surface as drag and resize."]
        ),
        RouteDescriptorDTO(
            id: RouteID.typeText.rawValue,
            method: "POST",
            path: "/v1/type_text",
            category: "action",
            summary: "Type text into a targeted or focused text-entry element and return verification evidence.",
            execution: actionPolicy(lane: .windowWrite, mainThreadBehavior: .avoid),
            implementationStatus: .implemented,
            notes: [
                "Prepares the target window without global activation, uses element-bound AX writes or confirmed PID-scoped Unicode delivery, and verifies exact text state.",
                "Success requires foreground preservation; no public focus mode or Return submission is hidden inside the route.",
            ]
        ),
        RouteDescriptorDTO(
            id: RouteID.paste.rawValue,
            method: "POST",
            path: "/v1/paste",
            category: "action",
            summary: "Paste text, Markdown, or HTML into an exact text target and restore the clipboard.",
            execution: actionPolicy(lane: .windowWrite, mainThreadBehavior: .avoid),
            implementationStatus: .implemented,
            notes: [
                "Paste focuses the exact target through the verified background click lane, dispatches Command-V to the target PID, and restores all original pasteboard items.",
                "Success requires exact target text verification, clipboard restoration, and foreground preservation.",
            ]
        ),
        RouteDescriptorDTO(
            id: RouteID.pressKey.rawValue,
            method: "POST",
            path: "/v1/press_key",
            category: "action",
            summary: "Press a key or key chord against the target window and return refreshed state.",
            execution: actionPolicy(lane: .windowWrite, mainThreadBehavior: .avoid),
            implementationStatus: .implemented,
            notes: [
                "Routes high-level chords through semantic AX operations when a generic, window-local equivalent can be verified, then falls back to WindowServer target-window preflight plus native CGEvent postToPid key delivery.",
                "The response reports the actual route used so callers can distinguish semantic actions from native key dispatch.",
                "If native key delivery dispatches but no effect is verified, the response warns callers to perform a safe click in the target content surface before retrying.",
            ]
        ),
        RouteDescriptorDTO(
            id: RouteID.setValue.rawValue,
            method: "POST",
            path: "/v1/set_value",
            category: "action",
            summary: "Set a value directly on a semantic replacement target and return verification evidence.",
            execution: actionPolicy(lane: .windowWrite, mainThreadBehavior: .avoid),
            implementationStatus: .implemented,
            notes: [
                "Uses direct AXUIElementSetAttributeValue(kAXValueAttribute), typed coercion, cursor approach, settle, reread, and exact-value verification.",
                "set_value does not type, focus, press Return, submit, or auto-confirm.",
                "Outcome classification is verifier-first. rawAXStatus is diagnostic AX telemetry and does not by itself decide success or failure.",
            ]
        ),
        RouteDescriptorDTO(
            id: RouteID.readText.rawValue,
            method: "POST",
            path: "/v1/read_text",
            category: "state",
            summary: "Read a full text value from a semantic target, with offset/length chunking.",
            execution: RouteExecutionPolicyDTO(
                lane: .windowRead,
                backgroundBehavior: .backgroundRequired,
                focusStealPolicy: .forbidden,
                mainThreadBehavior: .avoid,
                readActRead: false,
                allowsConcurrentClients: true,
                notes: ["Use this when projected value previews are truncated or logs/documents are too long for the model-facing tree."]
            ),
            implementationStatus: .implemented,
            notes: ["Reads kAXValueAttribute from the resolved live element and returns a bounded text slice."]
        ),
        RouteDescriptorDTO(
            id: RouteID.selectText.rawValue,
            method: "POST",
            path: "/v1/select_text",
            category: "action",
            summary: "Select text inside a semantic text target by exact substring and occurrence.",
            execution: actionPolicy(lane: .windowWrite, mainThreadBehavior: .avoid),
            implementationStatus: .implemented,
            notes: ["Sets kAXSelectedTextRangeAttribute directly. Use position before/after to place the caret around a text landmark."]
        ),
    ]

    static func descriptor(for routeID: RouteID) -> RouteDescriptorDTO {
        descriptors.first(where: { $0.id == routeID.rawValue })!
    }

    /// Documented top-level request field names for a route, in declaration order.
    /// Source of truth for strict request decoding (rejecting unknown top-level fields).
    static func requestFieldNames(for routeID: RouteID) -> [String] {
        (requestSchema(for: routeID.rawValue)?.fields ?? []).map(\.name)
    }

    static func bootstrapRouteDescriptors(baseURL: URL) -> [BootstrapRouteDTO] {
        descriptors.map { descriptor in
            BootstrapRouteDTO(
                id: descriptor.id,
                method: descriptor.method,
                path: descriptor.path,
                url: baseURL.appendingPathComponent(descriptor.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))).absoluteString,
                category: descriptor.category,
                summary: descriptor.summary
            )
        }
    }

    static func publicRoutes() -> [APIRouteDTO] {
        descriptors.map(publicRoute)
    }

    private static func publicRoute(_ descriptor: RouteDescriptorDTO) -> APIRouteDTO {
        APIRouteDTO(
            id: descriptor.id,
            method: descriptor.method,
            path: descriptor.path,
            category: descriptor.category,
            summary: descriptor.summary,
            notes: descriptor.notes,
            execution: descriptor.execution,
            implementationStatus: descriptor.implementationStatus,
            usage: APIDocumentation.usage(for: descriptor.id),
            request: requestSchema(for: descriptor.id),
            response: responseSchema(for: descriptor.id),
            errors: APIDocumentation.errors(for: descriptor.id)
        )
    }

    private static func requestSchema(for routeID: String) -> RouteBodySchemaDTO? {
        switch routeID {
        case RouteID.health.rawValue, RouteID.bootstrap.rawValue, RouteID.routes.rawValue:
            return nil
        case RouteID.listApps.rawValue:
            return json([])
        case RouteID.listWindows.rawValue:
            return json([
                field("pid", "integer", required: true, "Positive process identifier returned by list_apps."),
            ])
        case RouteID.launchApp.rawValue:
            return json([
                field("bundleID", "string | null", "Supply exactly one of bundleID or canonical appPath."),
                field("appPath", "string | null", "Canonical local .app path. Supply exactly one target form."),
                field("sessionID", "string", required: true, "Runtime task session used to scope allow-once decisions."),
            ])
        case RouteID.cursorFeedback.rawValue:
            return json([
                field("operation", "update | append | finish | hide | point", required: true),
                field("state", "idle | moving | acting | waiting | streaming | pointing | error", "Visual feedback state. Defaults from operation when omitted."),
                field("message", "string", "Public visible agent response or observation to show in the cursor-attached feedback bubble."),
                field("append", "boolean", "When true, append message to existing feedback text.", defaultValue: "false"),
                field("cursor", "CursorRequest"),
                field("window", "string", "Optional stable window ID. Provide it for immediate visible feedback before the cursor has an existing window attachment."),
                field("x", "number", "Optional AppKit-global x coordinate used as feedback anchor or pointing target."),
                field("y", "number", "Optional AppKit-global y coordinate used as feedback anchor or pointing target."),
                field("dwellMs", "number", "Optional finished/pointing dwell duration in milliseconds."),
                debugField(),
            ])
        case RouteID.getWindowState.rawValue:
            return json([
                field("window", "string", required: true, "Stable window ID from list_windows."),
                field("includeMenuBar", "boolean", "Include macOS menu bar nodes in the state capture.", defaultValue: "true"),
                field("menuPath", "string[]", "Optional menu path to open before reading transient menu state, e.g. [\"File\"]."),
                field("webTraversal", "visible | full", "Use full only for deep WebKit/Electron parity/debug traversal; visible keeps the fast AXVisibleChildren default for web areas.", defaultValue: "visible"),
                field("maxNodes", "integer", defaultValue: "6500"),
                field("imageMode", "path | base64 | omit", defaultValue: "path"),
                field("includeRawScreenshot", "boolean", defaultValue: "false"),
                field("debugMode", "none | summary | full", defaultValue: "none"),
                field("debug", "boolean", defaultValue: "false"),
                field("includeDiagnostics", "boolean"),
                field("includePlatformProfile", "boolean"),
                field("includeRawCapture", "boolean"),
                field("includeSemanticTree", "boolean"),
                field("includeProjectedTree", "boolean"),
                field("includeOCR", "boolean", "When true, run local Apple Vision OCR on the returned screenshot and include text anchors.", defaultValue: "false"),
                field("scopeTarget", #"{"kind":"display_index"|"node_id"|"refetch_fingerprint","value":integer|string}"#, "Optional target used to return only that node and its descendants in tree while keeping stable target indices."),
            ])
        case RouteID.findElements.rawValue:
            return json([
                field("window", "string", required: true, "Stable window ID from list_windows."),
                field("role", "string", "Exact projected displayRole or raw AX role, case-insensitive. At least role or text is required."),
                field("text", "string", "Case-insensitive substring across node title, description, help, and value preview. At least role or text is required."),
                field("includeMenuBar", "boolean", "Include macOS menu bar nodes in the capture.", defaultValue: "true"),
                field("webTraversal", "visible | full", "Use full only when the required web element is outside visible traversal.", defaultValue: "visible"),
                field("maxNodes", "integer", defaultValue: "6500"),
            ])
        case RouteID.runScript.rawValue:
            return json([
                field("language", "applescript | javascript", required: true),
                field("source", "string", required: true, "Arbitrary AppleScript or JavaScript for Automation source. Audit-logged owner-only."),
                field("timeoutMs", "integer", "Enforced execution timeout; values above 30000 are capped.", defaultValue: "10000"),
            ])
        case RouteID.annotateWindow.rawValue:
            return json([
                field("window", "string", required: true, "Stable window ID from list_windows."),
                field("includeMenuBar", "boolean", defaultValue: "false"),
                field("webTraversal", "visible | full", "Use full only for deep WebKit/Electron parity/debug traversal; visible keeps the fast AXVisibleChildren default for web areas.", defaultValue: "visible"),
                field("maxNodes", "integer", defaultValue: "6500"),
                field("maxMarks", "integer", "Maximum numbered marks to draw and return.", defaultValue: "80"),
                field("includeStaticText", "boolean", "When true, include static text nodes with frames in addition to actionable controls.", defaultValue: "false"),
                field("imageMode", "path | base64", "Return annotated image as a file path, or also inline PNG bytes as base64.", defaultValue: "path"),
            ])
        case RouteID.waitFor.rawValue:
            return json([
                field("window", "string", required: true),
                field("role", "string", "Optional display role to match."),
                field("label", "string", "Match title or description text, case-insensitive substring."),
                field("valueContains", "string", "Match the target value preview, case-insensitive substring."),
                field("windowTitleContains", "string", "Match the resolved window title, case-insensitive substring."),
                field("windowTitleChanged", "boolean", "Wait until the resolved window title differs from the first polled title.", defaultValue: "false"),
                field("urlContains", "string", "Match URL strings exposed by projected AX nodes, case-insensitive substring."),
                field("textContains", "string", "Match the projected rendered text, case-insensitive substring."),
                field("gone", "boolean", "Wait for the match to disappear instead of appear.", defaultValue: "false"),
                field("timeoutSeconds", "number", defaultValue: "10"),
                field("pollIntervalMs", "integer", defaultValue: "400"),
                field("includeMenuBar", "boolean"),
                field("maxNodes", "integer"),
                field("imageMode", "path | base64 | omit", "Controls only the returned final state; intermediate polls omit screenshots.", defaultValue: "path"),
            ])
        case RouteID.click.rawValue:
            return clickRequestSchema()
        case RouteID.scroll.rawValue:
            return json([
                field("window", "string", required: true),
                field("stateToken", "string"),
                actionTargetField(
                    required: true,
                    "Semantic target from get_window_state. Prefer node_id or refetch_fingerprint when available; display_index uses the rendered tree line number."
                ),
                field("direction", "up | down | left | right", required: true),
                field("pages", "number"),
                field("cursor", "CursorRequest"),
                field("includeMenuBar", "boolean"),
                field("maxNodes", "integer"),
                debugField(),
            ])
        case RouteID.performSecondaryAction.rawValue:
            return json([
                field("window", "string", required: true),
                field("stateToken", "string"),
                actionTargetField(
                    required: true,
                    "Semantic target whose secondaryActions or secondaryActionBindings include the requested label."
                ),
                field("action", "string", required: true, "Exact public label from the target node's secondaryActions array."),
                field("actionID", "string", "Optional stable descriptor ID from secondaryActionBindings; resolves before label fallback."),
                field("menuPath", "string[]", "Optional menu path to open during the pre-action read, e.g. [\"File\"]."),
                field("webTraversal", "visible | full", "Use full only for deep WebKit/Electron parity/debug traversal; visible keeps the fast AXVisibleChildren default for web areas.", defaultValue: "visible"),
                field("cursor", "CursorRequest"),
                field("includeMenuBar", "boolean"),
                field("maxNodes", "integer"),
                field("imageMode", "path | base64 | omit"),
                confirmField(),
                debugField(),
            ])
        case RouteID.drag.rawValue:
            return json([
                field("window", "string", required: true),
                field("toX", "number", required: true, "Destination window-origin x in AppKit-global logical points with a bottom-left origin."),
                field("toY", "number", required: true, "Destination window-origin y in AppKit-global logical points with a bottom-left origin."),
                field("cursor", "CursorRequest"),
            ])
        case RouteID.resize.rawValue:
            return json([
                field("window", "string", required: true),
                field("handle", "ResizeHandle", required: true),
                field("toX", "number", required: true, "Destination handle x in AppKit-global logical points with a bottom-left origin."),
                field("toY", "number", required: true, "Destination handle y in AppKit-global logical points with a bottom-left origin."),
                field("cursor", "CursorRequest"),
            ])
        case RouteID.setWindowFrame.rawValue:
            return json([
                field("window", "string", required: true),
                field("x", "number", required: true),
                field("y", "number", required: true),
                field("width", "number", required: true),
                field("height", "number", required: true),
                field("animate", "boolean", defaultValue: "true"),
                field("cursor", "CursorRequest"),
            ])
        case RouteID.typeText.rawValue:
            return json([
                field("window", "string", required: true),
                field("stateToken", "string"),
                actionTargetField(
                    required: false,
                    "Optional semantic text-entry target. Omit to type into the current focused text entry."
                ),
                field("text", "string", required: true),
                field(
                    "allowOpaqueFocusedSurface",
                    "boolean",
                    "After a coordinate click focuses a known text entry on an AX-opaque surface, allow PID-scoped Unicode posting when no semantic focused target is visible. Also requires confirm=true.",
                    defaultValue: "false"
                ),
                field("cursor", "CursorRequest"),
                field("includeMenuBar", "boolean"),
                field("maxNodes", "integer"),
                confirmField("Required to type into secure/password-like text entries."),
                debugField(),
            ])
        case RouteID.paste.rawValue:
            return json([
                field("window", "string", required: true),
                field("stateToken", "string"),
                actionTargetField(required: true, "Exact semantic text-entry target."),
                field("content", "string", required: true),
                field("format", "text | markdown | html", required: true),
                field("cursor", "CursorRequest"),
                field("includeMenuBar", "boolean"),
                field("maxNodes", "integer"),
                confirmField("Required for secure/password-like text entries."),
                debugField(),
            ])
        case RouteID.pressKey.rawValue:
            return json([
                field("window", "string", required: true),
                field("stateToken", "string"),
                field("key", "string", required: true, "Key or chord separated by +. Modifier aliases: command/cmd/meta/super, control/ctrl, option/alt, and shift. Examples: command+f, ctrl+shift+tab, option+left."),
                field("cursor", "CursorRequest"),
                field("includeMenuBar", "boolean"),
                field("maxNodes", "integer"),
                field("imageMode", "path | base64 | omit"),
                confirmField("Required for destructive shortcuts such as Command-Backspace or Command-Delete."),
                debugField(),
            ])
        case RouteID.setValue.rawValue:
            return json([
                field("window", "string", required: true),
                field("stateToken", "string"),
                actionTargetField(
                    required: true,
                    "Semantic target that reports value-set support."
                ),
                field("value", "string", required: true),
                field("cursor", "CursorRequest"),
                field("includeMenuBar", "boolean"),
                field("maxNodes", "integer"),
                confirmField("Required to write secure/password-like fields or clear an existing value."),
                debugField(),
            ])
        case RouteID.readText.rawValue:
            return json([
                field("window", "string", required: true),
                actionTargetField(required: true, "Semantic text target whose full AX value should be read."),
                field("offset", "integer", defaultValue: "0"),
                field("length", "integer", defaultValue: "20000"),
                field("includeMenuBar", "boolean"),
                field("maxNodes", "integer"),
            ])
        case RouteID.selectText.rawValue:
            return json([
                field("window", "string", required: true),
                field("stateToken", "string"),
                actionTargetField(required: true, "Semantic text target where the substring should be selected."),
                field("text", "string", required: true),
                field("occurrence", "integer", defaultValue: "1"),
                field("position", "select | before | after", defaultValue: "select"),
                field("includeMenuBar", "boolean"),
                field("maxNodes", "integer"),
                field("imageMode", "path | base64 | omit"),
                confirmField("Required to select text inside secure/password-like fields."),
                debugField(),
            ])
        default:
            return nil
        }
    }

    private static func responseSchema(for routeID: String) -> RouteBodySchemaDTO {
        switch routeID {
        case RouteID.health.rawValue:
            return json([
                field("ok", "boolean", required: true),
                field("contractVersion", "string", required: true),
                field("timestamp", "string", required: true),
            ])
        case RouteID.bootstrap.rawValue:
            return json([
                field("contractVersion", "string", required: true),
                field("baseURL", "string | null", required: true),
                field("startedAt", "string | null", required: true),
                field("permissions", "RuntimePermissions", required: true),
                field("instructions", "BootstrapInstructions", required: true),
                field("guide", "APIGuide", required: true, "High-level operating flow, common concepts, response interpretation, and troubleshooting guidance."),
                field("routes", "BootstrapRoute[]", required: true),
            ])
        case RouteID.routes.rawValue:
            return json([
                field("contractVersion", "string", required: true),
                field("guide", "APIGuide", required: true, "High-level operating flow, common concepts, response interpretation, and troubleshooting guidance."),
                field("routes", "APIRoute[]", required: true),
            ])
        case RouteID.listApps.rawValue:
            return json([
                field("contractVersion", "string", required: true),
                field("frontmostApp", "RunningApp | null", required: true),
                field("runningApps", "RunningApp[]", required: true),
                field("notes", "string[]", required: true),
            ])
        case RouteID.listWindows.rawValue:
            return json([
                field("contractVersion", "string", required: true),
                field("app", "AppReference", required: true),
                field("windows", "WindowSummary[]", required: true, "Each window includes attachedSurfaces discovered through AXSheet/AXDialog relationships."),
                field("notes", "string[]", required: true),
            ])
        case RouteID.launchApp.rawValue:
            return json([
                field("contractVersion", "string", required: true),
                field("ok", "boolean", required: true),
                field("classification", "success | unsupported | effect_not_verified | verifier_ambiguous", required: true),
                field("failureDomain", "unsupported | background_safety | null"),
                field("summary", "string", required: true),
                field("identity", "AppIdentity | null"),
                field("policyDecision", "ask | allowOnce | alwaysAllow | deny", required: true),
                field("pid", "integer | null"),
                field("launchState", "blocked | already_running | launched", required: true),
                field("windows", "string[]", required: true),
                field("activates", "boolean", required: true),
                field("foregroundPIDBefore", "integer | null"),
                field("foregroundPIDAfter", "integer | null"),
                field("foregroundPreserved", "boolean", required: true),
                field("foregroundFallbackUsed", "boolean", required: true, "Whether launch completion involved the target becoming foreground."),
                field("foregroundRestored", "boolean", required: true, "Whether BCU restored the application that was frontmost before launch."),
            ])
        case RouteID.cursorFeedback.rawValue:
            return json([
                field("contractVersion", "string", required: true),
                field("ok", "boolean", required: true),
                field("operation", "update | append | finish | hide | point", required: true),
                field("state", "idle | moving | acting | waiting | streaming | pointing | error", required: true),
                field("message", "string | null"),
                field("cursor", "CursorResponse", required: true),
                field("attachment", "window | deferred | disabled", required: true),
                field("targetPointAppKit", "Point | null"),
                field("clamped", "boolean", required: true),
                field("plannedDurationMs", "number | null"),
                field("warnings", "string[]", required: true),
            ])
        case RouteID.getWindowState.rawValue:
            return json([
                field("contractVersion", "string", required: true),
                field("stateToken", "string", required: true),
                field("interactionToken", "string", required: true, "Stable across rendered-text-only changes; changes when target identity or geometry changes."),
                field("window", "ResolvedWindow", required: true),
                field("attachedSurfaces", "AttachedSurface[]", required: true, "Live same-process sheets/dialogs attached to the root window."),
                field("screenshot", "Screenshot", required: true),
                field("tree", "AXTree", required: true, "Projected nodes expose displayIndex, nodeID, and refetchFingerprint as canonical action locators plus domIdentifier when the app publishes AXDOMIdentifier; nested identity/refetch locator objects are not serialized."),
                field("menuPresentation", "AXMenuPresentation | null"),
                field("focusedElement", "FocusedElement", required: true),
                field("selectionSummary", "AXFocusSelectionSnapshot | null"),
                field("backgroundSafety", "BackgroundSafety", required: true),
                field("performance", "ReadPerformance", required: true, "resolveMs, captureMs, projectionMs, screenshotMs, totalMs, plus ocrMs when includeOCR ran Apple Vision."),
                field("debug", "GetWindowStateDebug | null"),
                field("ocr", "OCRAnchorSummary | null"),
                field("notes", "string[]", required: true),
            ])
        case RouteID.findElements.rawValue:
            return json([
                field("contractVersion", "string", required: true),
                field("stateToken", "string", required: true, "Token from the state capture that produced matches."),
                field("interactionToken", "string", required: true, "Token from the same capture; pass it with directly actionable targets when required."),
                field("window", "ResolvedWindow", required: true),
                field("query", "FindElementsQuery", required: true),
                field("matches", "AXNode[]", required: true, "Only nodes matching every supplied query field; never the full tree."),
                field("matchCount", "integer", required: true),
                field("summary", "string", required: true),
                field("notes", "string[]", required: true),
            ])
        case RouteID.runScript.rawValue:
            return json([
                field("contractVersion", "string", required: true),
                field("language", "applescript | javascript", required: true),
                field("status", "integer", required: true, "osascript process exit status; process-level only."),
                field("stdout", "string", required: true),
                field("stderr", "string", required: true, "Compilation/runtime script failures are returned here with non-zero status."),
                field("stdoutTruncated", "boolean", required: true, "True when captured stdout exceeded 1048576 bytes; excess bytes were drained and discarded."),
                field("stderrTruncated", "boolean", required: true, "True when captured stderr exceeded 1048576 bytes; excess bytes were drained and discarded."),
                field("durationMs", "number", required: true),
                field("timedOut", "boolean", required: true),
                field("effectiveTimeoutMs", "integer", required: true, "Actual enforced timeout after applying the runtime cap."),
            ])
        case RouteID.annotateWindow.rawValue:
            return json([
                field("contractVersion", "string", required: true),
                field("stateToken", "string", required: true),
                field("window", "ResolvedWindow", required: true),
                field("screenshot", "Screenshot", required: true),
                field("annotatedImage", "ScreenshotImage | null"),
                field("marks", "WindowAnnotationMark[]", required: true),
                field("truncated", "boolean", required: true),
                field("maxMarks", "integer", required: true),
                field("backgroundSafety", "BackgroundSafety", required: true),
                field("performance", "ReadPerformance", required: true),
                field("notes", "string[]", required: true),
            ])
        case RouteID.waitFor.rawValue:
            return json([
                field("contractVersion", "string", required: true),
                field("ok", "boolean", required: true),
                field("conditionMet", "boolean", required: true),
                field("elapsedMs", "number", required: true),
                field("summary", "string", required: true),
                field("state", "AXPipelineV2Response", required: true),
                field("notes", "string[]", required: true),
            ])
        case RouteID.click.rawValue:
            return clickActionResponse()
        case RouteID.scroll.rawValue:
            return scrollActionResponse()
        case RouteID.performSecondaryAction.rawValue:
            return secondaryActionResponse()
        case RouteID.drag.rawValue:
            return actionResponse("DragResponse")
        case RouteID.resize.rawValue:
            return actionResponse("ResizeResponse")
        case RouteID.setWindowFrame.rawValue:
            return actionResponse("SetWindowFrameResponse")
        case RouteID.typeText.rawValue:
            return textActionResponse("TypeTextResponse")
        case RouteID.paste.rawValue:
            return json([
                field("contractVersion", "string", required: true),
                field("ok", "boolean", required: true),
                field("classification", "success | unsupported | effect_not_verified | verifier_ambiguous", required: true),
                field("failureDomain", "targeting | unsupported | transport | verification | background_safety | null"),
                field("summary", "string", required: true),
                field("window", "ResolvedWindow | null"),
                field("target", "AXActionTarget | null"),
                field("format", "text | markdown | html", required: true),
                field("contentLength", "integer", required: true),
                field("dispatchPrimitive", "string | null"),
                field("dispatchSucceeded", "boolean | null"),
                field("pasteboardRestored", "boolean", required: true),
                field("preStateToken", "string | null"),
                field("postStateToken", "string | null"),
                field("cursor", "ActionCursorTarget", required: true),
                field("warnings", "string[]", required: true),
                debugNotesField(),
                field("backgroundSafety", "TypeTextBackgroundSafety | null"),
                field("verification", "PasteVerification | null"),
            ])
        case RouteID.pressKey.rawValue:
            return pressKeyActionResponse()
        case RouteID.setValue.rawValue:
            return textActionResponse("SetValueResponse")
        case RouteID.readText.rawValue:
            return json([
                field("contractVersion", "string", required: true),
                field("ok", "boolean", required: true),
                field("summary", "string", required: true),
                field("window", "ResolvedWindow", required: true),
                field("target", "AXActionTarget", required: true),
                field("chunk", "TextChunk", required: true),
                field("warnings", "string[]", required: true),
            ])
        case RouteID.selectText.rawValue:
            return json([
                field("contractVersion", "string", required: true),
                field("ok", "boolean", required: true),
                field("classification", "success | unsupported | effect_not_verified | verifier_ambiguous", required: true),
                field("failureDomain", "targeting | unsupported | coercion | transport | verification | background_safety | app_specific_semantics | null"),
                field("summary", "string", required: true),
                field("window", "ResolvedWindow | null"),
                field("target", "AXActionTarget | null"),
                field("selectedRange", "TextSelectionRange | null"),
                field("preStateToken", "string | null"),
                field("postStateToken", "string | null"),
                field("postScreenshot", "Screenshot | null", "Returned when imageMode is path or base64 and the post-action reread captures an image."),
                field("warnings", "string[]", required: true),
                debugNotesField(),
            ])
        default:
            return json([
                field("contractVersion", "string", required: true),
                field("requestID", "string", required: true),
                field("status", "string", required: true),
                field("route", "RouteSummary", required: true),
                field("target", "RouteTargetSummary", required: true),
                field("notes", "string[]", required: true),
            ])
        }
    }

    private static func actionResponse(_ type: String) -> RouteBodySchemaDTO {
        json([
            field("contractVersion", "string", required: true),
            field("ok", "boolean", required: true),
            field("cursor", "CursorResponse", required: true),
            field("action", type + ".action", required: true),
            field("window", "MotionWindow", required: true),
            field("backgroundSafety", "BackgroundSafety", required: true),
            field("performance", "MotionPerformance", required: true),
            field("error", "ActionError | null"),
        ])
    }

    private static func clickRequestSchema() -> RouteBodySchemaDTO {
        json([
            field("window", "string", required: true),
            field("stateToken", "string"),
            field("interactionToken", "string", "Required with target.kind=ocr_anchor. Copy from the same get_window_state response that produced the OCR anchor."),
            actionTargetField(
                required: false,
                includeOCR: true,
                "Semantic target from get_window_state, or a local OCR anchor from get_window_state.ocr. Mutually exclusive with x/y."
            ),
            field("x", "number", "Model-facing screenshot x coordinate. Must be supplied with y and without target."),
            field("y", "number", "Model-facing screenshot y coordinate. Must be supplied with x and without target."),
            field("mode", "single | double", "Explicit click mode. Omitted mode defaults to single.", defaultValue: "single"),
            field("clickCount", "integer", "Explicit exact click count. Supported values are 1 and 2."),
            field("mouseButton", "left | right | middle", defaultValue: "left"),
            field("cursor", "CursorRequest"),
            field("includeMenuBar", "boolean"),
            field("maxNodes", "integer"),
            field("imageMode", "path | base64 | omit"),
            confirmField(),
            debugField(),
        ])
    }

    private static func clickActionResponse() -> RouteBodySchemaDTO {
        json([
            field("contractVersion", "string", required: true),
            field("ok", "boolean", required: true),
            field("classification", "success | unsupported | effect_not_verified | verifier_ambiguous", required: true),
            field("failureDomain", "targeting | unsupported | transport | verification | null"),
            field("summary", "string", required: true),
            field("window", "ResolvedWindow | null"),
            field("requestedTarget", "ClickRequestedTarget", required: true),
            field("target", "AXActionTarget | null"),
            field("clickCount", "integer | null"),
            field("mouseButton", "left | right | middle | null"),
            field("finalRoute", "coordinate_xy | ocr_anchor_xy | semantic_ax | ax_element_pointer_xy | semantic_ax_then_remaining_xy | coordinate_then_ax_hit_test | rejected", required: true),
            field("fallbackReason", "none | ax_coordinate_required | ax_multi_click_requires_xy | ax_first_click_unverified_using_full_element_pointer | missing_stable_ax_coordinate | unsupported_mouse_button | invalid_click_count | invalid_target | stale_coordinate_guard | transport_failed | coordinate_unverified_using_ax_hit_test", required: true),
            field("axAttempt", "exact_primary_ax_action | set_container_selected_rows | set_row_selected_true | safe_unique_descendant_retarget | ambiguous_descendant_click | coordinate_required | unsupported_primary_click | none | null"),
            field("coordinate", "ClickCoordinateMapping | null"),
            field("transports", "ClickTransportAttempt[]", required: true),
            field("routeSteps", "ClickRouteStep[]", required: true),
            field("preStateToken", "string | null"),
            field("postStateToken", "string | null"),
            field("cursor", "ActionCursorTarget", required: true),
            field("frontmostBundleBefore", "string | null"),
            field("frontmostBundleBeforeDispatch", "string | null"),
            field("frontmostBundleAfter", "string | null"),
            field("warnings", "string[]", required: true),
            debugNotesField(),
            field("performance", "ActionPerformance | null", "Monotonic route latency. Stage fields are populated as measurement seams become available; totalMs covers the complete click call."),
            field("verification", "ClickVerification | null", "Effect evidence. intentSignals lists the target-local or structural signals that justified success (target_region_changed, ocr_anchor_disappeared, focused_element_changed, modal_dialog_opened, window_title_changed on native surfaces, target_state_changed, web_area_text_changed on web renderers with a stable two-sample pre-dispatch baseline); an empty list means effect_not_verified. ambientOnlySignals names whole-window noise and unstable web-area text changes that never prove an effect on their own. webAreaTextChanged, webAreaBaselineStable, and webAreaBaselineDiagnostic report the scoped text evidence and any unavailable baseline or post-settle comparison without exposing captured text. targetRegionChangeThreshold reports the applied ratio threshold, and targetRegionDiagnostic/ocrAnchorDiagnostic explain other null evidence fields."),
            field("postScreenshot", "Screenshot | null", "Returned when imageMode is path or base64 and the post-action reread captures an image."),
        ])
    }

    private static func textActionResponse(_ type: String) -> RouteBodySchemaDTO {
        var fields = [
            field("contractVersion", "string", required: true),
            field("ok", "boolean", required: true),
            field("classification", "success | unsupported | effect_not_verified | verifier_ambiguous", required: true),
            field("failureDomain", "targeting | unsupported | coercion | transport | verification | background_safety | app_specific_semantics | null"),
            field("summary", "string", required: true),
            field("window", "ResolvedWindow | null"),
            field("target", "AXActionTarget | null"),
            field("cursor", "ActionCursorTarget", required: true),
            field("preStateToken", "string | null"),
            field("postStateToken", "string | null"),
            field("semanticAppropriate", "boolean | null"),
            field("semanticReasons", "string[]", required: true),
            field("liveElementResolution", "string | null"),
            field("warnings", "string[]", required: true),
            debugNotesField(),
            field("verification", type + ".verification | null"),
        ]

        if type == "SetValueResponse" {
            fields.insert(field("requestedValue", "SetValueRequestedValue", required: true), at: 6)
            fields.insert(field("rawAXStatus", "string | null"), at: 7)
            fields.insert(field("writePrimitive", "string | null"), at: 8)
        } else if type == "TypeTextResponse" {
            fields.insert(field("text", "string", required: true), at: 6)
            fields.insert(field("dispatchPrimitive", "string | null"), at: 7)
            fields.insert(field("dispatchSucceeded", "boolean | null"), at: 8)
            fields.insert(field("strategiesAttempted", "string[]", required: true), at: 9)
            fields.insert(field("retrySafe", "boolean", required: true, "False after any text transport attempt. Reread the target before continuing and never repeat the request blindly."), at: 10)
            fields.insert(field("foregroundFallbackUsed", "boolean", required: true, "Whether text dispatch required or continued with the target in the foreground."), at: 11)
            fields.insert(field("foregroundRestored", "boolean", required: true, "Whether BCU restored the application that was frontmost before the action."), at: 12)
            fields.insert(field("fallbackReason", "string | null"), at: 13)
            fields.insert(field("performance", "ActionPerformance | null"), at: 14)
            fields.insert(field("backgroundSafety", "TypeTextBackgroundSafety | null"), at: 15)
        }

        return json(fields)
    }

    private static func pressKeyActionResponse() -> RouteBodySchemaDTO {
        json([
            field("contractVersion", "string", required: true),
            field("ok", "boolean", required: true, "Transport-level success: true when the key chord dispatched (including dispatched_no_observed_effect). Inspect verification.classification for the observed effect signal."),
            field("classification", "success | unsupported | effect_not_verified | verifier_ambiguous", required: true),
            field("failureDomain", "targeting | unsupported | coercion | transport | verification | background_safety | app_specific_semantics | null"),
            field("summary", "string", required: true),
            field("window", "ResolvedWindow | null"),
            field("parsedKey", "PressKeyParsedKey | null"),
            field("action", "PressKeyAction | null"),
            field("preStateToken", "string | null"),
            field("postStateToken", "string | null"),
            field("cursor", "ActionCursorTarget", required: true),
            field("warnings", "string[]", required: true),
            debugNotesField(),
            field("verification", "PressKeyVerification | null", "Post-action verification block. verification.classification is success | dispatched_no_observed_effect | failed; also includes route-specific search, selection, text-state, selection-summary, focused-element, and visual-diff evidence plus the post stateToken when available."),
            field("postScreenshot", "Screenshot | null", "Returned when imageMode is path or base64 and the post-action reread captures an image."),
        ])
    }

    private static func scrollActionResponse() -> RouteBodySchemaDTO {
        json([
            field("contractVersion", "string", required: true),
            field("ok", "boolean", required: true),
            field("classification", "success | boundary | unsupported | unresolved | verifier_ambiguous", required: true),
            field("failureDomain", "targeting | unsupported | transport | verification | null"),
            field("issueBucket", "none | targeting | transport | verification | opacity", required: true),
            field("summary", "string", required: true),
            field("window", "ResolvedWindow | null"),
            field("requestedTarget", "AXActionTarget | null"),
            field("chosenContainer", "AXActionTarget | null"),
            field("direction", "up | down | left | right", required: true),
            field("pages", "number", required: true),
            field("winningMode", "background_safe_ax_ladder | post_to_pid_paging | targeted_scroll_wheel_post_to_pid | null"),
            field("winningStrategy", "ax_scroll_to_show_descendant | scrollbar_value | ax_page_action | post_to_pid_paging | targeted_scroll_wheel_post_to_pid | null"),
            field("planCandidates", "ScrollCandidate[]", required: true),
            field("transports", "ScrollTransportAttempt[]", required: true),
            field("preStateToken", "string | null"),
            field("postStateToken", "string | null"),
            field("cursor", "ActionCursorTarget", required: true),
            field("frontmostBundleBefore", "string | null"),
            field("frontmostBundleBeforeDispatch", "string | null"),
            field("frontmostBundleAfter", "string | null"),
            field("warnings", "string[]", required: true),
            debugNotesField(),
            field("verification", "ScrollVerificationSummary | null"),
            field("verificationReads", "ScrollVerificationRead[]", required: true),
        ])
    }

    private static func secondaryActionResponse() -> RouteBodySchemaDTO {
        json([
            field("contractVersion", "string", required: true),
            field("ok", "boolean", required: true),
            field("classification", "success | unsupported | effect_not_verified | verifier_ambiguous", required: true),
            field("failureDomain", "targeting | unsupported | transport | verification | app_specific_semantics | null"),
            field("summary", "string", required: true),
            field("window", "ResolvedWindow | null"),
            field("requestedAction", "SecondaryActionRequested", required: true),
            field("action", "SecondaryActionAction | null", required: false, "Attempted semantic route, dispatch primitive, transport status, and detail. Null when no dispatch was attempted."),
            field("outcome", "SecondaryActionOutcome", required: true, "Verifier-oriented outcome status/reason. Use this before raw AX status when deciding what happened."),
            field("target", "AXActionTarget | null"),
            field("dispatchTarget", "AXActionTarget | null"),
            field("binding", "SecondaryActionBinding | null"),
            field("transports", "SecondaryActionTransportAttempt[]; each attempt includes rawAXStatus, transportDisposition, and transportSuccess", required: true),
            field("preStateToken", "string | null"),
            field("postStateToken", "string | null"),
            field("postState", "AXPipelineV2Response | null"),
            field("cursor", "ActionCursorTarget", required: true),
            field("warnings", "string[]", required: true),
            debugNotesField(),
            field("verification", "SecondaryActionVerification | null", required: false, "Effect-specific verifier evidence. Prefer imageMode with screenshots when visible UI interpretation matters."),
            field("postScreenshot", "Screenshot | null", "Returned when imageMode is path or base64 and the post-action reread captures an image."),
        ])
    }

    private static func json(_ fields: [RouteFieldDTO]) -> RouteBodySchemaDTO {
        RouteBodySchemaDTO(contentType: "application/json", fields: fields)
    }

    private static func field(
        _ name: String,
        _ type: String,
        required: Bool = false,
        _ description: String? = nil,
        defaultValue: String? = nil
    ) -> RouteFieldDTO {
        RouteFieldDTO(
            name: name,
            type: type,
            required: required,
            description: description,
            defaultValue: defaultValue
        )
    }

    private static func actionTargetField(
        required: Bool,
        includeOCR: Bool = false,
        _ description: String
    ) -> RouteFieldDTO {
        let kind = includeOCR
            ? #"display_index"|"node_id"|"refetch_fingerprint"|"ocr_anchor"#
            : #"display_index"|"node_id"|"refetch_fingerprint"#
        return field(
            "target",
            #"{"kind":"\#(kind)","value":integer|string}"#,
            required: required,
            description
        )
    }

    private static func debugField() -> RouteFieldDTO {
        field(
            "debug",
            "boolean",
            required: false,
            "When true, include verbose implementation notes in action responses.",
            defaultValue: "false"
        )
    }

    private static func confirmField(_ description: String? = nil) -> RouteFieldDTO {
        field(
            "confirm",
            "boolean",
            required: false,
            description ?? "Required to proceed when runtime safety policy detects destructive or irreversible wording.",
            defaultValue: "false"
        )
    }

    private static func debugNotesField() -> RouteFieldDTO {
        field(
            "notes",
            "string[]",
            required: false,
            "Verbose implementation notes. Present only when the request includes debug: true."
        )
    }

    private static func actionPolicy(
        lane: RouteExecutionLaneDTO,
        mainThreadBehavior: MainThreadBehaviorDTO
    ) -> RouteExecutionPolicyDTO {
        RouteExecutionPolicyDTO(
            lane: lane,
            backgroundBehavior: .backgroundRequired,
            focusStealPolicy: .forbidden,
            mainThreadBehavior: mainThreadBehavior,
            readActRead: true,
            allowsConcurrentClients: true,
            notes: [
                "Mutating action routes should coordinate through a per-window write lane.",
                "If a future implementation cannot satisfy background safety, it must report that explicitly instead of silently stealing focus.",
                "Visual cursor overlay is visible by default in the HTTP runtime: omit cursor to reuse the stable agent cursor session, or pass cursor.id for a separate lane.",
            ]
        )
    }
}
