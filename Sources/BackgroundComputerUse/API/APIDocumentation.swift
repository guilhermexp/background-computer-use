import Foundation

enum APIDocumentation {
    static let guide = APIGuideDTO(
        summary: "Local loopback API for discovering macOS app windows, reading window state, and dispatching background-safe actions.",
        flow: [
            "Read $TMPDIR/background-computer-use/runtime-manifest.json first. Use baseURL from the manifest and send authToken as the X-Background-Computer-Use-Token header for every /v1 request.",
            "Call GET /v1/bootstrap next and stop if instructions.ready is false.",
            "Call GET /v1/routes for the complete route catalog, request fields, response fields, execution policy, examples, and error codes.",
            "Call POST /v1/list_apps to find a target app, then POST /v1/list_windows with an app name or bundle ID.",
            "Call POST /v1/get_window_state with a window ID and imageMode path or base64. Use the screenshot as visual ground truth and the projected tree for semantic targets.",
            "Use POST /v1/find_elements when role or text can identify a target without returning the full tree; its matches and interactionToken come from one capture.",
            "Use POST /v1/run_script only when an arbitrary Apple Events capability is required. It has no effect verification; always read state afterwards.",
            "Call one action route. Reuse stateToken when available; actions without cursor reuse the visible Agent cursor, and cursor.id creates a separate lane. Read state again before planning the next meaningful action.",
            "When showing cursor feedback, stream public agent-facing text or observations. Do not use hidden chain-of-thought, route labels, tool names, or product branding as bubble copy."
        ],
        concepts: [
            APIConceptDTO(
                name: "window",
                description: "Stable window ID returned by list_windows. Most state and action routes require this exact ID.",
                fields: nil
            ),
            APIConceptDTO(
                name: "stateToken",
                description: "Opaque snapshot token returned by get_window_state and action responses. Pass it back to action routes so stale-target checks can compare the action against the state you inspected.",
                fields: nil
            ),
            APIConceptDTO(
                name: "interactionToken",
                description: "Opaque target-identity and geometry token returned by get_window_state. It ignores rendered-text-only changes. Pass it with click target.kind=ocr_anchor so stale OCR anchors fail closed.",
                fields: nil
            ),
            APIConceptDTO(
                name: "session",
                description: "Optional action-exclusion lane selected with the X-Background-Computer-Use-Session header. Concurrent requests from the same session share the lane; another session receives HTTP 409 while it is held, and action-rate throttling returns HTTP 429.",
                fields: nil
            ),
            APIConceptDTO(
                name: "coordinates",
                description: "Window motion coordinates use AppKit-global logical points with a bottom-left origin. Screenshot coordinates are model-facing pixels with a top-left origin; use each route field description and screenshot coordinate contract to avoid mixing spaces.",
                fields: nil
            ),
            APIConceptDTO(
                name: "target",
                description: "Action target from get_window_state or find_elements. Use {\"kind\":\"display_index\",\"value\":N} for a rendered line, {\"kind\":\"node_id\",\"value\":\"...\"} for a stable node, or {\"kind\":\"refetch_fingerprint\",\"value\":\"...\"} when node_id is unavailable. Web nodes may also expose domIdentifier from AXDOMIdentifier for page-authored identity. Click additionally accepts {\"kind\":\"ocr_anchor\",\"value\":\"...\"} from get_window_state.ocr together with interactionToken. Refresh state after actions because target identity or geometry can change.",
                fields: [
                    RouteFieldDTO(name: "kind", type: "display_index | node_id | refetch_fingerprint | ocr_anchor (click only)", required: true, description: "How the route should resolve the target.", defaultValue: nil),
                    RouteFieldDTO(name: "value", type: "integer | string", required: true, description: "Integer for display_index; string for node_id, refetch_fingerprint, and ocr_anchor.", defaultValue: nil),
                ]
            ),
            APIConceptDTO(
                name: "attachedSurfaces",
                description: "Same-process AXSheet/AXDialog surfaces attached to a root window. get_window_state and list_windows expose them explicitly; screenshot capture composites their CG windows over the root when available.",
                fields: nil
            ),
            APIConceptDTO(
                name: "verification",
                description: "Click routes never treat dispatch as proof. A click is classification=success only when the transport dispatched AND verification.intentSignals is non-empty. The shared verifier accepts target-local or structural signals: target_region_changed (targetRegionChangeRatio at or above targetRegionChangeThreshold), a clean pre-gate ocr_anchor_disappeared, focused_element_changed, modal_dialog_opened, window_title_changed (native surfaces only), target_state_changed, and web_area_text_changed (web renderer only, after two identical pre-dispatch web-area text samples and a differing post-settle sample). Anchor disappearance is measured on a separate image with no agent cursor overlay; the OCR route computes it after coordinate escalation, so that route reports it as diagnostic evidence and never lets it upgrade the gate's verdict. Focused-element change compares stable AX element identity against a baseline sampled after the transport's focus-without-raise step. Missing clean evidence is null with a diagnostic and earns no credit. Whole-window rendered-text and selection-summary changes remain ambient noise on every surface; a web-renderer window-title change is ambient too. webAreaBaselineStable and webAreaBaselineDiagnostic expose whether the scoped baseline and post-settle comparison were usable; missing or unstable evidence never earns intent credit. Every click route uses this same gate. Other mutating routes still carry their own per-route verification blocks.",
                fields: nil
            ),
            APIConceptDTO(
                name: "imageMode",
                description: "Use path for local agents, base64 for remote-only consumers, and omit only when visual verification is not needed.",
                fields: [
                    RouteFieldDTO(name: "path", type: "mode", required: false, description: "Return screenshot file paths.", defaultValue: nil),
                    RouteFieldDTO(name: "base64", type: "mode", required: false, description: "Inline screenshot bytes as base64.", defaultValue: nil),
                    RouteFieldDTO(name: "omit", type: "mode", required: false, description: "Do not include screenshots.", defaultValue: nil),
                ]
            ),
            APIConceptDTO(
                name: "CursorRequest",
                description: "Optional override for the visible cursor session on action routes. When omitted, the HTTP runtime reuses the default agent cursor session.",
                fields: [
                    RouteFieldDTO(name: "id", type: "string", required: false, description: "Stable cursor session ID, for example agent-1.", defaultValue: "agent"),
                    RouteFieldDTO(name: "name", type: "string", required: false, description: "Short label displayed with the cursor.", defaultValue: "Agent"),
                    RouteFieldDTO(name: "color", type: "string", required: false, description: "CSS-style hex color, for example #20C46B.", defaultValue: "#0095A1"),
                ]
            ),
        ],
        responseReading: [
            "Transport errors use non-2xx HTTP status codes and the common error body: contractVersion, ok=false, error, message, requestID, and recovery.",
            "Action routes can return HTTP 200 with ok=false when the request was understood but the effect was unsupported, unresolved, unverified, or ambiguous. Read classification, failureDomain or issueBucket, summary, warnings, transports, and verification before retrying.",
            "For visual tasks, trust screenshots over AX-only summaries when they disagree. AX trees and verifier summaries can lag or miss purely visual state.",
            "Verbose implementation notes are omitted from most action responses unless the request includes debug: true."
        ],
        troubleshooting: [
            "invalid_request means the JSON body did not match the route's request fields or enum values. Inspect the route entry in /v1/routes.",
            "app_not_found means list_windows could not resolve the app query. Call list_apps and retry with the exact name or bundleID.",
            "window_not_found means the window ID is stale or closed. Call list_windows again and choose a live window.",
            "accessibility_denied or screenshot failures mean macOS privacy permissions need to be granted to the signed app bundle, then the app must be relaunched."
        ]
    )

