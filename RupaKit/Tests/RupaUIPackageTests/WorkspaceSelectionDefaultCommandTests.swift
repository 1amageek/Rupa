import RupaCore
import Testing
@testable import RupaUI

private func face(_ node: SceneNodeID, _ index: Int) -> SelectionTarget {
    SelectionTarget(sceneNodeID: node, component: .face(SelectionComponentID(rawValue: "generatedTopology:face/\(index)")))
}

private func edge(_ node: SceneNodeID, _ index: Int) -> SelectionTarget {
    SelectionTarget(sceneNodeID: node, component: .edge(SelectionComponentID(rawValue: "generatedTopology:edge/\(index)")))
}

@Test func faceOfASolidStartsPushFaceAndOpenSheetEdgesStartExtendSheet() {
    let (solid, sheet) = (SceneNodeID(), SceneNodeID())
    let faces = [face(solid, 0), face(solid, 3)]
    let edges = [edge(sheet, 1), edge(sheet, 2)]
    #expect(WorkspaceSelectionDefaultCommand.resolve(selected: faces, solidFaces: Set(faces), sheetOpenEdges: Set(edges))
        == .pushFaces(faces))
    #expect(WorkspaceSelectionDefaultCommand.resolve(selected: edges, solidFaces: Set(faces), sheetOpenEdges: Set(edges))
        == .extendSheet(edges: edges))
}

@Test func mixedOrOtherSelectionsStartNoDefaultCommand() {
    let (solid, sheet) = (SceneNodeID(), SceneNodeID())
    let solidFace = face(solid, 0)
    let openEdge = edge(sheet, 1)
    let innerEdge = edge(sheet, 4)
    let sheetFace = face(sheet, 0)
    func resolve(_ selected: [SelectionTarget]) -> WorkspaceSelectionDefaultCommand? {
        WorkspaceSelectionDefaultCommand.resolve(selected: selected, solidFaces: [solidFace], sheetOpenEdges: [openEdge])
    }
    #expect(resolve([]) == nil)
    #expect(resolve([solidFace, openEdge]) == nil)
    // An edge of a sheet that is not open, a face of a sheet, a whole object: nothing starts.
    #expect(resolve([innerEdge]) == nil)
    #expect(resolve([openEdge, innerEdge]) == nil)
    #expect(resolve([sheetFace]) == nil)
    #expect(resolve([SelectionTarget(sceneNodeID: solid)]) == nil)
}

@Test func aDefaultCommandRunsWhileItsDialogHoldsTheSameTargets() {
    let (solid, sheet) = (SceneNodeID(), SceneNodeID())
    let faces = [face(solid, 0), face(solid, 3)]
    let edges = [edge(sheet, 1)]
    let push = WorkspaceFaceEditSession(kind: .push(faces: faces))
    let extend = WorkspaceFaceEditSession(kind: .extendSheet(edges: edges, limit: SelectionTarget(sceneNodeID: solid)))
    #expect(WorkspaceSelectionDefaultCommand.pushFaces(faces.reversed()).isRunning(in: push))
    #expect(WorkspaceSelectionDefaultCommand.pushFaces([faces[0]]).isRunning(in: push) == false)
    #expect(WorkspaceSelectionDefaultCommand.extendSheet(edges: edges).isRunning(in: push) == false)
    // A limit picked in the dialog does not make it another command.
    #expect(WorkspaceSelectionDefaultCommand.extendSheet(edges: edges).isRunning(in: extend))
    #expect(WorkspaceSelectionDefaultCommand.targets(of: push) == faces)
    #expect(WorkspaceSelectionDefaultCommand.targets(of: extend) == edges)
    #expect(WorkspaceSelectionDefaultCommand.targets(of: WorkspaceFaceEditSession(kind: .hollow(targets: faces))) == nil)
}
