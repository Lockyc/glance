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

func fail(_ message: String, status: Int32) -> Never {
    FileHandle.standardError.write(Data("glance: \(message)\n".utf8))
    exit(status)
}

/// The CLI hands every request to the app (launching it if needed) rather than opening windows itself.
func appBundle() -> URL {
    guard let bundle = LaunchRequest.appBundle(containing: Bundle.main.executableURL!.resolvingSymlinksInPath()) else {
        fail("run from glance.app", status: 1)
    }
    return bundle
}

do {
    let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    switch try LaunchRequest.parse(Array(arguments), workingDirectory: cwd, launchedByLaunchServices: getppid() == 1) {
    case .help:
        print(LaunchRequest.usage)
        exit(0)
    case .activateApp:
        NSWorkspace.shared.openApplication(at: appBundle(), configuration: NSWorkspace.OpenConfiguration()) { _, error in
            if let error { fail(error.localizedDescription, status: 1) }
            exit(0)
        }
        dispatchMain()
    case .open(let request):
        NSWorkspace.shared.open([request.url], withApplicationAt: appBundle(),
                                configuration: NSWorkspace.OpenConfiguration()) { _, error in
            if let error { fail(error.localizedDescription, status: 1) }
            exit(0)
        }
        dispatchMain()
    case .launchApp:
        break
    }
} catch let error as LaunchRequest.ParseError {
    FileHandle.standardError.write(Data("glance: \(error.message)\n\(LaunchRequest.usage)\n".utf8))
    exit(2)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