    static func usage(for routeID: String) -> RouteUsageDTO {
        guard let id = RouteID(rawValue: routeID) else {
            return usage(
                whenToUse: "Use this registered route according to its method, path, request schema, and response schema.",
                exampleRequest: nil
            )
        }

        switch id {
        case .health:
            return usage(
                whenToUse: "Check that the loopback HTTP server is alive without touching app or window state.",
                useAfter: ["Runtime process has started."],
                successSignals: ["HTTP 200 and ok=true."],
                nextSteps: ["Read the runtime manifest, then call /v1/bootstrap with the manifest authToken header for permissions, baseURL, and route discovery."],
                exampleRequest: nil
            )
        case .bootstrap:
            return usage(
                whenToUse: "Start every client session here to confirm baseURL, macOS permissions, and route availability.",
                useAfter: ["Runtime manifest exists or a local base URL is known."],
                successSignals: ["HTTP 200, baseURL is present, and instructions.ready tells you whether action routes are safe to use."],
                nextSteps: ["If ready is false, follow instructions.user. If ready is true, call /v1/routes."],
                exampleRequest: nil
            )
        case .routes:
            return usage(
                whenToUse: "Discover how to call every endpoint, what each response means, and which errors to handle.",
                useAfter: ["Read the runtime manifest and call /v1/bootstrap first so you know the runtime is ready."],
                successSignals: ["HTTP 200 with a route entry for every supported id."],
                nextSteps: ["Use route.request.fields and route.usage.exampleRequest to build calls."],
                exampleRequest: nil
            )
        case .listApps:
            return usage(
                whenToUse: "Find targetable running apps and the current frontmost app.",
                useAfter: ["Bootstrap is ready."],
                successSignals: ["runningApps contains the app you intend to operate and includes its bundleID."],
                nextSteps: ["Call list_windows with the app name or bundleID."],
                exampleRequest: #"{}"#
            )
        case .listWindows:
            return usage(
                whenToUse: "Resolve an app query to live windows and obtain stable window IDs.",
                useAfter: ["Call list_apps, or already know an app name or bundleID."],
                successSignals: ["windows contains at least one on-screen window with a windowID."],
                nextSteps: ["Call get_window_state with the selected windowID."],
                exampleRequest: #"{"app":"Safari"}"#
            )
        case .cursorFeedback:
            return usage(
                whenToUse: "Stream the agent's public visible response or observation near the active cursor without dispatching input.",
                useAfter: ["Use before, between, or after action routes when the user should see the agent's visible narration, conclusion, or pointing cue."],
                successSignals: ["ok=true, cursor.id identifies the updated cursor lane, and attachment reports window, deferred, or disabled."],
                nextSteps: ["Use append with accumulated public assistant text, finish for a short readable dwell, hide to clear immediately, or point to schedule an asynchronous target cue."],
                exampleRequest: #"{"operation":"update","state":"streaming","message":"Vou comparar o que mudou na tela antes do proximo clique."}"#
            )
        case .getWindowState:
            return usage(
                whenToUse: "Read the current visual and semantic state of a window before planning or verifying actions.",
                useAfter: ["Call list_windows and choose a live windowID."],
                successSignals: ["stateToken, screenshot, tree, focusedElement, backgroundSafety, and notes are returned."],
                nextSteps: ["Pick a semantic target or screenshot coordinate, then call an action route."],
                exampleRequest: #"{"window":"WINDOW_ID","imageMode":"path","maxNodes":6500}"#
            )
        case .findElements:
            return usage(
                whenToUse: "Find projected nodes by exact role and/or accessible-text substring without reading the full tree payload.",
                useAfter: ["Call list_windows and choose a live windowID."],
                successSignals: ["matches contains only matching nodes; matchCount=0 with an explicit summary is a successful empty query result."],
                nextSteps: ["Use a returned nodeID, refetchFingerprint, or displayIndex with stateToken/interactionToken from this same response."],
                exampleRequest: #"{"window":"WINDOW_ID","role":"button","text":"Click me"}"#
            )
        case .runScript:
            return usage(
                whenToUse: "Execute arbitrary AppleScript or JavaScript for Automation without effect verification when no verified UI action route covers the operation.",
                useAfter: ["Use only after confirming the requested operation requires arbitrary Apple Events authority."],
                successSignals: ["status=0 reports process-level script success only; it does not claim any UI effect."],
                nextSteps: ["Call get_window_state or find_elements to confirm the intended effect after every execution."],
                exampleRequest: #"{"language":"applescript","source":"tell application \"Finder\" to get name of front window","timeoutMs":10000}"#
            )
        case .annotateWindow:
            return usage(
                whenToUse: "Visually ground a window with numbered screenshot marks before choosing a target.",
                useAfter: ["Call list_windows and choose a live windowID, or call get_window_state when you need the full tree first."],
                successSignals: ["annotatedImage is present when screenshot capture succeeds, and marks contains numbered targets with model-facing points."],
                nextSteps: ["Use marks[].target with click/type/scroll routes, or inspect annotatedImage.imagePath to align controls visually."],
                exampleRequest: #"{"window":"WINDOW_ID","maxMarks":80,"imageMode":"path"}"#
            )
        case .waitFor:
            return usage(
                whenToUse: "Wait for role/label/value, window title, URL-bearing nodes, or rendered text to match before continuing.",
                useAfter: ["Call an action that may trigger loading, navigation, modal display, or DOM/UI changes."],
                successSignals: ["conditionMet=true, or summary clearly reports a timeout with current state."],
                nextSteps: ["Use the returned fresh state for the next target instead of polling manually."],
                exampleRequest: #"{"window":"WINDOW_ID","textContains":"Deployment","timeoutSeconds":10,"imageMode":"path"}"#
            )
        case .click:
            return usage(
                whenToUse: "Activate a UI target by semantic target, or click a point in model-facing screenshot coordinates.",
                useAfter: ["Call get_window_state and identify a target or x/y coordinate."],
                successSignals: [
                    "ok=true and classification=success, which requires dispatch plus at least one verification.intentSignals entry.",
                    "classification=effect_not_verified with empty intentSignals means the events were posted but nothing target-local or structural changed; inspect ambientOnlySignals, targetRegionChangeRatio, targetRegionDiagnostic, and summary before retrying.",
                ],
                nextSteps: [
                    "Read get_window_state again when the UI may have changed.",
                    "A coordinate or ocr_anchor click that dispatches without proving an effect escalates once: the runtime hit-tests the accessibility element at that same point, in the same process, and presses it. Success through that path reports finalRoute=coordinate_then_ax_hit_test or fallbackReason=coordinate_unverified_using_ax_hit_test plus an ax_perform_action transport with liveElementResolution=ax_hit_test_at_click_point. Destructive wording on that element still requires confirm=true.",
                    "Do not retry the same coordinate blindly. Chromium discards pid-directed synthetic mouse events, so a point with no accessibility element under it (canvas, custom renderers) has no background pointer path; use an AX target (display_index/node_id) from the projected tree instead.",
                ],
                exampleRequest: #"{"window":"WINDOW_ID","stateToken":"STATE_TOKEN","target":{"kind":"display_index","value":12},"clickCount":1,"imageMode":"path"}"#
            )
        case .scroll:
            return usage(
                whenToUse: "Scroll a specific semantic element or scrollable ancestor in a direction.",
                useAfter: ["Call get_window_state and choose a target in or near the scrollable region."],
                successSignals: ["classification=success for movement, boundary for a real edge, or issueBucket explains unresolved failures."],
                nextSteps: ["Use postStateToken or read state again before targeting newly visible content."],
                exampleRequest: #"{"window":"WINDOW_ID","stateToken":"STATE_TOKEN","target":{"kind":"display_index","value":20},"direction":"down","pages":1}"#
            )
        case .performSecondaryAction:
            return usage(
                whenToUse: "Invoke a non-primary action exposed by a node, such as a secondaryActions label or binding.",
                useAfter: ["Call get_window_state and read the target node's secondaryActions or secondaryActionBindings."],
                successSignals: ["ok=true and outcome.status indicates the expected effect was verified or accepted."],
                nextSteps: ["Inspect postState or read state again, especially for menus or visual changes."],
                exampleRequest: #"{"window":"WINDOW_ID","stateToken":"STATE_TOKEN","target":{"kind":"display_index","value":8},"action":"Close","imageMode":"path"}"#
            )
        case .drag:
            return usage(
                whenToUse: "Move a window origin to an AppKit-global coordinate in logical points with a bottom-left origin.",
                useAfter: ["Call list_windows and choose a windowID."],
                successSignals: ["ok=true, action.effectVerified=true, and window.frameAfterAppKit reflects the requested movement."],
                nextSteps: ["Use get_window_state or list_windows to confirm final layout when needed."],
                exampleRequest: #"{"window":"WINDOW_ID","toX":120,"toY":90}"#
            )
        case .resize:
            return usage(
                whenToUse: "Resize a window by moving a named edge or corner handle to an AppKit-global coordinate in logical points with a bottom-left origin.",
                useAfter: ["Call list_windows and choose a windowID."],
                successSignals: ["ok=true, action.effectVerified=true, and window.frameAfterAppKit changed as intended."],
                nextSteps: ["Use get_window_state or list_windows to confirm final layout when needed."],
                exampleRequest: #"{"window":"WINDOW_ID","handle":"bottomRight","toX":1200,"toY":800}"#
            )
        case .setWindowFrame:
            return usage(
                whenToUse: "Set a window's frame directly; prefer this over drag/resize for deterministic layout.",
                useAfter: ["Call list_windows and choose a windowID."],
                successSignals: ["ok=true, action.effectVerified=true, and frameAfterAppKit matches x/y/width/height within platform tolerance."],
                nextSteps: ["Read state again if you will interact with content after resizing."],
                exampleRequest: #"{"window":"WINDOW_ID","x":80,"y":80,"width":1200,"height":800,"animate":true}"#
            )
        case .typeText:
            return usage(
                whenToUse: "Insert text into a focused text entry or a specific text-entry element.",
                useAfter: ["Call get_window_state and identify a text-entry target, or deliberately rely on the current focused element."],
                successSignals: ["ok=true and verification exact value or selection evidence matches the requested text."],
                nextSteps: ["Use press_key for explicit Return/Tab submission; type_text does not auto-submit."],
                exampleRequest: #"{"window":"WINDOW_ID","stateToken":"STATE_TOKEN","target":{"kind":"display_index","value":4},"text":"hello","focusAssistMode":"focus_and_caret_end"}"#
            )
        case .pressKey:
            return usage(
                whenToUse: "Send a key or key chord to the target window, including semantic shortcuts like command+f where supported.",
                useAfter: ["Call get_window_state when you need to verify focus, selection, or text effects."],
                successSignals: ["ok=true and action.route plus verification explain whether a semantic or native key path worked."],
                nextSteps: ["Read state again when the key may open UI, move focus, or change text.", "If native key delivery is attempted but no effect is verified, first perform a safe click in the target content surface, then retry press_key."],
                exampleRequest: #"{"window":"WINDOW_ID","stateToken":"STATE_TOKEN","key":"command+f","imageMode":"path"}"#
            )
        case .setValue:
            return usage(
                whenToUse: "Set a value directly through Accessibility on a semantic replacement target.",
                useAfter: ["Call get_window_state and choose a target whose node reports value-set support."],
                successSignals: ["ok=true and verification exactValueMatch is true."],
                nextSteps: ["Use type_text instead when you need keystroke semantics, focus movement, autocomplete, or submission behavior."],
                exampleRequest: #"{"window":"WINDOW_ID","stateToken":"STATE_TOKEN","target":{"kind":"display_index","value":4},"value":"hello"}"#
            )
        case .readText:
            return usage(
                whenToUse: "Read long text/log/document values when the projected tree only includes a preview.",
                useAfter: ["Call get_window_state and choose a text/value target."],
                successSignals: ["ok=true and chunk.text contains the requested bounded slice."],
                nextSteps: ["Increase offset to read the next chunk when chunk.truncated=true."],
                exampleRequest: #"{"window":"WINDOW_ID","target":{"kind":"display_index","value":4},"offset":0,"length":20000}"#
            )
        case .selectText:
            return usage(
                whenToUse: "Select a substring inside a text element, or place the caret before/after a text landmark.",
                useAfter: ["Call get_window_state and choose a text target with a readable AX value."],
                successSignals: ["ok=true and selectedRange reports the applied range."],
                nextSteps: ["Use type_text, press_key, or read_text depending on the next edit operation."],
                exampleRequest: #"{"window":"WINDOW_ID","stateToken":"STATE_TOKEN","target":{"kind":"display_index","value":4},"text":"needle","occurrence":1,"position":"select","imageMode":"path"}"#
            )
        }
    }

