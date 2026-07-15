import Foundation

func sleepRunLoop(_ duration: TimeInterval) {
    guard duration > 0 else { return }

    if Thread.isMainThread {
        RunLoop.current.run(until: Date().addingTimeInterval(duration))
    } else {
        Thread.sleep(forTimeInterval: duration)
    }
}
