import Foundation

struct RouterContext {
    let baseURL: URL?
    let startedAt: Date?
}

struct Router {
    private let auth: RuntimeAuth
    private let services = RuntimeServices()
    private let debugArtifactRecorder: DebugArtifactRecorder
    private let sessionLimiter: RuntimeSessionLimiter

    init(
        auth: RuntimeAuth,
        debugArtifactRecorder: DebugArtifactRecorder = DebugArtifactRecorder(),
        sessionLimiter: RuntimeSessionLimiter = RuntimeSessionLimiter()
    ) {
        self.auth = auth
        self.debugArtifactRecorder = debugArtifactRecorder
        self.sessionLimiter = sessionLimiter
        self.sessionLimiter.configure(
            maxActionsPerSecond: ProcessInfo.processInfo.environment["BACKGROUND_COMPUTER_USE_MAX_ACTIONS_PER_SECOND"]
                .flatMap(Double.init)
        )
    }

    func response(for request: HTTPRequest, context: RouterContext) -> HTTPResponse {
        guard request.path == "/health" || isLoopbackHost(request.headerValue(named: "Host")) else {
            return invalidHostResponse()
        }
        guard request.path == "/health" || auth.isAuthorized(request: request) else {
            return unauthorizedResponse()
        }

        switch (request.method, request.path) {
        case (.get, "/health"):
            return .json(
                HealthResponse(
                    ok: true,
                    contractVersion: ContractVersion.current,
                    timestamp: Time.iso8601String(from: Date())
                )
            )

        case (.get, "/v1/bootstrap"):
            let permissions = RuntimePermissionsSnapshot.current().dto
            let instructions = RuntimePermissionInstructions.make(permissions: permissions, baseURL: context.baseURL)
            RuntimePermissionPresenter.showIfNeeded(permissions: permissions, instructions: instructions)
            return .json(
                BootstrapResponse(
                    contractVersion: ContractVersion.current,
                    baseURL: context.baseURL?.absoluteString,
                    startedAt: context.startedAt.map(Time.iso8601String),
                    auth: auth.dto,
                    permissions: permissions,
                    instructions: instructions,
                    guide: APIDocumentation.guide,
                    routes: context.baseURL.map(RouteRegistry.bootstrapRouteDescriptors(baseURL:)) ?? []
                )
            )

        case (.get, "/v1/routes"):
            return .json(
                RouteListResponse(
                    contractVersion: ContractVersion.current,
                    guide: APIDocumentation.guide,
                    routes: RouteRegistry.publicRoutes()
                )
            )

        case (.post, "/v1/list_apps"):
            return decodeAndExecute(
                ListAppsRequest.self,
                routeID: .listApps,
                from: request,
                work: { _ in services.listApps() }
            )

        case (.post, "/v1/list_windows"):
            return decodeAndExecute(
                ListWindowsRequest.self,
                routeID: .listWindows,
                from: request,
                work: { payload in
                    try services.listWindows(payload)
                }
            )

        case (.post, "/v1/cursor_feedback"):
            return decodeAndExecute(
                CursorFeedbackRequest.self,
                routeID: .cursorFeedback,
                from: request,
                work: { payload in
                    try services.cursorFeedback(payload)
                }
            )

        case (.post, "/v1/get_window_state"):
            return decodeAndExecute(
                GetWindowStateRequest.self,
                routeID: .getWindowState,
                from: request,
                work: { payload in
                    try services.getWindowState(payload)
                }
            )

        case (.post, "/v1/annotate_window"):
            return decodeAndExecute(
                AnnotateWindowRequest.self,
                routeID: .annotateWindow,
                from: request,
                work: { payload in
                    try services.annotateWindow(payload)
                }
            )

        case (.post, "/v1/click"):
            return decodeAndExecute(
                ClickRequest.self,
                routeID: .click,
                from: request,
                work: { payload in
                    try services.click(payload)
                }
            )

        case (.post, "/v1/scroll"):
            return decodeAndExecute(
                ScrollRequest.self,
                routeID: .scroll,
                from: request,
                work: { payload in
                    try services.scroll(payload)
                }
            )

        case (.post, "/v1/perform_secondary_action"):
            return decodeAndExecute(
                PerformSecondaryActionRequest.self,
                routeID: .performSecondaryAction,
                from: request,
                work: { payload in
                    try services.performSecondaryAction(payload)
                }
            )

        case (.post, "/v1/drag"):
            return decodeAndExecute(
                DragRequest.self,
                routeID: .drag,
                from: request,
                work: { payload in
                    try services.drag(payload)
                }
            )

        case (.post, "/v1/resize"):
            return decodeAndExecute(
                ResizeRequest.self,
                routeID: .resize,
                from: request,
                work: { payload in
                    try services.resize(payload)
                }
            )

        case (.post, "/v1/set_window_frame"):
            return decodeAndExecute(
                SetWindowFrameRequest.self,
                routeID: .setWindowFrame,
                from: request,
                work: { payload in
                    try services.setWindowFrame(payload)
                }
            )

        case (.post, "/v1/type_text"):
            return decodeAndExecute(
                TypeTextRequest.self,
                routeID: .typeText,
                from: request,
                work: { payload in
                    try services.typeText(payload)
                }
            )

        case (.post, "/v1/press_key"):
            return decodeAndExecute(
                PressKeyRequest.self,
                routeID: .pressKey,
                from: request,
                work: { payload in
                    try services.pressKey(payload)
                }
            )

        case (.post, "/v1/set_value"):
            return decodeAndExecute(
                SetValueRequest.self,
                routeID: .setValue,
                from: request,
                work: { payload in
                    try services.setValue(payload)
                }
            )

        case (.post, "/v1/wait_for"):
            return decodeAndExecute(
                WaitForRequest.self,
                routeID: .waitFor,
                from: request,
                work: { payload in
                    try services.waitFor(payload)
                }
            )

        case (.post, "/v1/read_text"):
            return decodeAndExecute(
                ReadTextRequest.self,
                routeID: .readText,
                from: request,
                work: { payload in
                    try services.readText(payload)
                }
            )

        case (.post, "/v1/select_text"):
            return decodeAndExecute(
                SelectTextRequest.self,
                routeID: .selectText,
                from: request,
                work: { payload in
                    try services.selectText(payload)
                }
            )

        default:
            return .json(
                ErrorResponse(
                    error: "route_not_found",
                    message: "No route matched \(request.method.rawValue) \(request.path).",
                    requestID: UUID().uuidString,
                    recovery: [
                        "Call GET /v1/routes and use one of the advertised method/path pairs.",
                        "Check that the request uses the documented HTTP method."
                    ]
                ),
                statusCode: 404,
                reasonPhrase: "Not Found"
            )
        }
    }

