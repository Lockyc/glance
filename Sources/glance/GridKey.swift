import AppKit
import GlanceCore

/// The keys both grids share. Each grid decides what an arrow does.
enum GridKey: Equatable {
    case activate
    case exit
    case toggleFullScreen
    case arrow(Comparison.Move)

    static func from(_ event: NSEvent) -> GridKey? {
        let bare = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.numericPad, .function]).isEmpty
        switch event.keyCode {
        case 36, 76: return .activate // Return, keypad Enter
        case 53: return .exit // Esc
        case 123 where bare: return .arrow(.left)
        case 124 where bare: return .arrow(.right)
        case 125 where bare: return .arrow(.down)
        case 126 where bare: return .arrow(.up)
        default:
            guard bare else { return nil }
            switch event.charactersIgnoringModifiers {
            case "g", " ": return .exit
            case "f": return .toggleFullScreen
            default: return nil
            }
        }
    }
}