    static func errors(for routeID: String) -> [RouteErrorDTO] {
        guard let id = RouteID(rawValue: routeID) else {
            return commonErrors()
        }

        var errors: [RouteErrorDTO] = []

        if routeHasJSONBody(id) {
            errors.append(
                RouteErrorDTO(
                    statusCode: 400,
                    error: "invalid_request",
                    meaning: "The JSON body is missing, malformed, has a wrong type, or uses an unsupported enum value.",
                    recovery: [
                        "Inspect this route's request.fields.",
                        "Include all required fields and match enum values exactly."
                    ]
                )
            )
        }

        if routeNeedsAccessibility(id) {
            errors.append(
                RouteErrorDTO(
                    statusCode: 403,
                    error: "accessibility_denied",
                    meaning: "The runtime cannot read or control the target because macOS Accessibility permission is missing.",
                    recovery: [
                        "Grant Accessibility permission to the signed BackgroundComputerUse app bundle.",
                        "Quit and relaunch through script/start.sh or script/build_and_run.sh run."
                    ]
                )
            )
        }

        if id == .listWindows {
            errors.append(
                RouteErrorDTO(
                    statusCode: 404,
                    error: "app_not_found",
                    meaning: "The app query did not match a targetable running application.",
                    recovery: ["Call list_apps and retry with the exact name or bundleID."]
                )
            )
        }

        if routeNeedsWindow(id) {
            errors.append(
                RouteErrorDTO(
                    statusCode: 404,
                    error: "window_not_found",
                    meaning: "The supplied window ID no longer resolves to a live window.",
                    recovery: ["Call list_windows again and retry with a current windowID."]
                )
            )
        }

        errors.append(contentsOf: commonErrors())
        return errors
    }