    private func decodeAndExecute<Request: Decodable, Response: Encodable>(
        _ type: Request.Type,
        routeID: RouteID,
        from request: HTTPRequest,
        work: (Request) throws -> Response
    ) -> HTTPResponse {
        let requestID = UUID().uuidString
        if let unknownFields = unknownTopLevelFields(routeID: routeID, body: request.body) {
            let response = unknownFieldResponse(
                unknownFields: unknownFields,
                routeID: routeID,
                requestID: requestID
            )
            recordArtifact(requestID: requestID, routeID: routeID, request: request, response: response)
            return response
        }

        if isActionRoute(routeID) {
            let throttleDecision = sessionLimiter.beforeAction()
            guard throttleDecision.allowed else {
                let response = runtimeBusyResponse(
                    error: "rate_limited",
                    message: throttleDecision.reason ?? "Action rate limit exceeded.",
                    statusCode: 429,
                    reasonPhrase: "Too Many Requests",
                    requestID: requestID
                )
                recordArtifact(requestID: requestID, routeID: routeID, request: request, response: response)
                return response
            }
        }

        let sessionID = isActionRoute(routeID)
            ? request.headerValue(named: "X-Background-Computer-Use-Session")
            : nil
        var acquiredSessionID: String?
        if let sessionID, sessionID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            let sessionDecision = sessionLimiter.acquire(sessionID: sessionID)
            guard sessionDecision.allowed else {
                let response = runtimeBusyResponse(
                    error: "session_busy",
                    message: sessionDecision.reason ?? "Runtime is already in use by another session.",
                    statusCode: 409,
                    reasonPhrase: "Conflict",
                    requestID: requestID
                )
                recordArtifact(requestID: requestID, routeID: routeID, request: request, response: response)
                return response
            }
            acquiredSessionID = sessionID
        }
        defer {
            if let acquiredSessionID {
                sessionLimiter.release(sessionID: acquiredSessionID)
            }
        }

