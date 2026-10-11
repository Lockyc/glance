import AppKit
import GlanceCore

let arguments = CommandLine.arguments.dropFirst()

if arguments.contains("--list-types") {
    DefaultHandler.claimableTypes.forEach { print($0.identifier) }
    exit(0)
}

if arguments.contains("--make-default") {
    DefaultHandler.claimAll(appURL: Bundle.main.bundleURL) { claimed, failed in
        print("glance is the default viewer for \(claimed) image types")
        for type in failed { FileHandle.standardError.write(Data("could not claim \(type.identifier)\n".utf8)) }
        exit(failed.isEmpty ? 0 : 1)
    }
    dispatchMain()
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
