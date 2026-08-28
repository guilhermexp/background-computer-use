import BackgroundComputerUse
import BackgroundComputerUseControl
import Foundation

if CommandLine.arguments.dropFirst().first == "--ocr-worker" {
    OCRWorkerMain.run()
} else if CommandLine.arguments.dropFirst().first == "--ax-bootstrap-worker" {
    RendererAccessibilityWorkerMain.run(arguments: Array(CommandLine.arguments.dropFirst(2)))
} else {
    let controlRuntime = try? BCUControlRuntime()
    controlRuntime?.start()
    if let controlRuntime {
        BackgroundComputerUseControlBridge.configure(
            store: controlRuntime.policyStore,
            prompt: { identity, pid, sessionID in
                controlRuntime.prompt(identity: identity, pid: pid, sessionID: sessionID)
            },
            allowsMutations: {
                controlRuntime.allowsMutations()
            },
            allowsReads: {
                controlRuntime.allowsReads()
            },
            publishActivity: { sessionID, action, appBundleID, windowID, verdict, summary, screenshotPath in
                controlRuntime.publishActivity(
                    ActivityEnvelope(
                        id: UUID().uuidString,
                        sessionID: sessionID,
                        appBundleID: appBundleID,
                        windowID: windowID,
                        action: action,
                        verdict: verdict,
                        summary: summary,
                        screenshotPath: screenshotPath,
                        timestamp: Date()
                    )
                )
            }
        )
    }
    BackgroundComputerUseServer.run(controlRequired: true)
}
