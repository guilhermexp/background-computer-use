import Foundation

struct RuntimeServices {
    private let coordinator = RuntimeCoordinator()
    private let runningAppService = RunningAppService()
    private let windowListService = WindowListService()
    private let launchAppRouteService: LaunchAppRouteService
    private let windowStateService: WindowStateService
    private let findElementsRouteService: FindElementsRouteService
    private let scriptRouteService: ScriptRouteService
    private let windowDragRouteService: WindowDragRouteService
    private let windowResizeRouteService: WindowResizeRouteService
    private let setWindowFrameRouteService: SetWindowFrameRouteService
    private let setValueRouteService: SetValueRouteService
    private let typeTextRouteService: TypeTextRouteService
    private let pasteRouteService: PasteRouteService
    private let pressKeyRouteService: PressKeyRouteService
    private let scrollRouteService: ScrollRouteService
    private let secondaryActionRouteService: SecondaryActionRouteService
    private let clickRouteService: ClickRouteService
    private let waitForRouteService: WaitForRouteService
    private let windowAnnotationService: WindowAnnotationService
    private let textRouteService: TextRouteService
    private let cursorFeedbackRouteService: CursorFeedbackRouteService

    init(
        executionOptions: ActionExecutionOptions = .visualCursorEnabled,
        scriptAuditLogger: ScriptAuditLogger = ScriptAuditLogger()
    ) {
        windowStateService = WindowStateService(executionOptions: executionOptions)
        launchAppRouteService = LaunchAppRouteService(authorizer: ControlAuthorizationCenter.shared)
        findElementsRouteService = FindElementsRouteService(executionOptions: executionOptions)
        scriptRouteService = ScriptRouteService(auditLogger: scriptAuditLogger)
        windowDragRouteService = WindowDragRouteService(executionOptions: executionOptions)
        windowResizeRouteService = WindowResizeRouteService(executionOptions: executionOptions)
        setWindowFrameRouteService = SetWindowFrameRouteService(executionOptions: executionOptions)
        setValueRouteService = SetValueRouteService(executionOptions: executionOptions)
        typeTextRouteService = TypeTextRouteService(executionOptions: executionOptions)
        pasteRouteService = PasteRouteService(executionOptions: executionOptions)
        pressKeyRouteService = PressKeyRouteService(executionOptions: executionOptions)
        scrollRouteService = ScrollRouteService(executionOptions: executionOptions)
        secondaryActionRouteService = SecondaryActionRouteService(executionOptions: executionOptions)
        clickRouteService = ClickRouteService(executionOptions: executionOptions)
        waitForRouteService = WaitForRouteService(executionOptions: executionOptions)
        windowAnnotationService = WindowAnnotationService(executionOptions: executionOptions)
        textRouteService = TextRouteService(executionOptions: executionOptions)
        cursorFeedbackRouteService = CursorFeedbackRouteService(executionOptions: executionOptions)
    }

    func permissions() -> RuntimePermissionsDTO {
        RuntimePermissionsSnapshot.current().dto
    }

    func listApps() -> ListAppsResponse {
        execute(routeID: .listApps, target: .shared) {
            runningAppService.listApps()
        }
    }

    func listWindows(_ request: ListWindowsRequest) throws -> ListWindowsResponse {
        try execute(
            routeID: .listWindows,
            target: RouteTargetSummaryDTO(kind: .appPID, pid: request.pid, windowID: nil)
        ) {
            try windowListService.listWindows(pid: request.pid)
        }
    }

    func launchApp(_ request: LaunchAppRequest) throws -> LaunchAppResponse {
        try execute(routeID: .launchApp, target: .shared) {
            try launchAppRouteService.launchApp(request: request)
        }
    }

    func cursorFeedback(_ request: CursorFeedbackRequest) throws -> CursorFeedbackResponse {
        try execute(routeID: .cursorFeedback, target: .shared) {
            try cursorFeedbackRouteService.update(request: request)
        }
    }

    func getWindowState(_ request: GetWindowStateRequest) throws -> GetWindowStateResponse {
        try execute(routeID: .getWindowState, target: windowTarget(request.window)) {
            try windowStateService.getWindowState(request: request)
        }
    }

