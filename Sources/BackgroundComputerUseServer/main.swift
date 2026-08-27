import BackgroundComputerUse

if CommandLine.arguments.dropFirst().first == "--ocr-worker" {
    OCRWorkerMain.run()
} else {
    BackgroundComputerUseServer.run()
}
