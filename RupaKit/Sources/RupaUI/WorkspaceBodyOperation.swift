/// The commands on bodies that run as viewport dialogs, picking their operands by clicks: Boolean
/// (Q) and Cut (C). The palette and the Model menu start them as their keys do.
enum WorkspaceBodyOperation: String, CaseIterable, Identifiable {
    case boolean = "Boolean"
    case cut = "Cut"

    var id: Self { self }

    var systemImage: String {
        switch self {
        case .boolean: "square.on.square"
        case .cut: "scissors"
        }
    }

    var shortcut: String {
        switch self {
        case .boolean: "Q"
        case .cut: "C"
        }
    }
}