        do {
            let payload = try JSONSupport.decoder.decode(Request.self, from: request.body)
            let response = HTTPResponse.json(
                try work(payload),
                includeDebugNotes: includeDebugNotes(for: routeID, payload: payload)
            )
            recordArtifact(requestID: requestID, routeID: routeID, request: request, response: response)
            return response
        } catch {
            if error is DecodingError {
                let response = invalidRequestResponse(for: error, routeID: routeID, requestID: requestID)
                recordArtifact(requestID: requestID, routeID: routeID, request: request, response: response)
                return response
            }

            let response = errorResponse(for: error, routeID: routeID, requestID: requestID)
            recordArtifact(requestID: requestID, routeID: routeID, request: request, response: response)
            return response
        }
    }

    private func runtimeBusyResponse(
        error: String,
        message: String,
        statusCode: Int,
        reasonPhrase: String,
        requestID: String
    ) -> HTTPResponse {
        .json(
            ErrorResponse(
                error: error,
                message: message,
                requestID: requestID,
                recovery: [
                    "Retry after the current action completes.",
                    "Use X-Background-Computer-Use-Session to coordinate exclusive action batches."
                ]
            ),
            statusCode: statusCode,
            reasonPhrase: reasonPhrase
        )
    }

    private func recordArtifact(
        requestID: String,
        routeID: RouteID,
        request: HTTPRequest,
        response: HTTPResponse
    ) {
        _ = try? debugArtifactRecorder.record(
            requestID: requestID,
            routeID: routeID.rawValue,
            requestBody: request.body,
            responseBody: response.body
        )
    }

    private func unauthorizedResponse() -> HTTPResponse {
        .json(
            ErrorResponse(
                error: "unauthorized",
                message: "Missing or invalid \(RuntimeAuth.headerName) header.",
                requestID: UUID().uuidString,
                recovery: [
                    "Read the local runtime manifest at $TMPDIR/background-computer-use/runtime-manifest.json.",
                    "Send the manifest authToken value as the \(RuntimeAuth.headerName) header for all /v1 requests."
                ]
            ),
            statusCode: 401,
            reasonPhrase: "Unauthorized"
        )
    }

    private func invalidHostResponse() -> HTTPResponse {
        .json(
            ErrorResponse(
                error: "invalid_host",
                message: "The Host header must name the loopback runtime (127.0.0.1 or localhost).",
                requestID: UUID().uuidString,
                recovery: [
                    "Use baseURL from the runtime manifest without replacing its host.",
                    "Send a Host header beginning with 127.0.0.1 or localhost."
                ]
            ),
            statusCode: 403,
            reasonPhrase: "Forbidden"
        )
    }

    private func isLoopbackHost(_ host: String?) -> Bool {
        guard let normalized = host?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() else {
            return false
        }
        return normalized == "127.0.0.1"
            || normalized.hasPrefix("127.0.0.1:")
            || normalized == "localhost"
            || normalized.hasPrefix("localhost:")
    }

    private func includeDebugNotes<Request>(for routeID: RouteID, payload: Request) -> Bool {
        guard isActionRoute(routeID),
              let debugRequest = payload as? DebugNotesRequest else {
            return true
        }
        return debugRequest.debug == true
    }

    private func isActionRoute(_ routeID: RouteID) -> Bool {
        switch routeID {
        case .click, .scroll, .performSecondaryAction, .drag, .resize, .setWindowFrame, .typeText, .pressKey, .setValue, .selectText:
            return true
        default:
            return false
        }
    }

    private func unknownTopLevelFields(routeID: RouteID, body: Data) -> [String]? {
        guard let object = try? JSONSerialization.jsonObject(with: body),
              let dictionary = object as? [String: Any] else {
            return nil
        }
        let allowed = Set(RouteRegistry.requestFieldNames(for: routeID))
        let unknown = dictionary.keys.filter { allowed.contains($0) == false }.sorted()
        return unknown.isEmpty ? nil : unknown
    }

    private func unknownFieldResponse(
        unknownFields: [String],
        routeID: RouteID,
        requestID: String
    ) -> HTTPResponse {
        let accepted = RouteRegistry.requestFieldNames(for: routeID)
        let acceptedList = accepted.isEmpty ? "(none)" : accepted.joined(separator: ", ")
        let unknownList = unknownFields.joined(separator: ", ")
        return .json(
            ErrorResponse(
                error: "invalid_request",
                message: "Request body for \(routeID.rawValue) included unknown field(s): \(unknownList). Accepted fields: \(acceptedList).",
                requestID: requestID,
                recovery: [
                    "Remove the unknown field(s) \(unknownList) or correct the spelling against the route schema.",
                    "Call GET /v1/routes and inspect route '\(routeID.rawValue)' request.fields for the accepted fields.",
                    "Send Content-Type: application/json with a JSON object body for POST routes."
                ]
            ),
            statusCode: 400,
            reasonPhrase: "Bad Request"
        )
    }

    private func invalidRequestResponse(
        for error: Error,
        routeID: RouteID,
        requestID: String
    ) -> HTTPResponse {
        .json(
            ErrorResponse(
                error: "invalid_request",
                message: invalidRequestMessage(for: error, routeID: routeID),
                requestID: requestID,
                recovery: [
                    "Call GET /v1/routes and inspect route '\(routeID.rawValue)' request.fields.",
                    "Include all required fields and match enum values exactly.",
                    "Send Content-Type: application/json with a JSON object body for POST routes."
                ]
            ),
            statusCode: 400,
            reasonPhrase: "Bad Request"
        )
    }

    private func invalidRequestMessage(for error: Error, routeID: RouteID) -> String {
        guard case let DecodingError.keyNotFound(key, context) = error else {
            return "Request body does not match the \(routeID.rawValue) schema. \(decodingDetail(for: error))"
        }

        let path = codingPathDescription(context.codingPath + [key])
        return "Request body does not match the \(routeID.rawValue) schema. Missing required field '\(path)'."
    }

    private func decodingDetail(for error: Error) -> String {
        switch error {
        case DecodingError.typeMismatch(let type, let context):
            return "Expected \(type) at '\(codingPathDescription(context.codingPath))'. \(context.debugDescription)"
        case DecodingError.valueNotFound(let type, let context):
            return "Missing value for \(type) at '\(codingPathDescription(context.codingPath))'. \(context.debugDescription)"
        case DecodingError.dataCorrupted(let context):
            return "Invalid value at '\(codingPathDescription(context.codingPath))'. \(context.debugDescription)"
        case DecodingError.keyNotFound(let key, let context):
            let path = codingPathDescription(context.codingPath + [key])
            return "Missing required field '\(path)'."
        default:
            return "Decode error: \(error)."
        }
    }

    private func codingPathDescription(_ codingPath: [CodingKey]) -> String {
        let path = codingPath.map(\.stringValue).joined(separator: ".")
        return path.isEmpty ? "$" : path
    }

    func errorResponse(for error: Error, routeID: RouteID, requestID: String) -> HTTPResponse {
        switch error {
        case let screenshotError as CGWindowCaptureError:
            return .json(
                ErrorResponse(
                    error: "screenshot_failed",
                    message: "Screenshot capture failed for \(routeID.rawValue): \(String(describing: screenshotError))",
                    requestID: requestID,
                    recovery: [
                        "Confirm Screen Recording permission is granted to the signed BackgroundComputerUse app.",
                        "Retry after confirming the target window is still visible and captureable."
                    ]
                ),
                statusCode: 500,
                reasonPhrase: "Internal Server Error"
            )

        case let captureError as StatePipelineExperimentError:
            return .json(
                ErrorResponse(
                    error: "capture_failed",
                    message: "State capture failed for \(routeID.rawValue): \(String(describing: captureError))",
                    requestID: requestID,
                    recovery: [
                        "Retry once if the target UI was changing during capture.",
                        "Keep this requestID and inspect debug artifacts if the failure repeats."
                    ]
                ),
                statusCode: 500,
                reasonPhrase: "Internal Server Error"
            )

        case DiscoveryError.accessibilityDenied:
            return .json(
                ErrorResponse(
                    error: "accessibility_denied",
                    message: "Accessibility permission is required for \(routeID.rawValue).",
                    requestID: requestID,
                    recovery: [
                        "Grant Accessibility permission to BackgroundComputerUse in System Settings > Privacy & Security > Accessibility.",
                        "Quit and relaunch the signed app bundle through script/start.sh or script/build_and_run.sh run."
                    ]
                ),
                statusCode: 403,
                reasonPhrase: "Forbidden"
            )

        case DiscoveryError.appNotFound(let query):
            return .json(
                ErrorResponse(
                    error: "app_not_found",
                    message: "No targetable app matched query '\(query)'.",
                    requestID: requestID,
                    recovery: [
                        "Call POST /v1/list_apps and retry with an exact app name or bundleID.",
                        "Confirm the app is running and has at least one targetable process."
                    ]
                ),
                statusCode: 404,
                reasonPhrase: "Not Found"
            )

        case DiscoveryError.windowNotFound(let windowID):
            return .json(
                ErrorResponse(
                    error: "window_not_found",
                    message: "No live window matched window ID '\(windowID)'.",
                    requestID: requestID,
                    recovery: [
                        "Call POST /v1/list_windows again and use a current windowID.",
                        "Confirm the target window has not closed, minimized, or moved to a non-targetable state."
                    ]
                ),
                statusCode: 404,
                reasonPhrase: "Not Found"
            )

        case WaitForRouteError.invalidRequest(let message):
            return .json(
                ErrorResponse(
                    error: "invalid_request",
                    message: message,
                    requestID: requestID,
                    recovery: [
                        "Call GET /v1/routes and inspect route '\(routeID.rawValue)' request.fields.",
                        "Use windowTitleContains with gone=true for title disappearance waits.",
                        "Use windowTitleChanged=true only for waiting until the title differs from the first observed title."
                    ]
                ),
                statusCode: 400,
                reasonPhrase: "Bad Request"
            )

        default:
            return .json(
                ErrorResponse(
                    error: "internal_error",
                    message: "Route \(routeID.rawValue) failed: \(String(describing: error))",
                    requestID: requestID,
                    recovery: [
                        "Retry once if the target UI was changing.",
                        "If the route supports it, retry with debug=true and keep the requestID for logs."
                    ]
                ),
                statusCode: 500,
                reasonPhrase: "Internal Server Error"
            )
        }
    }
}
