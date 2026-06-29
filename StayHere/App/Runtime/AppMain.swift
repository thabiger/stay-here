import AppKit

@main
struct StayHereAppMain {
    static func main() {
        // Keep a strong process-lifetime reference: NSApplication.delegate is not a retaining owner.
        let appDelegate = AppDelegate()
        let app = NSApplication.shared
        app.delegate = appDelegate
        app.run()
    }
}