    private static func usage(
        whenToUse: String,
        useAfter: [String] = [],
        successSignals: [String] = [],
        nextSteps: [String] = [],
        exampleRequest: String?
    ) -> RouteUsageDTO {
        RouteUsageDTO(
            whenToUse: whenToUse,
            useAfter: useAfter,
            successSignals: successSignals,
            nextSteps: nextSteps,
            exampleRequest: exampleRequest
        )
    }

    private static func routeHasJSONBody(_ id: RouteID) -> Bool {
        switch id {
        case .health, .bootstrap, .routes:
            return false
        default:
            return true
        }
    }

    private static func routeNeedsAccessibility(_ id: RouteID) -> Bool {
        switch id {
        case .health, .bootstrap, .routes, .cursorFeedback, .runScript:
            return false
        default:
            return true
        }
    }

    private static func routeNeedsWindow(_ id: RouteID) -> Bool {
        switch id {
        case .getWindowState, .findElements, .annotateWindow, .click, .scroll, .performSecondaryAction, .drag, .resize, .setWindowFrame, .typeText, .pressKey, .setValue, .waitFor, .readText, .selectText:
            return true
        case .health, .bootstrap, .routes, .listApps, .listWindows, .cursorFeedback, .runScript:
            return false
        }
    }

    private static func commonErrors() -> [RouteErrorDTO] {
        [
            RouteErrorDTO(
                statusCode: 404,
                error: "route_not_found",
                meaning: "No registered route matched the method and path.",
                recovery: ["Call GET /v1/routes and use one of the advertised method/path pairs."]
            ),
            RouteErrorDTO(
                statusCode: 500,
                error: "internal_error",
                meaning: "The route failed after the request was accepted.",
                recovery: [
                    "Retry once if the target UI is changing.",
                    "If it persists, call the action with debug=true where supported and include requestID in logs."
                ]
            ),
        ]
    }
}