    func findElements(_ request: FindElementsRequest) throws -> FindElementsResponse {
        try execute(routeID: .findElements, target: windowTarget(request.window)) {
            try findElementsRouteService.findElements(request: request)
        }
    }

    func runScript(_ request: RunScriptRequest) throws -> RunScriptResponse {
        try execute(routeID: .runScript, target: .shared) {
            try scriptRouteService.runScript(request: request)
        }
    }

    func click(_ request: ClickRequest) throws -> ClickResponse {
        try execute(routeID: .click, target: windowTarget(request.window)) {
            try clickRouteService.click(request: request)
        }
    }

    func scroll(_ request: ScrollRequest) throws -> ScrollResponse {
        try execute(routeID: .scroll, target: windowTarget(request.window)) {
            try scrollRouteService.scroll(request: request)
        }
    }

    func performSecondaryAction(_ request: PerformSecondaryActionRequest) throws -> PerformSecondaryActionResponse {
        try execute(routeID: .performSecondaryAction, target: windowTarget(request.window)) {
            try secondaryActionRouteService.performSecondaryAction(request: request)
        }
    }

    func drag(_ request: DragRequest) throws -> DragResponse {
        try execute(routeID: .drag, target: windowTarget(request.window)) {
            try windowDragRouteService.drag(request: request)
        }
    }

    func resize(_ request: ResizeRequest) throws -> ResizeResponse {
        try execute(routeID: .resize, target: windowTarget(request.window)) {
            try windowResizeRouteService.resize(request: request)
        }
    }

    func setWindowFrame(_ request: SetWindowFrameRequest) throws -> SetWindowFrameResponse {
        try execute(routeID: .setWindowFrame, target: windowTarget(request.window)) {
            try setWindowFrameRouteService.setWindowFrame(request: request)
        }
    }

    func typeText(_ request: TypeTextRequest) throws -> TypeTextResponse {
        try execute(routeID: .typeText, target: windowTarget(request.window)) {
            try typeTextRouteService.typeText(request: request)
        }
    }

    func paste(_ request: PasteRequest) throws -> PasteResponse {
        try execute(routeID: .paste, target: windowTarget(request.window)) {
            try pasteRouteService.paste(request: request)
        }
    }

    func pressKey(_ request: PressKeyRequest) throws -> PressKeyResponse {
        try execute(routeID: .pressKey, target: windowTarget(request.window)) {
            try pressKeyRouteService.pressKey(request: request)
        }
    }

    func setValue(_ request: SetValueRequest) throws -> SetValueResponse {
        try execute(routeID: .setValue, target: windowTarget(request.window)) {
            try setValueRouteService.setValue(request: request)
        }
    }

    func waitFor(_ request: WaitForRequest) throws -> WaitForResponse {
        try execute(routeID: .waitFor, target: windowTarget(request.window)) {
            try waitForRouteService.waitFor(request: request)
        }
    }

    func annotateWindow(_ request: AnnotateWindowRequest) throws -> AnnotateWindowResponse {
        try execute(routeID: .annotateWindow, target: windowTarget(request.window)) {
            try windowAnnotationService.annotateWindow(request: request)
        }
    }

    func readText(_ request: ReadTextRequest) throws -> ReadTextResponse {
        try execute(routeID: .readText, target: windowTarget(request.window)) {
            try textRouteService.readText(request: request)
        }
    }

    func selectText(_ request: SelectTextRequest) throws -> SelectTextResponse {
        try execute(routeID: .selectText, target: windowTarget(request.window)) {
            try textRouteService.selectText(request: request)
        }
    }

    private func execute<Response>(
        routeID: RouteID,
        target: RouteTargetSummaryDTO,
        _ work: () throws -> Response
    ) rethrows -> Response {
        let route = RouteRegistry.descriptor(for: routeID)
        return try coordinator.execute(route: route, target: target, work)
    }

    private func windowTarget(_ windowID: String) -> RouteTargetSummaryDTO {
        RouteTargetSummaryDTO(kind: .window, pid: nil, windowID: windowID)
    }
}
