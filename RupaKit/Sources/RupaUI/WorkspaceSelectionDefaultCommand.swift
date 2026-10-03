import RupaCore

/// The command Plasticity runs on a selection made while nothing else runs (its default command):
/// faces of solids open Push Face on them, open edges of sheets open Extend Sheet on them. The
/// dialog started this way follows the selection: a later selection made in the viewport starts
/// the command for it, or ends the dialog when it calls for none; a selection changed any other
/// way, or another command starting, ends it.
enum WorkspaceSelectionDefaultCommand: Equatable {
    case pushFaces([SelectionTarget])
    case extendSheet(edges: [SelectionTarget])

    /// The command for `selected`: Push Face when every target is a face of a solid, Extend Sheet
    /// when every one is an open edge of a sheet, none otherwise.
    static func resolve(
        selected: [SelectionTarget],
        solidFaces: Set<SelectionTarget>,
        sheetOpenEdges: Set<SelectionTarget>
    ) -> WorkspaceSelectionDefaultCommand? {
        guard selected.isEmpty == false else { return nil }
        if selected.allSatisfy(solidFaces.contains) { return .pushFaces(selected) }
        if selected.allSatisfy(sheetOpenEdges.contains) { return .extendSheet(edges: selected) }
        return nil
    }

    /// The targets a dialog runs on when a default command could have started it: Push Face's
    /// faces, Extend Sheet's edges; nil for any other dialog.
    static func targets(of dialog: WorkspaceFaceEditSession) -> [SelectionTarget]? {
        switch dialog.kind {
        case let .push(faces, _): faces
        case let .extendSheet(edges, _): edges
        default: nil
        }
    }

    /// Whether `dialog` already runs this command on the same targets.
    func isRunning(in dialog: WorkspaceFaceEditSession) -> Bool {
        switch (self, dialog.kind) {
        case let (.pushFaces(faces), .push(running, _)): Set(faces) == Set(running)
        case let (.extendSheet(edges), .extendSheet(running, _)): Set(edges) == Set(running)
        default: false
        }
    }
}
